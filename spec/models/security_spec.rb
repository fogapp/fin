require "rails_helper"

RSpec.describe Security, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:investment_transactions).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:market_prices).dependent(:destroy) }
    it { is_expected.to have_many(:position_snapshots).dependent(:restrict_with_error) }
  end

  describe "validations" do
    it "validates uniqueness of cusip when present" do
      create(:security, cusip: "123456789")
      duplicate = build(:security, cusip: "123456789")
      expect(duplicate).not_to be_valid
    end

    it "allows multiple securities with blank cusip" do
      create(:security, :without_cusip)
      another = build(:security, :without_cusip)
      expect(another).to be_valid
    end
  end

  describe ".with_ticker" do
    it "excludes nil and empty tickers" do
      with_ticker = create(:security, ticker: "AAPL")
      create(:security, ticker: nil, cusip: "111111111")
      create(:security, ticker: "", cusip: "222222222")

      expect(Security.with_ticker).to contain_exactly(with_ticker)
    end
  end

  describe "#display_name" do
    it "joins ticker and name with em-dash" do
      s = build(:security, ticker: "AAPL", name: "Apple Inc")
      expect(s.display_name).to eq("AAPL — Apple Inc")
    end

    it "returns just the ticker when name is blank" do
      s = build(:security, ticker: "AAPL", name: "")
      expect(s.display_name).to eq("AAPL")
    end

    it "returns just the name when ticker is blank" do
      s = build(:security, ticker: nil, name: "Apple Inc")
      expect(s.display_name).to eq("Apple Inc")
    end

    it "falls back to cusip when ticker and name are blank" do
      s = build(:security, ticker: nil, name: nil, cusip: "037833100")
      expect(s.display_name).to eq("037833100")
    end
  end

  describe ".sanitize_name" do
    it "returns nil for blank input" do
      expect(Security.sanitize_name(nil)).to be_nil
      expect(Security.sanitize_name("")).to be_nil
      expect(Security.sanitize_name("   ")).to be_nil
    end

    it "strips dividend rate suffix" do
      expect(Security.sanitize_name("MARRIOTT INTERNATIONAL -CL A @ 0.67 PER SHARE")).to eq("MARRIOTT INTERNATIONAL -CL A")
    end

    it "trims at junk tail markers" do
      expect(Security.sanitize_name("APPLE INC CORPORATE ACTION ID: ABC123")).to eq("APPLE INC")
      expect(Security.sanitize_name("FOO BAR CASH IN LIEU details")).to eq("FOO BAR")
      expect(Security.sanitize_name("XYZ STOCK SPLIT 2:1")).to eq("XYZ")
      expect(Security.sanitize_name("ACME MERGER pending")).to eq("ACME")
      expect(Security.sanitize_name("WIDGET TENDER OFFER")).to eq("WIDGET")
      expect(Security.sanitize_name("ABC SPINOFF stuff")).to eq("ABC")
      expect(Security.sanitize_name("XYZ FRACTIONAL share")).to eq("XYZ")
      expect(Security.sanitize_name("FOO EVENT: dividend")).to eq("FOO")
      expect(Security.sanitize_name("BAR CORP ACTION reorg")).to eq("BAR")
    end

    it "is case-insensitive on tail markers" do
      expect(Security.sanitize_name("Acme corporate action id: 1")).to eq("Acme")
    end

    it "returns nil for junk start patterns" do
      expect(Security.sanitize_name("TRANSFER from broker")).to be_nil
      expect(Security.sanitize_name("DEPOSIT SWEEP cash")).to be_nil
      expect(Security.sanitize_name("WIRE in")).to be_nil
      expect(Security.sanitize_name("CHECK 1234")).to be_nil
    end

    it "returns nil if trimming leaves an empty string" do
      expect(Security.sanitize_name("CORPORATE ACTION ID: 1")).to be_nil
    end
  end

  describe "#junk_name?" do
    it "returns true for blank name" do
      expect(build(:security, name: nil).junk_name?).to be(true)
      expect(build(:security, name: "").junk_name?).to be(true)
    end

    it "returns true when name contains a junk tail marker" do
      expect(build(:security, name: "APPLE CORPORATE ACTION").junk_name?).to be(true)
      expect(build(:security, name: "FOO CASH IN LIEU").junk_name?).to be(true)
    end

    it "returns true when name matches a junk start pattern" do
      expect(build(:security, name: "TRANSFER stuff").junk_name?).to be(true)
    end

    it "returns false for clean names" do
      expect(build(:security, name: "APPLE INC").junk_name?).to be(false)
    end
  end

  describe "#to_param" do
    it "returns the ticker when present" do
      expect(build(:security, ticker: "AAPL").to_param).to eq("AAPL")
    end

    it "falls back to id when ticker is blank" do
      s = create(:security, ticker: nil, cusip: "999999999")
      expect(s.to_param).to eq(s.id.to_s)
    end
  end

  describe ".find_by_param!" do
    it "finds by ticker case-insensitively" do
      s = create(:security, ticker: "AAPL")
      expect(Security.find_by_param!("aapl")).to eq(s)
    end

    it "falls back to id lookup when no ticker matches" do
      s = create(:security, ticker: nil, cusip: "999999999")
      expect(Security.find_by_param!(s.id)).to eq(s)
    end

    it "raises when neither ticker nor id matches" do
      expect { Security.find_by_param!("does-not-exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "picks the security with the most transactions on ticker collision" do
      popular = create(:security, ticker: "DUP", cusip: "111111111")
      sparse  = create(:security, ticker: "DUP", cusip: "222222222")
      create_list(:investment_transaction, 3, security: popular)
      create(:investment_transaction, security: sparse)

      expect(Security.find_by_param!("DUP")).to eq(popular)
    end
  end
end
