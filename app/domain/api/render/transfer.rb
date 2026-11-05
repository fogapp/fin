# typed: strict

module Api
  module Render
    class Transfer < Api::Render::Base
      extend T::Sig

      # account_names: optional pre-built {account_id => name} hash so list
      # endpoints don't run one counterparty query per row.
      sig { params(t: ::Transfer, account_names: T.nilable(T::Hash[T.untyped, String])).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(t, account_names = nil)
        {
          id:                     t.id,
          from_transaction_id:   t.from_transaction_id,
          from_transaction_type: t.from_transaction_type,
          to_transaction_id:     t.to_transaction_id,
          to_transaction_type:   t.to_transaction_type,
          counterparty_account_id:   t.counterparty_account_id,
          counterparty_account_name: counterparty_name(t, account_names),
          amount:                t.amount&.to_f,
          note:                  t.note,
          kind:                  t.kind,
          include_in_spend:      t.include_in_spend,
          confirmed_at:          t.confirmed_at,
          confirmation_source:   t.confirmation_source,
          created_at:            t.created_at
        }
      end

      # Batch-loads both sides for a list of transfers — the per-transfer
      # from_transaction/to_transaction lookups were 2 queries per row.
      sig { params(transfers: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def serialize_all_with_details(transfers)
        ids_by_type = Hash.new { |h, k| h[k] = [] }
        transfers.each do |t|
          ids_by_type[t.from_transaction_type] << t.from_transaction_id if t.from_transaction_id && t.from_transaction_type
          ids_by_type[t.to_transaction_type]   << t.to_transaction_id   if t.to_transaction_id && t.to_transaction_type
        end

        lookup = {}
        ids_by_type.each do |type, ids|
          next unless ::Transfer::TRANSACTION_TYPES.include?(type)

          type.constantize.where(id: ids.uniq).each { |r| lookup[[ type, r.id ]] = r }
        end

        counterparty_ids = transfers.filter_map(&:counterparty_account_id).uniq
        account_names = ::Account.where(id: counterparty_ids).pluck(:id, :name).to_h

        transfers.map { |t| serialize_with_transaction_details(t, lookup, account_names) }
      end

      sig do
        params(
          t: ::Transfer,
          lookup: T.nilable(T::Hash[T.untyped, T.untyped]),
          account_names: T.nilable(T::Hash[T.untyped, String])
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def serialize_with_transaction_details(t, lookup = nil, account_names = nil)
        from = lookup ? lookup[[ t.from_transaction_type, t.from_transaction_id ]] : t.from_transaction
        to   = lookup ? lookup[[ t.to_transaction_type, t.to_transaction_id ]] : t.to_transaction
        base = serialize(t, account_names)
        base.merge(
          from_date:        from ? tx_date(from) : nil,
          from_description: from&.description,
          from_account_id:  from&.account_id,
          to_date:          to ? tx_date(to) : nil,
          to_description:   to&.description,
          to_account_id:    to&.account_id,
          date_diff:        (from && to) ? (tx_date(from).to_date - tx_date(to).to_date).abs.to_i : nil,
        )
      end

      private

      sig { params(t: ::Transfer, account_names: T.nilable(T::Hash[T.untyped, String])).returns(T.nilable(String)) }
      def counterparty_name(t, account_names)
        return nil unless t.counterparty_account_id
        return account_names[t.counterparty_account_id] if account_names

        t.counterparty_account&.name
      end

      # Cash rows carry transaction_date; investment rows carry trade_date.
      sig { params(tx: T.untyped).returns(T.untyped) }
      def tx_date(tx)
        tx.respond_to?(:transaction_date) ? tx.transaction_date : tx.trade_date
      end
    end
  end
end
