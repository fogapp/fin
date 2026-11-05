require "swagger_helper"

RSpec.describe "Households, Memberships & Invites", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── Households ────────────────────────────────────────────────────────────────

  path "/api/v1/households" do
    get "List households the current user belongs to" do
      tags "Households"
      produces "application/json"

      response "200", "households listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Household" }
        run_test!
      end
    end

    post "Create a new household (caller becomes admin)" do
      tags "Households"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string } },
        required: %w[name]
      }

      response "201", "household created" do
        schema "$ref" => "#/components/schemas/Household"
        let(:body) { { name: "My New Household" } }
        run_test!
      end
    end
  end

  path "/api/v1/households/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update household settings (admin only)" do
      tags "Households"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:                    { type: :string },
          workflow_log_level:      { type: :string, enum: %w[none info debug] },
          include_unvested_equity: { type: :boolean }
        }
      }

      response "200", "household renamed" do
        schema "$ref" => "#/components/schemas/Household"
        let(:id)   { token.household_id }
        let(:body) { { name: "Renamed", workflow_log_level: "debug", include_unvested_equity: true } }
        run_test!
      end

      response "403", "not an admin" do
        schema "$ref" => "#/components/schemas/Error"
        let(:non_admin_token) {
          h = create(:household)
          create(:household_membership, household: h, role: "member")
          create(:api_token, household: h)
        }
        let(:Authorization) { "Bearer #{non_admin_token.raw_token}" }
        let(:id) { non_admin_token.household_id }
        let(:body) { { name: "X" } }
        run_test!
      end
    end

    delete "Delete a household and all its data (admin only)" do
      tags "Households"
      produces "application/json"
      description "Returns a new bearer token scoped to one of the caller's remaining households."

      response "200", "household deleted, new token returned" do
        schema "$ref" => "#/components/schemas/Session"
        let(:user) { token.user }
        let(:other_household) { create(:household) }
        before { create(:household_membership, user: user, household: other_household, role: "admin") }
        let(:id) { token.household_id }
        run_test!
      end

      response "422", "last household — cannot delete" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { token.household_id }
        run_test!
      end
    end
  end

  # ── Household Memberships ─────────────────────────────────────────────────────

  path "/api/v1/household_memberships" do
    get "List members of the current household" do
      tags "Household Memberships"
      produces "application/json"

      response "200", "members listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/HouseholdMembership" }
        before { create(:household_membership, household: token.household, role: "member") }
        run_test!
      end
    end
  end

  path "/api/v1/household_memberships/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Change a member's role (admin only)" do
      tags "Household Memberships"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { role: { type: :string, enum: %w[admin member] } },
        required: %w[role]
      }

      response "200", "role updated" do
        schema "$ref" => "#/components/schemas/HouseholdMembership"
        let(:other_membership) { create(:household_membership, household: token.household, role: "member") }
        let(:id)   { other_membership.id }
        let(:body) { { role: "admin" } }
        run_test!
      end
    end

    delete "Remove a member (admin) or leave the household (self)" do
      tags "Household Memberships"

      response "204", "member removed" do
        let(:other_membership) { create(:household_membership, household: token.household, role: "member") }
        let(:id) { other_membership.id }
        run_test!
      end
    end
  end

  # ── Invites ───────────────────────────────────────────────────────────────────

  path "/api/v1/invites" do
    get "List active invites for the current household (admin only)" do
      tags "Invites"
      produces "application/json"

      response "200", "invites listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Invite" }
        before { create(:invite_code, household: token.household, role: "admin") }
        run_test!
      end
    end

    post "Create an invite link (admin only)" do
      tags "Invites"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          role:             { type: :string, enum: %w[admin member], description: "Role granted on acceptance" },
          expires_in_days:  { type: :integer, description: "Days until the link expires (default: 7)" }
        }
      }

      response "201", "invite created" do
        schema "$ref" => "#/components/schemas/InviteCreated"
        let(:body) { { role: "member", expires_in_days: 7 } }
        run_test!
      end
    end
  end

  path "/api/v1/invites/{code}" do
    parameter name: :code, in: :path, type: :string, required: true, description: "Invite code (not a UUID)"

    get "Look up an invite by code (no auth required)" do
      tags "Invites"
      produces "application/json"
      security []

      response "200", "invite found" do
        schema "$ref" => "#/components/schemas/InvitePreview"
        let(:invite) { create(:invite_code, household: token.household) }
        let(:code)   { invite.code }
        let(:Authorization) { nil }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:code) { "nonexistent" }
        let(:Authorization) { nil }
        run_test!
      end
    end

    delete "Revoke an invite (admin only)" do
      tags "Invites"

      response "204", "invite revoked" do
        let(:invite) { create(:invite_code, household: token.household) }
        let(:code)   { invite.code }
        run_test!
      end
    end
  end
end
