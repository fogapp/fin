require "rails_helper"

RSpec.describe CorporateAction do
  describe ".share_split_ratio?" do
    # Real ratios from production's corporate_actions.
    it "accepts genuine share splits" do
      [ 2.0, 4.0, 5.0, 10.0, 25.0, 1.5, 0.1, 0.5 ].each do |ratio|
        expect(described_class.share_split_ratio?(ratio)).to be(true), ratio.to_s
      end
    end

    it "rejects spin-off price adjustments filed as splits" do
      [ 1.061, 0.9535, 1.327, 1.241 ].each do |ratio|
        expect(described_class.share_split_ratio?(ratio)).to be(false), ratio.to_s
      end
    end

    it "rejects no-ops and nonsense" do
      [ 1.0, 0, -2, nil, 101.0 ].each do |ratio|
        expect(described_class.share_split_ratio?(ratio)).to be(false), ratio.inspect
      end
    end
  end

  it "only treats split rows as share splits" do
    security = create(:security)
    split    = described_class.new(security: security, kind: "split", ratio: 4, ex_date: Date.current, source: "tiingo")
    spinoff  = described_class.new(security: security, kind: "split", ratio: 1.061, ex_date: Date.current, source: "tiingo")

    expect([ split.share_split?, spinoff.share_split? ]).to eq([ true, false ])
  end
end
