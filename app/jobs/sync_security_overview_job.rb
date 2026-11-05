# typed: true

class SyncSecurityOverviewJob < ApplicationJob
  extend T::Sig

  include AlphaVantageRetries

  queue_as :market_data

  sig { params(security_id: String).void }
  def perform(security_id)
    with_alpha_vantage(security_id) do
      security = Security.find(security_id)
      if security.security_type == Security::CRYPTO_TYPE
        Rails.logger.info("[SyncSecurityOverviewJob] #{security.ticker}: skipping crypto security")
        next
      end
      SecurityOverviewSyncer.new(security).call
      Rails.logger.info("[SyncSecurityOverviewJob] #{security.ticker}: overview synced")
    end
  end
end
