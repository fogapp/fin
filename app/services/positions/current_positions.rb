# typed: strict

module Positions
  # Resolves "the current portfolio" from the three snapshot species:
  #
  # - imported  — holdings-CSV batches, dated by the statement. The latest
  #               batch date anchors the portfolio's as-of.
  # - plaid     — 'plaid_holding:' keyed rows, one per (account, security),
  #               refreshed in place by every Plaid sync. They are live
  #               observations, NOT batches: they never advance the imported
  #               as-of (they used to, evicting every CSV position on every
  #               sync), and are appended for securities the imported batch
  #               doesn't cover.
  # - computed  — 'computed:' rows synthesized from manual transactions and
  #               Coinbase balances; appended for securities not otherwise
  #               covered, without advancing the as-of.
  class CurrentPositions
    extend T::Sig

    COMPUTED_PREFIX_SQL = "source_row_hash LIKE 'computed:%'"
    PLAID_PREFIX_SQL    = "source_row_hash LIKE 'plaid_holding:%'"

    # Every sync restamps as_of_date on the rows it saw, so a Plaid row the
    # account's recent syncs stopped touching describes something Plaid no
    # longer reports — a sold holding, or (the July 2026 resolver cutover) a
    # security row Plaid abandoned for a differently-keyed one. Either way it
    # is not a current position, and counting it inflated the portfolio by
    # $1.2M for three weeks.
    #
    # PlaidSyncer#zero_stamp_missing_holdings is meant to zero these, but it
    # only runs when every holding in the response resolved cleanly — one bad
    # holding freezes the rest indefinitely. This gate doesn't care why the
    # row stopped being refreshed.
    #
    # The window is per account and relative to that account's own latest
    # observation, so an item that stops syncing entirely keeps its whole
    # portfolio (every row goes stale together) rather than emptying out.
    STALE_AFTER_DAYS = 7

    sig { returns(T.nilable(Date)) }
    def as_of_date
      @as_of_date ||= T.let(imported_as_of || plaid.maximum(:as_of_date), T.nilable(Date))
    end

    # All snapshots that make up the current portfolio. Coverage is keyed per
    # (account, security): the same instrument held in two accounts is two
    # positions, but two species describing the same account+instrument
    # deduplicate with imported > plaid > computed precedence.
    #
    # Resolution is memoised per instance. It costs four round trips plus a
    # scan of position_snapshots, and callers legitimately want the relation
    # more than once per request (the portfolio renderer alone reads it for
    # totals, allocation and the holdings list). Chaining .where/.group off
    # the returned relation spawns new relations rather than mutating this
    # one, so handing the same object to every caller is safe.
    sig { returns(T.untyped) }
    def relation
      ids = resolved_ids
      PositionSnapshot.where(id: ids.fetch(:base))
                      .or(PositionSnapshot.where(id: ids.fetch(:appended)))
    end

    private

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def resolved_ids
      @resolved_ids ||= T.let(compute_resolved_ids, T.nilable(T::Hash[Symbol, T.untyped]))
    end

    sig { returns(T.nilable(Date)) }
    def imported_as_of
      return @imported_as_of if defined?(@imported_as_of)

      @imported_as_of = T.let(imported.maximum(:as_of_date), T.nilable(Date))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def compute_resolved_ids
      base_snaps = imported.where(as_of_date: imported_as_of)
      covered = base_snaps.pluck(:account_id, :security_id).to_set

      # Plaid observations accumulate one row per sync date — only the
      # LATEST row per (account, security) is the current position. Taking
      # them all rendered N duplicate copies of every Plaid holding.
      #
      # account_id and security_id come back on the same rows, so the
      # follow-up "which pairs did we just cover" lookup that used to re-query
      # by id is folded into this one pass.
      latest_plaid = fresh_plaid
        .select("DISTINCT ON (account_id, security_id) id, account_id, security_id")
        .order(:account_id, :security_id, as_of_date: :desc, created_at: :desc)
      plaid_ids = latest_plaid.filter_map do |row|
        pair = [ row.account_id, row.security_id ]
        next if covered.include?(pair)

        covered << pair
        row.id
      end

      # The date gate only exists to drop computed rows that predate the
      # imported batch; with no imported batch the computed rows ARE the
      # portfolio (one row per pair, updated in place by recalculation).
      computed_scope = as_of_date ? computed.where(as_of_date: as_of_date..) : computed
      computed_ids = computed_scope.pluck(:id, :account_id, :security_id)
                                   .reject { |_, acct, sec| covered.include?([ acct, sec ]) }
                                   .map(&:first)

      { base: base_snaps.select(:id), appended: plaid_ids + computed_ids }
    end

    sig { returns(T.untyped) }
    def imported
      PositionSnapshot.where.not(COMPUTED_PREFIX_SQL).where.not(PLAID_PREFIX_SQL)
    end

    sig { returns(T.untyped) }
    def plaid
      PositionSnapshot.where(PLAID_PREFIX_SQL)
    end

    # Plaid rows still being refreshed by their account's syncs. See
    # STALE_AFTER_DAYS.
    #
    # The per-account cutoff is a grouped join rather than a correlated
    # subquery: as a correlation, that MAX(as_of_date) was re-derived once per
    # candidate row, so the work grew with the square of the Plaid rows per
    # account. Grouped, it's computed once per account. The derived column is
    # aliased because an unqualified account_id would otherwise be ambiguous
    # against the DISTINCT ON select that consumes this scope.
    sig { returns(T.untyped) }
    def fresh_plaid
      plaid
        .joins(<<~SQL.squish)
          JOIN (
            SELECT account_id AS fresh_account_id, MAX(as_of_date) AS latest_as_of
            FROM position_snapshots
            WHERE #{PLAID_PREFIX_SQL}
            GROUP BY account_id
          ) fresh ON fresh.fresh_account_id = position_snapshots.account_id
        SQL
        .where(
          "position_snapshots.as_of_date >= fresh.latest_as_of - ? * INTERVAL '1 day'",
          STALE_AFTER_DAYS
        )
    end

    sig { returns(T.untyped) }
    def computed
      PositionSnapshot.where(COMPUTED_PREFIX_SQL)
    end
  end
end
