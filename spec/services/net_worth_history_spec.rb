require "rails_helper"

RSpec.describe NetWorthHistory do
  let(:broker) { create(:broker) }

  def snap(account, time, amount)
    AccountBalanceSnapshot.create!(
      account: account, balance: amount, balance_currency: "USD",
      balance_usd: amount, source: "scheduled", recorded_at: time
    )
  end

  describe "series construction" do
    it "buckets accounts into groups, carries snapshots forward, and uses live balances today" do
      checking = create(:account, broker: broker, account_type: "Checking",    balance: 1200, balance_usd: 1200)
      card     = create(:account, broker: broker, account_type: "Credit Card", balance: 300,  balance_usd: 300)
      snap(checking, 10.days.ago, 1000)
      snap(card,     10.days.ago, 250)

      result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call

      mid = result[:series].find { |r| r[:date] == 5.days.ago.to_date.iso8601 }
      expect(mid[:cash]).to eq(1000.0)
      expect(mid[:credit]).to eq(-250.0)
      expect(mid[:net]).to eq(750.0)

      today = result[:series].last
      expect(today[:date]).to eq(Date.current.iso8601)
      expect(today[:cash]).to eq(1200.0)
      expect(today[:credit]).to eq(-300.0)
      expect(today[:net]).to eq(900.0)

      expect(result[:stats][:net_worth]).to eq(900.0)
      expect(result[:stats][:assets]).to eq(1200.0)
      expect(result[:stats][:liabilities]).to eq(300.0)
    end

    it "contributes nothing before an account's first snapshot" do
      account = create(:account, broker: broker, account_type: "Checking", balance: 500, balance_usd: 500)
      snap(account, 2.days.ago, 500)

      result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call
      first = result[:series].first
      expect(first[:cash]).to eq(0.0)
      expect(first[:net]).to eq(0.0)
    end

    it "excludes hidden accounts" do
      create(:account, broker: broker, account_type: "Checking", balance: 999, balance_usd: 999, hidden: true)

      result = described_class.new.call
      expect(result[:stats][:net_worth]).to eq(0.0)
      expect(result[:accounts]).to be_empty
    end
  end

  describe "investment accounts" do
    it "values accounts with position snapshots from positions, not balance snapshots" do
      account = create(:account, broker: broker, account_type: "Brokerage", balance: 999_999, balance_usd: 999_999)
      create(:position_snapshot, account: account, quantity: 10, price: 100, market_value: 1000)

      result = described_class.new.call
      expect(result[:stats][:investments]).to eq(1000.0)
      expect(result[:stats][:cash]).to eq(0.0)
      expect(result[:stats][:net_worth]).to eq(1000.0)

      breakdown = result[:accounts].find { |a| a[:id] == account.id }
      expect(breakdown[:group]).to eq("investments")
      expect(breakdown[:value]).to eq(1000.0)
    end
  end

  describe "loans" do
    it "replays payments for loans without a linked account" do
      # 12% APR → 1% monthly. First payment: 1000 interest, 1000 principal.
      loan = create(:loan, original_principal: 100_000, interest_rate: 12.0,
                           start_date: 60.days.ago.to_date)
      create(:cash_transaction, loan: loan, amount: -2000, transaction_date: 30.days.ago.to_date)

      result = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call
      expect(result[:stats][:loans]).to eq(99_000.0)
      expect(result[:stats][:net_worth]).to eq(-99_000.0)
      expect(result[:series].last[:loans]).to eq(-99_000.0)

      breakdown = result[:loans].find { |l| l[:id] == loan.id }
      expect(breakdown[:value]).to eq(99_000.0)
    end

    it "values loans linked to a visible account from that account's balance, without double-counting" do
      account = create(:account, broker: broker, account_type: "Other", name: "MORTGAGE LOAN",
                                 balance: 250_000, balance_usd: 250_000)
      create(:loan, account: account, original_principal: 300_000)

      result = described_class.new.call
      expect(result[:stats][:loans]).to eq(250_000.0)
      expect(result[:stats][:net_worth]).to eq(-250_000.0)
      expect(result[:loans]).to be_empty

      breakdown = result[:accounts].find { |a| a[:id] == account.id }
      expect(breakdown[:group]).to eq("loans")
    end

    it "classifies untyped accounts with loan-like names as loans" do
      account = create(:account, broker: broker, account_type: "Other", name: "Home Loan ...1234",
                                 balance: 50_000, balance_usd: 50_000)
      snap(account, 1.day.ago, 50_000)

      result = described_class.new.call
      expect(result[:stats][:loans]).to eq(50_000.0)
      expect(result[:accounts].find { |a| a[:id] == account.id }[:group]).to eq("loans")
    end
  end

  describe "breakdown baselines" do
    it "reports a nil start_value when the account had no data at range start" do
      account = create(:account, broker: broker, account_type: "Checking", balance: 5_000, balance_usd: 5_000)
      snap(account, 2.days.ago, 5_000)

      row = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call[:accounts]
        .find { |a| a[:id] == account.id }

      # nil, not 0.0 — the UI must be able to withhold a percent rather than
      # render "history began this week" as infinite growth from zero.
      expect(row[:start_value]).to be_nil
      expect(row[:change]).to eq(5_000.0)
      expect(row[:change_pct]).to be_nil
    end

    it "reports the real start_value when history covers the window" do
      account = create(:account, broker: broker, account_type: "Checking", balance: 5_000, balance_usd: 5_000)
      snap(account, 4.months.ago, 4_000)

      row = described_class.new(range: NetWorthHistory::RangeKey::ThreeMonths).call[:accounts]
        .find { |a| a[:id] == account.id }

      expect(row[:start_value]).to eq(4_000.0)
      expect(row[:change]).to eq(1_000.0)
      expect(row[:change_pct]).to eq(25.0)
    end
  end

  describe "ranges and sampling" do
    it "defaults to 1y with daily samples" do
      result = described_class.new(range: nil).call
      expect(result[:range]).to eq(NetWorthHistory::RangeKey::OneYear)
      expect(result[:series].size).to be_within(2).of(366)
    end

    it "rejects raw strings — ranges deserialize at the controller boundary" do
      expect { described_class.new(range: "bogus") }.to raise_error(TypeError)
    end

    it "honors an explicit from/to window that ends in the past" do
      checking = create(:account, broker: broker, account_type: "Checking", balance: 1500, balance_usd: 1500)
      snap(checking, Time.zone.local(2025, 1, 10, 12), 1000)
      snap(checking, Time.zone.local(2025, 6, 10, 12), 1200)

      travel_to(Time.zone.local(2026, 3, 15, 12)) do
        result = described_class.new(from: Date.new(2025, 1, 1), to: Date.new(2025, 12, 31)).call
        dates = result[:series].map { |r| Date.parse(r[:date]) }
        expect(dates.first).to eq(Date.new(2025, 1, 1))
        expect(dates.last).to eq(Date.new(2025, 12, 31))
        expect(result[:from]).to eq(Date.new(2025, 1, 1))
        expect(result[:to]).to eq(Date.new(2025, 12, 31))

        # The breakdown compares the window's end to its start, not to today…
        row = result[:accounts].find { |a| a[:id] == checking.id }
        expect(row).to include(value: 1200.0, start_value: nil)
        # …while the headline stats stay anchored to today's live balance.
        expect(result[:stats][:net_worth]).to eq(1500.0)
      end
    end

    it "clamps a window end past today to today" do
      result = described_class.new(from: 10.days.ago.to_date, to: 10.days.from_now.to_date).call
      expect(result[:to]).to eq(Date.current)
      expect(result[:series].last[:date]).to eq(Date.current.iso8601)
      expect(result[:series].size).to eq(11)
    end

    it "samples weekly when the all range spans years" do
      create(:loan, start_date: 3.years.ago.to_date)

      result = described_class.new(range: NetWorthHistory::RangeKey::All).call
      dates = result[:series].map { |r| Date.parse(r[:date]) }
      expect(dates.first).to eq(3.years.ago.to_date)
      expect((dates[-1] - dates[-2]).to_i).to eq(7)
    end
  end

  describe "stats and monthly deltas" do
    it "computes changes against historical anchors" do
      account = create(:account, broker: broker, account_type: "Checking", balance: 1200, balance_usd: 1200)
      snap(account, 45.days.ago, 1000)

      result = described_class.new.call
      expect(result[:stats][:changes]["1m"]).to eq({ amount: 200.0, pct: 20.0 })
      # No data 1 year ago → change is the full current net worth, pct undefined
      expect(result[:stats][:changes]["1y"]).to eq({ amount: 1200.0, pct: nil })
    end

    it "returns one delta per month for the trailing year" do
      result = described_class.new.call
      expect(result[:monthly_deltas].size).to eq(12)
      expect(result[:monthly_deltas].last[:month]).to eq(Date.current.strftime("%Y-%m"))
    end
  end
end
