# typed: strict

module Api
  module Render
    # A small status panel derived from the activity timeline plus queue
    # counts: last run per source, backlog, and workflow failure rate.
    class SystemHealth < Api::Render::Base
      extend T::Sig

      SOURCES = T.let(%w[
        plaid_sync coinbase_sync market_prices crypto_prices
        import transfer_detection recurring_detection system_audit
      ].freeze, T::Array[String])

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        latest = ::ActivityEntry
          .select("DISTINCT ON (source) *")
          .where(source: SOURCES)
          .order("source, occurred_at DESC")

        week_runs = ::WorkflowRun.where(created_at: 7.days.ago..)

        {
          sources: latest.map { |e|
            { source:      e.source,
              event:       e.event,
              severity:    e.severity,
              summary:     e.summary,
              occurred_at: e.occurred_at.iso8601,
              duration_ms: e.duration_ms }
          },
          workflows: {
            runs_7d:    week_runs.count,
            failed_7d:  week_runs.where(status: ::WorkflowRun::Status::Failed).count,
            waiting:    ::WorkflowRun.where(status: ::WorkflowRun::Status::Waiting).count
          },
          errors_24h: ::ActivityEntry.errors.where(occurred_at: 24.hours.ago..).count,
          market_data: market_data_health
        }
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def market_data_health
        links = ::InstrumentDataLink.enabled.group(:provider).count
        failing_links = ::InstrumentDataLink.enabled.where("consecutive_failures > 0")
        failing = failing_links.group(:provider).count
        # A concrete example error per provider so "failing" is explainable:
        # the most recently attempted failing link's error, one row per
        # provider straight from Postgres rather than loading every failing
        # link and grouping in Ruby.
        failing_samples = failing_links.where.not(last_error: nil)
                                       .select("DISTINCT ON (provider) provider, last_error")
                                       .order("provider, last_attempt_at DESC")
                                       .to_h { |link| [ link.provider, link.last_error&.truncate(140) ] }

        {
          providers: links.map { |provider, count|
            { provider: provider, instruments: count,
              failing: failing[provider] || 0,
              last_error: failing_samples[provider] }
          },
          stale_held_instruments: stale_held_instruments,
          open_drift_findings: ::Issue.active.where("key LIKE 'reconciliation:%'").count
        }
      end

      # > 5 days: weekends and market holidays make 2-3 day old EOD prices
      # normal, not stale. Freshness precedence matches
      # MarketData::PriceSeries.latest_quote (quote, then newest candle,
      # then legacy market_prices) but batched — the per-security
      # latest_quote calls were a 1-3 query N+1 over every held instrument.
      sig { returns(Integer) }
      def stale_held_instruments
        held = ::Positions::CurrentPositions.new.relation.distinct.pluck(:security_id)
        quote_as_of  = ::InstrumentQuote.where(security_id: held).pluck(:security_id, :as_of).to_h
        candle_dates = ::Candle.daily.where(security_id: held).group(:security_id).maximum(:date)
        legacy_dates = ::MarketPrice.where(security_id: held).group(:security_id).maximum(:date)
        held.count { |id|
          as_of = quote_as_of[id] || candle_dates[id]&.to_time || legacy_dates[id]&.to_time
          as_of.nil? || ((Time.current - as_of) / 1.day).floor > 5
        }
      end
    end
  end
end
