FactoryBot.define do
  factory :workflow do
    sequence(:name) { |n| "Workflow #{n}" }
    trigger_type { "cash_transaction.created" }
    trigger_config { {} }
    active { true }
    household { Current.household || create(:household) }
  end

  factory :workflow_step do
    workflow
    kind { "action" }
    config { { "action_type" => "set_memo", "params" => { "value" => "from workflow" } } }

    trait :branch do
      kind { "branch" }
      config do
        { "match_all" => true,
          "conditions" => [ { "field" => "description", "operator" => "contains", "value" => "STARBUCKS" } ] }
      end
    end

    trait :else_branch do
      kind { "branch" }
      config { { "else" => true } }
    end

    trait :wait do
      kind { "wait" }
      config { { "duration_seconds" => 300 } }
    end
  end

  factory :workflow_run do
    workflow
    household { Current.household || create(:household) }
    event_type { "cash_transaction.created" }
    status { "pending" }
  end
end
