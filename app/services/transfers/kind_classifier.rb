# typed: strict

module Transfers
  # Classifies a transfer's kind from its legs (identity), and derives the
  # default cashflow treatment (include_in_spend) from kind + shape.
  # Identity and treatment are deliberately orthogonal:
  #
  #   credit_card_payment, both legs tracked -> excluded (swipes already count)
  #   credit_card_payment, one-sided outflow to an external (untracked) card
  #                                          -> counted (cash-basis proxy: the
  #                                             payment is the only visibility
  #                                             into that card's spending)
  #   loan_payment                           -> counted (budgetable under its
  #                                             real category)
  #   transfer                               -> excluded (unchanged)
  #
  # Defaults only — the flag is editable per transfer.
  class KindClassifier
    extend T::Sig

    CREDIT_CARD_TYPE = "Credit Card"
    # Account types that hold a liability: money arriving there is a loan
    # payment even when the feed tags it as a plain account transfer (Plaid
    # labels mortgage servicing debits TRANSFER_OUT_ACCOUNT_TRANSFER).
    LIABILITY_TYPES = T.let(%w[mortgage loan auto\ loan car\ loan student\ loan line\ of\ credit heloc].freeze, T::Array[String])
    CC_PAYMENT_RAW_CATEGORY = "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"
    LOAN_RAW_CATEGORY_PREFIX = "LOAN_PAYMENTS"

    # A T::Struct rather than Data.define: the generated Data readers carry no
    # sigs, which `typed: strict` rejects, and spelling the two fields out
    # types them at every call site instead of leaving them untyped.
    class Classification < T::Struct
      const :kind, Transfer::Kind
      const :include_in_spend, T::Boolean
    end

    sig { params(transfer: Transfer).returns(Classification) }
    def self.classify(transfer)
      new(
        from: transfer.from_transaction,
        to: transfer.to_transaction,
        counterparty: transfer.counterparty_account
      ).classify
    end

    sig do
      params(
        from: T.nilable(T.any(CashTransaction, InvestmentTransaction)),
        to: T.nilable(T.any(CashTransaction, InvestmentTransaction)),
        counterparty: T.nilable(Account)
      ).void
    end
    def initialize(from:, to:, counterparty: nil)
      @from = from
      @to = to
      @counterparty = counterparty
    end

    sig { returns(Classification) }
    def classify
      kind = detect_kind
      Classification.new(kind: kind, include_in_spend: default_include_in_spend(kind))
    end

    private

    sig { returns(Transfer::Kind) }
    def detect_kind
      return Transfer::Kind::CreditCardPayment if credit_card_payment?
      return Transfer::Kind::LoanPayment if loan_payment?

      Transfer::Kind::Transfer
    end

    # The structural anchor: money arriving in a credit-card account (paired
    # inflow leg, or one-sided where the card is the untracked counterparty of
    # an outflow, or the card leg itself is present without its funding leg).
    sig { returns(T::Boolean) }
    def credit_card_payment?
      return true if credit_card_account?(inflow_leg&.account)
      return true if inflow_leg.nil? && credit_card_account?(@counterparty)
      return true if cash_legs.any? { |leg| leg.raw_category == CC_PAYMENT_RAW_CATEGORY }

      false
    end

    sig { returns(T::Boolean) }
    def loan_payment?
      return true if cash_legs.any? { |leg| leg.loan_id.present? }
      return true if cash_legs.any? { |leg| leg.raw_category.to_s.start_with?(LOAN_RAW_CATEGORY_PREFIX) }
      return true if liability_account?(inflow_leg&.account)
      return true if inflow_leg.nil? && liability_account?(@counterparty)

      false
    end

    sig { params(kind: Transfer::Kind).returns(T::Boolean) }
    def default_include_in_spend(kind)
      case kind
      when Transfer::Kind::LoanPayment
        true
      when Transfer::Kind::CreditCardPayment
        # Counted only when the outflow leg is the sole visibility into the
        # card's spending: a one-sided payment to an external (untracked) card.
        # T.must because Sorbet infers a chain of `&&` over T::Boolean operands
        # as T.nilable(T::Boolean), which doesn't satisfy the sig. Each operand
        # types as a plain boolean on its own; only the conjunction widens.
        T.must(outflow_leg.present? && inflow_leg.nil? && @counterparty&.kind == Account::Kind::External)
      else
        false
      end
    end

    sig { returns(T.nilable(T.any(CashTransaction, InvestmentTransaction))) }
    def inflow_leg
      [ @from, @to ].compact.find { |leg| leg_amount(leg).to_f.positive? }
    end

    sig { returns(T.nilable(T.any(CashTransaction, InvestmentTransaction))) }
    def outflow_leg
      [ @from, @to ].compact.find { |leg| leg_amount(leg).to_f.negative? }
    end

    sig { returns(T::Array[CashTransaction]) }
    def cash_legs
      [ @from, @to ].grep(CashTransaction)
    end

    sig { params(leg: T.any(CashTransaction, InvestmentTransaction)).returns(T.untyped) }
    def leg_amount(leg)
      leg.is_a?(InvestmentTransaction) ? leg.amount_usd : leg.amount
    end

    sig { params(account: T.nilable(Account)).returns(T::Boolean) }
    def credit_card_account?(account)
      account&.account_type == CREDIT_CARD_TYPE
    end

    sig { params(account: T.nilable(Account)).returns(T::Boolean) }
    def liability_account?(account)
      return false unless account

      LIABILITY_TYPES.include?(account.account_type.to_s.strip.downcase)
    end
  end
end
