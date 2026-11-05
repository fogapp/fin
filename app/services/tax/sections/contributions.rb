# typed: strict

module Tax
  module Sections
    # Retirement/HSA/education contributions per bucket, counted from
    # confirmed transfers into tax-advantaged accounts (including one-sided
    # transfers to external accounts) plus contribution adjustments.
    class Contributions < Base
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build
        filing_status = @context.profile&.filing_status || FilingStatus::Single
        by_account    = transfer_contributions_by_account
        accounts      = Account.where(household_id: @context.household.id)
                               .where.not(tax_treatment: "taxable")
                               .order(:name).to_a

        buckets = Parameters::CONTRIBUTION_BUCKETS.map do |key, definition|
          bucket_accounts = accounts.select { |a| definition[:treatments].include?(a.tax_treatment) }
          transfers_total = bucket_accounts.sum(0.0) { |a| by_account[a.id] || 0.0 }.round(2)
          adjustments_total = @context.adjustments
                                      .select { |a| a.kind == TaxAdjustment::Kind::Contribution && a.bucket == key }
                                      .sum(0.0) { |a| a.amount.to_f }.round(2)
          contributed = (transfers_total + adjustments_total).round(2)
          limit = begin
            Parameters.contribution_limit(key, @context.year, filing_status)
          rescue Parameters::Missing
            nil
          end

          {
            key:               key,
            label:             definition[:label],
            treatments:        definition[:treatments],
            informational:     definition[:informational],
            contributed:       contributed,
            transfers_total:   transfers_total,
            adjustments_total: adjustments_total,
            limit:             limit&.to_f,
            percent_of_limit:  limit&.positive? ? (contributed / limit * 100).round(1) : nil,
            note:              definition[:note],
            accounts: bucket_accounts.map { |a| { id: a.id, name: a.name, tax_treatment: a.tax_treatment } }
          }
        end

        {
          kind:    "fact",
          buckets: buckets,
          note: "Contributions counted from confirmed transfers into tagged accounts (including one-sided transfers to external accounts) plus contribution adjustments"
        }
      end

      private

      # In-year contribution dollars per destination account, from confirmed
      # transfers: the to-side account when present, otherwise the
      # counterparty account of a one-sided from-only transfer (money sent to
      # an unlinked external 401(k)).
      sig { returns(T::Hash[T.untyped, Float]) }
      def transfer_contributions_by_account
        result = Hash.new(0.0)

        transfers = Transfer.where(household_id: @context.household.id).confirmed.to_a
        # The legs are polymorphic (Cash/InvestmentTransaction); resolving them
        # per transfer via #to_transaction/#from_transaction was 1-2 queries per
        # row. One batched load per leg class replaces that walk.
        legs = transfer_legs_by_type_and_id(transfers)

        transfers.each do |transfer|
          to_transaction = legs[[ transfer.to_transaction_type, transfer.to_transaction_id ]]

          if to_transaction
            destination_id = to_transaction.account_id
            date           = transaction_date(to_transaction)
          elsif transfer.from_transaction_id && transfer.counterparty_account_id
            from_transaction = legs[[ transfer.from_transaction_type, transfer.from_transaction_id ]]
            next if from_transaction.nil?

            destination_id = transfer.counterparty_account_id
            date           = transaction_date(from_transaction)
          else
            next
          end

          next unless destination_id && date && @context.range.cover?(date)

          result[destination_id] += transfer.amount.to_f
        end

        result
      end

      # Both legs of every transfer, loaded with one query per transaction
      # class and keyed by [type, id]. A leg whose row was deleted simply has
      # no entry, matching the nil the old per-row find_by returned.
      sig { params(transfers: T::Array[Transfer]).returns(T::Hash[T::Array[T.untyped], T.untyped]) }
      def transfer_legs_by_type_and_id(transfers)
        ids_by_type = Hash.new { |h, k| h[k] = [] }
        transfers.each do |t|
          ids_by_type[t.to_transaction_type]   << t.to_transaction_id   if t.to_transaction_id
          ids_by_type[t.from_transaction_type] << t.from_transaction_id if t.from_transaction_id
        end

        ids_by_type.each_with_object({}) do |(type, ids), lookup|
          # Same whitelist Transfer#transaction_class applies — an unexpected
          # type resolves to no records rather than a constantize of user data.
          next unless Transfer::TRANSACTION_TYPES.include?(type)

          type.constantize.where(id: ids.uniq).each { |record| lookup[[ type, record.id ]] = record }
        end
      end

      sig { params(transaction: T.untyped).returns(T.nilable(Date)) }
      def transaction_date(transaction)
        transaction.respond_to?(:transaction_date) ? transaction.transaction_date : transaction.trade_date
      end
    end
  end
end
