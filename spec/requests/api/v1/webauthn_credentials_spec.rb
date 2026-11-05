require "rails_helper"

RSpec.describe "Api::V1::WebauthnCredentials", type: :request do
  let(:user)         { create(:user) }
  let(:token)        { create(:api_token, user: user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  def make_credential(user_record = user, nickname: nil, **attrs)
    user_record.webauthn_credentials.create!(
      { external_id: SecureRandom.uuid, public_key: SecureRandom.hex(32), sign_count: 0,
        nickname: nickname }.merge(attrs)
    )
  end

  describe "GET /api/v1/webauthn_credentials" do
    it "returns 401 without authentication" do
      get "/api/v1/webauthn_credentials"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user's passkeys oldest first with the listed fields" do
      make_credential(nickname: "Laptop",  created_at: 2.days.ago)
      make_credential(nickname: "Phone",   created_at: 1.day.ago)

      get "/api/v1/webauthn_credentials", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |c| c["nickname"] }).to eq([ "Laptop", "Phone" ])
      expect(body.first.keys).to match_array(%w[id nickname created_at last_used_at])
    end

    it "never exposes the public key or external id" do
      make_credential(nickname: "Laptop")

      get "/api/v1/webauthn_credentials", headers: auth_headers

      expect(response.parsed_body.first.keys).not_to include("public_key", "external_id")
    end

    it "does not return another user's passkeys" do
      make_credential(nickname: "Mine")
      make_credential(create(:user), nickname: "Theirs")

      get "/api/v1/webauthn_credentials", headers: auth_headers

      expect(response.parsed_body.map { |c| c["nickname"] }).to eq([ "Mine" ])
    end
  end

  describe "PATCH /api/v1/webauthn_credentials/:id" do
    it "renames the passkey and returns the updated record" do
      cred = make_credential(nickname: "Old")

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: { nickname: "MacBook Pro" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["nickname"]).to eq("MacBook Pro")
      expect(cred.reload.nickname).to eq("MacBook Pro")
    end

    it "trims surrounding whitespace" do
      cred = make_credential(nickname: "Old")

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: { nickname: "  Work laptop  " }, headers: auth_headers, as: :json

      expect(cred.reload.nickname).to eq("Work laptop")
    end

    # A passkey can't be un-named: clearing is rejected, not stored as NULL.
    it "refuses a whitespace-only nickname and keeps the existing name" do
      cred = make_credential(nickname: "Old")

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: { nickname: "   " }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Nickname can't be blank")
      expect(cred.reload.nickname).to eq("Old")
    end

    it "refuses an empty nickname, which is what the Devices panel sends when cleared" do
      cred = make_credential(nickname: "Old")

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: { nickname: "" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(cred.reload.nickname).to eq("Old")
    end

    it "refuses a request with no nickname at all" do
      cred = make_credential(nickname: "Old")

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: {}, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(cred.reload.nickname).to eq("Old")
    end

    it "still refuses to clear the name of a passkey that never had one" do
      cred = make_credential(nickname: nil)

      patch "/api/v1/webauthn_credentials/#{cred.id}",
            params: { nickname: "" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(cred.reload.nickname).to be_nil
    end

    it "returns 404 when renaming another user's passkey" do
      other = make_credential(create(:user), nickname: "Theirs")

      patch "/api/v1/webauthn_credentials/#{other.id}",
            params: { nickname: "Hijacked" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.nickname).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/webauthn_credentials/:id" do
    it "removes the passkey when the user has more than one" do
      keep   = make_credential(nickname: "Keep")
      remove = make_credential(nickname: "Remove")

      delete "/api/v1/webauthn_credentials/#{remove.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(user.webauthn_credentials.reload.map(&:id)).to eq([ keep.id ])
    end

    it "refuses to remove the only passkey, which would lock the user out" do
      only = make_credential(nickname: "Only")

      delete "/api/v1/webauthn_credentials/#{only.id}", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Cannot remove your only passkey")
      expect(only.reload).to be_persisted
    end

    it "returns 404 when deleting another user's passkey" do
      other_user = create(:user)
      make_credential(other_user, nickname: "A")
      target = make_credential(other_user, nickname: "B")

      delete "/api/v1/webauthn_credentials/#{target.id}", headers: auth_headers

      expect(response).to have_http_status(:not_found)
      expect(target.reload).to be_persisted
    end

    it "returns 401 without authentication" do
      cred = make_credential
      delete "/api/v1/webauthn_credentials/#{cred.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
