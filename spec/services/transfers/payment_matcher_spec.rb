require "rails_helper"

RSpec.describe Transfers::PaymentMatcher do
  let(:checking) { create(:account, account_type: "Checking", name: "Checking") }
  let(:card)     { create(:account, account_type: "Credit Card", name: "Sapphire") }

  def card_credit(attrs = {})
    create(:cash_transaction, :credit_card,
           { account: card, amount: 500.00, transaction_type: "Payment",
             description: "Payment received", transaction_date: Date.current - 1 }.merge(attrs))
  end

  def bank_debit(attrs = {})
    create(:cash_transaction, :bank,
           { account: checking, amount: -500.00,
             description: "ELECTRONIC WITHDRAWAL", transaction_date: Date.current }.merge(attrs))
  end

  describe "credit card payment pairs" do
    it "auto-confirms a structural pair with a signature description (S1+S3)" do
      debit  = bank_debit(description: "CHASE CREDIT CRD AUTOPAY 12345")
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")

      transfer = described_class.new(credit).match!

      expect(transfer).to be_confirmed
      expect(transfer.kind).to eq(Transfer::Kind::CreditCardPayment)
      expect(transfer.confirmation_source).to eq(Transfer::ConfirmationSource::Auto)
      expect(transfer.include_in_spend).to be(false)
      expect(debit.reload.transfer_id).to eq(transfer.id)
      expect(credit.reload.transfer_id).to eq(transfer.id)
      expect(transfer.from_transaction_id).to eq(debit.id)
      expect(transfer.to_transaction_id).to eq(credit.id)
    end

    it "auto-confirms on the Plaid PFC signal alone (S1+S2)" do
      bank_debit(description: "ONLINE TRANSFER 998877",
                 raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")
      credit = card_credit(description: "PYMT RECVD")

      transfer = described_class.new(credit).match!
      expect(transfer).to be_confirmed
      expect(transfer.kind).to eq(Transfer::Kind::CreditCardPayment)
    end

    it "auto-confirms via cadence once the account pair is established (S1+S4)" do
      old_debit  = bank_debit(description: "CHASE CREDIT CRD AUTOPAY", transaction_date: Date.current - 30)
      old_credit = card_credit(description: "AUTOMATIC PAYMENT - THANK", transaction_date: Date.current - 31)
      described_class.new(old_credit).match!

      bank_debit(description: "ELECTRONIC WITHDRAWAL")
      credit = card_credit(description: "PYMT RECVD")

      transfer = described_class.new(credit).match!
      expect(transfer).to be_confirmed
      expect(transfer.confirmation_source).to eq(Transfer::ConfirmationSource::Auto)
    end

    it "leaves a structure-only match as an unconfirmed candidate (bare S1)" do
      bank_debit(description: "ELECTRONIC WITHDRAWAL")
      credit = card_credit(description: "PYMT RECVD", transaction_type: "Return")

      transfer = described_class.new(credit).match!

      expect(transfer).not_to be_confirmed
      expect(transfer.kind).to eq(Transfer::Kind::CreditCardPayment)
      expect(credit.reload.transfer_id).to be_nil # candidates exclude nothing
    end

    it "probes from the bank side too (late-arriving funding leg)" do
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")
      debit  = bank_debit(description: "ELECTRONIC WITHDRAWAL")

      transfer = described_class.new(debit).match!
      expect(transfer).to be_confirmed
      expect(transfer.to_transaction_id).to eq(credit.id)
    end

    it "declines ambiguous matches (two identical debits)" do
      bank_debit(description: "CHASE CREDIT CRD AUTOPAY")
      other = create(:account, account_type: "Checking")
      bank_debit(account: other, description: "CHASE CREDIT CRD AUTOPAY")
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")

      expect(described_class.new(credit).match!).to be_nil
    end

    it "ignores counterparts outside the window" do
      bank_debit(description: "CHASE CREDIT CRD AUTOPAY", transaction_date: Date.current - 10)
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")

      expect(described_class.new(credit).match!).to be_nil
    end

    it "does nothing when the transaction is already linked or in a candidate" do
      debit  = bank_debit(description: "CHASE CREDIT CRD AUTOPAY")
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")
      Transfer.create!(from_transaction_id: debit.id, from_transaction_type: "CashTransaction",
                       to_transaction_id: credit.id, to_transaction_type: "CashTransaction",
                       amount: 500.00)

      expect(described_class.new(credit).match!).to be_nil
    end

    it "never pairs a plain bank debit with a non-card inflow" do
      savings = create(:account, account_type: "Savings")
      create(:cash_transaction, :bank, account: savings, amount: 500.00,
             description: "DEPOSIT", transaction_type: "Credit")
      debit = bank_debit(description: "CHASE CREDIT CRD AUTOPAY")

      expect(described_class.new(debit).match!).to be_nil
    end
  end

  describe "loan payments" do
    it "pairs and counts a loan payment (S2 loan) with include_in_spend" do
      loan_account = create(:account, account_type: "Other", name: "MORTGAGE LOAN")
      create(:cash_transaction, :bank, account: loan_account, amount: 2000.00,
             description: "PAYMENT", transaction_type: "Return")
      debit = bank_debit(amount: -2000.00, description: "Online Payment To Mortgage",
                         raw_category: "LOAN_PAYMENTS_MORTGAGE_PAYMENT")

      transfer = described_class.new(debit).match!

      expect(transfer).to be_confirmed
      expect(transfer.kind).to eq(Transfer::Kind::LoanPayment)
      expect(transfer.include_in_spend).to be(true)
    end
  end

  describe "one-sided upgrade" do
    it "fills the missing side when the tracked counterpart finally arrives" do
      debit = bank_debit(description: "CHASE CREDIT CRD AUTOPAY")
      one_sided = Transfer.create!(
        from_transaction_id: debit.id, from_transaction_type: "CashTransaction",
        counterparty_account_id: card.id, amount: 500.00,
        kind: "credit_card_payment", include_in_spend: true
      )
      one_sided.confirm!

      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")
      transfer = described_class.new(credit).match!

      expect(transfer.id).to eq(one_sided.id)
      expect(transfer.reload.counterparty_account_id).to be_nil
      expect(transfer.to_transaction_id).to eq(credit.id)
      expect(transfer.include_in_spend).to be(false) # both legs tracked now
      expect(credit.reload.transfer_id).to eq(transfer.id)
    end

    it "walks away when a concurrent probe claims the transfer first (re-check under lock)" do
      debit = bank_debit(description: "CHASE CREDIT CRD AUTOPAY")
      one_sided = Transfer.create!(
        from_transaction_id: debit.id, from_transaction_type: "CashTransaction",
        counterparty_account_id: card.id, amount: 500.00,
        kind: "credit_card_payment", include_in_spend: true
      )
      one_sided.confirm!

      winner_credit = card_credit(description: "AUTOMATIC PAYMENT - THANK")
      loser_credit  = card_credit(description: "AUTOMATIC PAYMENT - THANK")

      # Simulate the race: between the candidate query and acquiring the row
      # lock, the other leg's job fills the missing side.
      allow_any_instance_of(Transfer).to receive(:with_lock).and_wrap_original do |m, &blk|
        Transfer.unscoped.where(id: m.receiver.id, to_transaction_id: nil).update_all(
          to_transaction_id: winner_credit.id, to_transaction_type: "CashTransaction",
          counterparty_account_id: nil
        )
        m.call(&blk)
      end

      expect(described_class.new(loser_credit).match!).to be_nil
      expect(one_sided.reload.to_transaction_id).to eq(winner_credit.id)
      expect(loser_credit.reload.transfer_id).to be_nil
    end
  end

  describe "cadence for untracked counterparties (S5)" do
    let(:apple_card) { create(:account, account_type: "Credit Card", name: "Apple Card", kind: "external") }

    def precedent_for(debit)
      Transfer.create!(
        household_id: debit.household_id, amount: debit.amount.abs,
        kind: Transfer::Kind::CreditCardPayment, include_in_spend: true,
        counterparty_account_id: apple_card.id,
        from_transaction_id: debit.id, from_transaction_type: "CashTransaction"
      ).tap { |t| t.confirm!(source: Transfer::ConfirmationSource::User) }
    end

    it "links a repeat of a one-sided payment to the same counterparty, auto-confirmed" do
      earlier = bank_debit(description: "APPLECARD GSBANK PAYMENT 100001 WEB ID: 9999999999",
                           amount: -835.85, transaction_date: Date.current - 31,
                           raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")
      precedent = precedent_for(earlier)
      this_month = bank_debit(description: "APPLECARD GSBANK PAYMENT 170113 WEB ID: 9999999999",
                              amount: -1292.82, raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")

      transfer = described_class.new(this_month).match!

      expect(transfer).to be_present
      expect(transfer).to be_confirmed
      expect(transfer.confirmation_source).to eq(Transfer::ConfirmationSource::Auto)
      expect(transfer.kind).to eq(Transfer::Kind::CreditCardPayment)
      expect(transfer.counterparty_account_id).to eq(apple_card.id)
      expect(transfer.include_in_spend).to eq(precedent.include_in_spend)
      expect(transfer.from_transaction_id).to eq(this_month.id)
      expect(this_month.reload.transfer_id).to eq(transfer.id)
    end

    it "replays from the card side too (a card credit whose funding account is untracked)" do
      funding = create(:account, account_type: "Checking", name: "Outside Checking", kind: "external")
      earlier = card_credit(description: "AUTOMATIC PAYMENT - THANK", amount: 1729.40,
                            transaction_date: Date.current - 31)
      Transfer.create!(
        household_id: earlier.household_id, amount: earlier.amount, kind: Transfer::Kind::CreditCardPayment,
        counterparty_account_id: funding.id,
        to_transaction_id: earlier.id, to_transaction_type: "CashTransaction"
      ).confirm!(source: Transfer::ConfirmationSource::User)
      credit = card_credit(description: "AUTOMATIC PAYMENT - THANK", amount: 1253.51)

      transfer = described_class.new(credit).match!

      expect(transfer.to_transaction_id).to eq(credit.id)
      expect(transfer.counterparty_account_id).to eq(funding.id)
    end

    it "prefers a real counterpart over the precedent when one exists" do
      earlier = bank_debit(description: "APPLECARD GSBANK PAYMENT 1 WEB ID: 1", amount: -100.00,
                           transaction_date: Date.current - 31, raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")
      precedent_for(earlier)
      credit = card_credit(description: "PAYMENT THANK YOU", amount: 100.00, account: apple_card)
      debit  = bank_debit(description: "APPLECARD GSBANK PAYMENT 2 WEB ID: 2", amount: -100.00,
                          raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")

      transfer = described_class.new(debit).match!

      expect(transfer.to_transaction_id).to eq(credit.id)
      expect(transfer.counterparty_account_id).to be_nil
    end

    it "ignores a debit that carries no payment signal of its own" do
      earlier = bank_debit(description: "Zelle payment to Jordan 12345678", amount: -100.00,
                           transaction_date: Date.current - 31)
      precedent_for(earlier)
      repeat = bank_debit(description: "Zelle payment to Jordan 87654321", amount: -100.00)

      expect(described_class.new(repeat).match!).to be_nil
    end

    it "ignores a precedent with a different stable descriptor" do
      earlier = bank_debit(description: "APPLECARD GSBANK PAYMENT 1 WEB ID: 1", amount: -100.00,
                           transaction_date: Date.current - 31, raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")
      precedent_for(earlier)
      other = bank_debit(description: "Online Payment 10000000001 To BANK OF AMERICA NA",
                         amount: -900.00, raw_category: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT")

      expect(described_class.new(other).match!).to be_nil
    end
  end
end
