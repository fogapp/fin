# typed: true

# Detects likely transfer pairs across cash and investment transactions.
# A candidate pair is two transactions that:
#   - Belong to the same household (the raw SQL bypasses HouseholdScoped's
#     default scope, so the household predicate is applied explicitly)
#   - Are in different accounts
#   - Have amounts that sum to ~zero (one outflow, one inflow)
#   - Occur within CANDIDATE_DAYS of each other
#   - Are not already linked to a Transfer
#
# The anchor side of each query is bounded to a trailing LOOKBACK_MONTHS
# window so ancient unlinked rows stop being re-scanned every run (the
# counterpart side is implicitly bounded too — it must fall within
# CANDIDATE_DAYS of the anchor). Dismissals and existing candidates are
# durable rows keyed by transaction ids, so they are unaffected by the
# window shrinking.
class TransferCandidateService
  extend T::Sig

  DAYS            = T.let(Transfer::CANDIDATE_DAYS, Integer)
  TOLERANCE       = T.let(Transfer::AMOUNT_TOLERANCE, Numeric)
  LOOKBACK_MONTHS = 18

  Result = Data.define(:from_transaction, :from_type, :to_transaction, :to_type, :amount, :date_diff)

  sig { params(household_id: T.nilable(String)).void }
  def initialize(household_id: Current.household&.id)
    raise ArgumentError, "household_id is required (set Current.household or pass explicitly)" if household_id.blank?

    @household_id = T.let(household_id.to_s, String)
  end

  sig { returns(T::Array[T.untyped]) }
  def candidates
    (cash_to_cash + cash_to_investment + investment_to_cash).uniq { |r| pair_key(r) }
  end

  private

  # Runs one of the fixed candidate queries below with its two values —
  # the household and the lookback start — bound as :household_id and
  # :window_start; TOLERANCE and DAYS are constants.
  sig { params(sql: String).returns(T::Array[T::Hash[String, T.untyped]]) }
  def select_candidate_rows(sql)
    bound = ActiveRecord::Base.sanitize_sql_array([
      sql, { household_id: @household_id, window_start: Date.current - LOOKBACK_MONTHS.months }
    ])
    ActiveRecord::Base.connection.select_all(bound).to_a
  end

  # ── Cash ↔ Cash ─────────────────────────────────────────────────────────────

  sig { returns(T::Array[T.untyped]) }
  def cash_to_cash
    # Sargable join predicates: the counterpart's date/amount are expressed as
    # ranges around the anchor's values so composite indexes apply, instead of
    # ABS() expressions that force a quadratic nested loop.
    sql = <<~SQL
      SELECT a.id AS from_id, b.id AS to_id,
             ABS(a.amount) AS amount,
             ABS(a.transaction_date - b.transaction_date) AS date_diff
      FROM   cash_transactions a
      JOIN   cash_transactions b
               ON  b.household_id = :household_id
               AND b.account_id  != a.account_id
               AND b.transfer_id IS NULL
               AND a.id           < b.id
               AND b.amount > -a.amount - #{TOLERANCE}
               AND b.amount < -a.amount + #{TOLERANCE}
               AND b.transaction_date BETWEEN a.transaction_date - #{DAYS} AND a.transaction_date + #{DAYS}
      WHERE  a.household_id = :household_id
        AND  a.transfer_id IS NULL
        AND  a.transaction_date >= :window_start
    SQL

    rows = select_candidate_rows(sql)
    txns = CashTransaction.where(id: rows.flat_map { |r| [ r["from_id"], r["to_id"] ] }).index_by(&:id)

    rows.filter_map do |r|
      a = txns[r["from_id"]]
      b = txns[r["to_id"]]
      next unless a && b
      # Ensure `from` is the outflow (negative amount)
      from, to = a.amount < 0 ? [ a, b ] : [ b, a ]
      Result.new(from_transaction: from, from_type: "CashTransaction",
                 to_transaction:   to,   to_type:   "CashTransaction",
                 amount: r["amount"].to_f, date_diff: r["date_diff"].to_i)
    end
  end

  # ── Cash outflow → Investment inflow (cash deposit to brokerage) ─────────────

  sig { returns(T::Array[T.untyped]) }
  def cash_to_investment
    sql = <<~SQL
      SELECT c.id AS from_id, i.id AS to_id,
             ABS(c.amount) AS amount,
             ABS(c.transaction_date - i.trade_date) AS date_diff
      FROM   cash_transactions c
      JOIN   investment_transactions i
               ON  i.household_id = :household_id
               AND i.account_id  != c.account_id
               AND i.transfer_id IS NULL
               AND i.amount_usd > -c.amount - #{TOLERANCE}
               AND i.amount_usd < -c.amount + #{TOLERANCE}
               AND i.trade_date BETWEEN c.transaction_date - #{DAYS} AND c.transaction_date + #{DAYS}
      WHERE  c.household_id = :household_id
        AND  c.transfer_id IS NULL
        AND  c.amount < 0
        AND  c.transaction_date >= :window_start
    SQL

    rows = select_candidate_rows(sql)
    cash_txns = CashTransaction.where(id: rows.map { |r| r["from_id"] }).index_by(&:id)
    inv_txns  = InvestmentTransaction.where(id: rows.map { |r| r["to_id"] }).index_by(&:id)

    rows.filter_map do |r|
      from = cash_txns[r["from_id"]]
      to   = inv_txns[r["to_id"]]
      next unless from && to
      Result.new(from_transaction: from, from_type: "CashTransaction",
                 to_transaction:   to,   to_type:   "InvestmentTransaction",
                 amount: r["amount"].to_f, date_diff: r["date_diff"].to_i)
    end
  end

  # ── Investment outflow → Cash inflow (withdrawal from brokerage) ─────────────

  sig { returns(T::Array[T.untyped]) }
  def investment_to_cash
    sql = <<~SQL
      SELECT i.id AS from_id, c.id AS to_id,
             ABS(i.amount_usd) AS amount,
             ABS(i.trade_date - c.transaction_date) AS date_diff
      FROM   investment_transactions i
      JOIN   cash_transactions c
               ON  c.household_id = :household_id
               AND c.account_id  != i.account_id
               AND c.transfer_id IS NULL
               AND c.amount > -i.amount_usd - #{TOLERANCE}
               AND c.amount < -i.amount_usd + #{TOLERANCE}
               AND c.transaction_date BETWEEN i.trade_date - #{DAYS} AND i.trade_date + #{DAYS}
      WHERE  i.household_id = :household_id
        AND  i.transfer_id IS NULL
        AND  i.amount_usd < 0
        AND  i.trade_date >= :window_start
    SQL

    rows = select_candidate_rows(sql)
    inv_txns  = InvestmentTransaction.where(id: rows.map { |r| r["from_id"] }).index_by(&:id)
    cash_txns = CashTransaction.where(id: rows.map { |r| r["to_id"] }).index_by(&:id)

    rows.filter_map do |r|
      from = inv_txns[r["from_id"]]
      to   = cash_txns[r["to_id"]]
      next unless from && to
      Result.new(from_transaction: from, from_type: "InvestmentTransaction",
                 to_transaction:   to,   to_type:   "CashTransaction",
                 amount: r["amount"].to_f, date_diff: r["date_diff"].to_i)
    end
  end

  sig { params(r: T.untyped).returns(String) }
  def pair_key(r)
    [ r.from_type, r.from_transaction.id, r.to_type, r.to_transaction.id ].sort.join("-")
  end
end
