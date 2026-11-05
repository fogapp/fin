# typed: true

# A recurring charge stream (docs/subscriptions-redesign.md). Detection
# proposes rows as "suggested"; the user's accept/dismiss/end decisions are
# durable — the detector never resurfaces a row the user acted on. Accepted
# series are maintained by Recurring::Matcher, which attaches new
# transactions to expected RecurringOccurrence rows.
class RecurringSeries < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include EmitsWorkflowEvents
  # /review's subscription summary is served from the DataVersion cache, so
  # accept/dismiss/end must rotate it or the review digest goes stale.
  include BumpsHouseholdDataVersion

  # Lifecycle state. Detection proposes Suggested rows; user decisions and
  # the two automatic transitions move them through the rest.
  class Status < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Suggested = new("suggested")
      Active = new("active")
      Dismissed = new("dismissed")
      Lapsed = new("lapsed")
      Ended = new("ended")
    end
  end

  # Where the series came from: the detector or manual creation.
  class Source < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Detected = new("detected")
      Manual = new("manual")
    end
  end

  # Fixed-price subscription vs. variable-amount bill.
  class Kind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Subscription = new("subscription")
      Bill = new("bill")
    end
  end

  belongs_to :merchant, optional: true
  belongs_to :account, optional: true
  has_many :recurring_occurrences, dependent: :destroy

  # status => statuses it may move to. User transitions and the two automatic
  # ones (lapse after 2 consecutive misses, reactivate on a matching charge).
  TRANSITIONS = T.let({
    Status::Suggested => [ Status::Active, Status::Dismissed ],
    Status::Active    => [ Status::Dismissed, Status::Ended, Status::Lapsed ],
    Status::Lapsed    => [ Status::Active, Status::Ended, Status::Dismissed ],
    Status::Dismissed => [ Status::Suggested ],
    Status::Ended     => [ Status::Active, Status::Suggested ]
  }.freeze, T::Hash[Status, T::Array[Status]])

  # Consecutive missed occurrences before an active series auto-lapses.
  LAPSE_AFTER_MISSES = 2

  typed_enum :status, Status
  typed_enum :source, Source
  typed_enum :kind, Kind
  typed_enum :granularity, Recurring::Schedule::Granularity

  validates :quantity, numericality: { greater_than: 0 }
  validates :name, presence: true
  validates :series_key, presence: true, uniqueness: { scope: :household_id }
  validates :average_amount, presence: true
  validates :amount_tolerance, numericality: { greater_than: 0, less_than: 1 }

  scope :suggested, -> { where(status: Status::Suggested) }
  scope :active,    -> { where(status: Status::Active) }
  scope :lapsed,    -> { where(status: Status::Lapsed) }
  scope :dismissed, -> { where(status: Status::Dismissed) }
  scope :ended,     -> { where(status: Status::Ended) }
  # Series whose schedule the matcher/monitor still track.
  scope :tracking,  -> { where(status: [ Status::Suggested, Status::Active, Status::Lapsed ]) }

  sig { returns(Recurring::Schedule) }
  def schedule
    Recurring::Schedule.new(granularity: granularity, quantity: quantity, anchor: anchor || {})
  end

  sig { returns(String) }
  def cadence_description
    schedule.description
  end

  sig { returns(Float) }
  def monthly_equivalent
    (average_amount.to_f * schedule.periods_per_year / 12.0)
  end

  sig { returns(T::Boolean) }
  def at_risk?
    status == Status::Active && misses_streak == 1
  end

  # Absolute dollar band accepted when matching a transaction to this series.
  sig { returns(T::Range[Float]) }
  def amount_band
    avg = average_amount.to_f
    slack = [ avg * amount_tolerance.to_f, 1.0 ].max
    (avg - slack)..(avg + slack)
  end

  # A disallowed lifecycle move — the client's error, rendered as a 422.
  class InvalidTransition < StandardError; end

  sig { params(new_status: Status).void }
  def transition_to!(new_status)
    allowed = TRANSITIONS.fetch(status, [])
    raise InvalidTransition, "cannot move #{status} -> #{new_status}" unless allowed.include?(new_status)

    stamps = { Status::Active => { accepted_at: Time.current }, Status::Dismissed => { dismissed_at: Time.current }, Status::Ended => { ended_at: Time.current } }
    update!({ status: new_status, misses_streak: 0 }.merge(stamps.fetch(new_status, {})))
  end

  # The user-driven transitions below carry their side effects with them,
  # each in one transaction: a tracked series always has a pending forecast,
  # and an untracked one never keeps one.
  sig { void }
  def accept!
    transaction do
      transition_to!(Status::Active)
      ensure_pending_occurrence!
    end
  end

  sig { void }
  def dismiss!
    transaction do
      transition_to!(Status::Dismissed)
      recurring_occurrences.pending.destroy_all
    end
  end

  sig { void }
  def mark_ended!
    transaction do
      transition_to!(Status::Ended)
      recurring_occurrences.pending.destroy_all
    end
  end

  # dismissed -> back to the review queue; ended -> tracked again.
  sig { void }
  def restore!
    transaction do
      transition_to!(status == Status::Dismissed ? Status::Suggested : Status::Active)
      ensure_pending_occurrence! if status == Status::Active
    end
  end

  # "Mark as recurring" from a transaction: the source transaction becomes
  # the first paid occurrence and seeds the series' charge-history stamps.
  sig { params(txn: CashTransaction).void }
  def adopt_transaction!(txn)
    charged = txn.amount.to_d.abs.round(2)
    recurring_occurrences.create!(
      expected_date: txn.transaction_date, status: RecurringOccurrence::Status::Paid,
      cash_transaction_id: txn.id, charged_date: txn.transaction_date,
      amount: charged, expected_amount: average_amount
    )
    update!(first_charge_date: txn.transaction_date, last_charge_date: txn.transaction_date,
            last_amount: charged)
  end

  # A tracked series must always have a forecast row for the matcher and
  # monitor to advance; called after transitions back into active.
  sig { void }
  def ensure_pending_occurrence!
    return if recurring_occurrences.pending.exists?

    expected = next_expected_date || schedule.next_on_or_after(Date.current)
    update!(next_expected_date: expected)
    recurring_occurrences.find_or_create_by!(expected_date: expected) do |o|
      o.status = RecurringOccurrence::Status::Upcoming
      o.expected_amount = average_amount
    end
  end

  # After a cadence edit the old pending forecasts are on the wrong dates —
  # drop them and reproject from today under the new schedule.
  sig { void }
  def reset_pending_schedule!
    recurring_occurrences.pending.destroy_all
    update!(next_expected_date: schedule.next_on_or_after(Date.current))
    ensure_pending_occurrence!
  end
end
