# Ledger schemas: accounts, brokers, cash and investment transactions,
# categories, tags, merchants, saved views, transfers, lots and search.
# Mirrors Api::Render::{Account,Broker,CashTransaction,Category,Tag,Merchant,
# SavedView,Transfer,InvestmentLot,AccountHoldings,AccountBalanceSnapshot,
# Search} and Concerns::SerializesInvestmentTransaction.
module OpenapiSchemas
  module Ledger
    UUID      = { type: :string, format: :uuid }.freeze
    DATE      = { type: :string, format: :date }.freeze
    DATE_TIME = { type: :string, format: "date-time" }.freeze
    NUMBER    = { type: :number, format: :float }.freeze
    STRING    = { type: :string }.freeze

    def self.nullable(schema) = schema.merge(nullable: true)

    # A $ref that may be null. OpenAPI 3.0 ignores siblings of $ref, so the
    # nullable flag rides on an allOf wrapper instead.
    def self.nullable_ref(name) = { allOf: [ ref(name) ], nullable: true }

    def self.ref(name) = { "$ref" => "#/components/schemas/#{name}" }

    # An object whose every property is always present (nullable ones are
    # sent as null, not omitted) unless listed in `optional:`.
    def self.object(properties = nil, optional: [], **inline)
      properties ||= inline
      { type: :object, properties: properties, required: properties.keys.map(&:to_s) - optional.map(&:to_s) }
    end

    # { "YYYY-MM-DD" => number } month buckets.
    MONTHLY = { type: :object, additionalProperties: { type: :number },
                description: "Keyed by the first day of each month (YYYY-MM-DD)" }.freeze
    # { name => amount } breakdowns, largest first.
    NAMED_AMOUNTS = { type: :object, additionalProperties: { type: :number } }.freeze

    ACCOUNT_KINDS  = %w[standard external].freeze
    TAX_TREATMENTS = %w[taxable traditional_401k traditional_ira roth_401k roth_ira hsa education other].freeze
    BUDGET_KINDS   = %w[fixed flex non_monthly].freeze
    TRANSFER_KINDS = %w[transfer credit_card_payment loan_payment].freeze

    ACCOUNT = {
      id:               UUID,
      name:             STRING,
      account_number:   STRING,
      account_type:     nullable(STRING),
      balance:          nullable(NUMBER),
      balance_currency: nullable(STRING),
      balance_usd:      nullable(NUMBER),
      broker_id:        nullable(UUID),
      broker_name:      nullable(STRING),
      plaid_item_id:    nullable(UUID),
      hidden:           { type: :boolean },
      kind:             { type: :string, enum: ACCOUNT_KINDS },
      tax_treatment:    { type: :string, enum: TAX_TREATMENTS }
    }.freeze

    CATEGORY = {
      id:          UUID,
      name:        STRING,
      parent_id:   nullable(UUID),
      budget_kind: { type: :string, enum: BUDGET_KINDS },
      charitable:  { type: :boolean }
    }.freeze

    MERCHANT = {
      id:            UUID,
      name:          STRING,
      category_id:   nullable(UUID),
      category_name: nullable(STRING),
      notes:         nullable(STRING),
      excluded:      { type: :boolean }
    }.freeze

    TRANSFER = {
      id:                        UUID,
      from_transaction_id:       nullable(UUID),
      from_transaction_type:     nullable({ type: :string, enum: %w[CashTransaction InvestmentTransaction] }),
      to_transaction_id:         nullable(UUID),
      to_transaction_type:       nullable({ type: :string, enum: %w[CashTransaction InvestmentTransaction] }),
      counterparty_account_id:   nullable(UUID),
      counterparty_account_name: nullable(STRING),
      amount:                    nullable(NUMBER),
      note:                      nullable(STRING),
      kind:                      { type: :string, enum: TRANSFER_KINDS },
      include_in_spend:          { type: :boolean },
      confirmed_at:              nullable(DATE_TIME),
      confirmation_source:       nullable({ type: :string, enum: %w[user auto workflow] }),
      created_at:                DATE_TIME
    }.freeze

    TRANSACTION_ROW = {
      id:               UUID,
      transaction_date: DATE,
      description:      nullable(STRING),
      amount:           NUMBER,
      account_name:     nullable(STRING)
    }.freeze

    # Api::Render's transaction-context rows (CashTransactions::Context#row).
    CONTEXT_ROW = TRANSACTION_ROW.merge(
      merchant_name: nullable(STRING),
      category_id:   nullable(UUID),
      category_name: nullable(STRING),
      transfer_id:   nullable(UUID)
    ).freeze

    INVESTMENT_LOT_FIELDS = {
      account_id:    nullable(UUID),
      account_name:  nullable(STRING),
      acquired_date: nullable(DATE),
      quantity:      NUMBER,
      cost_basis:    NUMBER,
      unit_cost:     nullable(NUMBER)
    }.freeze

    OpenapiSchemas.register(
      # ── Accounts & brokers ────────────────────────────────────────────────
      Account: object(ACCOUNT),
      AccountWithStats: object(ACCOUNT.merge(
        cash_transaction_count:       { type: :integer },
        investment_transaction_count: { type: :integer },
        portfolio_value:              NUMBER,
        latest_transaction_date:      nullable(DATE),
        linked_loan_id:               nullable(UUID)
      )),
      AccountBalancePoint: object(
        date:             DATE,
        balance:          NUMBER,
        balance_currency: nullable(STRING),
        balance_usd:      nullable(NUMBER),
        source:           { type: :string, enum: %w[scheduled plaid_sync coinbase_sync alchemy_sync manual] }
      ),
      AccountHoldingPosition: object(
        id:                UUID,
        security_id:       UUID,
        security_ticker:   nullable(STRING),
        security_name:     nullable(STRING),
        security_cusip:    nullable(STRING),
        security_label:    nullable(STRING),
        quantity:          NUMBER,
        price:             NUMBER,
        market_value:      NUMBER,
        cost_basis:        NUMBER,
        unrealized_gl:     NUMBER,
        unrealized_gl_pct: NUMBER,
        asset_class:       nullable(STRING),
        est_annual_income: NUMBER,
        dividend_yield:    NUMBER,
        as_of_date:        DATE
      ),
      AccountHoldings: object(
        as_of_date: nullable(DATE.merge(description: "Null when the account holds nothing")),
        positions:  { type: :array, items: ref("AccountHoldingPosition") }
      ),
      Broker: object(
        id:            UUID,
        name:          nullable(STRING),
        account_count: { type: :integer }
      ),
      BrokerDetail: object(
        id:            UUID,
        name:          nullable(STRING),
        account_count: { type: :integer },
        accounts:      {
          type: :array,
          items: object(id: UUID, name: STRING, account_number: STRING, account_type: nullable(STRING))
        }
      ),

      # ── Cash transactions ─────────────────────────────────────────────────
      TagRef: object(id: UUID, name: STRING),
      CashTransaction: object(
        id:                        UUID,
        source:                    { type: :string, enum: %w[bank credit_card] },
        transaction_date:          DATE,
        post_date:                 nullable(DATE),
        description:               nullable(STRING),
        amount:                    NUMBER,
        transaction_type:          nullable(STRING.merge(description: "Open vocabulary — CSV importers pass bank types through verbatim")),
        category_id:               nullable(UUID),
        category_name:             nullable(STRING),
        category_parent_name:      nullable(STRING.merge(description: "Set when the category is a subcategory")),
        merchant_id:               nullable(UUID),
        merchant_name:             nullable(STRING),
        account_id:                nullable(UUID),
        account_name:              nullable(STRING),
        balance:                   nullable(NUMBER),
        memo:                      nullable(STRING),
        transfer_id:               nullable(UUID),
        transfer_kind:             nullable({ type: :string, enum: TRANSFER_KINDS }),
        transfer_include_in_spend: nullable({ type: :boolean }),
        loan_id:                   nullable(UUID),
        loan_name:                 nullable(STRING),
        budget_excluded:           { type: :boolean, description: "Left out of budgets (a one-off purchase); still counts in cashflow" },
        tags:                      { type: :array, items: ref("TagRef") },
        created_at:                DATE_TIME,
        updated_at:                DATE_TIME
      ),
      CashTransactionFilterCount: object(
        transactions: { type: :array, items: ref("CashTransaction") },
        total:        { type: :integer, description: "Every match, not just the returned sample" }
      ),
      CashTransactionBulkUpdate: object(
        updated:     { type: :integer, description: "Rows that exist in this household, whether or not any field changed" },
        account_id:  nullable(UUID),
        merchant_id: nullable(UUID),
        category_id: nullable(UUID),
        tag_ids:     { type: :array, items: UUID }
      ),
      SimilarTransaction: object(TRANSACTION_ROW.merge(match: { type: :string, enum: %w[exact similar] })),
      SimilarTransactions: object(
        transactions: { type: :array, items: ref("SimilarTransaction") },
        total:        { type: :integer, description: "Every match, not just the returned slice" },
        total_amount: NUMBER
      ),
      TransactionContextRow: object(CONTEXT_ROW),
      TransactionContextNearby: object(CONTEXT_ROW.merge(
        date_diff: { type: :integer, description: "Days from the transaction (negative = before)" }
      )),
      TransactionContext: object(
        history: object(
          basis: { type: :string, enum: %w[merchant description none], description: "What makes a row a peer" },
          label: nullable(STRING),
          total: { type: :integer, description: "Every peer, not just the plotted rows" },
          rows:  { type: :array, items: ref("TransactionContextRow"), description: "Oldest first; always includes the transaction" }
        ),
        stats: nullable(object(
          count:               { type: :integer },
          ordinal:             { type: :integer, description: "This row's position among its peers, oldest = 1" },
          median:              NUMBER,
          p25:                 NUMBER,
          p75:                 NUMBER,
          min:                 NUMBER,
          max:                 NUMBER,
          percentile:          NUMBER.merge(description: "Share of peers at or below this amount, 0..1"),
          ratio_to_median:     nullable(NUMBER),
          first_date:          DATE,
          last_date:           DATE,
          trailing_year_total: NUMBER,
          trailing_year_count: { type: :integer }
        )),
        cadence: nullable(object(
          granularity:          { type: :string, enum: %w[week month year] },
          quantity:             { type: :integer },
          anchor:               { type: :object, additionalProperties: true },
          description:          STRING,
          confidence:           NUMBER,
          hit_rate:             NUMBER,
          matched_count:        { type: :integer },
          missed_count:         { type: :integer },
          includes_transaction: { type: :boolean },
          average_amount:       NUMBER,
          next_expected_date:   DATE,
          matched_ids:          { type: :array, items: UUID }
        )),
        series: nullable(object(
          id:                   UUID,
          name:                 STRING,
          status:               { type: :string, enum: %w[suggested active dismissed lapsed ended] },
          kind:                 { type: :string, enum: %w[subscription bill] },
          cadence_description:  STRING,
          next_expected_date:   nullable(DATE),
          average_amount:       NUMBER,
          annual_equivalent:    NUMBER,
          includes_transaction: { type: :boolean, description: "This row is one of the series' paid charges" }
        )),
        treatment: object(
          spend:             { type: :boolean },
          income:            { type: :boolean },
          budget:            { type: :boolean },
          merchant_excluded: { type: :boolean }
        ),
        budget: nullable(object(
          scope:         { type: :string, enum: %w[line everything_else] },
          category_id:   nullable(UUID),
          category_name: nullable(STRING),
          period:        { type: :string, enum: %w[monthly yearly] },
          month:         STRING,
          available:     nullable(NUMBER),
          actual:        NUMBER,
          before:        NUMBER,
          contribution:  NUMBER,
          remaining:     nullable(NUMBER),
          typical:       nullable(NUMBER),
          history:       { type: :array, items: object(month: STRING, planned: NUMBER, actual: NUMBER) }
        )),
        duplicates: { type: :array, items: ref("TransactionContextNearby") },
        related:    { type: :array, items: ref("TransactionContextNearby") },
        same_day:   object(total: { type: :integer }, rows: { type: :array, items: ref("TransactionContextRow") }),
        suggested_category: nullable(object(
          category_id: UUID, category_name: nullable(STRING), count: { type: :integer }, of: { type: :integer }
        ))
      ),
      TransferSearchResult: object(TRANSACTION_ROW.merge(
        amount_diff: NUMBER.merge(description: "Distance from the exact counterpart amount (0 = exact)"),
        date_diff:   { type: :integer, description: "Days from the transaction being linked" }
      )),

      # ── Categories, tags, merchants ───────────────────────────────────────
      Category: object(CATEGORY),
      CategoryWithStats: object(CATEGORY.merge(transaction_count: { type: :integer })),
      CategoryDetail: object(CATEGORY.merge(
        parent:               nullable(object(id: UUID, name: STRING)),
        subcategories:        {
          type: :array,
          items: object(id: UUID, name: STRING, transaction_count: { type: :integer }, total_spend: NUMBER)
        },
        total_count:          { type: :integer },
        total_spend:          NUMBER,
        total_returns:        NUMBER,
        by_merchant:          NAMED_AMOUNTS,
        monthly_spend:        MONTHLY,
        monthly_spend_rollup: MONTHLY
      )),
      Tag: object(id: UUID, name: STRING),
      TagWithStats: object(
        id:                UUID,
        name:              STRING,
        transaction_count: { type: :integer },
        total_spend:       NUMBER
      ),
      TagDetail: object(
        id:            UUID,
        name:          STRING,
        total_count:   { type: :integer },
        total_spend:   NUMBER,
        total_returns: NUMBER,
        by_category:   NAMED_AMOUNTS,
        monthly_spend: MONTHLY
      ),
      Merchant: object(MERCHANT),
      MerchantWithStats: object(MERCHANT.merge(transaction_count: { type: :integer })),
      MerchantDetail: object(MERCHANT.merge(
        monthly_spend:  MONTHLY,
        monthly_counts: { type: :object, additionalProperties: { type: :integer } },
        monthly_income: MONTHLY
      )),

      # ── Saved views ───────────────────────────────────────────────────────
      SavedViewSort: object(field: STRING, dir: { type: :string, enum: %w[asc desc] }),
      SavedView: object(
        id:             UUID,
        name:           STRING,
        conditions:     {
          type: :array,
          items: object(field: STRING, operator: STRING, value: { description: "Operator-dependent; usually a string" })
        },
        match_all:      { type: :boolean },
        group_by:       nullable(STRING),
        primary_sort:   nullable_ref("SavedViewSort"),
        secondary_sort: nullable_ref("SavedViewSort"),
        created_at:     DATE_TIME
      ),

      # ── Transfers ─────────────────────────────────────────────────────────
      Transfer: object(TRANSFER),
      TransferWithDetails: object(TRANSFER.merge(
        from_date:        nullable(DATE),
        from_description: nullable(STRING),
        from_account_id:  nullable(UUID),
        to_date:          nullable(DATE),
        to_description:   nullable(STRING),
        to_account_id:    nullable(UUID),
        date_diff:        nullable({ type: :integer })
      )),

      # ── Investment transactions & lots ────────────────────────────────────
      InvestmentTransaction: object(
        id:                        UUID,
        trade_date:                DATE,
        description:               nullable(STRING),
        quantity:                  NUMBER,
        price_usd:                 NUMBER,
        amount_usd:                NUMBER,
        cost_usd:                  NUMBER,
        income_usd:                NUMBER,
        gl_short_usd:              NUMBER,
        gl_long_usd:               NUMBER,
        account_id:                UUID,
        account_name:              STRING,
        security_id:               nullable(UUID),
        security_ticker:           nullable(STRING),
        security_name:             nullable(STRING),
        transaction_type:          nullable(STRING.merge(description: "The broker's code description")),
        transaction_type_category: nullable(STRING.merge(description: "Purchase, Sale, Dividend, …"))
      ),
      InvestmentTransactionReprocess: object(
        {
          status:       { type: :string, enum: %w[updated skipped] },
          as_of_date:   DATE,
          market_value: NUMBER,
          reason:       STRING
        },
        optional: %i[as_of_date market_value reason]
      ),
      InvestmentLot: object(INVESTMENT_LOT_FIELDS.merge(
        id:          UUID,
        security_id: UUID,
        notes:       nullable(STRING)
      )),
      InvestmentLotPreview: object(INVESTMENT_LOT_FIELDS.merge(
        account_id:    UUID,
        acquired_date: DATE,
        description:   nullable(STRING)
      )),

      # ── Reconciliation ────────────────────────────────────────────────────
      ReconciliationAcceptResult: object(
        status: { type: :string, enum: %w[adjusted in_sync already_accepted no_observation] },
        delta:  NUMBER
      ),

      # ── Sitewide search ───────────────────────────────────────────────────
      SearchResults: object(
        merchants:               { type: :array, items: object(id: UUID, name: STRING, category_name: nullable(STRING)) },
        categories:              { type: :array, items: object(id: UUID, name: STRING, parent_name: nullable(STRING)) },
        tags:                    { type: :array, items: ref("TagRef") },
        accounts:                {
          type: :array,
          items: object(id: UUID, name: STRING, account_type: nullable(STRING), kind: { type: :string, enum: ACCOUNT_KINDS })
        },
        transactions:            {
          type: :array,
          items: object(
            id: UUID, description: nullable(STRING), amount: NUMBER, transaction_date: DATE,
            merchant_name: nullable(STRING), category_name: nullable(STRING)
          )
        },
        loans:                   { type: :array, items: object(id: UUID, name: STRING, lender: nullable(STRING)) },
        investment_transactions: {
          type: :array,
          items: object(
            id: UUID, description: nullable(STRING), amount: nullable(NUMBER), trade_date: DATE,
            security_id: nullable(UUID), security_ticker: nullable(STRING), security_name: nullable(STRING)
          )
        },
        securities:              {
          type: :array,
          items: object(id: UUID, name: nullable(STRING), ticker: nullable(STRING), security_type: nullable(STRING))
        }
      )
    )
  end
end
