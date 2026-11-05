# typed: strict

module Recurring
  # A user-created subscription: born active and accepted, optionally
  # adopting an existing transaction as its first payment — and any earlier
  # charges of the same stream as its history — with its first pending
  # occurrence projected from the schedule after the latest of them. Everything happens in one
  # transaction — a failure adopting the transaction or scheduling the first
  # occurrence must not leave a half-created series behind.
  class CreateManualSeries
    extend T::Sig

    sig do
      params(attributes: T::Hash[T.untyped, T.untyped], schedule: Recurring::Schedule,
             adopted: T.nilable(CashTransaction), history: T::Array[CashTransaction]).returns(RecurringSeries)
    end
    def self.call(attributes:, schedule:, adopted: nil, history: [])
      new(attributes: attributes, schedule: schedule, adopted: adopted, history: history).call
    end

    sig do
      params(attributes: T::Hash[T.untyped, T.untyped], schedule: Recurring::Schedule,
             adopted: T.nilable(CashTransaction), history: T::Array[CashTransaction]).void
    end
    def initialize(attributes:, schedule:, adopted: nil, history: [])
      @attributes = T.let(attributes.to_h.with_indifferent_access, ActiveSupport::HashWithIndifferentAccess)
      @schedule   = schedule
      # One charge per date (an occurrence is keyed by its date), oldest
      # first; the explicitly adopted row wins its date.
      charges = ([ adopted ].compact + history).uniq(&:id).uniq(&:transaction_date)
      @charges = T.let(charges.sort_by(&:transaction_date), T::Array[CashTransaction])
    end

    sig { returns(RecurringSeries) }
    def call
      latest = @charges.last
      next_expected = latest ? @schedule.advance(latest.transaction_date) : @schedule.next_on_or_after(Date.current)

      series = RecurringSeries.new(@attributes.merge(
        status: RecurringSeries::Status::Active, source: RecurringSeries::Source::Manual, accepted_at: Time.current,
        series_key: series_key,
        next_expected_date: next_expected
      ))
      ActiveRecord::Base.transaction do
        series.save!
        @charges.each { |charge| series.adopt_transaction!(charge) }
        first = @charges.first
        series.update!(first_charge_date: first.transaction_date) if first
        series.recurring_occurrences.create!(
          expected_date: next_expected, status: RecurringOccurrence::Status::Upcoming,
          expected_amount: series.average_amount
        )
      end
      series
    end

    private

    # Same key format Recurring::Detector groups by (merchant, else
    # normalized description), suffixed when that key is already taken.
    sig { returns(String) }
    def series_key
      base = if @attributes[:merchant_id].present?
        "merchant:#{@attributes[:merchant_id]}"
      elsif @attributes[:description_pattern].present?
        "desc:#{Recurring::Normalizer.normalize(@attributes[:description_pattern])}"
      end
      return "manual:#{SecureRandom.hex(6)}" if base.nil?

      RecurringSeries.exists?(series_key: base) ? "#{base}:manual:#{SecureRandom.hex(4)}" : base
    end
  end
end
