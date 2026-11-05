require "rails_helper"

RSpec.describe Tax::Parameters do
  describe ".figures_status" do
    it "marks federal 2026 and CA 2025 final, CA 2026 projected" do
      expect(described_class.figures_status(:federal, 2026)).to eq(:final)
      expect(described_class.figures_status(:california, 2025)).to eq(:final)
      expect(described_class.figures_status(:california, 2026)).to eq(:projected)
    end
  end

  describe "lookup" do
    it "raises Missing for an unregistered year" do
      expect { described_class.federal(2024) }.to raise_error(Tax::Parameters::Missing)
      expect { described_class.california(2030) }.to raise_error(Tax::Parameters::Missing)
    end

    it "carries CA 2026 with the same figures as CA 2025" do
      expect(described_class.california(2026).except(:figures_status))
        .to eq(described_class.california(2025).except(:figures_status))
    end

    it "doubles every single bracket top for CA MFJ" do
      brackets = described_class.california(2025).fetch(:ordinary_brackets)
      singles = brackets[Tax::FilingStatus::Single].map(&:last).compact
      mfj     = brackets[Tax::FilingStatus::Mfj].map(&:last).compact
      expect(mfj).to eq(singles.map { |top| top * 2 })
    end

    it "keys every per-status table by Tax::FilingStatus" do
      %i[ordinary_brackets ltcg_brackets standard_deduction].each do |table|
        expect(described_class.federal(2026).fetch(table).keys)
          .to contain_exactly(*Tax::FilingStatus.values)
      end
      expect(described_class.california(2025).fetch(:standard_deduction).keys)
        .to contain_exactly(*Tax::FilingStatus.values)
    end
  end
end
