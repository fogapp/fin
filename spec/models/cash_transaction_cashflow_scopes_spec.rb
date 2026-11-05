require "rails_helper"

# The structural exclusion semantics that replaced the description-ILIKE
# heuristics (docs/credit-card-payments.md §C).
RSpec.describe CashTransaction, "cashflow scopes" do
  let(:checking) { create(:account, account_type: "Checking") }
  let(:card)     { create(:account, account_type: "Credit Card") }

  def link!(outflow, inflow, include_in_spend: false, kind: "credit_card_payment")
    Transfer.create!(
      from_transaction_id: outflow.id, from_transaction_type: "CashTransaction",
      to_transaction_id: inflow.id, to_transaction_type: "CashTransaction",
      amount: outflow.amount.abs, kind: kind, include_in_spend: include_in_spend
    ).tap(&:confirm!)
  end

  describe ".spend_like" do
    it "counts unlinked bank payment legs as spend (the review chip surfaces them)" do
      debit = create(:cash_transaction, :bank, account: checking, amount: -500.0,
                     description: "CHASE CREDIT CRD AUTOPAY")
      expect(CashTransaction.spend_like).to include(debit)
      expect(CashTransaction.payment_suspects).to include(debit)
    end

    it "excludes both legs of a linked card payment" do
      debit  = create(:cash_transaction, :bank, account: checking, amount: -500.0,
                      description: "CHASE CREDIT CRD AUTOPAY")
      credit = create(:cash_transaction, :credit_card, :payment, account: card, amount: 500.0)
      link!(debit, credit)

      expect(CashTransaction.spend_like).not_to include(debit)
      expect(CashTransaction.spend_like).not_to include(credit)
      expect(CashTransaction.payment_suspects).not_to include(debit)
    end

    it "keeps the outflow leg countable when include_in_spend is set (proxy/loan)" do
      debit  = create(:cash_transaction, :bank, account: checking, amount: -2000.0,
                      description: "Online Payment To Mortgage")
      inflow = create(:cash_transaction, :bank, account: create(:account, account_type: "Other"),
                      amount: 2000.0, description: "PAYMENT", transaction_type: "Return")
      link!(debit, inflow, include_in_spend: true, kind: "loan_payment")

      expect(CashTransaction.spend_like).to include(debit)
      expect(CashTransaction.spend_like).not_to include(inflow)
      expect(CashTransaction.income_like).not_to include(inflow)
    end

    it "still excludes card-side Payment rows even before linking" do
      credit = create(:cash_transaction, :credit_card, :payment, account: card, amount: 500.0)
      expect(CashTransaction.spend_like).not_to include(credit)
    end
  end

  describe ".income_like" do
    it "counts unlinked bank credits regardless of description" do
      credit = create(:cash_transaction, :bank, :credit, account: checking,
                      amount: 500.0, description: "CREDIT CARD AUTOPAY REFUND")
      expect(CashTransaction.income_like).to include(credit)
    end

    it "excludes any linked inflow leg, even on an include_in_spend transfer" do
      debit  = create(:cash_transaction, :bank, account: checking, amount: -500.0)
      inflow = create(:cash_transaction, :bank, :credit,
                      account: create(:account, account_type: "Savings"), amount: 500.0)
      link!(debit, inflow, include_in_spend: true)

      expect(CashTransaction.income_like).not_to include(inflow)
    end
  end

  describe ".payment_suspects" do
    it "flags LOAN_PAYMENTS-tagged and signature-matching unlinked debits only" do
      tagged    = create(:cash_transaction, :bank, account: checking, amount: -100.0,
                         description: "ACH WEB 12345", raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")
      signature = create(:cash_transaction, :bank, account: checking, amount: -200.0,
                         description: "APPLECARD GSBANK PAYMENT")
      zelle     = create(:cash_transaction, :bank, account: checking, amount: -300.0,
                         description: "Zelle payment to Jane Doe")

      expect(CashTransaction.payment_suspects).to include(tagged, signature)
      expect(CashTransaction.payment_suspects).not_to include(zelle)
    end
  end
end
