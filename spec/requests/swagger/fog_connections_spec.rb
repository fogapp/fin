require "swagger_helper"

# The consent page's API: a household admin answers what fog asks for an app.
RSpec.describe "Fog connections", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  let(:asked) do
    FogIntegrations.ask(consumer: "newtab", offer: "finance",
      return_to: "https://fog.example/api/integrations/return?state=abc")
  end
  let(:ticket) { asked.consent.delete_prefix("/connect/") }

  path "/api/v1/fog_connections/{ticket}" do
    parameter name: :ticket, in: :path, type: :string, required: true,
      description: "The ticket in the page's address, /connect/<ticket>"

    get "What fog is asking for an app" do
      tags "Fog connections"
      produces "application/json"
      description "Household admins only: the app, the offer's words, and whether it can still be answered."

      response "200", "the request" do
        schema "$ref" => "#/components/schemas/FogConnection"
        run_test! do |response|
          expect(response.parsed_body).to include("consumer" => "newtab", "state" => "pending")
        end
      end

      response "403", "not a household admin" do
        schema "$ref" => "#/components/schemas/Error"
        let(:member_token) do
          h = create(:household)
          create(:household_membership, household: h, role: "member")
          create(:api_token, household: h)
        end
        let(:Authorization) { "Bearer #{member_token.raw_token}" }
        run_test!
      end

      response "404", "no such request in this household" do
        schema "$ref" => "#/components/schemas/Error"
        let(:ticket) { "nope" }
        run_test!
      end
    end
  end

  path "/api/v1/fog_connections/{ticket}/approve" do
    parameter name: :ticket, in: :path, type: :string, required: true

    post "Let the app read Fin" do
      tags "Fog connections"
      produces "application/json"
      description "Mints a read-only API token in the caller's name for fog to claim; the browser then goes to return_to."

      response "200", "approved" do
        schema "$ref" => "#/components/schemas/FogConnectionAnswer"
        run_test! do |response|
          expect(response.parsed_body["return_to"]).to end_with("state=abc&result=approved")
        end
      end

      response "409", "already answered" do
        schema "$ref" => "#/components/schemas/Error"
        before { FogIntegrations.decline!(ticket) }
        run_test!
      end

      response "410", "expired" do
        schema "$ref" => "#/components/schemas/Error"
        before { FogIntegration.unscoped.where(ticket_digest: Digest::SHA256.hexdigest(ticket)).update_all(expires_at: 1.minute.ago) }
        run_test!
      end
    end
  end

  path "/api/v1/fog_connections/{ticket}/decline" do
    parameter name: :ticket, in: :path, type: :string, required: true

    post "Refuse the app" do
      tags "Fog connections"
      produces "application/json"

      response "200", "declined" do
        schema "$ref" => "#/components/schemas/FogConnectionAnswer"
        run_test! do |response|
          expect(response.parsed_body["return_to"]).to end_with("state=abc&result=declined")
        end
      end
    end
  end
end
