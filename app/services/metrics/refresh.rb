# typed: strict

module Metrics
  # Nightly maintenance for the metric_points store, per household:
  #
  #   - a registered metric with no stored points gets a full backfill (this
  #     is how newly added definitions self-onboard — register the class and
  #     the next nightly run produces its history)
  #   - everything else gets a trailing-window recompute: 3 months for
  #     monthly metrics, 35 days for daily ones, absorbing late-arriving or
  #     edited transactions and settling snapshots/prices
  #
  # One failing definition logs and moves on — a broken metric must not
  # block the rest of the sweep.
  class Refresh
    extend T::Sig

    TRAILING_MONTHS = 3
    TRAILING_DAYS   = 35

    sig { void }
    def call
      household = Current.household!

      Metrics::Registry.all.each do |definition_class|
        if MetricPoint.for_key(definition_class.key).none?
          Backfill.new.call(definition_class)
        else
          refresh_trailing(definition_class)
        end
      rescue StandardError => e
        Rails.logger.error("[Metrics::Refresh] #{definition_class.key} failed for household=#{household.id}: #{e.class}: #{e.message}")
      end
    end

    private

    sig { params(definition_class: T.class_of(Definition)).void }
    def refresh_trailing(definition_class)
      today = Date.current
      from = if definition_class.granularity == Metrics::Granularity::Month
        (today << (TRAILING_MONTHS - 1)).beginning_of_month
      else
        today - TRAILING_DAYS
      end

      Store.write!(definition_class, from: from, to: today)
    end
  end
end
