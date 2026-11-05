require "rails_helper"

RSpec.describe Tax::ChecklistSeeder do
  let(:household) { Current.household }
  let(:year)      { 2026 }

  def seeded_items
    TaxChecklistItem.where(tax_year: year).order(:kind, :source_label)
  end

  it "seeds every document kind from ledger data and is idempotent" do
    create(:tax_profile, tax_year: year)

    broker = create(:broker, name: "Vanguard")
    account = create(:account, broker: broker)
    create(:investment_transaction, account: account, trade_date: Date.new(year, 3, 1))

    create(:loan, name: "Home Loan", status: "active", start_date: Date.new(year - 2, 1, 1))
    # Paid-off loans don't get a 1098 row.
    create(:loan, name: "Old Loan", status: "paid_off", start_date: Date.new(year - 5, 1, 1))

    company = create(:equity_company, name: "Rocketry")
    iso = create(:equity_grant, :fully_vested, equity_company: company, grant_type: "iso",
                 strike_price: 1, quantity: 100, grant_date: Date.new(year - 1, 1, 1))
    exercise = create(:equity_grant_event, equity_grant: iso, kind: "exercise",
                      occurred_on: Date.new(year, 2, 20), quantity: 10, share_price: 4)

    create(:account, name: "My IRA", tax_treatment: "traditional_ira")
    create(:account, name: "My 401k", tax_treatment: "traditional_401k") # W-2 territory, no 5498

    giving = create(:category, charitable: true)
    big_gift = create(:cash_transaction, source: "credit_card", transaction_type: "Sale",
                      account: account, category: giving, amount: -300,
                      transaction_date: Date.new(year, 4, 2), description: "RED CROSS")
    create(:cash_transaction, source: "credit_card", transaction_type: "Sale",
           account: account, category: giving, amount: -100,
           transaction_date: Date.new(year, 5, 2), description: "SMALL GIFT") # under $250

    described_class.ensure!(household: household, year: year)
    first_pass = seeded_items.pluck(:kind, :source_label)

    expect(first_pass).to include(
      [ TaxChecklistItem::Kind::W2, "Employer" ],
      [ TaxChecklistItem::Kind::Form1099Consolidated, "Vanguard" ],
      [ TaxChecklistItem::Kind::Form1098, "Home Loan" ],
      [ TaxChecklistItem::Kind::Form3921, "Rocketry — #{Date.new(year, 2, 20).iso8601}" ],
      [ TaxChecklistItem::Kind::Form5498, "My IRA" ]
    )
    expect(first_pass.map(&:first)).not_to include(TaxChecklistItem::Kind::K1)
    expect(first_pass.select { |kind, _| kind == TaxChecklistItem::Kind::Form1098 }.length).to eq(1)
    expect(first_pass.select { |kind, _| kind == TaxChecklistItem::Kind::CharitableReceipt }.length).to eq(1)

    receipt = seeded_items.find_by(kind: TaxChecklistItem::Kind::CharitableReceipt)
    expect(receipt.source_label).to eq("RED CROSS — $300.00 on #{Date.new(year, 4, 2).iso8601}")
    expect(receipt.reference_id).to eq(big_gift.id)
    expect(seeded_items.find_by(kind: TaxChecklistItem::Kind::Form3921).reference_id).to eq(exercise.id)
    expect(seeded_items.pluck(:auto_seeded).uniq).to eq([ true ])
    expect(seeded_items.pluck(:status).uniq).to eq([ TaxChecklistItem::Status::Expected ])

    # Second run adds nothing and preserves user edits.
    seeded_items.find_by(kind: TaxChecklistItem::Kind::W2).update!(status: "received")
    expect { described_class.ensure!(household: household, year: year) }
      .not_to change { seeded_items.count }
    expect(seeded_items.find_by(kind: TaxChecklistItem::Kind::W2).status).to eq(TaxChecklistItem::Status::Received)
  end

  it "seeds nothing for an empty household" do
    other = create(:household)
    described_class.ensure!(household: other, year: year)
    expect(TaxChecklistItem.unscoped.where(household_id: other.id)).to be_empty
  end
end
