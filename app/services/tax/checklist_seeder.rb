# typed: strict

module Tax
  # Seeds the document checklist for a (household, year) from ledger data:
  # a W-2 when a profile exists, a consolidated 1099 per broker with
  # investment activity, a 1098 per active loan, a 3921 per ISO exercise,
  # a 5498 per IRA, and a receipt reminder per $250+ charitable gift
  # (the substantiation threshold of IRC §170(f)(8)).
  #
  # Idempotent by the [household, year, kind, source_label] unique index —
  # find_or_create_by only ever adds missing rows, so user status edits
  # (received / n_a) survive re-seeding. Called from the report GET and the
  # weekly TaxScanJob.
  class ChecklistSeeder
    extend T::Sig

    CHARITABLE_RECEIPT_THRESHOLD = 250

    # Accounts that generate Form 5498 (IRA contribution information).
    # 401(k)s report through the W-2 instead, so they are not seeded here.
    IRA_TREATMENTS = T.let(
      [ Account::TaxTreatment::TraditionalIra, Account::TaxTreatment::RothIra ].freeze,
      T::Array[Account::TaxTreatment]
    )

    sig { params(household: Household, year: Integer).void }
    def self.ensure!(household:, year:)
      new(household: household, year: year).ensure!
    end

    sig { params(household: Household, year: Integer).void }
    def initialize(household:, year:)
      @household = T.let(household, Household)
      @year      = T.let(year, Integer)
      @range     = T.let(Date.new(year, 1, 1)..Date.new(year, 12, 31), T::Range[Date])
    end

    sig { void }
    def ensure!
      seed_w2
      seed_consolidated_1099s
      seed_1098s
      seed_3921s
      seed_5498s
      seed_charitable_receipts
    end

    private

    sig { void }
    def seed_w2
      return unless TaxProfile.where(household_id: @household.id).exists?(tax_year: @year)

      seed(kind: TaxChecklistItem::Kind::W2, source_label: "Employer", notes: "Expected by January 31")
    end

    sig { void }
    def seed_consolidated_1099s
      broker_names = InvestmentTransaction
        .where(household_id: @household.id, trade_date: @range)
        .joins(account: :broker)
        .distinct
        .pluck("brokers.name")

      broker_names.each do |name|
        seed(kind: TaxChecklistItem::Kind::Form1099Consolidated, source_label: name,
             notes: "Expected mid-February; corrected versions common into March")
      end
    end

    sig { void }
    def seed_1098s
      Loan.where(household_id: @household.id, status: Loan::Status::Active)
          .where(start_date: ..@range.last)
          .find_each do |loan|
        seed(kind: TaxChecklistItem::Kind::Form1098, source_label: loan.name, notes: "Expected by mid-February")
      end
    end

    sig { void }
    def seed_3921s
      EquityGrantEvent
        .where(household_id: @household.id, kind: EquityGrantEvent::Kind::Exercise, occurred_on: @range)
        .joins(equity_grant: :equity_company)
        .where(equity_grants: { grant_type: EquityGrant::GrantType::Iso })
        .includes(equity_grant: :equity_company)
        .find_each do |event|
        company = T.must(event.equity_grant).equity_company
        seed(kind: TaxChecklistItem::Kind::Form3921,
             source_label: "#{T.must(company).name} — #{event.occurred_on.iso8601}",
             reference_id: event.id)
      end
    end

    sig { void }
    def seed_5498s
      Account.where(household_id: @household.id, tax_treatment: IRA_TREATMENTS).find_each do |account|
        seed(kind: TaxChecklistItem::Kind::Form5498, source_label: account.name, notes: "Informational — arrives ~May")
      end
    end

    sig { void }
    def seed_charitable_receipts
      category_ids = Category.where(household_id: @household.id, charitable: true).pluck(:id)
      return if category_ids.empty?

      CashTransaction.spend_like
        .where(household_id: @household.id, transaction_date: @range, category_id: category_ids)
        .where("ABS(amount) >= ?", CHARITABLE_RECEIPT_THRESHOLD)
        .includes(:merchant)
        .find_each do |txn|
        label = "#{txn.merchant&.name || txn.description} — $#{format('%.2f', txn.amount.abs)} on #{txn.transaction_date.iso8601}"
        seed(kind: TaxChecklistItem::Kind::CharitableReceipt, source_label: label, reference_id: txn.id)
      end
    end

    sig do
      params(kind: TaxChecklistItem::Kind, source_label: String,
             notes: T.nilable(String), reference_id: T.nilable(String)).void
    end
    def seed(kind:, source_label:, notes: nil, reference_id: nil)
      TaxChecklistItem.find_or_create_by!(
        household_id: @household.id, tax_year: @year, kind: kind, source_label: source_label
      ) do |item|
        item.status       = TaxChecklistItem::Status::Expected
        item.auto_seeded  = true
        item.notes        = notes
        item.reference_id = reference_id
      end
    rescue ActiveRecord::RecordNotUnique
      # Concurrent report loads can race find_or_create_by; the row exists,
      # which is all ensure! promises.
    end
  end
end
