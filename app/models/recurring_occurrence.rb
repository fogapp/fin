# typed: true

# One expected or observed charge of a RecurringSeries. Doubles as evidence
# (paid rows link the matched transaction), forecast (upcoming/due), and the
# missed-payment signal (missed). "skipped" is a user action: don't count
# this gap against the series.
class RecurringOccurrence < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # /review counts paid-like occurrences from the DataVersion cache, so
  # attach/skip/pay transitions must rotate it.
  include BumpsHouseholdDataVersion

  # Occurrence state: settled evidence (Paid/PaidAmountChanged), forecast
  # (Upcoming/Due), missed-payment signal (Missed), or a user-waived gap
  # (Skipped).
  class Status < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Paid = new("paid")
      PaidAmountChanged = new("paid_amount_changed")
      Upcoming = new("upcoming")
      Due = new("due")
      Missed = new("missed")
      Skipped = new("skipped")
    end
  end

  PAID_STATUSES = T.let([ Status::Paid, Status::PaidAmountChanged ].freeze, T::Array[Status])
  PENDING_STATUSES = T.let([ Status::Upcoming, Status::Due ].freeze, T::Array[Status])

  belongs_to :recurring_series, counter_cache: :occurrences_count
  belongs_to :cash_transaction, optional: true

  typed_enum :status, Status

  validates :expected_date, presence: true, uniqueness: { scope: :recurring_series_id }

  scope :paid_like, -> { where(status: PAID_STATUSES) }
  scope :pending,   -> { where(status: PENDING_STATUSES) }
  scope :missed,    -> { where(status: Status::Missed) }
  scope :chronological, -> { order(:expected_date) }

  before_validation :inherit_household, on: :create

  # Unlink the matched transaction. The row reverts to forecast state:
  # a still-future date becomes upcoming again; a past one counts as
  # missed, since detaching says "that charge wasn't this subscription".
  sig { void }
  def detach!
    update!(
      cash_transaction_id: nil, charged_date: nil, amount: nil,
      status: expected_date >= Date.current ? Status::Upcoming : Status::Missed
    )
  end

  # User-waived gap: don't count this occurrence against the series.
  sig { void }
  def skip!
    update!(status: Status::Skipped)
  end

  # Signed difference vs. the expected amount (positive = charged more).
  sig { returns(T.nilable(Float)) }
  def amount_delta
    return nil if amount.nil? || expected_amount.nil?

    (amount.to_f.abs - expected_amount.to_f.abs).round(2).to_f
  end

  private

  def inherit_household
    self[:household_id] ||= recurring_series&.household_id
  end
end
