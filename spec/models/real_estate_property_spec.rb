require "rails_helper"

RSpec.describe RealEstateProperty do
  describe "#current_value" do
    it "returns the newest market valuation" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Purchase, as_of: Date.new(2019, 6, 1), amount: 720_000)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)

      expect(property.current_value).to eq(912_000)
    end

    it "prefers a manual entry over an estimate recorded the same day" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 950_000)

      expect(property.current_value).to eq(950_000)
      expect(property.current_valuation.source).to eq(RealEstateValuation::Source::Manual)
    end

    it "lets a newer estimate win back over an older manual entry" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current - 7, amount: 950_000)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)

      expect(property.current_value).to eq(912_000)
    end

    it "ignores tax assessments, which run below market value" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current - 3, amount: 912_000)
      property.record_valuation!(source: RealEstateValuation::Source::TaxAssessment, as_of: Date.current, amount: 648_000)

      expect(property.current_value).to eq(912_000)
    end

    it "is nil with no valuations" do
      expect(create(:real_estate_property).current_value).to be_nil
    end
  end

  describe "#record_valuation!" do
    it "updates in place rather than stacking when the same source and date repeat" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 900_000)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 912_000)

      expect(property.valuations.where(source: "rentcast").count).to eq(1)
      expect(property.current_value).to eq(912_000)
    end
  end

  describe "purchase price" do
    it "anchors the chart as a Purchase valuation" do
      property = create(:real_estate_property, purchase_date: Date.new(2019, 6, 1), purchase_price: 720_000)

      expect(property.valuations.where(source: "purchase").pluck(:as_of, :amount))
        .to eq([ [ Date.new(2019, 6, 1), 720_000.to_d ] ])
    end

    it "moves with a corrected date instead of leaving a stale point" do
      property = create(:real_estate_property, purchase_date: Date.new(2019, 6, 1), purchase_price: 720_000)
      property.update!(purchase_date: Date.new(2019, 7, 1))

      expect(property.valuations.where(source: "purchase").pluck(:as_of)).to eq([ Date.new(2019, 7, 1) ])
    end

    it "is removed when the purchase details are cleared" do
      property = create(:real_estate_property, purchase_date: Date.new(2019, 6, 1), purchase_price: 720_000)
      property.update!(purchase_price: nil)

      expect(property.valuations.where(source: "purchase")).to be_empty
    end
  end

  describe "valuation sync on save" do
    it "leaves valuations alone when an unrelated column changes" do
      property = create(:real_estate_property, purchase_date: Date.new(2019, 6, 1), purchase_price: 720_000)

      queries = count_queries { property.update!(notes: "new roof 2024", last_synced_at: Time.current) }

      expect(queries.grep(/real_estate_valuations/)).to be_empty
    end

    it "records the sale point when the property is marked sold" do
      property = create(:real_estate_property)

      property.update!(status: "sold", sold_date: Date.new(2025, 3, 1), sold_price: 800_000)

      sale = property.valuations.find_by(source: RealEstateValuation::Source::Sale.serialize)
      expect(sale).to have_attributes(as_of: Date.new(2025, 3, 1), amount: 800_000)
    end
  end

  describe "#value_breakpoints" do
    it "emits one carry-forward point per date" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Purchase, as_of: Date.new(2019, 6, 1), amount: 720_000)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.new(2026, 7, 1), amount: 912_000)

      expect(property.value_breakpoints).to eq([
        [ Date.new(2019, 6, 1), 720_000.0 ],
        [ Date.new(2026, 7, 1), 912_000.0 ]
      ])
    end

    it "drops to zero the day after a sale so the proceeds aren't double-counted" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.new(2026, 5, 1), amount: 900_000)
      property.update!(status: "sold", sold_date: Date.new(2026, 6, 1), sold_price: 925_000)

      expect(property.value_breakpoints).to eq([
        [ Date.new(2026, 5, 1), 900_000.0 ],
        [ Date.new(2026, 6, 1), 925_000.0 ],
        [ Date.new(2026, 6, 2), 0.0 ]
      ])
    end

    it "excludes valuations recorded after the sale date" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.new(2026, 7, 1), amount: 940_000)
      property.update!(status: "sold", sold_date: Date.new(2026, 6, 1), sold_price: 925_000)

      expect(property.value_breakpoints.map(&:first)).not_to include(Date.new(2026, 7, 1))
    end
  end

  describe "mortgage linkage" do
    it "reports equity and LTV from the linked loan's current balance" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 1_000_000)
      create(:loan, real_estate_property: property, original_principal: 400_000, status: "active")

      expect(property.reload.mortgage_balance).to eq(400_000)
      expect(property.equity).to eq(600_000)
      expect(property.loan_to_value).to eq(40.0)
    end

    it "distinguishes no mortgage from a paid-off one" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 1_000_000)

      expect(property.mortgage_balance).to be_nil
      expect(property.equity).to eq(1_000_000)
      expect(property.loan_to_value).to be_nil
    end

    it "replays each loan's amortization once however often the balance is read" do
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Manual, as_of: Date.current, amount: 1_000_000)
      create(:loan, real_estate_property: property, original_principal: 400_000, status: "active")
      property.reload

      loan = property.loans.to_a.first
      allow(loan).to receive(:each_payment).and_call_original
      3.times { property.equity && property.loan_to_value && property.mortgage_balance }

      expect(loan).to have_received(:each_payment).once
    end

    it "unlinks rather than destroys the loan when the property is deleted" do
      property = create(:real_estate_property)
      loan = create(:loan, real_estate_property: property)

      property.destroy!

      expect(loan.reload.real_estate_property_id).to be_nil
    end
  end

  describe "validations" do
    it "requires a sale date when marked sold" do
      property = build(:real_estate_property, status: "sold", sold_date: nil)
      expect(property).not_to be_valid
      expect(property.errors[:sold_date]).to be_present
    end
  end

  describe "#query_address" do
    it "prefers RentCast's canonical form once one is known" do
      property = create(:real_estate_property, formatted_address: "5500 Grand Lake Dr, San Antonio, TX 78244")
      expect(property.query_address).to eq("5500 Grand Lake Dr, San Antonio, TX 78244")
    end

    # RentCast documents "Street, City, State, Zip" — a space between state
    # and zip makes some addresses fail to geolocate.
    it "assembles a comma-separated address from the entered parts otherwise" do
      property = create(:real_estate_property, address_line1: "1 Main St", city: "Austin", state: "TX", zip_code: "78701")
      expect(property.query_address).to eq("1 Main St, Austin, TX, 78701")
    end

    it "omits parts that weren't entered" do
      property = create(:real_estate_property, address_line1: "1 Main St", city: "Austin",
                                               state: "TX", zip_code: nil)
      expect(property.query_address).to eq("1 Main St, Austin, TX")
    end
  end
end
