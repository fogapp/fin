# typed: strict

module Tax
  # The estimated-tax installment calendar for one tax year. Federal and
  # California share the same four due dates (Apr 15 / Jun 15 / Sep 15 /
  # Jan 15 of the following year); the payment-window boundaries are what
  # quarters are derived from. California weights installments 30/40/0/30
  # (the weights live in Parameters; STATE_WEIGHTS mirrors them for callers
  # without a parameter year).
  module DueDates
    extend T::Sig

    QUARTER_LABELS  = T.let(%w[Q1 Q2 Q3 Q4].freeze, T::Array[String])
    FEDERAL_WEIGHTS = T.let([ 0.25, 0.25, 0.25, 0.25 ].freeze, T::Array[Float])
    STATE_WEIGHTS   = T.let([ 0.30, 0.40, 0.0, 0.30 ].freeze, T::Array[Float])

    sig { params(year: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.for_year(year)
      [
        { label: "Q1", date: Date.new(year, 4, 15),     window: Date.new(year, 1, 1)..Date.new(year, 4, 15) },
        { label: "Q2", date: Date.new(year, 6, 15),     window: Date.new(year, 4, 16)..Date.new(year, 6, 15) },
        { label: "Q3", date: Date.new(year, 9, 15),     window: Date.new(year, 6, 16)..Date.new(year, 9, 15) },
        { label: "Q4", date: Date.new(year + 1, 1, 15), window: Date.new(year, 9, 16)..Date.new(year + 1, 1, 15) }
      ]
    end

    # The installment a payment counts toward, clamped to Q1/Q4 for
    # payments outside the year's windows (early payments and late Q4
    # catch-ups both happen in real life).
    sig { params(year: Integer, paid_on: Date).returns(String) }
    def self.quarter_for(year, paid_on)
      quarters = for_year(year)
      return "Q1" if paid_on < T.must(quarters.first).fetch(:window).first

      match = quarters.find { |q| q.fetch(:window).cover?(paid_on) }
      (match || T.must(quarters.last)).fetch(:label)
    end
  end
end
