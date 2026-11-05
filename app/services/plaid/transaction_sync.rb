# typed: strict

module Plaid
  # The cash-transaction domain of a Plaid sync: pages /transactions/sync
  # from the given cursor and ingests added/modified/removed rows. Cursor
  # OWNERSHIP stays with PlaidSyncer — after each cleanly-applied page this
  # service yields the next cursor to the coordinator's persistence block.
  class TransactionSync
    extend T::Sig

    # The fields whose rewrite invalidates what creation-time matching saw.
    REPLAY_FIELDS = T.let(%w[description amount transaction_date].freeze, T::Array[String])

    sig { params(context: SyncContext).void }
    def initialize(context)
      @context = T.let(context, SyncContext)
    end

    sig do
      params(result: ::PlaidSyncer::Result, cursor: T.nilable(String),
             persist_cursor: T.proc.params(cursor: T.nilable(String)).void).void
    end
    def call(result, cursor:, &persist_cursor)
      loop do
        response = @context.client.sync_transactions(@context.plaid_item.access_token, cursor: cursor)
        errors_before = result.errors.size

        response.added.each do |txn|
          next if @context.skip_account?(txn.account_id)
          process_added(txn, result)
        rescue => e
          result.errors << { transaction_id: txn.transaction_id, error: e.message }
        end

        response.modified.each do |txn|
          next if @context.skip_account?(txn.account_id)
          process_modified(txn, result)
        rescue => e
          result.errors << { transaction_id: txn.transaction_id, error: e.message }
        end

        response.removed.each do |txn|
          next if @context.skip_account?(txn.account_id)
          process_removed(txn, result)
        rescue => e
          result.errors << { transaction_id: txn.transaction_id, error: e.message }
        end

        # Plaid never re-delivers data behind a saved cursor, so a page with
        # any processing failure must not have its cursor persisted — stop
        # paging and let the next sync replay it (ingest is idempotent via the
        # source_row_hash unique index).
        break if result.errors.size > errors_before

        cursor = response.next_cursor
        persist_cursor.call(cursor)
        break unless response.has_more
      end
    end

    private

    sig { params(txn: T.untyped, result: ::PlaidSyncer::Result).void }
    def process_added(txn, result)
      plaid_account = @context.plaid_account_for(txn.account_id)
      return unless plaid_account&.linked?

      hash          = txn.transaction_id
      description   = txn.name
      stored_amount = -txn.amount
      txn_date      = txn.authorized_date || txn.date

      return if ::CashTransaction.exists?(source_row_hash: hash)

      # Pending→posted settlement: Plaid retires the pending transaction_id and
      # issues the posted row under a NEW id, delivered as removed(pending) +
      # added(posted, pending_transaction_id: <old id>) in the same update.
      # Without adoption the destroy/recreate cycle wipes everything the user
      # attached to the pending row (merchant, category, transfer link, tags,
      # memo). Re-pointing the existing row at the new id also turns the
      # paired removed event into a no-op, since #call processes added before
      # removed within each page.
      if (pending_id = txn.pending_transaction_id) &&
         (pending_row = ::CashTransaction.find_by(source_row_hash: pending_id))
        adopt_posted(pending_row, txn, credit_card: plaid_account.credit?)
        result.modified += 1
        return
      end

      # Content-based dedup for reconnected Plaid items: Plaid issues new transaction_ids
      # on a fresh item even for existing transactions, so check for a match by content
      # and adopt the new hash so future modified/removed events find it correctly.
      #
      # Only safe on a reconnect-style sync (cursor was nil at sync start) — on an
      # incremental sync two genuinely distinct identical transactions (two
      # same-price purchases, same card, same day) would wrongly collapse into one.
      # update! (not update_columns) so the household DataVersion callback fires.
      if @context.first_sync && (existing = ::CashTransaction.find_by(account: plaid_account.account, transaction_date: txn_date, amount: stored_amount, description: description))
        existing.update!(source_row_hash: hash)
        ::Issue.create!(
          title:    "Duplicate Plaid transaction merged",
          body:     "Plaid returned a transaction that already exists under a different ID, likely due to a reconnect. " \
                    "The existing record was updated to track the new Plaid ID.\n\n" \
                    "Account: #{T.must(plaid_account.account).name}\n" \
                    "Date: #{txn_date}\nAmount: #{stored_amount}\nDescription: #{description}",
          severity: ::Severity::Warning,
          source:   "plaid_sync"
        )
        return
      end

      source = plaid_account.credit? ? :credit_card : :bank
      transaction_type = plaid_transaction_type(txn, credit_card: plaid_account.credit?)
      # Payment legs are money movement, not merchant activity — a merchant rule
      # matching the descriptor (e.g. "Online Payment ... To Auto Loan") would
      # miscategorize them as spending.
      payment = transaction_type == ::CashTransaction::TransactionType::Payment
      match = payment ? nil : ::Merchants::RuleMatcher.match_result(description)

      ::CashTransaction.create!(
        source:           source,
        transaction_date: txn_date,
        post_date:        txn.date,
        description:      description,
        amount:           stored_amount,
        raw_category:     txn.personal_finance_category&.detailed,
        transaction_type: transaction_type.serialize,
        merchant:         match&.merchant,
        category:         match&.category || (payment ? nil : category_from_plaid(txn)),
        account:          plaid_account.account,
        source_row_hash:  hash
      )
      result.added += 1
    rescue ActiveRecord::RecordNotUnique
      # A concurrent sync inserted the same source_row_hash between our
      # exists? check and the create — the row is there, nothing to do.
    end

    # Settle a pending row onto its posted identity. Plaid-owned fields
    # (identity, description, amount, dates, raw category) refresh from the
    # posted data; user-owned state (merchant, category, transaction_type,
    # transfer link, memo, tags) is preserved. Merchant/category fill in from
    # the posted description only where the row has none, mirroring create.
    sig { params(existing: ::CashTransaction, txn: T.untyped, credit_card: T::Boolean).void }
    def adopt_posted(existing, txn, credit_card:)
      payment = plaid_transaction_type(txn, credit_card: credit_card) == ::CashTransaction::TransactionType::Payment
      match = (payment || existing.merchant_id) ? nil : ::Merchants::RuleMatcher.match_result(txn.name)

      existing.update!(
        source_row_hash:  txn.transaction_id,
        description:      txn.name,
        amount:           -txn.amount,
        transaction_date: txn.authorized_date || txn.date,
        post_date:        txn.date,
        raw_category:     txn.personal_finance_category&.detailed,
        merchant:         existing.merchant || match&.merchant,
        category:         existing.category || match&.category || (payment ? nil : category_from_plaid(txn))
      )
      replay_after_rewrite(existing)
    end

    # Everything keyed on creation — the payment probe and created-triggered
    # workflows — already ran against the pending row's provisional
    # descriptor and amount. Plaid's posted values are often different
    # ("APPLECARD GSBANK PAYMENT ..." arrives pending under a shorter name),
    # so a rule that would match the posted row never saw it. Re-offer the
    # row once its identifying fields settle; DispatchJob skips workflows that
    # already acted on it.
    sig { params(existing: ::CashTransaction).void }
    def replay_after_rewrite(existing)
      rewritten = existing.saved_changes.keys & REPLAY_FIELDS
      return if rewritten.empty?

      ::Transfers::PaymentMatchJob.perform_later(existing.id) if existing.transfer_id.nil?
      ::Workflows::Events.publish("cash_transaction.created", subject: existing,
                                  payload: { "replay" => "posted", "changes" => rewritten })
    end

    sig { params(txn: T.untyped, result: ::PlaidSyncer::Result).void }
    def process_modified(txn, result)
      hash = txn.transaction_id
      existing = ::CashTransaction.find_by(source_row_hash: hash)
      return unless existing

      existing.update!(
        description: txn.name,
        amount:      -txn.amount,
        post_date:   txn.date
      )
      replay_after_rewrite(existing)
      result.modified += 1
    end

    sig { params(txn: T.untyped, result: ::PlaidSyncer::Result).void }
    def process_removed(txn, result)
      ::CashTransaction.where(source_row_hash: txn.transaction_id).destroy_all
      result.removed += 1
    end

    sig { params(txn: T.untyped, credit_card: T::Boolean).returns(::CashTransaction::TransactionType) }
    def plaid_transaction_type(txn, credit_card:)
      primary = txn.personal_finance_category&.primary
      return ::CashTransaction::TransactionType::Payment if primary == "LOAN_PAYMENTS"
      # A credit into a card account tagged as an inbound transfer is a payment
      # or funding event, not a merchant refund — the "Return" fallback would
      # spuriously subtract it from spend.
      return ::CashTransaction::TransactionType::Payment if credit_card && txn.amount.negative? && primary == "TRANSFER_IN"
      # Plaid's category for a card autopayment drifts (it has arrived as
      # INCOME_SALARY); the descriptor's payment signature is the stable
      # signal, and it's what the matcher keys on anyway.
      return ::CashTransaction::TransactionType::Payment if credit_card && txn.amount.negative? && ::Transfers::PaymentSignals.signature?(txn.name)
      txn.amount.negative? ? ::CashTransaction::TransactionType::Return : ::CashTransaction::TransactionType::Sale
    end

    sig { params(txn: T.untyped).returns(T.nilable(::Category)) }
    def category_from_plaid(txn)
      primary = txn.personal_finance_category&.primary
      ::Category.find_by(name: primary) if primary
    end
  end
end
