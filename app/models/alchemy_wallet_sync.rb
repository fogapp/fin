# typed: true

# Transaction-sync state for one (wallet, network) pair: the incremental
# head cursor (last_synced_block) plus resumable backfill progress. Created
# lazily the first time the syncer sees a pair; on first sight the cursor is
# pinned to the safe head and history is handed to the backfill job, so the
# two never contend.
class AlchemyWalletSync < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  belongs_to :alchemy_wallet

  class BackfillStatus < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Pending   = new("pending")
      Running   = new("running")
      Completed = new("completed")
      Failed    = new("failed")
    end
  end

  typed_enum :backfill_status, BackfillStatus

  validates :network, presence: true,
                      inclusion: { in: AlchemyWallet::SUPPORTED_NETWORKS },
                      uniqueness: { scope: :alchemy_wallet_id }

  sig { returns(T::Boolean) }
  def backfill_completed? = backfill_status == BackfillStatus::Completed
end
