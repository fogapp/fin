require "rails_helper"

RSpec.describe MarketData::Downsample do
  describe ".weekly_beyond_window" do
    it "keeps rows inside the daily window untouched" do
      rows = (0..5).map { |i| [ Date.current - i, 10.0 + i ] }.reverse
      expect(described_class.weekly_beyond_window(rows)).to eq(rows)
    end

    it "thins rows beyond the window to one per week, keeping the week's last row" do
      old_start = Date.current - described_class::DAILY_WINDOW_DAYS - 28
      old_rows = (0..27).map { |i| [ old_start + i, 1.0 + i ] }
      recent   = [ [ Date.current, 99.0 ] ]

      result = described_class.weekly_beyond_window(old_rows + recent)

      old_kept = result[0..-2]
      expect(old_kept.length).to be_between(4, 5)
      # Each kept row is the last of its ISO week.
      expect(old_kept.map { |d, _| [ d.cwyear, d.cweek ] }.uniq.length).to eq(old_kept.length)
      expect(old_kept.map(&:first)).to eq(old_kept.map(&:first).sort)
      expect(result.last).to eq([ Date.current, 99.0 ])
    end
  end
end
