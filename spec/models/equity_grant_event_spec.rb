require "rails_helper"

RSpec.describe EquityGrantEvent, type: :model do
  # 100 shares vesting quarterly over the past year: 3 tranches (75) vested.
  let(:grant) do
    create(:equity_grant, quantity: 100, grant_date: Date.current - 10.months,
           vesting_interval: "quarterly", vesting_occurrences: 4, cliff_installments: 0)
  end

  describe "exercise/settlement overdraw" do
    it "rejects exercising more than has vested as of the event date" do
      event = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                    quantity: 80, occurred_on: Date.current)
      expect(event).not_to be_valid
      expect(event.errors[:quantity]).to include("exceeds vested shares")
    end

    it "counts prior events of the same kind against the vested total" do
      create(:equity_grant_event, equity_grant: grant, kind: "exercise",
             quantity: 50, occurred_on: Date.current - 1.month)

      over = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                   quantity: 30, occurred_on: Date.current)
      expect(over).not_to be_valid
      expect(over.errors[:quantity]).to include("exceeds vested shares")

      ok = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                 quantity: 25, occurred_on: Date.current)
      expect(ok).to be_valid
    end

    it "evaluates vesting as of the event's own date" do
      early = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                    quantity: 50, occurred_on: grant.grant_date + 4.months)
      expect(early).not_to be_valid

      later = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                    quantity: 50, occurred_on: grant.grant_date + 7.months)
      expect(later).to be_valid
    end
  end

  describe "sale overdraw" do
    it "rejects selling more than has been exercised or settled" do
      create(:equity_grant_event, equity_grant: grant, kind: "exercise",
             quantity: 40, occurred_on: Date.current - 1.month)

      over = build(:equity_grant_event, equity_grant: grant, kind: "sale",
                   quantity: 41, occurred_on: Date.current)
      expect(over).not_to be_valid
      expect(over.errors[:quantity]).to include("exceeds exercised or settled shares")

      ok = build(:equity_grant_event, equity_grant: grant, kind: "sale",
                 quantity: 40, occurred_on: Date.current, buyer_type: "third_party")
      expect(ok).to be_valid
    end
  end

  describe "field applicability" do
    it "allows method only on exercises and settlements" do
      sale = build(:equity_grant_event, equity_grant: grant, kind: "cancellation",
                   quantity: 5, method: "cash", occurred_on: Date.current)
      expect(sale).not_to be_valid
      expect(sale.errors[:method]).to be_present

      exercise = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                       quantity: 5, method: "cash", occurred_on: Date.current)
      expect(exercise).to be_valid
    end

    it "allows buyer_type only on sales" do
      exercise = build(:equity_grant_event, equity_grant: grant, kind: "exercise",
                       quantity: 5, buyer_type: "company_tender", occurred_on: Date.current)
      expect(exercise).not_to be_valid
      expect(exercise.errors[:buyer_type]).to be_present
    end

    it "rejects unknown kinds, methods, and buyer types" do
      expect(build(:equity_grant_event, equity_grant: grant, kind: "gift")).not_to be_valid
      expect(build(:equity_grant_event, equity_grant: grant, method: "barter")).not_to be_valid
      expect(build(:equity_grant_event, equity_grant: grant, kind: "sale", buyer_type: "friend")).not_to be_valid
    end
  end
end
