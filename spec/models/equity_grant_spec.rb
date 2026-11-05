require "rails_helper"

RSpec.describe EquityGrant, type: :model do
  describe "strike price by grant type" do
    it "requires a strike for iso and nso grants" do
      %w[iso nso].each do |type|
        grant = build(:equity_grant, grant_type: type, strike_price: nil)
        expect(grant).not_to be_valid
        expect(grant.errors[:strike_price]).to include("is required for #{type} grants")
      end
    end

    it "forbids a strike for rsu and rsa grants" do
      %w[rsu rsa].each do |type|
        grant = build(:equity_grant, grant_type: type, strike_price: 1.25)
        expect(grant).not_to be_valid
        expect(grant.errors[:strike_price]).to include("must be blank for #{type} grants")
      end
    end
  end

  it "defaults vesting_commencement_date to grant_date" do
    grant = create(:equity_grant, grant_date: Date.new(2025, 3, 1), vesting_commencement_date: nil)
    expect(grant.vesting_commencement_date).to eq(Date.new(2025, 3, 1))
  end

  it "keeps an explicit vesting_commencement_date" do
    grant = create(:equity_grant, grant_date: Date.new(2025, 3, 1),
                   vesting_commencement_date: Date.new(2025, 1, 15))
    expect(grant.vesting_commencement_date).to eq(Date.new(2025, 1, 15))
  end

  it "requires a vesting interval for flat schedules but not with custom tranches" do
    flat = build(:equity_grant, vesting_interval: nil, vesting_occurrences: 48)
    expect(flat).not_to be_valid
    expect(flat.errors[:vesting_interval]).to be_present

    custom = build(:equity_grant, :rsu, vesting_interval: nil, vesting_occurrences: nil,
                   cliff_installments: 0,
                   custom_tranches: [ { "date" => "2026-01-01", "quantity" => 10 } ])
    expect(custom).to be_valid
  end

  it "rejects malformed custom tranches" do
    grant = build(:equity_grant, :rsu, custom_tranches: [ { "date" => "not-a-date", "quantity" => 10 } ])
    expect(grant).not_to be_valid
    expect(grant.errors[:custom_tranches]).to be_present
  end

  it "rejects unknown grant types and non-positive quantities" do
    expect(build(:equity_grant, grant_type: "espp")).not_to be_valid
    expect(build(:equity_grant, quantity: 0)).not_to be_valid
  end

  it "sums event quantities by kind" do
    grant = create(:equity_grant, :rsu, :fully_vested, quantity: 100, grant_date: Date.current - 1.year)
    create(:equity_grant_event, equity_grant: grant, kind: "settlement", quantity: 40,
           occurred_on: Date.current - 1.month)
    create(:equity_grant_event, equity_grant: grant, kind: "sale", quantity: 10,
           occurred_on: Date.current)

    expect(grant.settled_quantity).to eq(40)
    expect(grant.sold_quantity).to eq(10)
    expect(grant.exercised_quantity).to eq(0)
  end
end
