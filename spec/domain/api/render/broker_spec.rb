require "rails_helper"

RSpec.describe Api::Render::Broker do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns brokers sorted by name with account_count" do
      b1 = create(:broker, name: "Zebra")
      b2 = create(:broker, name: "Alpha")
      create(:account, broker: b2)
      create(:account, broker: b2)

      result = renderer.index
      expect(result.map { |b| b[:name] }).to eq([ "Alpha", "Zebra" ])
      expect(result.find { |b| b[:name] == "Alpha" }[:account_count]).to eq(2)
      expect(result.find { |b| b[:name] == "Zebra" }[:account_count]).to eq(0)
    end
  end

  describe "#show" do
    it "includes broker fields and nested accounts" do
      broker = create(:broker)
      create(:account, broker: broker, name: "Savings")
      create(:account, broker: broker, name: "Checking")

      result = renderer(id: broker.id).show
      expect(result[:id]).to eq(broker.id)
      expect(result[:accounts].map { |a| a[:name] }).to eq([ "Checking", "Savings" ])
      expect(result[:accounts].first.keys).to match_array(%i[id name account_number account_type])
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: 0).show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes id, name, and account_count" do
      broker = create(:broker)
      result = renderer.serialize(broker)
      expect(result.keys).to match_array(%i[id name account_count])
    end
  end
end
