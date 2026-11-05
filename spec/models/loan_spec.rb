require "rails_helper"

RSpec.describe Loan do
  describe "#balance_breakpoints" do
    it "starts at the original principal on the start date" do
      loan = create(:loan, original_principal: 100_000, start_date: Date.new(2025, 1, 15))
      expect(loan.balance_breakpoints).to eq([ [ Date.new(2025, 1, 15), 100_000.to_d ] ])
    end

    it "steps the balance down with each payment using the interest/principal split" do
      # 12% APR → 1% monthly. Payment 1: 1000 interest / 1000 principal.
      # Payment 2: 990 interest / 1010 principal.
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2025, 1, 1))
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.new(2025, 2, 1))
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.new(2025, 3, 1))

      expect(loan.balance_breakpoints).to eq([
        [ Date.new(2025, 1, 1), 100_000.to_d ],
        [ Date.new(2025, 2, 1), 99_000.to_d ],
        [ Date.new(2025, 3, 1), 97_990.to_d ]
      ])
    end

    it "starts from the balance anchor and ignores earlier payments" do
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2024, 1, 1),
                           balance_anchor_amount: 50_000, balance_anchor_date: Date.new(2025, 1, 1))
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.new(2024, 6, 1))
      create(:cash_transaction, loan: loan, amount: -1500, transaction_date: Date.new(2025, 2, 1))

      expect(loan.balance_breakpoints).to eq([
        [ Date.new(2025, 1, 1), 50_000.to_d ],
        [ Date.new(2025, 2, 1), 49_000.to_d ] # 500 interest / 1000 principal
      ])
    end

    it "stays flat for interest-only loans" do
      loan = create(:loan, original_principal: 100_000, interest_only: true, start_date: Date.new(2025, 1, 1))
      create(:cash_transaction, loan: loan, amount: -1000, transaction_date: Date.new(2025, 2, 1))

      expect(loan.balance_breakpoints).to eq([ [ Date.new(2025, 1, 1), 100_000.to_d ] ])
    end

    it "takes escrow off each linked payment before splitting interest and principal" do
      # 12% APR → 1% monthly. A 2,500 payment carrying 500 of escrow puts
      # 2,000 toward the loan: 1000 interest / 1000 principal.
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2025, 1, 1),
                           monthly_payment: 2500, escrow_property_tax: 300, escrow_insurance: 200)
      create(:cash_transaction, loan: loan, amount: -2500, transaction_date: Date.new(2025, 2, 1))

      expect(loan.balance_breakpoints.last).to eq([ Date.new(2025, 2, 1), 99_000.to_d ])
    end
  end

  describe "escrow" do
    let(:loan) do
      create(:loan, original_principal: 100_000, interest_rate: 12.0, term_months: 360,
                    start_date: Date.new(2025, 1, 1), monthly_payment: 2500,
                    escrow_property_tax: 300, escrow_insurance: 150, escrow_other: 50)
    end

    it "separates principal and interest from the full monthly payment" do
      expect(loan.escrow_payment).to eq(500)
      expect(loan.computed_monthly_payment).to eq(2500)
      expect(loan.principal_and_interest_payment).to eq(2000)
    end

    it "amortizes only principal and interest, so escrow doesn't shorten the payoff" do
      without_escrow = create(:loan, original_principal: 100_000, interest_rate: 12.0, term_months: 360,
                                     start_date: Date.new(2025, 1, 1), monthly_payment: 2000)

      schedule = loan.amortization_schedule
      expect(schedule.length).to eq(without_escrow.amortization_schedule.length)
      expect(schedule.first).to include(payment: 2500.0, interest: 1000.0, principal: 1000.0, escrow: 500.0)
      expect(loan.total_scheduled_interest).to eq(without_escrow.total_scheduled_interest)
    end

    it "adds escrow on top of a computed payment when none is entered" do
      computed = create(:loan, original_principal: 100_000, interest_rate: 6.0, term_months: 360)
      with_escrow = create(:loan, original_principal: 100_000, interest_rate: 6.0, term_months: 360,
                                  escrow_property_tax: 400)

      expect(with_escrow.principal_and_interest_payment).to eq(computed.principal_and_interest_payment)
      expect(with_escrow.computed_monthly_payment).to eq(computed.computed_monthly_payment + 400)
    end

    it "tracks escrow paid, split across taxes, insurance and other" do
      create(:cash_transaction, loan: loan, amount: -2500, transaction_date: Date.new(2025, 2, 1))
      create(:cash_transaction, loan: loan, amount: -2500, transaction_date: Date.new(2025, 3, 1))

      stats = loan.payment_stats
      expect(stats).to include(
        total_paid: 5000, escrow_paid: 1000,
        property_tax_paid: 600, insurance_paid: 300, other_escrow_paid: 100
      )
      expect(stats[:principal_paid] + stats[:interest_paid]).to eq(4000)
    end

    it "keeps escrow out of the mortgage interest figure" do
      create(:cash_transaction, loan: loan, amount: -2500, transaction_date: Date.new(2025, 2, 1))

      expect(loan.interest_paid_between(Date.new(2025, 1, 1)..Date.new(2025, 12, 31))).to eq(1000)
    end

    it "rejects a monthly payment that doesn't exceed the escrow it includes" do
      loan.monthly_payment = 500

      expect(loan).not_to be_valid
      expect(loan.errors[:monthly_payment]).to be_present
    end

    it "rejects negative escrow amounts" do
      loan.escrow_insurance = -1

      expect(loan).not_to be_valid
    end
  end

  describe "#current_balance" do
    it "matches payment_stats' balance, from origination or from the anchor" do
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2025, 1, 1))
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.new(2025, 2, 1))
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: Date.new(2025, 3, 1))

      expect(loan.current_balance).to eq(97_990.to_d)
      expect(loan.current_balance).to eq(loan.payment_stats[:current_balance])

      anchored = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2024, 1, 1),
                               balance_anchor_amount: 50_000, balance_anchor_date: Date.new(2025, 1, 1))
      create(:cash_transaction, loan: anchored, amount: -2000, transaction_date: Date.new(2024, 6, 1))
      create(:cash_transaction, loan: anchored, amount: -1500, transaction_date: Date.new(2025, 2, 1))

      expect(anchored.current_balance).to eq(49_000.to_d)
      expect(anchored.current_balance).to eq(anchored.payment_stats[:current_balance])
    end

    it "doesn't serve a stale balance after the loan is edited" do
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0, start_date: Date.new(2025, 1, 1))
      expect(loan.current_balance).to eq(100_000.to_d)

      loan.update!(balance_anchor_amount: 80_000, balance_anchor_date: Date.new(2025, 6, 1))

      expect(loan.current_balance).to eq(80_000.to_d)
    end
  end
end
