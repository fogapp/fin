# typed: strict

module Workflows
  module Actions
    # Enqueues one of the allowlisted sync jobs.
    class TriggerSync
      extend T::Sig

      TARGETS = T.let(%w[plaid coinbase alchemy alchemy_transactions
                         market_prices crypto_prices
                         security_news system_audit reconciliation fx_rates
                         recurring_detection].freeze, T::Array[String])

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        target = params["target"].to_s
        return { status: :error, error: "unknown sync target: #{target.inspect}" } unless TARGETS.include?(target)

        case target
        when "plaid"         then PlaidSyncJob.perform_later
        when "coinbase"      then CoinbaseSyncJob.perform_later(run.household_id)
        when "alchemy"       then AlchemySyncJob.perform_later(run.household_id)
        when "alchemy_transactions" then ::Alchemy::TransactionSyncJob.perform_later(run.household_id)
        when "market_prices" then MarketPriceSyncJob.perform_later
        when "crypto_prices" then SyncCryptoPricesJob.perform_later(run.household_id)
        when "security_news" then SyncSecurityNewsJob.perform_later
        when "system_audit"  then SystemAuditJob.perform_later
        when "reconciliation" then Reconciliation::SweepJob.perform_later
        when "fx_rates"      then MarketData::FxSyncJob.perform_later
        when "recurring_detection" then Recurring::DetectJob.perform_later(household_id: run.household_id)
        end

        { status: :applied, target: target }
      end
    end
  end
end
