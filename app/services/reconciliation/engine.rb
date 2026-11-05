# typed: strict

module Reconciliation
  # Diffs the ledger-derived positions against the latest custodian
  # observation (position snapshot) per account and turns disagreements into
  # actionable findings: an Issue per drifting pair (auto-resolving when the
  # drift clears), a reconciliation.drift_detected workflow event, and an
  # activity summary.
  #
  # Drift means transactions are missing or wrong — the audit's "holdings
  # are off" turned from silently wrong numbers into an inbox.
  module Engine
    extend T::Sig

    QUANTITY_TOLERANCE = T.let(BigDecimal("0.0001"), BigDecimal)
    RELATIVE_TOLERANCE = T.let(BigDecimal("0.005"), BigDecimal) # 0.5%

    # `kind` is a FindingKind.
    Finding = Struct.new(:account, :security, :ledger_qty, :observed_qty, :kind, keyword_init: true)

    sig { params(household: Household).returns(T::Array[Finding]) }
    def self.run(household)
      findings = T.let([], T::Array[Finding])

      Current.set(household: household) do
        observed_accounts.each do |account|
          observations = latest_observations(account)
          ledger = Position.where(account_id: account.id).index_by(&:security_id)

          # Ledger-only pairs are meaningful; observation-only pairs are
          # too — both mean missing activity somewhere.
          drifting = (observations.keys | ledger.keys).filter_map do |security_id|
            observed_qty = observations[security_id]&.quantity.to_d
            ledger_qty   = ledger[security_id]&.quantity.to_d
            [ security_id, ledger_qty, observed_qty ] if drift?(ledger_qty, observed_qty)
          end

          # One batched load instead of a Security.find_by per drifting pair.
          securities = Security.where(id: drifting.map(&:first)).index_by(&:id)
          drifting.each do |security_id, ledger_qty, observed_qty|
            security = securities[security_id]
            next unless security

            findings << Finding.new(
              account: account, security: security,
              ledger_qty: ledger_qty, observed_qty: observed_qty,
              kind: finding_kind(ledger_qty, observed_qty)
            )
          end

          resolve_cleared(account, findings)
        end

        report(household, findings)
      end

      findings
    end

    sig { params(ledger_qty: BigDecimal, observed_qty: BigDecimal).returns(T::Boolean) }
    def self.drift?(ledger_qty, observed_qty)
      diff = (ledger_qty - observed_qty).abs
      return false if diff <= QUANTITY_TOLERANCE

      base = [ ledger_qty.abs, observed_qty.abs ].max
      base.positive? ? (diff / base) > RELATIVE_TOLERANCE : true
    end

    sig { params(ledger_qty: BigDecimal, observed_qty: BigDecimal).returns(FindingKind) }
    def self.finding_kind(ledger_qty, observed_qty)
      return FindingKind::MissingFromLedger if ledger_qty.zero?
      return FindingKind::MissingFromCustodian if observed_qty.zero?

      FindingKind::QuantityDrift
    end

    # Accounts with at least one custodian observation — accounts fed only
    # by manual transactions have nothing to reconcile against.
    sig { returns(T::Array[Account]) }
    def self.observed_accounts
      account_ids = PositionSnapshot
        .where.not("source_row_hash LIKE 'computed:%'")
        .distinct.pluck(:account_id).compact
      Account.where(id: account_ids).to_a
    end
    private_class_method :observed_accounts

    # Latest observation per security within the account (per-account as_of).
    sig { params(account: Account).returns(T::Hash[T.untyped, PositionSnapshot]) }
    def self.latest_observations(account)
      as_of = PositionSnapshot.where(account_id: account.id)
                              .where.not("source_row_hash LIKE 'computed:%'")
                              .maximum(:as_of_date)
      return {} unless as_of

      PositionSnapshot.where(account_id: account.id, as_of_date: as_of)
                      .where.not("source_row_hash LIKE 'computed:%'")
                      .index_by(&:security_id)
    end
    private_class_method :latest_observations

    sig { params(account: Account, findings: T::Array[Finding]).void }
    def self.resolve_cleared(account, findings)
      open_keys = findings.select { |f| f.account.id == account.id }
                          .map { |f| finding_key(f.account, f.security) }
      # Issue.resolve!'s semantics (active.where(key:).update_all), set-wise.
      Issue.active.where("key LIKE ?", "reconciliation:#{account.id}:%").where.not(key: open_keys)
           .update_all(dismissed_at: Time.current)
    end
    private_class_method :resolve_cleared

    sig { params(account: Account, security: Security).returns(String) }
    def self.finding_key(account, security)
      "reconciliation:#{account.id}:#{security.id}"
    end

    sig { params(household: Household, findings: T::Array[Finding]).void }
    def self.report(household, findings)
      Issue.raise_each!(findings.map do |f|
        {
          key:      finding_key(f.account, f.security),
          title:    "Holdings drift: #{f.security.display_name} in #{f.account.name}",
          body:     "The custodian reports #{f.observed_qty.to_f} but the transaction ledger " \
                    "accounts for #{f.ledger_qty.to_f} (#{f.kind.serialize.humanize.downcase}). " \
                    "Transactions are likely missing or misclassified.",
          severity: Severity::Warning,
          source:   "reconciliation"
        }
      end)

      findings.each do |f|
        Workflows::Events.publish("reconciliation.drift_detected", subject: f.account,
                                  payload: { "security" => f.security.display_name,
                                             "ticker" => f.security.ticker,
                                             "ledger_quantity" => f.ledger_qty.to_f,
                                             "observed_quantity" => f.observed_qty.to_f,
                                             "kind" => f.kind.serialize })
      end

      return if findings.empty?

      Activity.record(
        source: "reconciliation", event: "drift_detected", severity: Severity::Warning,
        summary: "Reconciliation found #{findings.size} drifting holding#{findings.size == 1 ? '' : 's'} " \
                 "across #{findings.map { |f| f.account.id }.uniq.size} account(s)",
        payload: { findings: findings.map { |f|
          { account: f.account.name, ticker: f.security.ticker,
            ledger: f.ledger_qty.to_f, observed: f.observed_qty.to_f, kind: f.kind.serialize }
        } },
        household_id: household.id
      )
    end
    private_class_method :report
  end
end
