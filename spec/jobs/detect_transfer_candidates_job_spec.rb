require "rails_helper"

RSpec.describe DetectTransferCandidatesJob, type: :job do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }

  def cash_txn(account:, amount:)
    create(:cash_transaction, :bank, account: account, amount: amount)
  end

  def build_result(from_txn, to_txn, amount: from_txn.amount.abs)
    TransferCandidateService::Result.new(
      from_transaction: from_txn,
      from_type:        "CashTransaction",
      to_transaction:   to_txn,
      to_type:          "CashTransaction",
      amount:           amount,
      date_diff:        0
    )
  end

  let(:service) { instance_double(TransferCandidateService) }

  before { allow(TransferCandidateService).to receive(:new).and_return(service) }

  describe "#perform" do
    context "when there are matched pairs" do
      it "creates Transfer records for each matched pair" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        result   = build_result(from_txn, to_txn)

        allow(service).to receive(:candidates).and_return([ result ])

        expect { described_class.perform_now }
          .to change(Transfer, :count).by(1)

        transfer = Transfer.last
        expect(transfer.from_transaction_id).to eq(from_txn.id)
        expect(transfer.to_transaction_id).to eq(to_txn.id)
        expect(transfer.amount).to eq(500.0)
        expect(transfer.confirmed_at).to be_nil
      end
    end

    context "when from_transaction is already in any Transfer" do
      it "skips the pair" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        other    = cash_txn(account: account_b, amount: 100.00)

        # Create an existing transfer that includes from_txn
        Transfer.create!(
          from_transaction_id:   from_txn.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     other.id,
          to_transaction_type:   "CashTransaction",
          amount:                500.00
        )

        result = build_result(from_txn, to_txn)
        allow(service).to receive(:candidates).and_return([ result ])

        expect { described_class.perform_now }.not_to change(Transfer, :count)
      end
    end

    context "when to_transaction is already in any Transfer" do
      it "skips the pair" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        other    = cash_txn(account: account_a, amount: -100.00)

        # Create an existing transfer that includes to_txn
        Transfer.create!(
          from_transaction_id:   other.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     to_txn.id,
          to_transaction_type:   "CashTransaction",
          amount:                100.00
        )

        result = build_result(from_txn, to_txn)
        allow(service).to receive(:candidates).and_return([ result ])

        expect { described_class.perform_now }.not_to change(Transfer, :count)
      end
    end

    context "on RecordNotUnique" do
      it "does not raise" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        result   = build_result(from_txn, to_txn)

        allow(service).to receive(:candidates).and_return([ result ])
        allow(Transfer).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect { described_class.perform_now }.not_to raise_error
      end
    end

    context "on RecordInvalid" do
      it "skips the bad candidate and still processes the rest of the run" do
        bad_from  = cash_txn(account: account_a, amount: -500.00)
        bad_to    = cash_txn(account: account_b, amount: 500.00)
        good_from = cash_txn(account: account_a, amount: -75.00)
        good_to   = cash_txn(account: account_b, amount: 75.00)

        allow(service).to receive(:candidates).and_return([
          build_result(bad_from, bad_to),
          build_result(good_from, good_to)
        ])
        raised = false
        allow(Transfer).to receive(:create!).and_wrap_original do |m, *args, **kwargs|
          unless raised
            raised = true
            raise ActiveRecord::RecordInvalid.new(Transfer.new)
          end
          m.call(*args, **kwargs)
        end

        expect { described_class.perform_now }
          .to change(Transfer, :count).by(1)
          .and change(ActivityEntry, :count).by(1) # summary still recorded

        expect(Transfer.last.from_transaction_id).to eq(good_from.id)
      end
    end

    context "removing stale unconfirmed candidates" do
      it "destroys an unconfirmed Transfer whose from_transaction now has a transfer_id" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)

        stale = Transfer.create!(
          from_transaction_id:   from_txn.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     to_txn.id,
          to_transaction_type:   "CashTransaction",
          amount:                500.00
        )

        # Simulate that from_txn is now linked elsewhere (transfer_id is set)
        from_txn.update_columns(transfer_id: stale.id)

        allow(service).to receive(:candidates).and_return([])

        expect { described_class.perform_now }
          .to change(Transfer, :count).by(-1)
        expect(Transfer.exists?(stale.id)).to be false
      end

      it "preserves confirmed Transfers regardless of transaction transfer_id state" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)

        confirmed = Transfer.create!(
          from_transaction_id:   from_txn.id,
          from_transaction_type: "CashTransaction",
          to_transaction_id:     to_txn.id,
          to_transaction_type:   "CashTransaction",
          amount:                500.00,
          confirmed_at:          Time.current
        )
        # Even with transfer_id set, confirmed transfers are not in Transfer.candidates scope
        from_txn.update_columns(transfer_id: confirmed.id)

        allow(service).to receive(:candidates).and_return([])

        expect { described_class.perform_now }.not_to change(Transfer, :count)
        expect(Transfer.exists?(confirmed.id)).to be true
      end

      it "destroys an unconfirmed Transfer whose leg was deleted, keeping healthy ones" do
        gone     = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        stale = Transfer.create!(from_transaction_id: gone.id, from_transaction_type: "CashTransaction",
                                 to_transaction_id: to_txn.id, to_transaction_type: "CashTransaction", amount: 500.00)
        gone.delete

        healthy_from = cash_txn(account: account_a, amount: -75.00)
        healthy = Transfer.create!(counterparty_account: account_b, amount: 75.00,
                                   from_transaction_id: healthy_from.id, from_transaction_type: "CashTransaction")

        allow(service).to receive(:candidates).and_return([])

        described_class.perform_now

        expect(Transfer.exists?(stale.id)).to be false
        expect(Transfer.exists?(healthy.id)).to be true
      end
    end

    context "when two matched pairs share a leg" do
      it "creates only the first, without re-querying transfers per candidate" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_one   = cash_txn(account: account_b, amount: 500.00)
        to_two   = cash_txn(account: account_b, amount: 500.00)
        allow(service).to receive(:candidates)
          .and_return([ build_result(from_txn, to_one), build_result(from_txn, to_two) ])

        queries = count_queries { described_class.perform_now }

        expect(Transfer.pluck(:to_transaction_id)).to eq([ to_one.id ])
        expect(queries.grep(/SELECT 1 AS one FROM "transfers"/)).to be_empty
      end
    end

    context "when the pair was previously dismissed" do
      it "does not recreate the candidate, in either orientation" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)

        TransferDismissal.create!(
          from_transaction_type: "CashTransaction", from_transaction_id: to_txn.id,
          to_transaction_type:   "CashTransaction", to_transaction_id:   from_txn.id,
          household_id: from_txn.household_id
        )
        allow(service).to receive(:candidates).and_return([ build_result(from_txn, to_txn) ])

        expect { described_class.perform_now }.not_to change(Transfer, :count)
      end

      it "still creates candidates pairing those transactions with other partners" do
        from_txn = cash_txn(account: account_a, amount: -500.00)
        to_txn   = cash_txn(account: account_b, amount: 500.00)
        other    = cash_txn(account: account_b, amount: 500.00)

        # (from, other) was dismissed; (from, to) is a fresh suggestion.
        TransferDismissal.create!(
          from_transaction_type: "CashTransaction", from_transaction_id: from_txn.id,
          to_transaction_type:   "CashTransaction", to_transaction_id:   other.id,
          household_id: from_txn.household_id
        )
        allow(service).to receive(:candidates).and_return([ build_result(from_txn, to_txn) ])

        expect { described_class.perform_now }.to change(Transfer, :count).by(1)
        expect(Transfer.last.to_transaction_id).to eq(to_txn.id)
      end
    end
  end
end
