# typed: strict

module Households
  # Seeds a new household with the scheduled workflows that used to live as
  # bespoke settings screens (market sync schedule, system audit, scheduled
  # jobs): one system, visible and editable in the workflow builder, run-now
  # able, observable in runs and the activity timeline.
  #
  # Idempotent via seed_key — existing seeded workflows are left untouched,
  # so re-running never clobbers a household's customizations.
  module SeedDefaultWorkflows
    extend T::Sig

    DEFAULTS = T.let([
      {
        seed_key:    "market_data_sync",
        name:        "Market data sync",
        description: "Fetches daily candles for held, watched, and benchmark instruments",
        config:      { "frequency" => "daily", "at" => "05:00" },
        target:      "market_prices"
      },
      {
        seed_key:    "crypto_quotes_sync",
        name:        "Crypto quotes sync",
        description: "Refreshes crypto spot prices",
        config:      { "frequency" => "hourly", "every_hours" => 4 },
        target:      "crypto_prices"
      },
      {
        seed_key:    "security_news_sync",
        name:        "Security news sync",
        description: "Pulls news for held and watched instruments",
        config:      { "frequency" => "daily", "at" => "06:00" },
        target:      "security_news"
      },
      {
        seed_key:    "bank_sync",
        name:        "Bank & card sync",
        description: "Syncs connected Plaid institutions",
        config:      { "frequency" => "hourly", "every_hours" => 6 },
        target:      "plaid"
      },
      {
        seed_key:    "coinbase_sync",
        name:        "Coinbase sync",
        description: "Syncs Coinbase accounts and transactions",
        config:      { "frequency" => "hourly", "every_hours" => 4 },
        target:      "coinbase"
      },
      {
        seed_key:    "reconciliation_sweep",
        name:        "Reconciliation sweep",
        description: "Rebuilds ledger positions and flags drift against custodian holdings",
        config:      { "frequency" => "daily", "at" => "03:30" },
        target:      "reconciliation"
      },
      {
        seed_key:    "system_audit",
        name:        "System audit",
        description: "Checks data health and raises issues for anything off",
        config:      { "frequency" => "daily", "at" => "04:00" },
        target:      "system_audit"
      },
      {
        seed_key:    "recurring_detection",
        name:        "Subscription detection",
        description: "Reviews transaction history for recurring charges: matches new charges onto accepted subscriptions, flags missed payments, and adds new suggestions for review",
        config:      { "frequency" => "daily", "at" => "06:30" },
        target:      "recurring_detection"
      }
    ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

    # Non-schedule seeds: event-triggered defaults.
    EVENT_DEFAULTS = T.let([
      {
        seed_key:     "monthly_review",
        name:         "Monthly review",
        description:  "Notifies you when last month's review is ready",
        trigger_type: "review.month_ready",
        steps: [
          { kind: "action",
            config: { "action_type" => "notify",
                      "params" => {
                        "title" => "Your {{month_label}} review is ready",
                        "body"  => "Income, spending, net worth, and budget for {{month_label}} — tap to read it.",
                        "severity" => "info",
                        "href" => "/review?month={{month}}"
                      } } }
        ]
      },
      {
        seed_key:     "charge_upcoming",
        name:         "Charge coming up",
        description:  "Notifies you a few days before an expected recurring charge",
        trigger_type: "subscription.charge_upcoming",
        steps: [
          { kind: "action",
            config: { "action_type" => "notify",
                      "params" => {
                        "title" => "Upcoming charge: {{name}}",
                        "body"  => "{{name}} is expected around {{expected_date}} for about ${{expected_amount}}.",
                        "severity" => "info",
                        "href" => "/cashflow#section=subscriptions"
                      } } }
        ]
      },
      {
        seed_key:     "budget_alerts",
        name:         "Budget alerts",
        description:  "Notifies you when a category approaches or exceeds its monthly budget",
        trigger_type: "budget.category_exceeded",
        steps: [
          { kind: "action",
            config: { "action_type" => "notify",
                      "params" => {
                        "title" => "Budget exceeded: {{name}}",
                        "body"  => "{{name}} is over its monthly budget.",
                        "severity" => "warning"
                      } } }
        ]
      }
    ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

    sig { params(household: Household).returns(Integer) }
    def self.call(household)
      created = 0
      Current.set(household: household) do
        EVENT_DEFAULTS.each do |default|
          next if Workflow.exists?(seed_key: default[:seed_key])

          workflow = Workflow.create!(
            name:         default[:name],
            description:  default[:description],
            trigger_type: default[:trigger_type],
            seed_key:     default[:seed_key],
            active:       true
          )
          workflow.replace_steps!(default[:steps])
          created += 1
        end

        DEFAULTS.each do |default|
          next if Workflow.exists?(seed_key: default[:seed_key])

          workflow = Workflow.create!(
            name:           default[:name],
            description:    default[:description],
            trigger_type:   Workflows::Catalog::SCHEDULE_TRIGGER,
            trigger_config: default[:config],
            seed_key:       default[:seed_key],
            active:         true
          )
          workflow.replace_steps!([
            { kind: "action",
              config: { "action_type" => "trigger_sync",
                        "params" => { "target" => default[:target] } } }
          ])
          created += 1
        end
      end
      Workflows::Events.reset_cache
      created
    end
  end
end
