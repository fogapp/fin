require "rails_helper"

RSpec.describe RealEstate::PropertyRefresher do
  let!(:config)  { create(:rentcast_configuration, api_key: "test-key") }
  let(:property) { create(:real_estate_property, address_line1: "5500 Grand Lake Dr") }

  let(:record_body) do
    {
      id:               "5500-Grand-Lake-Dr,-San-Antonio,-TX-78244",
      formattedAddress: "5500 Grand Lake Dr, San Antonio, TX 78244",
      latitude:         29.475962,
      longitude:        -98.351442,
      propertyType:     "Single Family",
      bedrooms:         3,
      bathrooms:        2,
      squareFootage:    1878,
      lotSize:          8850,
      yearBuilt:        1973,
      hoa:              { fee: 175 },
      lastSaleDate:     "2024-11-18T00:00:00.000Z",
      lastSalePrice:    270_000,
      taxAssessments:   {
        "2023" => { year: 2023, value: 200_000 },
        "2024" => { year: 2024, value: 216_513 }
      },
      history:          {
        "2019-06-01" => { event: "Sale", date: "2019-06-01T00:00:00.000Z", price: 180_000 }
      }
    }
  end

  def stub_record(body = record_body, status: 200)
    stub_request(:get, "https://api.rentcast.io/v1/properties")
      .with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_value(body = { price: 912_000, priceRangeLow: 870_000, priceRangeHigh: 960_000 }, status: 200)
    stub_request(:get, "https://api.rentcast.io/v1/avm/value")
      .with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "value refresh" do
    it "records today's estimate with its confidence range" do
      stub_record
      stub_value

      described_class.new(property).call

      valuation = property.reload.valuations.find_by(source: "rentcast")
      expect(valuation.as_of).to eq(Date.current)
      expect(valuation.amount).to eq(912_000)
      expect(valuation.value_low).to eq(870_000)
      expect(valuation.value_high).to eq(960_000)
      expect(property.current_value).to eq(912_000)
    end

    it "stamps the sync and clears a previous error" do
      property.update!(last_sync_error: "old failure")
      stub_record
      stub_value

      described_class.new(property).call

      expect(property.reload.last_sync_error).to be_nil
      expect(property.last_synced_at).to be_present
    end
  end

  describe "history seeding" do
    it "seeds one tax assessment per year, dated year-end" do
      stub_record
      stub_value

      described_class.new(property).call

      expect(property.reload.valuations.where(source: "tax_assessment").pluck(:as_of, :amount))
        .to match_array([
          [ Date.new(2023, 12, 31), 200_000.to_d ],
          [ Date.new(2024, 12, 31), 216_513.to_d ]
        ])
    end

    it "keeps assessments out of the property's market value" do
      stub_record
      stub_value

      described_class.new(property).call

      expect(property.reload.current_value).to eq(912_000)
    end

    it "seeds recorded sales from the history map and the last sale" do
      stub_record
      stub_value

      described_class.new(property).call

      expect(property.reload.valuations.where(source: "sale").pluck(:as_of, :amount))
        .to match_array([
          [ Date.new(2019, 6, 1),  180_000.to_d ],
          [ Date.new(2024, 11, 18), 270_000.to_d ]
        ])
    end

    it "caches the property facts" do
      stub_record
      stub_value

      described_class.new(property).call

      property.reload
      expect(property.bedrooms).to eq(3)
      expect(property.square_footage).to eq(1878)
      expect(property.year_built).to eq(1973)
      expect(property.hoa_fee).to eq(175)
      expect(property.formatted_address).to eq("5500 Grand Lake Dr, San Antonio, TX 78244")
      expect(property.facts_synced_at).to be_present
    end

    it "re-seeding the same payload does not duplicate points" do
      stub_record
      stub_value

      described_class.new(property).call
      described_class.new(property, force_facts: true).call

      expect(property.reload.valuations.where(source: "tax_assessment").count).to eq(2)
      expect(property.valuations.where(source: "sale").count).to eq(2)
    end
  end

  describe "request budget" do
    it "spends two requests on a first sync and one thereafter" do
      stub_record
      stub_value

      expect { described_class.new(property).call }.to change { config.reload.requests_used }.by(2)
      expect { described_class.new(property).call }.to change { config.reload.requests_used }.by(1)
    end

    it "refreshes the facts again once the cache ages out" do
      stub_record
      stub_value
      property.update!(facts_synced_at: (RealEstateProperty::FACTS_TTL + 1.day).ago)

      expect { described_class.new(property).call }.to change { config.reload.requests_used }.by(2)
    end
  end

  describe "failures" do
    it "drops an unfindable address to manual and raises an issue" do
      stub_record({}, status: 404)
      stub_value({}, status: 404)

      described_class.new(property).call

      expect(property.reload.sync_enabled).to be false
      expect(property.last_sync_error).to be_present
      expect(Issue.active.where(key: "rentcast_property_#{property.id}")).to be_present
    end

    it "still records a value when only the record lookup fails" do
      stub_record({}, status: 404)
      stub_value

      described_class.new(property).call

      expect(property.reload.current_value).to eq(912_000)
      expect(property.sync_enabled).to be true
    end

    it "backfills facts from the estimate's subject property when the record lookup fails" do
      stub_record({}, status: 404)
      stub_value({ price: 912_000, subjectProperty: { bedrooms: 4, squareFootage: 2200 } })

      described_class.new(property).call

      expect(property.reload.bedrooms).to eq(4)
      expect(property.square_footage).to eq(2200)
    end

    it "records the error and re-raises on a provider failure" do
      stub_record
      stub_value({}, status: 500)

      expect { described_class.new(property).call }.to raise_error(Rentcast::Client::Error)
      expect(property.reload.last_sync_error).to be_present
      expect(Issue.active.where(key: "rentcast_property_#{property.id}")).to be_present
    end

    it "resolves an open issue once a sync succeeds" do
      Issue.raise_once!(key: "rentcast_property_#{property.id}", title: "old")
      stub_record
      stub_value

      described_class.new(property).call

      expect(Issue.active.where(key: "rentcast_property_#{property.id}")).to be_empty
    end
  end
end
