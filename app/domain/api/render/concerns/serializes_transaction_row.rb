# typed: strict

module Api
  module Render
    module Concerns
      # The lightweight cash-transaction row used by "pick a transaction"
      # surfaces (loan payment candidates, manual transfer pairing) — one
      # definition so the two pickers can't drift apart. transaction_date is
      # a Date; ActiveSupport encodes it as "YYYY-MM-DD", byte-identical to
      # the .to_s one caller used to emit.
      module SerializesTransactionRow
        extend T::Sig

        sig { params(t: ::CashTransaction).returns(T::Hash[Symbol, T.untyped]) }
        def transaction_row(t)
          {
            id:               t.id,
            transaction_date: t.transaction_date,
            description:      t.description,
            amount:           t.amount.to_f,
            account_name:     t.account&.name
          }
        end
      end
    end
  end
end
