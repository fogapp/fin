require "rails_helper"

RSpec.describe "Api::V1::Notifications", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  it "lists notifications with an unread count and marks them read" do
    n1 = Notification.create!(household: Current.household, title: "Rent posted")
    n2 = Notification.create!(household: Current.household, title: "Old news", read_at: 1.day.ago)

    get "/api/v1/notifications", headers: auth_headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["unread_count"]).to eq(1)
    expect(body["notifications"].map { |n| n["title"] }).to include("Rent posted", "Old news")

    post "/api/v1/notifications/#{n1.id}/read", headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(n1.reload.read_at).to be_present

    get "/api/v1/notifications", params: { unread: "true" }, headers: auth_headers
    expect(response.parsed_body["notifications"]).to be_empty
    expect(n2.reload.read_at).to be_present # untouched sanity: was already read
  end

  it "read_all clears the badge" do
    2.times { |i| Notification.create!(household: Current.household, title: "N#{i}") }

    post "/api/v1/notifications/read_all", headers: auth_headers
    expect(response).to have_http_status(:no_content)
    expect(Notification.unread.count).to eq(0)
  end

  it "hides other households' notifications" do
    other = create(:household, name: "Other")
    Notification.create!(household: other, title: "Secret")

    get "/api/v1/notifications", headers: auth_headers
    expect(response.parsed_body["notifications"]).to be_empty
  end
end
