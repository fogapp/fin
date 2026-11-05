# typed: strict

module Workflows
  # The machine-readable description of everything a workflow can be built
  # from: trigger types, the condition fields available per subject model,
  # and (from Phase C) the action types with their param schemas. Drives the
  # builder UI via GET /api/v1/workflows/catalog.
  module Catalog
    extend T::Sig

    # Short alias for the operator vocabulary shared with the rules engine;
    # instances JSON-encode as their serialized strings, so the catalog
    # endpoint's wire format is unchanged.
    Op = Conditions::Operator

    # Models whose lifecycle events (created/updated/deleted) can trigger
    # workflows. Key => class name; keys are the public event prefixes.
    RECORD_MODELS = T.let({
      "cash_transaction"       => "CashTransaction",
      "investment_transaction" => "InvestmentTransaction",
      "account"                => "Account",
      "transfer"               => "Transfer",
      "loan"                   => "Loan",
      "recurring_series"       => "RecurringSeries",
      "position_snapshot"      => "PositionSnapshot",
      "merchant"               => "Merchant",
      "security"               => "Security",
      "category"               => "Category"
    }.freeze, T::Hash[String, String])

    LIFECYCLE_EVENTS = T.let(%w[created updated deleted].freeze, T::Array[String])

    # "<key>.any" triggers fire for both created and updated events —
    # the shape rules with trigger_event "any" migrate onto.
    ANY_SUFFIX = T.let("any", String)

    # App-level domain events: type => the subject model the run receives.
    APP_EVENTS = T.let({
      "plaid.sync_completed"          => "PlaidItem",
      "coinbase.sync_completed"       => "Household",
      "alchemy.sync_completed"        => "Household",
      "alchemy.transactions_synced"   => "Household",
      "import.completed"              => "CsvImport",
      "transfer.candidate_detected"   => "Transfer",
      "transfer.payment_detected"     => "Transfer",
      "transfer.auto_confirmed"       => "Transfer",
      "workflow.run_failed"           => "WorkflowRun",
      "system.error_recorded"         => "ActivityEntry",
      "reconciliation.drift_detected" => "Account",
      "budget.category_approaching"   => "Category",
      "budget.category_exceeded"      => "Category",
      "equity.vest_upcoming"          => "EquityGrant",
      "equity.vest_occurred"          => "EquityGrant",
      "equity.grant_expiring"         => "EquityGrant",
      "equity.exercise_window_closing" => "EquityGrant",
      "tax.quarterly_due_approaching"      => "Household",
      "tax.safe_harbor_behind"             => "Household",
      "tax.contribution_limit_approaching" => "Household",
      "tax.document_overdue"               => "Household",
      "tax.wash_sale_detected"             => "Household",
      "subscription.suggested"       => "RecurringSeries",
      "subscription.price_changed"   => "RecurringSeries",
      "subscription.payment_missed"  => "RecurringSeries",
      "subscription.lapsed"          => "RecurringSeries",
      "subscription.charge_upcoming" => "RecurringSeries",
      "review.month_ready"           => "Household"
    }.freeze, T::Hash[String, String])

    # Condition fields per subject model. CashTransaction/InvestmentTransaction
    # reuse the parity-tested rules registry; the rest are defined here.
    EXTRA_FIELDS = T.let({
      "Account" => {
        "name"             => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::NotEquals, Op::Contains ] },
        "account_type"     => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "balance"          => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "balance_usd"      => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "balance_currency" => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "hidden"           => { type: :boolean, operators: [ Op::Equals ] }
      },
      "Transfer" => {
        "amount"           => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "confirmed_at"     => { type: :datetime, operators: [ Op::Blank, Op::Present ] },
        "kind"             => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "include_in_spend" => { type: :boolean, operators: [ Op::Equals ] },
        "note"             => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::Contains, Op::Blank, Op::Present ] }
      },
      "Loan" => {
        "name"          => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::Contains ] },
        "status"        => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "loan_type"     => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "interest_rate" => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] }
      },
      "RecurringSeries" => {
        "status"         => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "kind"           => { type: :string,  operators: [ Op::Equals, Op::NotEquals ] },
        "granularity"    => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "average_amount" => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "confidence"     => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] },
        "misses_streak"  => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] }
      },
      "PositionSnapshot" => {
        "quantity"             => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "market_value"         => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] },
        "unrealized_gain_loss" => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] },
        "asset_class"          => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In, Op::Blank, Op::Present ] }
      },
      "Merchant" => {
        "name"     => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::Contains ] },
        "excluded" => { type: :boolean, operators: [ Op::Equals ] }
      },
      "Category" => {
        "name"        => { type: :string, operators: [ Op::Matches, Op::Equals, Op::Contains ] },
        "budget_kind" => { type: :string, operators: [ Op::Equals, Op::NotEquals, Op::In ] }
      },
      "Security" => {
        "ticker"           => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "name"             => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::Contains ] },
        "instrument_class" => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "current_price"    => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] },
        "price_age_days"   => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] },
        "day_change_pct"   => { type: :numeric, operators: [ Op::GreaterThan, Op::LessThan ] }
      },
      "PlaidItem" => {
        "status" => { type: :string, operators: [ Op::Equals, Op::NotEquals ] }
      },
      "CsvImport" => {
        "status" => { type: :string, operators: [ Op::Equals, Op::NotEquals ] },
        "kind"   => { type: :string, operators: [ Op::Equals, Op::NotEquals, Op::In ] }
      },
      "Household"   => {},
      "EquityGrant" => {
        "label"           => { type: :string,  operators: [ Op::Matches, Op::Equals, Op::Contains ] },
        "grant_type"      => { type: :string,  operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "quantity"        => { type: :numeric, operators: [ Op::Equals, Op::GreaterThan, Op::LessThan ] },
        "expiration_date" => { type: :datetime, operators: [ Op::Blank, Op::Present ] }
      },
      "ActivityEntry" => {
        "source"   => { type: :string, operators: [ Op::Equals, Op::NotEquals, Op::In ] },
        "event"    => { type: :string, operators: [ Op::Equals, Op::NotEquals, Op::Contains ] },
        "severity" => { type: :string, operators: [ Op::Equals, Op::NotEquals ] },
        "summary"  => { type: :string, operators: [ Op::Contains, Op::Matches ] }
      },
      "WorkflowRun" => {
        "status"     => { type: :string, operators: [ Op::Equals, Op::NotEquals ] },
        "event_type" => { type: :string, operators: [ Op::Equals, Op::NotEquals, Op::Contains ] }
      }
    }.freeze, T::Hash[String, T.untyped])

    sig { returns(T::Array[String]) }
    def self.record_event_types
      RECORD_MODELS.keys.flat_map { |key| (LIFECYCLE_EVENTS + [ ANY_SUFFIX ]).map { |ev| "#{key}.#{ev}" } }
    end

    # The .any alias for a concrete lifecycle event type (nil for deletes —
    # running an "any" workflow against a gone subject helps no one).
    sig { params(event_type: String).returns(T.nilable(String)) }
    def self.any_alias_for(event_type)
      prefix, event = event_type.split(".", 2)
      return nil unless RECORD_MODELS.key?(prefix.to_s)
      return nil unless %w[created updated].include?(event)

      "#{prefix}.#{ANY_SUFFIX}"
    end

    # "monitor" workflows watch a subject scope for a condition edge instead
    # of reacting to a single event; their subject model comes from
    # trigger_config["subject"].
    MONITOR_TRIGGER = T.let("monitor", String)
    SCHEDULE_TRIGGER = T.let("schedule", String)

    sig { returns(T::Array[String]) }
    def self.trigger_types
      record_event_types + APP_EVENTS.keys + [ MONITOR_TRIGGER, SCHEDULE_TRIGGER ]
    end

    sig { params(class_name: String).returns(T.nilable(String)) }
    def self.key_for(class_name)
      RECORD_MODELS.key(class_name)
    end

    # The subject model class name a trigger type delivers.
    sig { params(trigger_type: String).returns(T.nilable(String)) }
    def self.subject_class_for(trigger_type)
      return APP_EVENTS[trigger_type] if APP_EVENTS.key?(trigger_type)

      prefix = trigger_type.split(".").first.to_s
      RECORD_MODELS[prefix]
    end

    sig { params(class_name: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.fields_for(class_name)
      return {} if class_name.nil?
      return Conditions::Registry.fields_for(class_name) if Conditions::Registry.valid_resource?(class_name)

      EXTRA_FIELDS.fetch(class_name, {})
    end

    sig { params(class_name: T.nilable(String), field: String).returns(T::Boolean) }
    def self.valid_field?(class_name, field)
      fields_for(class_name).key?(field)
    end
  end
end
