require "swagger_helper"

RSpec.describe "Subscriptions", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/subscriptions" do
    get "List recurring series with a lifecycle status" do
      tags "Subscriptions"
      produces "application/json"
      parameter name: :status, in: :query, required: false,
                schema: { type: :string, enum: %w[suggested active dismissed lapsed ended] },
                description: "Lifecycle status to list (default active)"

      response "200", "series and summary" do
        schema "$ref" => "#/components/schemas/SubscriptionsData"
        before { wealth }
        run_test!
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end

    post "Add a subscription by hand" do
      tags "Subscriptions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:                { type: :string },
          kind:                { type: :string, enum: %w[subscription bill] },
          granularity:         { type: :string, enum: %w[day week month year] },
          quantity:            { type: :integer, description: "Every N granularity units (default 1)" },
          anchor:              { type: :object, additionalProperties: {}, description: "e.g. { day_of_month: 15 }" },
          average_amount:      { type: :number },
          amount_tolerance:    { type: :number },
          merchant_id:         { type: :string, format: :uuid },
          account_id:          { type: :string, format: :uuid },
          description_pattern: { type: :string },
          notes:               { type: :string },
          cash_transaction_id: { type: :string, format: :uuid, description: "A charge to adopt as the first occurrence" },
          history_transaction_ids: { type: :array, items: { type: :string, format: :uuid },
                                     description: "Earlier charges of the same stream to adopt as paid history (ones another series tracks are skipped)" }
        },
        required: %w[name granularity]
      }

      response "201", "subscription created" do
        schema "$ref" => "#/components/schemas/SubscriptionDetail"
        let(:body) do
          { name: "Gym", kind: "subscription", granularity: "month", anchor: { day_of_month: 1 }, average_amount: 45,
            merchant_id: create(:merchant, name: "Gym Co").id }
        end
        run_test!
      end
    end
  end

  path "/api/v1/subscriptions/upcoming" do
    get "Forecast charges in the next N days" do
      tags "Subscriptions"
      produces "application/json"
      parameter name: :days, in: :query, type: :integer, required: false, description: "Forecast horizon in days (default 30, max 365)"

      response "200", "upcoming charges" do
        schema "$ref" => "#/components/schemas/UpcomingCharges"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/subscriptions/calendar" do
    get "A month's expected and charged occurrences" do
      tags "Subscriptions"
      produces "application/json"
      parameter name: :month, in: :query, type: :string, required: false, description: "YYYY-MM (default: this month)"

      response "200", "calendar month" do
        schema "$ref" => "#/components/schemas/SubscriptionsCalendarData"
        before { wealth }
        run_test!
      end

      response "400", "malformed month" do
        schema "$ref" => "#/components/schemas/Error"
        let(:month) { "not-a-month" }
        run_test!
      end
    end
  end

  path "/api/v1/subscriptions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "A series with its full occurrence history" do
      tags "Subscriptions"
      produces "application/json"

      response "200", "series detail" do
        schema "$ref" => "#/components/schemas/SubscriptionDetail"
        let(:id) { wealth.series.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch "Update a series" do
      tags "Subscriptions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:             { type: :string },
          kind:             { type: :string, enum: %w[subscription bill] },
          notes:            { type: :string },
          average_amount:   { type: :number },
          amount_tolerance: { type: :number }
        }
      }

      response "200", "series updated" do
        schema "$ref" => "#/components/schemas/SubscriptionDetail"
        let(:id)   { wealth.series.id }
        let(:body) { { notes: "Family plan" } }
        run_test!
      end
    end

    delete "Delete a series and its occurrences" do
      tags "Subscriptions"

      response "204", "series deleted" do
        let(:id) { create(:recurring_series).id }
        run_test!
      end
    end
  end

  {
    "accept"  => [ "Accept a suggested series", "suggested" ],
    "dismiss" => [ "Dismiss a series (drops its pending forecasts)", "suggested" ],
    "restore" => [ "Restore a dismissed series", "dismissed" ],
    "end"     => [ "End an active subscription", "active" ]
  }.each do |action, (summary, from_status)|
    path "/api/v1/subscriptions/{id}/#{action}" do
      parameter name: :id, in: :path, type: :string, format: :uuid, required: true

      post summary do
        tags "Subscriptions"
        produces "application/json"

        response "200", "series after the transition" do
          schema "$ref" => "#/components/schemas/SubscriptionDetail"
          let(:id) do
            series = create(:recurring_series, status: from_status, dismissed_at: (from_status == "dismissed" ? 1.day.ago : nil),
                                               accepted_at: (from_status == "active" ? 1.week.ago : nil))
            create(:recurring_occurrence, recurring_series: series)
            series.id
          end
          run_test!
        end

        next unless action == "dismiss"

        response "422", "transition not allowed from the current status" do
          schema "$ref" => "#/components/schemas/ValidationErrors"
          let(:id) { create(:recurring_series, status: "ended", ended_at: 1.day.ago).id }
          run_test!
        end
      end
    end
  end

  {
    "detach" => "Unlink the charge matched to an occurrence",
    "skip"   => "Skip an expected occurrence"
  }.each do |action, summary|
    path "/api/v1/subscriptions/{id}/occurrences/{occurrence_id}/#{action}" do
      parameter name: :id,            in: :path, type: :string, format: :uuid, required: true
      parameter name: :occurrence_id, in: :path, type: :string, format: :uuid, required: true

      post summary do
        tags "Subscriptions"
        produces "application/json"

        response "200", "series after the change" do
          schema "$ref" => "#/components/schemas/SubscriptionDetail"
          let(:id) { wealth.series.id }
          let(:occurrence_id) do
            status = action == "detach" ? "paid" : "upcoming"
            wealth.series.recurring_occurrences.find_by!(status: status).id
          end
          run_test!
        end
      end
    end
  end
end
