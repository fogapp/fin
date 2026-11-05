require "swagger_helper"

RSpec.describe "Instance settings", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  path "/api/v1/instance_settings" do
    get "Instance-wide settings: the time zone and the zones to choose from" do
      tags "Instance Settings"
      produces "application/json"

      response "200", "instance settings" do
        schema "$ref" => "#/components/schemas/InstanceSettings"
        run_test! do |response|
          expect(response.parsed_body["time_zone"]).to eq("America/Los_Angeles")
        end
      end
    end

    patch "Change the instance time zone (household admin only)" do
      tags "Instance Settings"
      description "Accepts an IANA identifier or a Rails zone name and stores the IANA identifier. " \
                  "Every request and background job runs in this zone."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { time_zone: { type: :string, example: "America/New_York" } },
        required: %w[time_zone]
      }

      response "200", "time zone changed" do
        schema "$ref" => "#/components/schemas/InstanceSettings"
        let(:body) { { time_zone: "America/New_York" } }
        run_test! do |response|
          expect(response.parsed_body["time_zone"]).to eq("America/New_York")
        end
      end

      response "403", "caller is not a household admin" do
        schema "$ref" => "#/components/schemas/Error"
        let(:token) do
          membership = create(:household_membership, household: create(:household), role: "member")
          create(:api_token, user: membership.user, household: membership.household)
        end
        let(:body) { { time_zone: "America/New_York" } }
        run_test!
      end

      response "422", "unknown time zone" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { time_zone: "Mars/Olympus_Mons" } }
        run_test!
      end
    end
  end
end
