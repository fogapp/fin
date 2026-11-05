require "rails_helper"

RSpec.describe "Api::V1::Issues", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  def make_issue(**attrs)
    Issue.create!({ title: "Something needs attention", severity: Severity::Warning }.merge(attrs))
  end

  describe "GET /api/v1/issues" do
    it "returns 401 without authentication" do
      get "/api/v1/issues"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns active issues newest first with the fields the inbox renders" do
      make_issue(title: "Older", created_at: 2.days.ago)
      make_issue(title: "Newer", created_at: 1.day.ago)

      get "/api/v1/issues", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |i| i["title"] }).to eq([ "Newer", "Older" ])
      expect(body.first.keys).to include("id", "key", "title", "body", "severity", "source", "dismissed_at", "created_at")
    end

    it "omits already-dismissed issues" do
      make_issue(title: "Open")
      make_issue(title: "Gone", dismissed_at: Time.current)

      get "/api/v1/issues", headers: auth_headers

      expect(response.parsed_body.map { |i| i["title"] }).to eq([ "Open" ])
    end

    it "does not leak issues from another household" do
      make_issue(title: "Mine")
      Current.set(household: create(:household)) { make_issue(title: "Theirs") }

      get "/api/v1/issues", headers: auth_headers

      expect(response.parsed_body.map { |i| i["title"] }).to eq([ "Mine" ])
    end
  end

  describe "DELETE /api/v1/issues/:id" do
    it "dismisses the issue and returns it with dismissed_at set" do
      issue = make_issue(title: "Dismiss me")

      delete "/api/v1/issues/#{issue.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["dismissed_at"]).to be_present
      expect(issue.reload.dismissed_at).to be_present
      expect(Issue.unscoped.where(id: issue.id)).to be_present # dismissed, not deleted
    end

    it "returns 404 for an unknown issue" do
      delete "/api/v1/issues/#{SecureRandom.uuid}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to be_present
    end

    it "returns 404 for an issue in another household" do
      other = Current.set(household: create(:household)) { make_issue(title: "Theirs") }

      delete "/api/v1/issues/#{other.id}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(other.reload.dismissed_at).to be_nil
    end
  end

  describe "POST /api/v1/issues/dismiss_all" do
    it "dismisses every active issue and reports the count" do
      make_issue(title: "One")
      make_issue(title: "Two")

      post "/api/v1/issues/dismiss_all", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["dismissed"]).to eq(2)
      expect(Issue.active.count).to eq(0)
    end

    it "dismisses only the requested source when one is given" do
      make_issue(title: "Audit", source: "system_audit")
      make_issue(title: "Sync",  source: "plaid")

      post "/api/v1/issues/dismiss_all", params: { source: "system_audit" },
           headers: auth_headers, as: :json

      expect(response.parsed_body["dismissed"]).to eq(1)
      expect(Issue.active.pluck(:title)).to eq([ "Sync" ])
    end

    it "leaves another household's issues untouched" do
      make_issue(title: "Mine")
      other = Current.set(household: create(:household)) { make_issue(title: "Theirs") }

      post "/api/v1/issues/dismiss_all", headers: auth_headers

      expect(response.parsed_body["dismissed"]).to eq(1)
      expect(other.reload.dismissed_at).to be_nil
    end
  end
end
