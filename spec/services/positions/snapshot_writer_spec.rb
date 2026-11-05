require "rails_helper"

RSpec.describe Positions::SnapshotWriter do
  let(:account)   { create(:account) }
  let(:security)  { create(:security) }
  let(:household) { account.household }
  let(:writer)    { described_class.new(prefix: "src", household_id: household.id, as_of: Date.new(2026, 9, 1)) }

  describe "#upsert!" do
    it "keys the row by prefix and parts, and updates it in place on the next sync" do
      writer.upsert!([ "w1", security.id ], account_id: account.id, security: security, quantity: 2, price: 5, market_value: 10)
      writer.upsert!([ "w1", security.id ], account_id: account.id, security: security, quantity: 3, price: 5, market_value: 15)

      snap = PositionSnapshot.find_by!(source_row_hash: "src:w1:#{security.id}")
      expect([ snap.quantity, snap.as_of_date, snap.household_id ]).to eq([ 3, Date.new(2026, 9, 1), household.id ])
      expect(writer.seen).to eq(Set["src:w1:#{security.id}"])
    end
  end

  describe "#zero_stamp_missing!" do
    def snapshot(hash, account: self.account, cost_basis: 900)
      create(:position_snapshot, account: account, source_row_hash: hash, quantity: 4, cost_basis: cost_basis,
                                 household_id: household.id)
    end

    it "zeroes rows under the swept ids that this sync didn't report" do
      reported = snapshot("src:w1:a")
      gone     = snapshot("src:w1:b")
      other    = snapshot("src:w2:c")
      writer.upsert!([ "w1", "a" ], account_id: account.id, security: reported.security, quantity: 4, price: 1, market_value: 4)

      writer.zero_stamp_missing!(under: [ "w1" ])

      expect([ reported, gone, other ].map { |s| s.reload.quantity }).to eq([ 4, 0, 4 ])
      expect(gone.reload.as_of_date).to eq(Date.new(2026, 9, 1))
      expect(gone.cost_basis).to eq(900)
    end

    it "clears cost basis when asked and leaves skipped accounts alone" do
      skipped_account = create(:account)
      gone    = snapshot("src:w1:b")
      skipped = snapshot("src:w1:d", account: skipped_account)

      writer.zero_stamp_missing!(under: [ "w1" ], skip_account_ids: [ skipped_account.id ], clear_cost_basis: true)

      expect([ gone.reload.quantity, gone.cost_basis ]).to eq([ 0, nil ])
      expect(skipped.reload.quantity).to eq(4)
    end
  end

  describe ".set_holdings_balance!" do
    it "writes the rounded USD balance and records a balance snapshot" do
      described_class.set_holdings_balance!(account, BigDecimal("123.456"), source: AccountBalanceSnapshot::Source::AlchemySync)

      expect(account.reload.balance_usd).to eq(BigDecimal("123.46"))
      expect(AccountBalanceSnapshot.where(account: account).pluck(:balance)).to eq([ BigDecimal("123.46") ])
    end
  end
end
