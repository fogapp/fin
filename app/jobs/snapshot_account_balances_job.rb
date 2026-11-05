# typed: true

class SnapshotAccountBalancesJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    Account.where.not(balance: nil).find_each do |account|
      AccountBalanceSnapshot.record(account, source: AccountBalanceSnapshot::Source::Scheduled)
    rescue => e
      Rails.logger.error("[SnapshotAccountBalancesJob] account=#{account.id} failed: #{e.message}")
    end
  end
end
