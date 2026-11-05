# typed: strict

module Tax
  # The weekly tax vigilance rules (docs/tax-center-design.md): given one
  # household's year report, which workflow events are due today.
  #
  #   tax.quarterly_due_approaching      — an installment is exactly 14 or 3
  #                                        days out with $0 paid in its window
  #   tax.safe_harbor_behind             — federal or CA prior-year safe
  #                                        harbor is uncovered
  #   tax.contribution_limit_approaching — a bucket is at ≥90% and <100% of
  #                                        its limit (stateless weekly scan, so
  #                                        this repeats weekly while in the
  #                                        band — accepted for v1)
  #   tax.document_overdue               — an expected W-2 / consolidated 1099
  #                                        / 1098 is past its arrival window
  #                                        (checked for this and last tax year,
  #                                        since year-Y documents arrive in Y+1)
  #   tax.wash_sale_detected             — a wash-sale finding with a sale in
  #                                        the last 45 days
  #
  # Returns events rather than publishing them; TaxScanJob publishes.
  class VigilanceScan
    extend T::Sig

    Event = T.type_alias { [ String, T::Hash[String, T.untyped] ] }

    DUE_SOON_OFFSETS_DAYS   = T.let([ 14, 3 ].freeze, T::Array[Integer])
    WASH_SALE_LOOKBACK_DAYS = 45
    CONTRIBUTION_WARN_RATIO = 0.90

    # kind => [month, day] of the (tax_year + 1) arrival deadline.
    DOCUMENT_DEADLINES = T.let({
      TaxChecklistItem::Kind::W2                   => [ 2, 15 ],
      TaxChecklistItem::Kind::Form1099Consolidated => [ 3, 15 ],
      TaxChecklistItem::Kind::Form1098             => [ 2, 15 ]
    }.freeze, T::Hash[TaxChecklistItem::Kind, [ Integer, Integer ]])

    sig { params(household: Household, year: Integer, today: Date).void }
    def initialize(household:, year:, today: Date.current)
      @household = household
      @year      = year
      @today     = today
    end

    sig { returns(T::Array[Event]) }
    def events
      Tax::ChecklistSeeder.ensure!(household: @household, year: @year)
      report = Tax::YearReport.build(household: @household, year: @year)

      due_dates(report) + safe_harbor(report) + contributions(report) + documents + wash_sales(report)
    end

    private

    sig { params(report: T::Hash[Symbol, T.untyped]).returns(T::Array[Event]) }
    def due_dates(report)
      report.dig(:payments, :due_dates).filter_map do |entry|
        due = Date.iso8601(entry[:date])
        next unless DUE_SOON_OFFSETS_DAYS.any? { |days| due == @today + days }
        next unless entry[:paid_in_window].zero?

        [ "tax.quarterly_due_approaching", {
          "jurisdiction" => entry[:jurisdiction],
          "date"         => entry[:date],
          "label"        => entry[:label]
        } ]
      end
    end

    sig { params(report: T::Hash[Symbol, T.untyped]).returns(T::Array[Event]) }
    def safe_harbor(report)
      report.dig(:payments, :safe_harbor).filter_map do |jurisdiction, harbor|
        next unless harbor[:status] == "uncovered"

        [ "tax.safe_harbor_behind", {
          "jurisdiction"    => jurisdiction.to_s,
          "required_annual" => harbor[:required_annual],
          "paid"            => harbor[:paid]
        } ]
      end
    end

    sig { params(report: T::Hash[Symbol, T.untyped]).returns(T::Array[Event]) }
    def contributions(report)
      report.dig(:contributions, :buckets).filter_map do |bucket|
        limit = bucket[:limit]
        next if bucket[:informational] || limit.nil? || limit.zero?

        ratio = bucket[:contributed] / limit
        next unless ratio >= CONTRIBUTION_WARN_RATIO && bucket[:contributed] < limit

        [ "tax.contribution_limit_approaching", {
          "bucket"      => bucket[:key],
          "contributed" => bucket[:contributed],
          "limit"       => limit
        } ]
      end
    end

    sig { returns(T::Array[Event]) }
    def documents
      TaxChecklistItem
        .where(household_id: @household.id, status: TaxChecklistItem::Status::Expected,
               kind: DOCUMENT_DEADLINES.keys, tax_year: [ @year - 1, @year ])
        .to_a
        .filter_map do |item|
          month, day = DOCUMENT_DEADLINES.fetch(item.kind)
          next unless @today > Date.new(item.tax_year + 1, month, day)

          [ "tax.document_overdue", {
            # Serialized: the payload rides through ActiveJob argument
            # serialization, which rejects T::Enum instances.
            "kind"         => item.kind.serialize,
            "source_label" => item.source_label,
            "tax_year"     => item.tax_year
          } ]
        end
    end

    sig { params(report: T::Hash[Symbol, T.untyped]).returns(T::Array[Event]) }
    def wash_sales(report)
      report.dig(:flags, :wash_sales).filter_map do |finding|
        age = @today - finding[:sale_date]
        next unless age >= 0 && age <= WASH_SALE_LOOKBACK_DAYS

        [ "tax.wash_sale_detected", {
          "security_label"   => finding[:security_label],
          "sale_date"        => finding[:sale_date].iso8601,
          "sale_account"     => finding[:sale_account],
          "loss"             => finding[:loss],
          "purchase_date"    => finding[:purchase_date].iso8601,
          "purchase_account" => finding[:purchase_account],
          "permanent"        => finding[:permanent]
        } ]
      end
    end
  end
end
