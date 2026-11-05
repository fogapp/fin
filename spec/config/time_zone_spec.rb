require "rails_helper"

# Pins the app's day/month-boundary semantics after the switch from UTC to
# America/Los_Angeles (perf/reliability audit finding #10). At 6pm PT on
# July 31 the UTC calendar has already flipped to August 1; every "which
# day/month is it" decision must side with the household's local calendar.
RSpec.describe "Application time zone" do
  it "runs in America/Los_Angeles" do
    expect(Time.zone.name).to eq("America/Los_Angeles")
  end

  it "keeps evening activity in the local month (6pm PT July 31 is still July)" do
    travel_to Time.zone.local(2026, 7, 31, 18, 0, 0) do
      expect(Time.current.utc.to_date).to eq(Date.new(2026, 8, 1)) # UTC already flipped...
      expect(Date.current).to eq(Date.new(2026, 7, 31))            # ...but the app has not
      expect(Date.current.month).to eq(7)
    end
  end

  it "books a UTC-stamped provider timestamp to the local trade date" do
    # A Coinbase trade at 6:30pm PT July 31 arrives as 2026-08-01T01:30:00Z;
    # Date.parse would have booked it to August.
    expect(Time.zone.parse("2026-08-01T01:30:00Z").to_date).to eq(Date.new(2026, 7, 31))
  end

  it "buckets balance snapshots by local day, matching .record's same-day dedup" do
    account = create(:account)

    travel_to Time.zone.local(2026, 7, 31, 15, 0, 0) do # 22:00 UTC Jul 31
      AccountBalanceSnapshot.record(account, source: AccountBalanceSnapshot::Source::Manual, balance: 100, balance_usd: 100)
    end
    travel_to Time.zone.local(2026, 7, 31, 18, 0, 0) do # 01:00 UTC Aug 1
      # Same local day but a different UTC day — must update in place, and
      # daily_series must report one July 31 bucket, not a spurious Aug 1 row.
      AccountBalanceSnapshot.record(account, source: AccountBalanceSnapshot::Source::Manual, balance: 150, balance_usd: 150)
    end

    expect(AccountBalanceSnapshot.where(account_id: account.id).count).to eq(1)

    series = AccountBalanceSnapshot.daily_series(account.id).to_a
    expect(series.size).to eq(1)
    expect(series.first.attributes["date"].to_date).to eq(Date.new(2026, 7, 31))
    expect(series.first.balance_usd).to eq(150)
  end
end
