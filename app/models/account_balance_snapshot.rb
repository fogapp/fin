# typed: true

class AccountBalanceSnapshot < ApplicationRecord
  extend T::Sig

  include BumpsHouseholdDataVersion

  belongs_to :account

  # No household_id column — the owning household is reached via account.
  # Coalesced like every other model: syncers record one snapshot per
  # account in a loop.
  bumps_data_version_via :account

  # What triggered the snapshot: the nightly job, one of the syncers, or a
  # manual balance edit.
  class Source < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Scheduled = new("scheduled")
      PlaidSync = new("plaid_sync")
      CoinbaseSync = new("coinbase_sync")
      AlchemySync = new("alchemy_sync")
      Manual = new("manual")
    end
  end

  typed_enum :source, Source
  validates :balance, :source, :recorded_at, presence: true

  scope :ordered, -> { order(recorded_at: :asc) }

  # SQL expression for "the local calendar day of recorded_at". Timestamps
  # are stored UTC; DATE(recorded_at) alone would bucket by UTC day, which
  # disagrees with Time.zone day boundaries (an 6pm PT snapshot is already
  # "tomorrow" in UTC) and with .record's Time.zone-based same-day dedup.
  #
  # Built as an Arel node, so the zone is a quoted literal and callers can
  # order/group by it directly (or embed its #to_sql in a DISTINCT ON).
  sig { returns(Arel::Nodes::NamedFunction) }
  def self.local_date
    utc = Arel::Nodes::InfixOperation.new("AT TIME ZONE", arel_table[:recorded_at], Arel::Nodes.build_quoted("UTC"))
    local = Arel::Nodes::InfixOperation.new("AT TIME ZONE", utc, Arel::Nodes.build_quoted(Time.zone.tzinfo.name))
    Arel::Nodes::NamedFunction.new("DATE", [ local ])
  end

  # One row per (account, day, source): every sync calls record, and
  # unconditional inserts grew the table without bound. Updating the existing
  # row keeps daily_series' DISTINCT ON (date) picking the freshest balance
  # and still fires the after_commit DataVersion bump. (No unique index —
  # migrations are owned elsewhere — so a concurrent race can still insert a
  # duplicate; daily_series tolerates that.)
  sig do
    params(
      account: Account,
      source: Source,
      balance: T.nilable(Numeric),
      balance_currency: T.nilable(String),
      balance_usd: T.nilable(Numeric),
      time: T.any(Time, ActiveSupport::TimeWithZone)
    ).returns(T.nilable(AccountBalanceSnapshot))
  end
  def self.record(account, source:, balance: account.balance, balance_currency: account.balance_currency, balance_usd: account.balance_usd, time: Time.current)
    return unless balance.present?

    attrs = {
      balance:          balance,
      balance_currency: balance_currency || "USD",
      balance_usd:      balance_usd,
      recorded_at:      time
    }

    # T.unsafe: TimeWithZone's RBI lacks the DateAndTime::Calculations
    # methods (all_day &c.), though they exist at runtime.
    existing = where(account_id: account.id, source: source, recorded_at: T.unsafe(time).all_day)
               .order(recorded_at: :desc)
               .first
    if existing
      existing.update!(**attrs)
      existing
    else
      create!(account: account, source: source, **attrs)
    end
  end

  # from/to bound the window inside the DISTINCT ON subquery so out-of-range
  # rows never rank; nil keeps the historical unbounded behavior.
  sig { params(account_id: String, from: T.nilable(Date), to: T.nilable(Date)).returns(T.untyped) }
  def self.daily_series(account_id, from: nil, to: nil)
    day = local_date
    inner = select("DISTINCT ON (#{day.to_sql}) balance, balance_currency, balance_usd, source, recorded_at")
      .select(day.as("date"))
      .where(account_id: account_id)
      .order(day, recorded_at: :desc)
    inner = inner.where(recorded_at: from.beginning_of_day..) if from
    inner = inner.where(recorded_at: ..to.end_of_day) if to

    # Explicit receiver: `from` here is the window kwarg, not the relation method.
    all.from(inner, :account_balance_snapshots).order("date ASC")
  end
end
