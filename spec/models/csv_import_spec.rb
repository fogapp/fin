require "rails_helper"

RSpec.describe CsvImport, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:target_account).class_name("Account").optional }
    it "has an attached file" do
      expect(CsvImport.new).to respond_to(:file)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:source_filename) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, processing: 1, completed: 2, failed: 3) }
    it { is_expected.to define_enum_for(:kind).with_values(transactions: 0, holdings: 1, unknown: 2, credit_card: 3, checking: 4, spreadsheet: 5) }
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at desc" do
        old   = create(:csv_import, created_at: 2.days.ago)
        newer = create(:csv_import, created_at: 1.hour.ago)

        expect(CsvImport.recent.to_a).to eq([ newer, old ])
      end
    end
  end

  describe "#duration_seconds" do
    it "returns nil when started_at is missing" do
      import = build(:csv_import, started_at: nil, finished_at: Time.current)
      expect(import.duration_seconds).to be_nil
    end

    it "returns nil when finished_at is missing" do
      import = build(:csv_import, started_at: Time.current, finished_at: nil)
      expect(import.duration_seconds).to be_nil
    end

    it "computes elapsed seconds rounded to 2 places" do
      started = Time.current
      import  = build(:csv_import, started_at: started, finished_at: started + 12.345.seconds)

      expect(import.duration_seconds).to eq(12.35)
    end
  end
end
