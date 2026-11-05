# typed: true

module MarketData
  # Daily second-source price verification, after the 5:00am candle sync so
  # it compares today's freshly written series.
  class CrossCheckJob < ApplicationJob
    extend T::Sig

    queue_as :market_data
    limits_concurrency to: 1, key: -> { "market_data_cross_check" }

    sig { void }
    def perform
      result = MarketData::CrossCheck.run
      Rails.logger.info(
        "[MarketData::CrossCheckJob] checked=#{result.checked} clean=#{result.clean} " \
        "mismatched=#{result.mismatched} skipped=#{result.skipped}"
      )
    end
  end
end
