# Component schemas for the wealth/analytics endpoints: cashflow, subscriptions,
# portfolio, market, loans, net worth, real estate, budget, equity, tax, stats
# and review. Names match frontend/src/api/types.ts so the generated types can
# alias one-to-one.

OpenapiSchemas.register({
  ActivityData: {
    type: :object,
    properties: {
      days: { type: :array, items: { "$ref" => "#/components/schemas/ActivityDay" } },
      net: { type: :number },
      total_income: { type: :number },
      total_spend: { type: :number }
    },
    required: %w[days total_spend total_income net]
  },
  ActivityDay: {
    type: :object,
    properties: { date: { type: :string }, income: { type: :number }, spend: { type: :number } },
    required: %w[date spend income]
  },
  AmortizationEntry: {
    type: :object,
    properties: {
      balance: { type: :number },
      escrow: { type: :number },
      interest: { type: :number },
      payment: { type: :number },
      payment_date: { type: :string },
      payment_number: { type: :number },
      principal: { type: :number }
    },
    required: %w[payment_number payment_date payment principal interest escrow balance]
  },
  BenchmarkEntry: {
    type: :object,
    properties: {
      label: { type: :string },
      prices: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      symbol: { type: :string },
      syncing: { type: :boolean }
    },
    required: %w[symbol label prices syncing]
  },
  BenchmarkMeta: {
    type: :object,
    properties: { label: { type: :string }, symbol: { type: :string } },
    required: %w[symbol label]
  },
  BudgetAutofillResult: {
    type: :object,
    properties: { filled: { type: :number } },
    required: %w[filled]
  },
  BudgetPeriod: {
    type: :object,
    properties: {
      income_planned: { type: :number, nullable: true },
      month: { type: :string },
      other_planned: { type: :number, nullable: true }
    },
    required: %w[month income_planned other_planned]
  },
  BudgetCalendarCell: {
    type: :object,
    properties: {
      actual: { type: :number },
      override: { type: :boolean, description: "This month has its own one-month amount" },
      planned: { type: :number, nullable: true }
    },
    required: %w[planned override actual]
  },
  BudgetCalendarData: {
    type: :object,
    properties: {
      months: { type: :array, items: { type: :string } },
      rows: { type: :array, items: { "$ref" => "#/components/schemas/BudgetCalendarRow" } },
      totals: { type: :object, additionalProperties: { "$ref" => "#/components/schemas/BudgetCalendarCell" } },
      year: { type: :number }
    },
    required: %w[year months rows totals]
  },
  BudgetCalendarRow: {
    type: :object,
    properties: {
      annual: { type: :number, nullable: true, description: "A yearly budget's amount" },
      category_id: { type: :string },
      category_name: { type: :string },
      months: { type: :object, additionalProperties: { "$ref" => "#/components/schemas/BudgetCalendarCell" } },
      parent_id: { type: :string, nullable: true },
      period: { "$ref" => "#/components/schemas/BudgetPeriodKind" },
      total_actual: { type: :number },
      total_planned: { type: :number }
    },
    required: %w[category_id category_name parent_id period annual months total_planned total_actual]
  },
  BudgetData: {
    type: :object,
    properties: {
      actual: { type: :number },
      everything_else: {
        type: :object,
        description: "Spend outside every budgeted category, and the household's optional amount for it",
        properties: {
          actual: { type: :number },
          planned: { type: :number, nullable: true },
          projected: { type: :number, nullable: true },
          remaining: { type: :number, nullable: true },
          uncategorized: { type: :number }
        },
        required: %w[planned actual uncategorized remaining projected]
      },
      forecast: {
        type: :object,
        nullable: true,
        description: "End-of-month projection (current month only)",
        properties: {
          available: { type: :number },
          over_by: { type: :number },
          overages: {
            type: :array,
            items: {
              type: :object,
              properties: { category_id: { type: :string }, category_name: { type: :string }, over: { type: :number } },
              required: %w[category_id category_name over]
            }
          },
          projected: { type: :number }
        },
        required: %w[projected available over_by overages]
      },
      income: {
        type: :object,
        properties: {
          actual: { type: :number },
          planned: { type: :number, nullable: true },
          suggestion: { type: :number, nullable: true }
        },
        required: %w[planned actual suggestion]
      },
      left_to_plan: { type: :number, nullable: true },
      lines: { type: :array, items: { "$ref" => "#/components/schemas/BudgetLine" } },
      month: { type: :string },
      pace: {
        type: :object,
        properties: { current: { type: :boolean }, percent_elapsed: { type: :number } },
        required: %w[percent_elapsed current]
      },
      planned: { type: :number },
      remaining: { type: :number },
      yearly: {
        type: :object,
        properties: {
          actual: { type: :number },
          lines: { type: :array, items: { "$ref" => "#/components/schemas/BudgetLine" } },
          planned: { type: :number },
          remaining: { type: :number },
          set_aside: { type: :number, description: "Yearly amounts ÷ 12" }
        },
        required: %w[planned actual remaining set_aside lines]
      }
    },
    required: %w[month income planned actual remaining left_to_plan lines yearly everything_else pace forecast]
  },
  BudgetKind: { type: :string, enum: [ "fixed", "flex", "non_monthly" ] },
  BudgetLine: {
    type: :object,
    properties: {
      actual: { type: :number, description: "This month's spend; year to date for a yearly line" },
      category_id: { type: :string },
      category_name: { type: :string },
      id: { type: :string, nullable: true },
      mode: { type: :string, enum: %w[ongoing month_only] },
      month_actual: { type: :number },
      parent_id: { type: :string, nullable: true },
      parent_name: { type: :string, nullable: true },
      percent_used: { type: :number },
      period: { "$ref" => "#/components/schemas/BudgetPeriodKind" },
      planned: { type: :number },
      projected: { type: :number, nullable: true },
      remaining: { type: :number },
      rolled_up_children: { type: :array, items: { "$ref" => "#/components/schemas/BudgetLineRolledUpChild" } },
      rollover: { type: :boolean },
      rollover_amount: { type: :number },
      set_in: { type: :string, description: "YYYY-MM the amount was set" },
      typical: { type: :number, description: "Median monthly spend (trailing-year total for a yearly line)" }
    },
    required: %w[id category_id category_name parent_id parent_name period mode set_in planned rollover rollover_amount actual month_actual remaining percent_used typical projected rolled_up_children]
  },
  BudgetLineHistory: {
    type: :object,
    properties: {
      category_id: { type: :string },
      months: { type: :array, items: { "$ref" => "#/components/schemas/BudgetLineHistoryMonth" } }
    },
    required: %w[category_id months]
  },
  BudgetLineHistoryMonth: {
    type: :object,
    properties: { actual: { type: :number }, month: { type: :string }, planned: { type: :number } },
    required: %w[month planned actual]
  },
  BudgetLineRolledUpChild: {
    type: :object,
    properties: { actual: { type: :number }, category_id: { type: :string }, name: { type: :string } },
    required: %w[category_id name actual]
  },
  BudgetPeriodKind: { type: :string, enum: %w[monthly yearly] },
  BudgetSuggestion: {
    type: :object,
    properties: {
      budgeted: { type: :boolean },
      category_id: { type: :string },
      category_name: { type: :string },
      history: {
        type: :array,
        items: {
          type: :object,
          properties: { actual: { type: :number }, month: { type: :string } },
          required: %w[month actual]
        }
      },
      parent_id: { type: :string, nullable: true },
      parent_name: { type: :string, nullable: true },
      recurring_monthly: { type: :number },
      suggested: { type: :number },
      typical: { type: :number },
      unusual: {
        type: :array,
        items: {
          type: :object,
          properties: {
            amount: { type: :number },
            description: { type: :string, nullable: true },
            id: { type: :string },
            transaction_date: { type: :string }
          },
          required: %w[id transaction_date description amount]
        }
      },
      year_total: { type: :number }
    },
    required: %w[category_id category_name parent_id parent_name budgeted typical suggested year_total recurring_monthly history unusual]
  },
  BudgetSuggestions: {
    type: :object,
    properties: {
      categories: { type: :array, items: { "$ref" => "#/components/schemas/BudgetSuggestion" } },
      everything_else: {
        type: :object,
        properties: { suggested: { type: :number }, typical: { type: :number } },
        required: %w[typical suggested]
      },
      month: { type: :string }
    },
    required: %w[month categories everything_else]
  },
  BuysData: {
    type: :object,
    properties: {
      by_account: { type: :object, additionalProperties: { type: :number } },
      cumulative_invested: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      monthly_volume: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      top_securities: { type: :array, items: { "$ref" => "#/components/schemas/TopSecurity" } },
      totals: {
        type: :object,
        properties: {
          all_time: { type: :number },
          avg: { type: :number },
          count: { type: :number },
          count_12mo: { type: :number },
          last_12mo: { type: :number },
          ytd: { type: :number }
        },
        required: %w[all_time ytd last_12mo count count_12mo avg]
      },
      transactions: { type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" } }
    },
    required: %w[totals monthly_volume top_securities by_account cumulative_invested transactions]
  },
  CandleData: {
    type: :object,
    properties: {
      candles: { type: :array, items: { "$ref" => "#/components/schemas/CandlePoint" } },
      events: { type: :array, items: { "$ref" => "#/components/schemas/CorporateEvent" } },
      granularity: { type: :string, enum: [ "1d", "1w" ] },
      id: { type: :string },
      latest_price: { allOf: [ { "$ref" => "#/components/schemas/LatestPrice" } ], nullable: true },
      prev_close: { type: :number, nullable: true },
      range: { "$ref" => "#/components/schemas/CandleRange" },
      ticker: { type: :string, nullable: true }
    },
    required: %w[id ticker range granularity prev_close latest_price candles events]
  },
  CandlePoint: {
    type: :object,
    properties: {
      c: { type: :number },
      h: { type: :number, nullable: true },
      l: { type: :number, nullable: true },
      o: { type: :number, nullable: true },
      t: { type: :string },
      v: { type: :number, nullable: true }
    },
    required: %w[t o h l c v]
  },
  CandleRange: { type: :string, enum: [ "1m", "3m", "6m", "ytd", "1y", "5y", "max" ] },
  CashflowData: {
    type: :object,
    properties: {
      card_payments: {
        type: :object,
        properties: {
          card_spend_90d: { type: :number },
          lmo: { type: :number },
          mtd: { type: :number },
          paid_90d: { type: :number }
        },
        required: %w[mtd lmo card_spend_90d paid_90d]
      },
      monthly_income: { type: :object, additionalProperties: { type: :number } },
      monthly_spend: { type: :object, additionalProperties: { type: :number } },
      monthly_spend_common: { type: :object, additionalProperties: { type: :number } },
      outliers: { type: :array, items: { "$ref" => "#/components/schemas/SpendingOutlier" } },
      payment_suspects: { type: :number },
      summary: {
        type: :object,
        properties: {
          lmo_income: { type: :number },
          lmo_spend: { type: :number },
          lmo_spend_common: { type: :number },
          mtd_income: { type: :number },
          mtd_net: { type: :number },
          mtd_spend: { type: :number },
          mtd_spend_common: { type: :number },
          savings_rate_ytd: { type: :number, nullable: true },
          ytd_income: { type: :number },
          ytd_net: { type: :number },
          ytd_spend: { type: :number },
          ytd_spend_common: { type: :number }
        },
        required: %w[mtd_income mtd_spend mtd_spend_common mtd_net lmo_income lmo_spend lmo_spend_common ytd_income ytd_spend ytd_spend_common ytd_net savings_rate_ytd]
      },
      top_categories: { type: :array, items: { "$ref" => "#/components/schemas/SpendTotal" } },
      top_categories_common: { type: :array, items: { "$ref" => "#/components/schemas/SpendTotal" } },
      top_income_sources: { type: :object, additionalProperties: { type: :number } },
      top_merchants: { type: :array, items: { "$ref" => "#/components/schemas/SpendTotal" } },
      top_merchants_common: { type: :array, items: { "$ref" => "#/components/schemas/SpendTotal" } }
    },
    required: %w[summary card_payments payment_suspects monthly_income monthly_spend monthly_spend_common top_categories top_categories_common top_merchants top_merchants_common top_income_sources outliers]
  },
  CashflowSankeyData: {
    type: :object,
    properties: {
      common: {
        type: :object,
        properties: {
          links: {
            type: :array,
            items: {
              type: :object,
              properties: { source: { type: :number }, target: { type: :number }, value: { type: :number } },
              required: %w[source target value]
            }
          },
          nodes: { type: :array, items: { "$ref" => "#/components/schemas/CashflowSankeyNode" } },
          outlier_transaction_ids: { type: :array, items: { type: :string } },
          totals: {
            type: :object,
            properties: { income: { type: :number }, savings: { type: :number }, spend: { type: :number } },
            required: %w[income spend savings]
          }
        },
        required: %w[links nodes outlier_transaction_ids totals]
      },
      from: { type: :string },
      links: {
        type: :array,
        items: {
          type: :object,
          properties: { source: { type: :number }, target: { type: :number }, value: { type: :number } },
          required: %w[source target value]
        }
      },
      nodes: { type: :array, items: { "$ref" => "#/components/schemas/CashflowSankeyNode" } },
      to: { type: :string },
      totals: {
        type: :object,
        properties: { income: { type: :number }, savings: { type: :number }, spend: { type: :number } },
        required: %w[income spend savings]
      }
    },
    required: %w[common from links nodes to totals]
  },
  CashflowSankeyMember: {
    type: :object,
    properties: {
      category_id: { type: :string, nullable: true },
      category_ids: { type: :array, items: { type: :string } },
      merchant_id: { type: :string, nullable: true },
      name: { type: :string },
      value: { type: :number }
    },
    required: %w[name value]
  },
  CashflowSankeyNode: {
    type: :object,
    properties: {
      category_id: { type: :string, nullable: true },
      category_ids: { type: :array, items: { type: :string } },
      kind: { "$ref" => "#/components/schemas/CashflowSankeyNodeKind" },
      members: { type: :array, items: { "$ref" => "#/components/schemas/CashflowSankeyMember" } },
      merchant_id: { type: :string, nullable: true },
      name: { type: :string }
    },
    required: %w[name kind]
  },
  CashflowSankeyNodeKind: { type: :string, enum: [ "income_source", "shortfall", "hub", "category", "savings" ] },
  CompactStats: {
    type: :object,
    properties: {
      cc_avg: { type: :number, nullable: true },
      cc_avg_change: { type: :number, nullable: true },
      cc_count: { type: :number },
      cc_count_change: { type: :number, nullable: true },
      income: { type: :number },
      income_change: { type: :number, nullable: true },
      spend: { type: :number },
      spend_change: { type: :number, nullable: true }
    },
    required: %w[spend spend_change income income_change cc_count cc_count_change cc_avg cc_avg_change]
  },
  CorporateEvent: {
    type: :object,
    properties: {
      amount: { type: :number, nullable: true },
      date: { type: :string },
      kind: { type: :string, enum: [ "split", "dividend" ] },
      ratio: { type: :number, nullable: true }
    },
    required: %w[kind date ratio amount]
  },
  CostBasisData: {
    type: :object,
    properties: {
      positions: { type: :array, items: { "$ref" => "#/components/schemas/CostBasisPosition" } },
      summary: {
        type: :object,
        properties: {
          complete: { type: :number },
          known_cost_basis: { type: :number },
          partial: { type: :number },
          total_positions: { type: :number },
          total_value: { type: :number },
          unknown: { type: :number }
        },
        required: %w[total_positions complete partial unknown total_value known_cost_basis]
      }
    },
    required: %w[summary positions]
  },
  CostBasisLot: {
    type: :object,
    properties: {
      account_id: { type: :string, nullable: true },
      account_name: { type: :string, nullable: true },
      acquired_date: { type: :string, nullable: true },
      cost_basis: { type: :number },
      id: { type: :string },
      notes: { type: :string, nullable: true },
      quantity: { type: :number },
      unit_cost: { type: :number, nullable: true }
    },
    required: %w[id account_id account_name acquired_date quantity cost_basis unit_cost notes]
  },
  CostBasisPosition: {
    type: :object,
    properties: {
      asset_class: { type: :string, nullable: true },
      avg_cost_per_share: { type: :number, nullable: true },
      bought_quantity: { type: :number },
      computed_cost_basis: { type: :number, nullable: true },
      current_quantity: { type: :number },
      current_value: { type: :number },
      earliest_transaction: { type: :string, nullable: true },
      gap_quantity: { type: :number },
      label: { type: :string, nullable: true },
      lots: { type: :array, items: { "$ref" => "#/components/schemas/CostBasisLot" } },
      name: { type: :string, nullable: true },
      net_quantity: { type: :number },
      security_id: { type: :string },
      sold_quantity: { type: :number },
      status: { type: :string, enum: [ "complete", "partial", "unknown" ] },
      ticker: { type: :string, nullable: true },
      transaction_count: { type: :number },
      unrealized_gl: { type: :number, nullable: true }
    },
    required: %w[security_id ticker name label current_quantity current_value asset_class bought_quantity sold_quantity net_quantity gap_quantity computed_cost_basis avg_cost_per_share unrealized_gl status transaction_count earliest_transaction lots]
  },
  CryptoData: {
    type: :object,
    properties: {
      balance_history: { type: :object, additionalProperties: { type: :number } },
      by_account: { type: :object, additionalProperties: { type: :number } },
      cumulative_invested: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      monthly_volume: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      positions: { type: :array, items: { "$ref" => "#/components/schemas/CryptoPosition" } },
      recent: { type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" } },
      summary: {
        type: :object,
        properties: {
          buy_count: { type: :number },
          total_cost: { type: :number },
          total_invested: { type: :number },
          total_value: { type: :number },
          unrealized_gl: { type: :number },
          ytd_invested: { type: :number }
        },
        required: %w[total_value total_cost unrealized_gl total_invested buy_count ytd_invested]
      },
      top_assets: { type: :array, items: { "$ref" => "#/components/schemas/TopSecurity" } }
    },
    required: %w[summary positions balance_history monthly_volume cumulative_invested top_assets by_account recent]
  },
  CryptoPosition: {
    type: :object,
    properties: {
      cost_basis: { type: :number },
      cusip: { type: :string, nullable: true },
      id: { type: :string },
      label: { type: :string, nullable: true },
      market_value: { type: :number },
      name: { type: :string, nullable: true },
      price: { type: :number },
      quantity: { type: :number },
      security_id: { type: :string },
      ticker: { type: :string, nullable: true },
      unrealized_gl: { type: :number },
      unrealized_gl_pct: { type: :number }
    },
    required: %w[id security_id ticker name cusip label quantity price market_value cost_basis unrealized_gl unrealized_gl_pct]
  },
  # A chart point as a two-element array. OpenAPI 3.0 has no tuple type,
  # so the element type is the union; the frontend's alias narrows it back
  # to [string, number].
  DateValuePair: {
    type: :array,
    items: { anyOf: [ { type: :string }, { type: :number } ] },
    minItems: 2,
    maxItems: 2,
    description: "[ISO date, value]"
  },
  DashboardData: {
    type: :object,
    properties: {
      activity_chart: {
        type: :array,
        items: {
          type: :object,
          properties: {
            data: {
              type: :array,
              items: { "$ref" => "#/components/schemas/DateValuePair" }
            },
            name: { type: :string }
          },
          required: %w[name data]
        }
      },
      allocation: { type: :object, additionalProperties: { type: :number } },
      compact_stats: { "$ref" => "#/components/schemas/CompactStats" },
      income_series: { type: :object, additionalProperties: { type: :number } },
      monthly_spend: { type: :object, additionalProperties: { type: :number } },
      portfolio_chart: { type: :object, additionalProperties: { type: :number } },
      recent_transactions: { type: :array, items: { "$ref" => "#/components/schemas/RecentTransaction" } },
      stats: { "$ref" => "#/components/schemas/DashboardStats" }
    },
    required: %w[stats compact_stats portfolio_chart allocation income_series monthly_spend activity_chart recent_transactions]
  },
  DashboardStats: {
    type: :object,
    properties: {
      cost_basis: { type: :number },
      income_ytd: { type: :number },
      portfolio_value: { type: :number },
      transactions: { type: :number },
      unrealized: { type: :number }
    },
    required: %w[portfolio_value unrealized cost_basis transactions income_ytd]
  },
  DividendsData: {
    type: :object,
    properties: {
      by_account: { type: :object, additionalProperties: { type: :number } },
      cumulative_dividends: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      monthly_dividends: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      top_securities: { type: :array, items: { "$ref" => "#/components/schemas/TopSecurity" } },
      totals: {
        type: :object,
        properties: {
          avg: { type: :number },
          count: { type: :number },
          count_12mo: { type: :number },
          last_12mo: { type: :number },
          lifetime: { type: :number },
          ytd: { type: :number }
        },
        required: %w[lifetime ytd last_12mo count count_12mo avg]
      },
      transactions: { type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" } }
    },
    required: %w[totals monthly_dividends top_securities by_account cumulative_dividends transactions]
  },
  EquityCompany: {
    type: :object,
    properties: {
      c_corp: { type: :boolean },
      fmv_entries: { type: :array, items: { "$ref" => "#/components/schemas/EquityFmvEntry" } },
      grants: { type: :array, items: { "$ref" => "#/components/schemas/EquityGrant" } },
      id: { type: :string },
      latest_fmv: {
        type: :object,
        properties: {
          effective_date: { type: :string },
          price_per_share: { type: :number },
          source: { type: :string },
          stale: { type: :boolean }
        },
        required: %w[effective_date price_per_share source stale],
        nullable: true
      },
      name: { type: :string },
      notes: { type: :string, nullable: true },
      preferred_price: { type: :number, nullable: true },
      public_company: { type: :boolean },
      qsbs_candidate: { type: :boolean },
      security_id: { type: :string, nullable: true },
      share_price: { type: :number, nullable: true },
      ticker: { type: :string, nullable: true }
    },
    required: %w[id name public_company security_id ticker c_corp qsbs_candidate preferred_price notes share_price latest_fmv fmv_entries grants]
  },
  EquityEventKind: { type: :string, enum: [ "exercise", "settlement", "sale", "cancellation" ] },
  EquityFmvEntry: {
    type: :object,
    properties: {
      effective_date: { type: :string },
      id: { type: :string },
      price_per_share: { type: :number },
      source: { type: :string }
    },
    required: %w[id price_per_share effective_date source]
  },
  EquityGrant: {
    type: :object,
    properties: {
      cliff_installments: { type: :number },
      custom_tranches: {
        type: :array,
        items: {
          type: :object,
          properties: { date: { type: :string }, quantity: { type: :number } },
          required: %w[date quantity]
        },
        nullable: true
      },
      double_trigger: { type: :boolean },
      early_exercisable: { type: :boolean },
      events: { type: :array, items: { "$ref" => "#/components/schemas/EquityGrantEvent" } },
      exercised_quantity: { type: :number },
      expiration_date: { type: :string, nullable: true },
      grant_date: { type: :string },
      grant_type: { "$ref" => "#/components/schemas/EquityGrantType" },
      id: { type: :string },
      label: { type: :string, nullable: true },
      next_vest: {
        type: :object,
        properties: { date: { type: :string }, quantity: { type: :number } },
        required: %w[date quantity],
        nullable: true
      },
      notes: { type: :string, nullable: true },
      pte_window_days: { type: :number, nullable: true },
      quantity: { type: :number },
      settled_quantity: { type: :number },
      sold_quantity: { type: :number },
      strike_price: { type: :number, nullable: true },
      tranches: { type: :array, items: { "$ref" => "#/components/schemas/EquityTranche" } },
      unvested_quantity: { type: :number },
      unvested_value: { type: :number, nullable: true },
      vested_quantity: { type: :number },
      vested_value: { type: :number, nullable: true },
      vesting_commencement_date: { type: :string },
      vesting_interval: { type: :string, nullable: true },
      vesting_occurrences: { type: :number, nullable: true }
    },
    required: %w[id label grant_type grant_date vesting_commencement_date quantity strike_price early_exercisable double_trigger expiration_date pte_window_days vesting_interval vesting_occurrences cliff_installments custom_tranches notes vested_quantity unvested_quantity exercised_quantity settled_quantity sold_quantity vested_value unvested_value next_vest tranches events]
  },
  EquityGrantEvent: {
    type: :object,
    properties: {
      buyer_type: { type: :string, nullable: true },
      election_83b: { type: :boolean },
      election_83b_date: { type: :string, nullable: true },
      id: { type: :string },
      kind: { "$ref" => "#/components/schemas/EquityEventKind" },
      method: { type: :string, nullable: true },
      notes: { type: :string, nullable: true },
      occurred_on: { type: :string },
      quantity: { type: :number },
      share_price: { type: :number, nullable: true },
      shares_withheld: { type: :number, nullable: true }
    },
    required: %w[id kind occurred_on quantity share_price method buyer_type election_83b election_83b_date shares_withheld notes]
  },
  EquityGrantType: { type: :string, enum: [ "iso", "nso", "rsu", "rsa" ] },
  EquitySummary: {
    type: :object,
    properties: {
      companies: { type: :array, items: { "$ref" => "#/components/schemas/EquityCompany" } },
      totals: {
        type: :object,
        properties: {
          unvested_value: { type: :number },
          upcoming_vests: { type: :array, items: { "$ref" => "#/components/schemas/EquityUpcomingVest" } },
          vested_value: { type: :number }
        },
        required: %w[vested_value unvested_value upcoming_vests]
      }
    },
    required: %w[companies totals]
  },
  EquityTranche: {
    type: :object,
    properties: { date: { type: :string }, quantity: { type: :number }, vested: { type: :boolean } },
    required: %w[date quantity vested]
  },
  EquityUpcomingVest: {
    type: :object,
    properties: {
      company_id: { type: :string },
      company_name: { type: :string },
      date: { type: :string },
      grant_id: { type: :string },
      grant_label: { type: :string, nullable: true },
      grant_type: { "$ref" => "#/components/schemas/EquityGrantType" },
      quantity: { type: :number },
      value: { type: :number, nullable: true }
    },
    required: %w[date quantity value grant_id grant_label grant_type company_id company_name]
  },
  ExercisePlan: {
    type: :object,
    properties: {
      crossover: {
        type: :object,
        properties: {
          binding: { type: :string, enum: [ "federal", "california" ] },
          shares: { type: :number },
          spread: { type: :number }
        },
        required: %w[shares spread binding],
        nullable: true
      },
      curve: {
        type: :array,
        items: {
          type: :object,
          properties: {
            california_amt: { type: :number },
            federal_amt: { type: :number },
            quantity: { type: :number },
            total: { type: :number }
          },
          required: %w[quantity federal_amt california_amt total]
        }
      },
      escape_hatch_deadline: { type: :string },
      exclusions: { type: :array, items: { type: :string } },
      exercisable_quantity: { type: :number },
      figures_status: {
        type: :object,
        properties: { federal: { type: :string }, state: { type: :string } },
        required: %w[federal state]
      },
      nso_gap: { allOf: [ { "$ref" => "#/components/schemas/ExercisePlanNsoGap" } ], nullable: true },
      profile: { "$ref" => "#/components/schemas/TaxProfile" },
      safe_harbor: {
        type: :object,
        properties: {
          california: { "$ref" => "#/components/schemas/ExercisePlanSafeHarbor" },
          federal: { "$ref" => "#/components/schemas/ExercisePlanSafeHarbor" }
        },
        required: %w[federal california]
      },
      scenarios: { type: :object, additionalProperties: { "$ref" => "#/components/schemas/ExercisePlanScenario" } },
      share_price: { type: :number },
      simulation: {
        type: :object,
        properties: {
          california_amt: { type: :number },
          exercise_cost: { type: :number },
          federal_amt: { type: :number },
          marginal_rate_next_share: { type: :number },
          post_exercise_agi: { type: :number },
          post_exercise_federal_amti: { type: :number },
          quantity: { type: :number },
          spread: { type: :number },
          total_cash_needed: { type: :number }
        },
        required: %w[quantity spread federal_amt california_amt exercise_cost total_cash_needed marginal_rate_next_share post_exercise_agi
                     post_exercise_federal_amti]
      },
      stress: {
        type: :object,
        properties: {
          drop_pct: { type: :number },
          price_after: { type: :number },
          share_value_after: { type: :number },
          tax_still_owed: { type: :number },
          underwater: { type: :number }
        },
        required: %w[drop_pct price_after share_value_after tax_still_owed underwater]
      },
      strike_price: { type: :number },
      tax_year: { type: :number }
    },
    required: %w[tax_year figures_status share_price strike_price exercisable_quantity crossover simulation curve scenarios safe_harbor stress nso_gap escape_hatch_deadline exclusions profile]
  },
  ExercisePlanNsoGap: {
    type: :object,
    properties: {
      california_gap: { type: :number },
      california_marginal_rate: { type: :number },
      california_withholding_rate: { type: :number },
      federal_gap: { type: :number },
      federal_marginal_rate: { type: :number },
      federal_withholding_rate: { type: :number },
      spread: { type: :number },
      total_gap: { type: :number }
    },
    required: %w[spread federal_marginal_rate federal_withholding_rate federal_gap california_marginal_rate california_withholding_rate california_gap total_gap]
  },
  ExercisePlanSafeHarbor: {
    type: :object,
    properties: {
      current_agi: { type: :number, nullable: true },
      installment_weights: { type: :array, items: { type: :number }, nullable: true },
      note: { type: :string, nullable: true },
      paid: { type: :number, nullable: true },
      required_annual: { type: :number, nullable: true },
      set_aside: { type: :number, nullable: true },
      status: { type: :string, enum: [ "covered", "uncovered", "unknown", "unavailable" ] },
      withheld: { type: :number, nullable: true }
    },
    required: %w[status]
  },
  ExercisePlanScenario: {
    type: :object,
    properties: {
      california: { type: :number },
      exercise_year: {
        type: :object,
        properties: { california: { type: :number }, federal: { type: :number } },
        required: %w[federal california]
      },
      federal: { type: :number },
      note: { type: :string, nullable: true },
      nso_gap: { allOf: [ { "$ref" => "#/components/schemas/ExercisePlanNsoGap" } ], nullable: true },
      proceeds: { type: :number, nullable: true },
      sale_year: {
        type: :object,
        properties: { california: { type: :number }, federal: { type: :number } },
        required: %w[federal california]
      }
    }
  },
  IndexStat: {
    type: :object,
    properties: {
      close: { type: :number, nullable: true },
      date: { type: :string, nullable: true },
      day_change_pct: { type: :number, nullable: true },
      label: { type: :string },
      spark: { type: :array, items: { type: :number } },
      symbol: { type: :string }
    },
    required: %w[symbol label close date day_change_pct spark]
  },
  InstrumentClass: {
    type: :string,
    enum: [
      "equity",
      "etf",
      "mutual_fund",
      "bond",
      "cash_equivalent",
      "crypto",
      "commodity",
      "option",
      "fx",
      "real_asset",
      "other"
    ]
  },
  LatestPrice: {
    type: :object,
    properties: {
      age_days: { type: :number },
      close: { type: :number },
      date: { type: :string },
      source: { "$ref" => "#/components/schemas/PriceSource" }
    },
    required: %w[date close source age_days]
  },
  Loan: {
    type: :object,
    properties: {
      account_id: { type: :string, nullable: true },
      account_name: { type: :string, nullable: true },
      balance_anchor_amount: { type: :number, nullable: true },
      balance_anchor_date: { type: :string, nullable: true },
      created_at: { type: :string },
      current_balance: { type: :number },
      entered_monthly_payment: { type: :number, nullable: true },
      escrow_insurance: { type: :number, nullable: true },
      escrow_other: { type: :number, nullable: true },
      escrow_paid: { type: :number },
      escrow_payment: { type: :number },
      escrow_property_tax: { type: :number, nullable: true },
      id: { type: :string },
      insurance_paid: { type: :number },
      interest_only: { type: :boolean },
      interest_paid: { type: :number },
      interest_rate: { type: :number },
      lender: { type: :string, nullable: true },
      loan_type: { type: :string },
      merchant_id: { type: :string, nullable: true },
      merchant_name: { type: :string, nullable: true },
      monthly_payment: { type: :number },
      name: { type: :string },
      notes: { type: :string, nullable: true },
      original_principal: { type: :number },
      other_escrow_paid: { type: :number },
      payments_count: { type: :number },
      principal_and_interest_payment: { type: :number },
      principal_paid: { type: :number },
      property_tax_paid: { type: :number },
      start_date: { type: :string },
      status: { type: :string, enum: [ "active", "paid_off", "refinanced" ] },
      term_months: { type: :number },
      total_paid: { type: :number },
      total_scheduled_interest: { type: :number },
      updated_at: { type: :string }
    },
    required: %w[id name lender loan_type original_principal interest_rate term_months start_date monthly_payment entered_monthly_payment principal_and_interest_payment escrow_property_tax escrow_insurance escrow_other escrow_payment status notes interest_only merchant_id merchant_name account_id account_name balance_anchor_amount balance_anchor_date total_scheduled_interest total_paid principal_paid interest_paid escrow_paid property_tax_paid insurance_paid other_escrow_paid current_balance payments_count created_at updated_at]
  },
  LoanDetail: {
    type: :object,
    properties: {
      account_id: { type: :string, nullable: true },
      account_name: { type: :string, nullable: true },
      amortization_schedule: { type: :array, items: { "$ref" => "#/components/schemas/AmortizationEntry" } },
      balance_anchor_amount: { type: :number, nullable: true },
      balance_anchor_date: { type: :string, nullable: true },
      created_at: { type: :string },
      current_balance: { type: :number },
      entered_monthly_payment: { type: :number, nullable: true },
      escrow_insurance: { type: :number, nullable: true },
      escrow_other: { type: :number, nullable: true },
      escrow_paid: { type: :number },
      escrow_payment: { type: :number },
      escrow_property_tax: { type: :number, nullable: true },
      id: { type: :string },
      insurance_paid: { type: :number },
      interest_only: { type: :boolean },
      interest_paid: { type: :number },
      interest_rate: { type: :number },
      lender: { type: :string, nullable: true },
      linked_transactions: { type: :array, items: { "$ref" => "#/components/schemas/LoanTransaction" } },
      loan_type: { type: :string },
      merchant_id: { type: :string, nullable: true },
      merchant_name: { type: :string, nullable: true },
      monthly_payment: { type: :number },
      name: { type: :string },
      notes: { type: :string, nullable: true },
      original_principal: { type: :number },
      other_escrow_paid: { type: :number },
      payments_count: { type: :number },
      principal_and_interest_payment: { type: :number },
      principal_paid: { type: :number },
      property_tax_paid: { type: :number },
      start_date: { type: :string },
      status: { type: :string, enum: [ "active", "paid_off", "refinanced" ] },
      term_months: { type: :number },
      total_paid: { type: :number },
      total_scheduled_interest: { type: :number },
      updated_at: { type: :string }
    },
    required: %w[account_id account_name amortization_schedule balance_anchor_amount balance_anchor_date created_at current_balance entered_monthly_payment escrow_insurance escrow_other escrow_paid escrow_payment escrow_property_tax id insurance_paid interest_only interest_paid interest_rate lender linked_transactions loan_type merchant_id merchant_name monthly_payment name notes original_principal other_escrow_paid payments_count principal_and_interest_payment principal_paid property_tax_paid start_date status term_months total_paid total_scheduled_interest updated_at]
  },
  LoanTransaction: {
    type: :object,
    properties: {
      account_name: { type: :string, nullable: true },
      amount: { type: :number },
      description: { type: :string },
      id: { type: :string },
      transaction_date: { type: :string }
    },
    required: %w[id transaction_date description amount account_name]
  },
  MarketNewsItem: {
    type: :object,
    properties: {
      param: { type: :string, nullable: true },
      published_at: { type: :string },
      sentiment: { type: :string, nullable: true },
      sentiment_score: { type: :number, nullable: true },
      source: { type: :string },
      summary: { type: :string },
      ticker: { type: :string, nullable: true },
      title: { type: :string },
      url: { type: :string }
    },
    required: %w[param published_at sentiment sentiment_score source summary ticker title url]
  },
  MarketSummaryData: {
    type: :object,
    properties: {
      as_of: { type: :string },
      indices: { type: :array, items: { "$ref" => "#/components/schemas/IndexStat" } },
      movers: {
        type: :object,
        properties: {
          gainers: { type: :array, items: { "$ref" => "#/components/schemas/MoverStat" } },
          losers: { type: :array, items: { "$ref" => "#/components/schemas/MoverStat" } }
        },
        required: %w[gainers losers]
      },
      news: { type: :array, items: { "$ref" => "#/components/schemas/MarketNewsItem" } }
    },
    required: %w[as_of indices movers news]
  },
  MoverStat: {
    type: :object,
    properties: {
      close: { type: :number, nullable: true },
      day_change_pct: { type: :number },
      display_name: { type: :string },
      id: { type: :string },
      instrument_class: { "$ref" => "#/components/schemas/InstrumentClass" },
      name: { type: :string, nullable: true },
      param: { type: :string },
      spark: { type: :array, items: { type: :number } },
      ticker: { type: :string, nullable: true }
    },
    required: %w[id param ticker name display_name instrument_class close day_change_pct spark]
  },
  NetWorthAccountRow: {
    type: :object,
    properties: {
      account_type: { type: :string, nullable: true },
      broker: { type: :string, nullable: true },
      change: { type: :number },
      change_pct: { type: :number, nullable: true },
      group: { "$ref" => "#/components/schemas/NetWorthGroup" },
      id: { type: :string },
      name: { type: :string },
      start_value: { type: :number, nullable: true },
      value: { type: :number }
    },
    required: %w[id name broker account_type group value start_value change change_pct]
  },
  NetWorthChange: {
    type: :object,
    properties: { amount: { type: :number }, pct: { type: :number, nullable: true } },
    required: %w[amount pct]
  },
  NetWorthData: {
    type: :object,
    properties: {
      accounts: { type: :array, items: { "$ref" => "#/components/schemas/NetWorthAccountRow" } },
      equity: { type: :array, items: { "$ref" => "#/components/schemas/NetWorthEquityRow" } },
      from: { type: :string },
      loans: { type: :array, items: { "$ref" => "#/components/schemas/NetWorthLoanRow" } },
      monthly_deltas: {
        type: :array,
        items: {
          type: :object,
          properties: { change: { type: :number }, month: { type: :string } },
          required: %w[month change]
        }
      },
      properties: { type: :array, items: { "$ref" => "#/components/schemas/NetWorthPropertyRow" } },
      range: { "$ref" => "#/components/schemas/NetWorthRange" },
      series: { type: :array, items: { "$ref" => "#/components/schemas/NetWorthSeriesPoint" } },
      stats: { "$ref" => "#/components/schemas/NetWorthStats" },
      to: { type: :string }
    },
    required: %w[range series stats monthly_deltas accounts loans properties equity]
  },
  NetWorthEquityRow: {
    type: :object,
    properties: {
      change: { type: :number },
      change_pct: { type: :number, nullable: true },
      grant_count: { type: :number },
      id: { type: :string },
      include_unvested: { type: :boolean },
      name: { type: :string },
      public_company: { type: :boolean },
      start_value: { type: :number, nullable: true },
      ticker: { type: :string, nullable: true },
      unvested_value: { type: :number },
      value: { type: :number },
      vested_value: { type: :number }
    },
    required: %w[id name ticker public_company grant_count value start_value change change_pct vested_value unvested_value include_unvested]
  },
  NetWorthGroup: { type: :string, enum: [ "cash", "investments", "crypto", "real_estate", "equity", "credit", "loans" ] },
  NetWorthLoanRow: {
    type: :object,
    properties: {
      change: { type: :number },
      change_pct: { type: :number, nullable: true },
      id: { type: :string },
      lender: { type: :string, nullable: true },
      loan_type: { type: :string },
      name: { type: :string },
      start_value: { type: :number, nullable: true },
      value: { type: :number }
    },
    required: %w[id name loan_type lender value start_value change change_pct]
  },
  NetWorthProjectionData: {
    type: :object,
    properties: {
      annual_growth_percent: { type: :number },
      monthly_contribution: { type: :number },
      series: {
        type: :array,
        items: {
          type: :object,
          properties: { month: { type: :string }, value: { type: :number } },
          required: %w[month value]
        }
      },
      starting: { type: :number },
      years: { type: :number }
    },
    required: %w[starting monthly_contribution annual_growth_percent years series]
  },
  NetWorthPropertyRow: {
    type: :object,
    properties: {
      address: { type: :string },
      change: { type: :number },
      change_pct: { type: :number, nullable: true },
      equity: { type: :number },
      id: { type: :string },
      mortgage_balance: { type: :number, nullable: true },
      name: { type: :string },
      start_value: { type: :number, nullable: true },
      status: { "$ref" => "#/components/schemas/RealEstateStatus" },
      value: { type: :number }
    },
    required: %w[id name address status value start_value change change_pct mortgage_balance equity]
  },
  NetWorthRange: { type: :string, enum: [ "3m", "ytd", "1y", "all" ] },
  NetWorthSeriesPoint: {
    type: :object,
    properties: {
      assets: { type: :number },
      cash: { type: :number },
      credit: { type: :number },
      crypto: { type: :number },
      date: { type: :string },
      equity: { type: :number },
      investments: { type: :number },
      liabilities: { type: :number },
      loans: { type: :number },
      net: { type: :number },
      real_estate: { type: :number }
    },
    required: %w[date cash investments crypto real_estate equity credit loans assets liabilities net]
  },
  NetWorthStats: {
    type: :object,
    properties: {
      assets: { type: :number },
      cash: { type: :number },
      changes: { type: :object, additionalProperties: { "$ref" => "#/components/schemas/NetWorthChange" } },
      credit: { type: :number },
      crypto: { type: :number },
      equity: { type: :number },
      investments: { type: :number },
      liabilities: { type: :number },
      loans: { type: :number },
      net_worth: { type: :number },
      real_estate: { type: :number }
    },
    required: %w[net_worth assets liabilities cash investments crypto real_estate equity credit loans changes]
  },
  NewsArticle: {
    type: :object,
    properties: {
      published_at: { type: :string },
      sentiment: { type: :string, nullable: true },
      sentiment_score: { type: :number, nullable: true },
      source: { type: :string },
      summary: { type: :string },
      title: { type: :string },
      url: { type: :string }
    },
    required: %w[title url source published_at summary sentiment sentiment_score]
  },
  PortfolioData: {
    type: :object,
    properties: {
      as_of_date: { type: :string, nullable: true },
      by_asset_class: { type: :object, additionalProperties: { type: :number } },
      portfolio_history: { type: :object, additionalProperties: { type: :number } },
      positions: { type: :array, items: { "$ref" => "#/components/schemas/Position" } },
      summary: {
        type: :object,
        properties: {
          est_annual_income: { type: :number },
          total_cost_basis: { type: :number },
          total_value: { type: :number },
          unrealized_gl: { type: :number }
        },
        required: %w[total_value total_cost_basis unrealized_gl est_annual_income]
      }
    },
    required: %w[as_of_date summary by_asset_class portfolio_history positions]
  },
  PortfolioPerformanceData: {
    type: :object,
    properties: {
      end_value: { type: :number, nullable: true },
      from: { type: :string },
      net_external_flows: { type: :number },
      start_value: { type: :number, nullable: true },
      to: { type: :string },
      twr_annualized_pct: { type: :number, nullable: true },
      twr_pct: { type: :number, nullable: true },
      xirr_pct: { type: :number, nullable: true }
    },
    required: %w[from to start_value end_value net_external_flows twr_pct twr_annualized_pct xirr_pct]
  },
  Position: {
    type: :object,
    properties: {
      as_of_date: { type: :string },
      asset_class: { type: :string, nullable: true },
      cost_basis: { type: :number },
      dividend_yield: { type: :number },
      est_annual_income: { type: :number },
      id: { type: :string },
      market_value: { type: :number },
      price: { type: :number },
      quantity: { type: :number },
      security_cusip: { type: :string, nullable: true },
      security_id: { type: :string },
      security_label: { type: :string, nullable: true },
      security_name: { type: :string, nullable: true },
      security_ticker: { type: :string, nullable: true },
      unrealized_gl: { type: :number },
      unrealized_gl_pct: { type: :number }
    },
    required: %w[id security_id security_ticker security_name security_cusip security_label as_of_date quantity price market_value cost_basis unrealized_gl unrealized_gl_pct asset_class est_annual_income dividend_yield]
  },
  PriceSource: { type: :string, enum: [ "coin_market_cap", "alpha_vantage", "coin_gecko", "tiingo", "eod", "legacy", "custodian" ] },
  RealEstateFacts: {
    type: :object,
    properties: {
      bathrooms: { type: :number, nullable: true },
      bedrooms: { type: :number, nullable: true },
      hoa_fee: { type: :number, nullable: true },
      latitude: { type: :number, nullable: true },
      longitude: { type: :number, nullable: true },
      lot_size: { type: :number, nullable: true },
      property_type: { type: :string, nullable: true },
      square_footage: { type: :number, nullable: true },
      year_built: { type: :number, nullable: true }
    },
    required: %w[property_type bedrooms bathrooms square_footage lot_size year_built hoa_fee latitude longitude]
  },
  RealEstateIndex: {
    type: :object,
    properties: {
      properties: { type: :array, items: { "$ref" => "#/components/schemas/RealEstateProperty" } },
      rentcast: {
        type: :object,
        properties: {
          configured: { type: :boolean },
          last_synced_at: { type: :string, nullable: true },
          remaining_quota: { type: :number, nullable: true },
          request_limit: { type: :number }
        },
        required: %w[configured remaining_quota request_limit last_synced_at]
      },
      totals: {
        type: :object,
        properties: {
          count: { type: :number },
          equity: { type: :number },
          mortgage: { type: :number },
          value: { type: :number }
        },
        required: %w[value mortgage equity count]
      }
    },
    required: %w[properties totals rentcast]
  },
  RealEstateProperty: {
    type: :object,
    properties: {
      address_line1: { type: :string },
      address_line2: { type: :string, nullable: true },
      city: { type: :string, nullable: true },
      created_at: { type: :string },
      display_address: { type: :string },
      equity: { type: :number, nullable: true },
      formatted_address: { type: :string, nullable: true },
      id: { type: :string },
      last_sync_error: { type: :string, nullable: true },
      last_synced_at: { type: :string, nullable: true },
      loan_to_value: { type: :number, nullable: true },
      mortgage_balance: { type: :number, nullable: true },
      mortgages: {
        type: :array,
        items: {
          type: :object,
          properties: { id: { type: :string }, lender: { type: :string, nullable: true }, name: { type: :string } },
          required: %w[id name lender]
        }
      },
      name: { type: :string },
      purchase_date: { type: :string, nullable: true },
      purchase_price: { type: :number, nullable: true },
      sold_date: { type: :string, nullable: true },
      sold_price: { type: :number, nullable: true },
      state: { type: :string, nullable: true },
      status: { "$ref" => "#/components/schemas/RealEstateStatus" },
      sync_enabled: { type: :boolean },
      updated_at: { type: :string },
      value: { type: :number, nullable: true },
      value_as_of: { type: :string, nullable: true },
      value_high: { type: :number, nullable: true },
      value_low: { type: :number, nullable: true },
      value_source: { allOf: [ { "$ref" => "#/components/schemas/RealEstateValuationSource" } ], nullable: true },
      zip_code: { type: :string, nullable: true }
    },
    required: %w[id name address_line1 address_line2 city state zip_code formatted_address display_address status purchase_date purchase_price sold_date sold_price value value_source value_as_of value_low value_high mortgage_balance equity loan_to_value mortgages sync_enabled last_synced_at last_sync_error created_at updated_at]
  },
  RealEstatePropertyDetail: {
    type: :object,
    properties: {
      address_line1: { type: :string },
      address_line2: { type: :string, nullable: true },
      city: { type: :string, nullable: true },
      created_at: { type: :string },
      display_address: { type: :string },
      equity: { type: :number, nullable: true },
      facts: { "$ref" => "#/components/schemas/RealEstateFacts" },
      formatted_address: { type: :string, nullable: true },
      id: { type: :string },
      last_sync_error: { type: :string, nullable: true },
      last_synced_at: { type: :string, nullable: true },
      loan_to_value: { type: :number, nullable: true },
      mortgage_balance: { type: :number, nullable: true },
      mortgages: {
        type: :array,
        items: {
          type: :object,
          properties: { id: { type: :string }, lender: { type: :string, nullable: true }, name: { type: :string } },
          required: %w[id name lender]
        }
      },
      name: { type: :string },
      notes: { type: :string, nullable: true },
      purchase_date: { type: :string, nullable: true },
      purchase_price: { type: :number, nullable: true },
      sold_date: { type: :string, nullable: true },
      sold_price: { type: :number, nullable: true },
      state: { type: :string, nullable: true },
      status: { "$ref" => "#/components/schemas/RealEstateStatus" },
      sync_enabled: { type: :boolean },
      updated_at: { type: :string },
      valuations: { type: :array, items: { "$ref" => "#/components/schemas/RealEstateValuation" } },
      value: { type: :number, nullable: true },
      value_as_of: { type: :string, nullable: true },
      value_high: { type: :number, nullable: true },
      value_low: { type: :number, nullable: true },
      value_source: { allOf: [ { "$ref" => "#/components/schemas/RealEstateValuationSource" } ], nullable: true },
      zip_code: { type: :string, nullable: true }
    },
    required: %w[address_line1 address_line2 city created_at display_address equity facts formatted_address id last_sync_error last_synced_at loan_to_value mortgage_balance mortgages name notes purchase_date purchase_price sold_date sold_price state status sync_enabled updated_at valuations value value_as_of value_high value_low value_source zip_code]
  },
  RealEstateStatus: { type: :string, enum: [ "owned", "sold" ] },
  RealEstateValuation: {
    type: :object,
    properties: {
      amount: { type: :number },
      as_of: { type: :string },
      id: { type: :string },
      source: { "$ref" => "#/components/schemas/RealEstateValuationSource" },
      value_high: { type: :number, nullable: true },
      value_low: { type: :number, nullable: true }
    },
    required: %w[id as_of amount source value_low value_high]
  },
  RealEstateValuationSource: { type: :string, enum: [ "rentcast", "manual", "purchase", "sale", "tax_assessment" ] },
  RecentTransaction: {
    type: :object,
    properties: {
      account_name: { type: :string, nullable: true },
      amount: { type: :number },
      date: { type: :string },
      description: { type: :string },
      kind: { type: :string, enum: [ "investment", "cash" ] },
      secondary: { type: :string, nullable: true },
      transaction_type: { type: :string }
    },
    required: %w[kind date description amount account_name secondary transaction_type]
  },
  RecurringOccurrence: {
    type: :object,
    properties: {
      amount: { type: :number, nullable: true },
      amount_delta: { type: :number, nullable: true },
      cash_transaction_id: { type: :string, nullable: true },
      charged_date: { type: :string, nullable: true },
      expected_amount: { type: :number, nullable: true },
      expected_date: { type: :string },
      id: { type: :string },
      status: { "$ref" => "#/components/schemas/RecurringOccurrenceStatus" },
      transaction: {
        type: :object,
        properties: {
          account_name: { type: :string, nullable: true },
          description: { type: :string },
          id: { type: :string }
        },
        required: %w[id description account_name]
      }
    },
    required: %w[id expected_date status charged_date amount expected_amount amount_delta cash_transaction_id]
  },
  RecurringOccurrenceStatus: { type: :string, enum: [ "paid", "paid_amount_changed", "upcoming", "due", "missed", "skipped" ] },
  RecurringSeries: {
    type: :object,
    properties: {
      accepted_at: { type: :string, nullable: true },
      amount_tolerance: { type: :number },
      anchor: { type: :object, additionalProperties: {} },
      annual_equivalent: { type: :number },
      at_risk: { type: :boolean },
      average_amount: { type: :number },
      cadence_description: { type: :string },
      confidence: { type: :number },
      confidence_label: { type: :string, enum: [ "high", "medium", "low" ] },
      description_pattern: { type: :string, nullable: true },
      dismissed_at: { type: :string, nullable: true },
      ended_at: { type: :string, nullable: true },
      first_charge_date: { type: :string, nullable: true },
      granularity: { type: :string, enum: [ "week", "month", "year" ] },
      id: { type: :string },
      kind: { type: :string, enum: [ "subscription", "bill" ] },
      last_amount: { type: :number, nullable: true },
      last_charge_date: { type: :string, nullable: true },
      max_amount: { type: :number, nullable: true },
      merchant_id: { type: :string, nullable: true },
      min_amount: { type: :number, nullable: true },
      misses_streak: { type: :number },
      monthly_equivalent: { type: :number },
      name: { type: :string },
      next_expected_date: { type: :string, nullable: true },
      notes: { type: :string, nullable: true },
      occurrences_count: { type: :number },
      price_changed_recently: { type: :boolean },
      quantity: { type: :number },
      source: { type: :string, enum: [ "detected", "manual" ] },
      status: { "$ref" => "#/components/schemas/RecurringSeriesStatus" },
      timeline: { type: :array, items: { "$ref" => "#/components/schemas/RecurringOccurrence" } }
    },
    required: %w[id name status source kind merchant_id description_pattern granularity quantity anchor cadence_description average_amount last_amount min_amount max_amount amount_tolerance monthly_equivalent annual_equivalent confidence confidence_label first_charge_date last_charge_date next_expected_date occurrences_count misses_streak at_risk price_changed_recently notes accepted_at dismissed_at ended_at]
  },
  RecurringSeriesStatus: { type: :string, enum: [ "suggested", "active", "dismissed", "lapsed", "ended" ] },
  RentcastConfiguration: {
    type: :object,
    properties: {
      api_key_set: { type: :boolean },
      configured: { type: :boolean },
      last_synced_at: { type: :string, nullable: true },
      property_count: { type: :number },
      quota: { "$ref" => "#/components/schemas/RentcastQuota" }
    },
    required: %w[api_key_set configured last_synced_at property_count quota]
  },
  RentcastQuota: {
    type: :object,
    properties: {
      limit: { type: :number },
      period_start: { type: :string },
      remaining: { type: :number },
      resets_on: { type: :string },
      used: { type: :number }
    },
    required: %w[used limit remaining period_start resets_on]
  },
  ReviewData: {
    type: :object,
    properties: {
      budget: {
        type: :object,
        properties: { actual: { type: :number }, planned: { type: :number }, remaining: { type: :number } },
        required: %w[planned actual remaining]
      },
      cashflow: {
        type: :object,
        properties: {
          income: { type: :number },
          net: { type: :number },
          prev_income: { type: :number },
          prev_net: { type: :number },
          prev_spend: { type: :number },
          savings_rate: { type: :number, nullable: true },
          spend: { type: :number }
        },
        required: %w[income spend net prev_income prev_spend prev_net savings_rate]
      },
      largest_transactions: {
        type: :array,
        items: {
          type: :object,
          properties: {
            amount: { type: :number },
            category_name: { type: :string, nullable: true },
            description: { type: :string },
            id: { type: :string },
            transaction_date: { type: :string }
          },
          required: %w[id description category_name transaction_date amount]
        }
      },
      month: { type: :string },
      net_worth: {
        type: :object,
        properties: {
          change: { type: :number, nullable: true },
          ending: { type: :number },
          starting: { type: :number, nullable: true }
        },
        required: %w[ending starting change],
        nullable: true
      },
      subscriptions: {
        type: :object,
        properties: { paid_count: { type: :number }, paid_total: { type: :number } },
        required: %w[paid_count paid_total]
      },
      top_categories: { type: :array, items: { "$ref" => "#/components/schemas/ReviewRankedRow" } },
      top_merchants: { type: :array, items: { "$ref" => "#/components/schemas/ReviewRankedRow" } }
    },
    required: %w[month cashflow top_categories top_merchants largest_transactions net_worth budget subscriptions]
  },
  ReviewRankedRow: {
    type: :object,
    properties: { amount: { type: :number }, id: { type: :string }, name: { type: :string } },
    required: %w[id name amount]
  },
  SavedReport: {
    type: :object,
    properties: {
      config: { "$ref" => "#/components/schemas/SavedReportConfig" },
      created_at: { type: :string },
      id: { type: :string },
      name: { type: :string }
    },
    required: %w[id name config created_at]
  },
  SavedReportConfig: {
    type: :object,
    properties: {
      account_id: { type: :string, nullable: true },
      custom_range: {
        type: :object,
        properties: { from: { type: :string }, to: { type: :string } },
        required: %w[from to],
        nullable: true
      },
      exclude_tag_ids: { type: :array, items: { type: :string }, nullable: true },
      hash: { type: :string },
      preset: { type: :string },
      section: { type: :string },
      tag_id: { type: :string, nullable: true }
    },
    additionalProperties: {}
  },
  SecurityDetail: {
    type: :object,
    properties: {
      cusip: { type: :string, nullable: true },
      display_name: { type: :string },
      dividends: {
        type: :object,
        properties: { last_12mo: { type: :number }, lifetime: { type: :number }, ytd: { type: :number } },
        required: %w[lifetime ytd last_12mo]
      },
      id: { type: :string },
      instrument_class: { "$ref" => "#/components/schemas/InstrumentClass" },
      latest_price: {
        type: :object,
        properties: {
          age_days: { type: :number },
          close: { type: :number },
          date: { type: :string },
          source: { "$ref" => "#/components/schemas/PriceSource" }
        },
        required: %w[date close],
        nullable: true
      },
      name: { type: :string },
      overview: { allOf: [ { "$ref" => "#/components/schemas/SecurityOverview" } ], nullable: true },
      position: {
        type: :object,
        properties: {
          as_of_date: { type: :string },
          by_account: {
            type: :array,
            items: {
              type: :object,
              properties: { account: { type: :string }, market_value: { type: :number }, quantity: { type: :number } },
              required: %w[account quantity market_value]
            }
          },
          cost_basis: { type: :number },
          market_value: { type: :number },
          quantity: { type: :number },
          unrealized_gl: { type: :number }
        },
        required: %w[as_of_date quantity market_value cost_basis unrealized_gl by_account],
        nullable: true
      },
      price_chart: {
        type: :array,
        items: {
          type: :array,
          items: { anyOf: [ { type: :string }, { type: :number } ], nullable: true },
          minItems: 3,
          maxItems: 3,
          description: "[ISO date, close, volume]; volume is null where the source had none"
        }
      },
      recent_transactions: { type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" } },
      security_type: { type: :string, nullable: true },
      slug: { type: :string, nullable: true },
      ticker: { type: :string },
      watched: { type: :boolean }
    },
    required: %w[id ticker name cusip security_type instrument_class display_name slug price_chart latest_price position dividends watched overview recent_transactions]
  },
  SecurityOverview: {
    type: :object,
    properties: {
      analyst_target_price: { type: :number, nullable: true },
      beta: { type: :number, nullable: true },
      country: { type: :string, nullable: true },
      description: { type: :string, nullable: true },
      dividend_per_share: { type: :number, nullable: true },
      dividend_yield: { type: :number, nullable: true },
      eps: { type: :number, nullable: true },
      ex_dividend_date: { type: :string, nullable: true },
      exchange: { type: :string, nullable: true },
      fetched_at: { type: :string, nullable: true },
      forward_pe: { type: :number, nullable: true },
      industry: { type: :string, nullable: true },
      market_cap: { type: :number, nullable: true },
      pe_ratio: { type: :number, nullable: true },
      profit_margin: { type: :number, nullable: true },
      return_on_equity: { type: :number, nullable: true },
      revenue_ttm: { type: :number, nullable: true },
      sector: { type: :string, nullable: true },
      shares_outstanding: { type: :number, nullable: true },
      week_52_high: { type: :number, nullable: true },
      week_52_low: { type: :number, nullable: true }
    },
    required: %w[sector industry exchange country description market_cap pe_ratio forward_pe eps beta dividend_yield dividend_per_share week_52_high week_52_low analyst_target_price profit_margin return_on_equity revenue_ttm shares_outstanding ex_dividend_date fetched_at]
  },
  SecurityRefreshResult: {
    type: :object,
    properties: { status: { type: :string, enum: [ "syncing" ] }, syncing: { type: :boolean }, ticker: { type: :string, nullable: true } },
    required: %w[status ticker syncing]
  },
  SecuritySummary: {
    type: :object,
    properties: {
      cusip: { type: :string, nullable: true },
      day_change_pct: { type: :number, nullable: true },
      display_name: { type: :string },
      id: { type: :string },
      instrument_class: { "$ref" => "#/components/schemas/InstrumentClass" },
      latest_price: { allOf: [ { "$ref" => "#/components/schemas/LatestPrice" } ], nullable: true },
      market_value: { type: :number },
      name: { type: :string, nullable: true },
      security_type: { type: :string, nullable: true },
      slug: { type: :string, nullable: true },
      spark: { type: :array, items: { type: :number } },
      ticker: { type: :string, nullable: true },
      watched: { type: :boolean },
      ytd_change_pct: { type: :number, nullable: true }
    },
    required: %w[id ticker name cusip slug security_type instrument_class display_name latest_price ytd_change_pct day_change_pct spark market_value watched]
  },
  SecurityWatchResult: {
    type: :object,
    properties: {
      id: { type: :string },
      name: { type: :string, nullable: true },
      syncing: { type: :boolean },
      ticker: { type: :string, nullable: true },
      watched: { type: :boolean }
    },
    required: %w[id ticker name watched syncing]
  },
  SellsData: {
    type: :object,
    properties: {
      by_account: { type: :object, additionalProperties: { type: :number } },
      cumulative_realized: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      monthly_gl: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      monthly_volume: { type: :array, items: { "$ref" => "#/components/schemas/DateValuePair" } },
      top_securities: { type: :array, items: { "$ref" => "#/components/schemas/TopSecurity" } },
      totals: {
        type: :object,
        properties: {
          avg: { type: :number },
          count: { type: :number },
          count_12mo: { type: :number },
          proceeds: { type: :number },
          proceeds_12mo: { type: :number },
          proceeds_ytd: { type: :number },
          realized_long: { type: :number },
          realized_net: { type: :number },
          realized_short: { type: :number }
        },
        required: %w[proceeds proceeds_ytd proceeds_12mo count count_12mo avg realized_short realized_long realized_net]
      },
      transactions: { type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" } }
    },
    required: %w[totals monthly_volume monthly_gl top_securities by_account cumulative_realized transactions]
  },
  SpendBreakdown: {
    type: :object,
    properties: {
      months: { type: :object, additionalProperties: { type: :object, additionalProperties: { type: :number } } },
      series: { type: :array, items: { "$ref" => "#/components/schemas/SpendBreakdownSeries" } }
    },
    required: %w[series months]
  },
  SpendBreakdownData: {
    type: :object,
    properties: {
      category: { "$ref" => "#/components/schemas/SpendBreakdown" },
      category_common: { "$ref" => "#/components/schemas/SpendBreakdown" },
      from: { type: :string },
      merchant: { "$ref" => "#/components/schemas/SpendBreakdown" },
      merchant_common: { "$ref" => "#/components/schemas/SpendBreakdown" },
      monthly_spend: { type: :object, additionalProperties: { type: :number } },
      monthly_spend_common: { type: :object, additionalProperties: { type: :number } },
      to: { type: :string }
    },
    required: %w[from to monthly_spend monthly_spend_common category category_common merchant merchant_common]
  },
  SpendBreakdownSeries: { type: :object, properties: { id: { type: :string }, name: { type: :string } }, required: %w[id name] },
  SpendTotal: {
    type: :object,
    properties: {
      amount: { type: :number },
      avg_monthly: { type: :number },
      id: { type: :string },
      largest: { type: :number },
      name: { type: :string }
    },
    required: %w[id name amount avg_monthly largest]
  },
  SpendingOutlier: {
    type: :object,
    properties: {
      amount: { type: :number },
      category_name: { type: :string },
      description: { type: :string },
      multiple: { type: :number, nullable: true },
      transaction_date: { type: :string },
      transaction_id: { type: :string }
    },
    required: %w[transaction_id description category_name transaction_date amount multiple]
  },
  StatBreakdown: {
    type: :object,
    properties: {
      label: { type: :string },
      rows: { type: :array, items: { "$ref" => "#/components/schemas/StatBreakdownRow" } }
    },
    required: %w[label rows]
  },
  StatBreakdownRow: {
    type: :object,
    properties: {
      label: { type: :string },
      unit: { "$ref" => "#/components/schemas/StatUnit" },
      value: { type: :number }
    },
    required: %w[label value]
  },
  StatDetailData: {
    type: :object,
    properties: {
      breakdowns: { type: :array, items: { "$ref" => "#/components/schemas/StatBreakdown" }, nullable: true },
      description: { type: :string, nullable: true },
      direction: { "$ref" => "#/components/schemas/StatDirection" },
      drill: { allOf: [ { "$ref" => "#/components/schemas/StatDrill" } ], nullable: true },
      granularity: { "$ref" => "#/components/schemas/StatGranularity" },
      group: { type: :string },
      key: { type: :string },
      label: { type: :string },
      range: {
        type: :object,
        properties: { from: { type: :string }, to: { type: :string } },
        required: %w[from to]
      },
      series: { type: :array, items: { "$ref" => "#/components/schemas/StatPoint" } },
      summary: {
        type: :object,
        properties: {
          avg: { type: :number, nullable: true },
          change_pct: { type: :number, nullable: true },
          changes: {
            type: :object,
            properties: {
              "1m": { type: :number, nullable: true },
              "1y": { type: :number, nullable: true },
              "3m": { type: :number, nullable: true },
              ytd: { type: :number, nullable: true }
            },
            required: [ "1m", "3m", "ytd", "1y" ]
          },
          latest: { allOf: [ { "$ref" => "#/components/schemas/StatPoint" } ], nullable: true },
          max: {
            type: :object,
            properties: { date: { type: :string }, value: { type: :number, nullable: true } },
            required: %w[date value],
            nullable: true
          },
          min: {
            type: :object,
            properties: { date: { type: :string }, value: { type: :number, nullable: true } },
            required: %w[date value],
            nullable: true
          },
          pace: { allOf: [ { "$ref" => "#/components/schemas/StatPace" } ], nullable: true },
          previous: { allOf: [ { "$ref" => "#/components/schemas/StatPoint" } ], nullable: true }
        },
        required: %w[latest previous change_pct pace min max avg changes]
      },
      unit: { "$ref" => "#/components/schemas/StatUnit" },
      value_type: { "$ref" => "#/components/schemas/StatValueType" }
    },
    required: %w[breakdowns description direction drill granularity group key label range series summary unit value_type]
  },
  StatDirection: { type: :string, enum: [ "up_good", "down_good", "neutral" ] },
  StatDrill: {
    type: :object,
    properties: { params: { type: :object, additionalProperties: { type: :string } }, route: { type: :string } },
    required: %w[route params]
  },
  StatGranularity: { type: :string, enum: [ "day", "month" ] },
  StatPace: {
    type: :object,
    properties: { projected: { type: :number }, vs_previous_pct: { type: :number, nullable: true } },
    required: %w[projected vs_previous_pct]
  },
  StatPoint: {
    type: :object,
    properties: { date: { type: :string }, partial: { type: :boolean }, value: { type: :number, nullable: true } },
    required: %w[date value]
  },
  StatSummary: {
    type: :object,
    properties: {
      change_pct: { type: :number, nullable: true },
      description: { type: :string, nullable: true },
      direction: { "$ref" => "#/components/schemas/StatDirection" },
      drill: { allOf: [ { "$ref" => "#/components/schemas/StatDrill" } ], nullable: true },
      granularity: { "$ref" => "#/components/schemas/StatGranularity" },
      group: { type: :string },
      key: { type: :string },
      label: { type: :string },
      latest: { allOf: [ { "$ref" => "#/components/schemas/StatPoint" } ], nullable: true },
      pace: { allOf: [ { "$ref" => "#/components/schemas/StatPace" } ], nullable: true },
      previous: { allOf: [ { "$ref" => "#/components/schemas/StatPoint" } ], nullable: true },
      sparkline: { type: :array, items: { "$ref" => "#/components/schemas/StatPoint" } },
      unit: { "$ref" => "#/components/schemas/StatUnit" },
      value_type: { "$ref" => "#/components/schemas/StatValueType" }
    },
    required: %w[change_pct description direction drill granularity group key label latest pace previous sparkline unit value_type]
  },
  StatUnit: { type: :string, enum: [ "currency", "count", "percent" ] },
  StatValueType: { type: :string, enum: [ "flow", "level" ] },
  StatsIndexData: {
    type: :object,
    properties: {
      as_of: { type: :string, nullable: true },
      groups: {
        type: :array,
        items: {
          type: :object,
          properties: { key: { type: :string }, label: { type: :string } },
          required: %w[key label]
        }
      },
      stats: { type: :array, items: { "$ref" => "#/components/schemas/StatSummary" } }
    },
    required: %w[as_of groups stats]
  },
  SubscriptionDetail: {
    type: :object,
    properties: {
      accepted_at: { type: :string, nullable: true },
      amount_tolerance: { type: :number },
      anchor: { type: :object, additionalProperties: {} },
      annual_equivalent: { type: :number },
      at_risk: { type: :boolean },
      average_amount: { type: :number },
      cadence_description: { type: :string },
      confidence: { type: :number },
      confidence_label: { type: :string, enum: [ "high", "medium", "low" ] },
      description_pattern: { type: :string, nullable: true },
      dismissed_at: { type: :string, nullable: true },
      ended_at: { type: :string, nullable: true },
      first_charge_date: { type: :string, nullable: true },
      granularity: { type: :string, enum: [ "week", "month", "year" ] },
      id: { type: :string },
      kind: { type: :string, enum: [ "subscription", "bill" ] },
      last_amount: { type: :number, nullable: true },
      last_charge_date: { type: :string, nullable: true },
      max_amount: { type: :number, nullable: true },
      merchant_id: { type: :string, nullable: true },
      min_amount: { type: :number, nullable: true },
      misses_streak: { type: :number },
      monthly_equivalent: { type: :number },
      name: { type: :string },
      next_expected_date: { type: :string, nullable: true },
      notes: { type: :string, nullable: true },
      occurrences: { type: :array, items: { "$ref" => "#/components/schemas/RecurringOccurrence" } },
      occurrences_count: { type: :number },
      price_changed_recently: { type: :boolean },
      quantity: { type: :number },
      source: { type: :string, enum: [ "detected", "manual" ] },
      status: { "$ref" => "#/components/schemas/RecurringSeriesStatus" },
      timeline: { type: :array, items: { "$ref" => "#/components/schemas/RecurringOccurrence" } }
    },
    required: %w[accepted_at amount_tolerance anchor annual_equivalent at_risk average_amount cadence_description confidence confidence_label description_pattern dismissed_at ended_at first_charge_date granularity id kind last_amount last_charge_date max_amount merchant_id min_amount misses_streak monthly_equivalent name next_expected_date notes occurrences occurrences_count price_changed_recently quantity source status]
  },
  SubscriptionsCalendarData: {
    type: :object,
    properties: {
      month: { type: :string },
      occurrences: { type: :array, items: { "$ref" => "#/components/schemas/SubscriptionsCalendarOccurrence" } }
    },
    required: %w[month occurrences]
  },
  SubscriptionsCalendarOccurrence: {
    type: :object,
    properties: {
      amount: { type: :number, nullable: true },
      amount_delta: { type: :number, nullable: true },
      cash_transaction_id: { type: :string, nullable: true },
      charged_date: { type: :string, nullable: true },
      expected_amount: { type: :number, nullable: true },
      expected_date: { type: :string },
      id: { type: :string },
      name: { type: :string },
      series_id: { type: :string },
      status: { "$ref" => "#/components/schemas/RecurringOccurrenceStatus" },
      transaction: {
        type: :object,
        properties: {
          account_name: { type: :string, nullable: true },
          description: { type: :string },
          id: { type: :string }
        },
        required: %w[id description account_name]
      }
    },
    required: %w[amount amount_delta cash_transaction_id charged_date expected_amount expected_date id name series_id status]
  },
  SubscriptionsData: {
    type: :object,
    properties: {
      series: { type: :array, items: { "$ref" => "#/components/schemas/RecurringSeries" } },
      summary: { "$ref" => "#/components/schemas/SubscriptionsSummary" }
    },
    required: %w[summary series]
  },
  SubscriptionsSummary: {
    type: :object,
    properties: {
      active_count: { type: :number },
      annual_total: { type: :number },
      lapsed_count: { type: :number },
      month_paid: { type: :number },
      month_remaining: { type: :number },
      monthly_total: { type: :number },
      suggested_count: { type: :number }
    },
    required: %w[active_count suggested_count lapsed_count monthly_total annual_total month_paid month_remaining]
  },
  TaxAdjustment: {
    type: :object,
    properties: {
      amount: { type: :number },
      bucket: { type: :string, nullable: true },
      id: { type: :string },
      jurisdiction: { type: :string, enum: [ "federal", "state", "both" ] },
      kind: { type: :string, enum: [ "income", "deduction", "credit", "payment", "contribution" ] },
      label: { type: :string },
      notes: { type: :string, nullable: true },
      tax_year: { type: :number }
    },
    required: %w[id tax_year kind jurisdiction label amount bucket notes]
  },
  TaxAdjustmentGroup: {
    type: :object,
    properties: {
      items: { type: :array, items: { "$ref" => "#/components/schemas/TaxAdjustment" } },
      kind: { "$ref" => "#/components/schemas/TaxKind" },
      total: { type: :number }
    },
    required: %w[kind total items]
  },
  TaxCharitableGift: {
    type: :object,
    properties: {
      amount: { type: :number },
      date: { type: :string },
      description: { type: :string },
      receipt: { type: :boolean },
      transaction_id: { type: :string }
    },
    required: %w[transaction_id date description amount receipt]
  },
  TaxChecklistItem: {
    type: :object,
    properties: {
      auto_seeded: { type: :boolean },
      id: { type: :string },
      kind: { type: :string },
      notes: { type: :string, nullable: true },
      reference_id: { type: :string, nullable: true },
      source_label: { type: :string },
      status: { type: :string, enum: [ "expected", "received", "corrected", "n_a" ] },
      tax_year: { type: :number }
    },
    required: %w[id tax_year kind source_label status auto_seeded reference_id notes]
  },
  TaxEstimatedPayment: {
    type: :object,
    properties: {
      amount: { type: :number },
      id: { type: :string },
      jurisdiction: { type: :string, enum: [ "federal", "state" ] },
      notes: { type: :string, nullable: true },
      paid_on: { type: :string },
      quarter: { type: :string, nullable: true },
      tax_year: { type: :number }
    },
    required: %w[id tax_year jurisdiction paid_on amount quarter notes]
  },
  TaxExport: {
    type: :object,
    properties: {
      format: { type: :string, enum: [ "json" ] },
      generated_at: { type: :string },
      note: { type: :string },
      report: { "$ref" => "#/components/schemas/TaxReport" },
      transactions: {
        type: :object,
        properties: {
          charitable: { type: :array, items: { "$ref" => "#/components/schemas/TaxCharitableGift" } },
          estimated_payments: { type: :array, items: { "$ref" => "#/components/schemas/TaxEstimatedPayment" } },
          realized_sales: { type: :array, items: { "$ref" => "#/components/schemas/TaxRealizedSale" } }
        },
        required: %w[charitable realized_sales estimated_payments]
      }
    },
    required: %w[generated_at format note report transactions]
  },
  TaxJurisdictionLiability: {
    type: :object,
    properties: {
      amt: { type: :number },
      credits: { type: :number },
      effective_rate: { type: :number },
      marginal_ordinary_rate: { type: :number, nullable: true },
      projected_refund_or_owed: { type: :number },
      regular_tax: { type: :number },
      taxable_income: { type: :number, nullable: true },
      total: { type: :number },
      withheld_and_paid: { type: :number }
    },
    required: %w[regular_tax amt total credits taxable_income effective_rate marginal_ordinary_rate withheld_and_paid projected_refund_or_owed]
  },
  TaxKind: { type: :string, enum: [ "fact", "record", "estimate" ] },
  TaxProfile: {
    type: :object,
    properties: {
      amt_credit_carryforward_ca: { type: :number },
      amt_credit_carryforward_federal: { type: :number },
      complete: { type: :boolean },
      filing_status: { type: :string, enum: [ "single", "mfj" ] },
      id: { type: :string, nullable: true },
      itemized_other: { type: :number },
      itemizing: { type: :boolean },
      ltcg_qd_income: { type: :number },
      other_ordinary_income: { type: :number },
      persisted: { type: :boolean },
      prior_year_agi: { type: :number, nullable: true },
      prior_year_total_tax: { type: :number, nullable: true },
      projected_state_tax: { type: :number, nullable: true },
      projected_wages: { type: :number },
      salt_paid: { type: :number },
      state: { type: :string },
      state_name: { type: :string },
      state_tax_source: { type: :string, enum: [ "modeled", "entered", "no_income_tax" ] },
      tax_year: { type: :number },
      ytd_withholding_federal: { type: :number },
      ytd_withholding_state: { type: :number }
    },
    required: %w[id tax_year filing_status state state_name state_tax_source projected_state_tax projected_wages other_ordinary_income ltcg_qd_income itemizing salt_paid itemized_other prior_year_total_tax prior_year_agi ytd_withholding_federal ytd_withholding_state amt_credit_carryforward_federal amt_credit_carryforward_ca complete]
  },
  TaxRealizedSale: {
    type: :object,
    properties: {
      account: { type: :string },
      date: { type: :string },
      lt: { type: :number },
      proceeds: { type: :number, nullable: true },
      security: { type: :string, nullable: true },
      st: { type: :number }
    },
    required: %w[date security account proceeds st lt]
  },
  TaxReport: {
    type: :object,
    properties: {
      contributions: {
        type: :object,
        properties: {
          buckets: {
            type: :array,
            items: {
              type: :object,
              properties: {
                accounts: {
                  type: :array,
                  items: {
                    type: :object,
                    properties: { id: { type: :string }, name: { type: :string }, tax_treatment: { type: :string } },
                    required: %w[id name tax_treatment]
                  }
                },
                adjustments_total: { type: :number },
                contributed: { type: :number },
                informational: { type: :boolean },
                key: { type: :string },
                label: { type: :string },
                limit: { type: :number, nullable: true },
                note: { type: :string, nullable: true },
                percent_of_limit: { type: :number, nullable: true },
                transfers_total: { type: :number },
                treatments: { type: :array, items: { type: :string } }
              },
              required: %w[key label treatments informational contributed transfers_total adjustments_total limit percent_of_limit accounts]
            }
          },
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          note: { type: :string, nullable: true }
        },
        required: %w[kind buckets]
      },
      deductions: {
        type: :object,
        properties: {
          adjustments: { "$ref" => "#/components/schemas/TaxAdjustmentGroup" },
          charitable: {
            type: :object,
            properties: {
              gifts: {
                type: :array,
                items: { "$ref" => "#/components/schemas/TaxCharitableGift" }
              },
              total: { type: :number }
            },
            required: %w[total gifts]
          },
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          mortgage_interest: {
            type: :object,
            properties: {
              loans: {
                type: :array,
                items: {
                  type: :object,
                  properties: { interest_paid: { type: :number }, loan_id: { type: :string }, name: { type: :string } },
                  required: %w[loan_id name interest_paid]
                }
              },
              note: { type: :string, nullable: true },
              total: { type: :number }
            },
            required: %w[total loans]
          },
          salt: {
            type: :object,
            properties: {
              amount: { type: :number },
              kind: { "$ref" => "#/components/schemas/TaxKind" },
              note: { type: :string, nullable: true },
              state_estimated_payments: { type: :number },
              state_withholding: { type: :number }
            },
            required: %w[kind state_withholding state_estimated_payments amount]
          }
        },
        required: %w[kind mortgage_interest charitable salt adjustments]
      },
      documents: {
        type: :object,
        properties: {
          items: { type: :array, items: { "$ref" => "#/components/schemas/TaxChecklistItem" } },
          kind: { "$ref" => "#/components/schemas/TaxKind" }
        },
        required: %w[kind items]
      },
      flags: {
        type: :object,
        properties: {
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          note: { type: :string, nullable: true },
          wash_sales: {
            type: :array,
            items: {
              type: :object,
              properties: {
                loss: { type: :number },
                permanent: { type: :boolean },
                purchase_account: { type: :string },
                purchase_date: { type: :string },
                sale_account: { type: :string },
                sale_date: { type: :string },
                security_id: { type: :string },
                security_label: { type: :string }
              },
              required: %w[security_id security_label sale_date sale_account loss purchase_date purchase_account permanent]
            }
          }
        },
        required: %w[kind wash_sales]
      },
      generated_at: { type: :string },
      income: {
        type: :object,
        properties: {
          adjustments: { "$ref" => "#/components/schemas/TaxAdjustmentGroup" },
          dividends: { type: :number },
          equity_comp: {
            type: :object,
            properties: {
              events: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    amt_spread: { type: :number, nullable: true },
                    company: { type: :string },
                    grant_label: { type: :string, nullable: true },
                    grant_type: { type: :string },
                    id: { type: :string },
                    kind: { type: :string },
                    occurred_on: { type: :string },
                    ordinary_income: { type: :number, nullable: true },
                    quantity: { type: :number },
                    share_price: { type: :number, nullable: true },
                    skipped: { type: :boolean },
                    strike_price: { type: :number, nullable: true }
                  },
                  required: %w[id kind grant_type grant_label company occurred_on quantity share_price strike_price ordinary_income amt_spread skipped]
                }
              },
              iso_amt_spread: { type: :number },
              notes: { type: :array, items: { type: :string } },
              ordinary_income: { type: :number }
            },
            required: %w[ordinary_income iso_amt_spread events notes]
          },
          interest: { type: :number },
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          realized_gains: {
            type: :object,
            properties: {
              by_security: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    label: { type: :string },
                    long_term: { type: :number },
                    security_id: { type: :string },
                    short_term: { type: :number },
                    total: { type: :number }
                  },
                  required: %w[security_id label short_term long_term total]
                }
              },
              long_term: { type: :number },
              short_term: { type: :number },
              total: { type: :number }
            },
            required: %w[short_term long_term total by_security]
          },
          wages: {
            type: :object,
            properties: {
              amount: { type: :number },
              kind: { "$ref" => "#/components/schemas/TaxKind" },
              note: { type: :string, nullable: true }
            },
            required: %w[kind amount]
          }
        },
        required: %w[kind wages interest dividends realized_gains equity_comp adjustments]
      },
      liability: {
        type: :object,
        properties: {
          assumptions: {
            type: :object,
            properties: {
              figures_status: {
                type: :object,
                properties: { federal: { type: :string }, state: { type: :string, nullable: true } },
                required: %w[federal state]
              },
              notes: { type: :array, items: { type: :string } }
            },
            required: %w[figures_status notes]
          },
          bracket_headroom: {
            type: :object,
            properties: {
              ltcg_zero_headroom: { type: :number },
              note: { type: :string, nullable: true },
              to_next_federal_bracket: {
                type: :object,
                properties: { amount: { type: :number }, current_rate: { type: :number }, next_rate: { type: :number } },
                required: %w[amount current_rate next_rate],
                nullable: true
              }
            },
            required: %w[to_next_federal_bracket ltcg_zero_headroom]
          },
          credits: { "$ref" => "#/components/schemas/TaxAdjustmentGroup" },
          federal: { "$ref" => "#/components/schemas/TaxJurisdictionLiability" },
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          state: { "$ref" => "#/components/schemas/TaxJurisdictionLiability" },
          total_liability: { type: :number }
        },
        required: %w[kind assumptions federal state credits total_liability bracket_headroom],
        nullable: true
      },
      payments: {
        type: :object,
        properties: {
          due_dates: {
            type: :array,
            items: {
              type: :object,
              properties: {
                date: { type: :string },
                jurisdiction: { type: :string },
                label: { type: :string },
                paid_in_window: { type: :number },
                status: { type: :string },
                weight: { type: :number }
              },
              required: %w[jurisdiction label date weight paid_in_window status]
            }
          },
          federal: {
            type: :object,
            properties: {
              estimated: { type: :array, items: { "$ref" => "#/components/schemas/TaxEstimatedPayment" } },
              total: { type: :number },
              withholding: { type: :number }
            },
            required: %w[withholding estimated total]
          },
          kind: { "$ref" => "#/components/schemas/TaxKind" },
          safe_harbor: {
            type: :object,
            properties: {
              federal: { "$ref" => "#/components/schemas/TaxSafeHarbor" },
              state: { "$ref" => "#/components/schemas/TaxSafeHarbor" }
            },
            required: %w[federal state]
          },
          state: {
            type: :object,
            properties: {
              estimated: { type: :array, items: { "$ref" => "#/components/schemas/TaxEstimatedPayment" } },
              total: { type: :number },
              withholding: { type: :number }
            },
            required: %w[withholding estimated total]
          }
        },
        required: %w[kind federal state due_dates safe_harbor]
      },
      profile: { allOf: [ { "$ref" => "#/components/schemas/TaxProfile" } ], nullable: true },
      year: { type: :number }
    },
    required: %w[year generated_at profile income deductions liability payments contributions flags documents]
  },
  TaxSafeHarbor: {
    type: :object,
    properties: {
      current_agi: { type: :number, nullable: true },
      installment_weights: { type: :array, items: { type: :number }, nullable: true },
      note: { type: :string, nullable: true },
      paid: { type: :number, nullable: true },
      required_annual: { type: :number, nullable: true },
      status: { type: :string, enum: [ "covered", "uncovered", "unknown", "unavailable", "not_applicable" ] }
    },
    required: %w[status]
  },
  TickerSearchResults: {
    type: :object,
    properties: { results: { type: :array, items: { "$ref" => "#/components/schemas/TickerSearchResult" } } },
    required: %w[results]
  },
  TickerSearchResult: {
    type: :object,
    properties: {
      currency: { type: :string, nullable: true },
      instrument_class: { type: :string },
      match_score: { type: :number },
      name: { type: :string },
      region: { type: :string, nullable: true },
      security_type: { type: :string },
      ticker: { type: :string }
    },
    required: %w[ticker name security_type region currency instrument_class match_score]
  },
  TopSecurity: {
    type: :object,
    properties: {
      count: { type: :number },
      name: { type: :string },
      ticker: { type: :string },
      total: { type: :number }
    },
    required: %w[ticker name total count]
  },
  UpcomingCharges: {
    type: :object,
    properties: { upcoming: { type: :array, items: { "$ref" => "#/components/schemas/UpcomingCharge" } } },
    required: %w[upcoming]
  },
  UpcomingCharge: {
    type: :object,
    properties: {
      expected_amount: { type: :number, nullable: true },
      expected_date: { type: :string },
      name: { type: :string },
      occurrence_id: { type: :string },
      series_id: { type: :string },
      status: { type: :string }
    },
    required: %w[occurrence_id series_id name expected_date expected_amount status]
  }
})
