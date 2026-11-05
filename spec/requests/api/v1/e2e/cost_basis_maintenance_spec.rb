require "rails_helper"

# E2E flow: a user has imported investment transactions and wants to set up
# cost-basis lots from them. They preview, commit, see the result roll up
# in /cost_basis, then manually add another lot and re-check.
RSpec.describe "E2E: cost basis maintenance", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account) }
  let(:security)     { create(:security, ticker: "AAPL", name: "Apple Inc.") }
  let!(:purchase_type) { create(:transaction_type, :purchase) }

  before do
    # A current-position snapshot (10 shares, $1,500 mkt value)
    create(:position_snapshot, security: security, account: account,
           as_of_date: Date.current, quantity: 10, market_value: 1_500.0,
           asset_class: "Equity")

    # Two real purchases that together cover the 10 shares
    create(:investment_transaction, security: security, account: account,
           transaction_type: purchase_type, trade_date: Date.new(2026, 1, 1),
           quantity: 4, amount_usd: 400, cost_usd: 400)
    create(:investment_transaction, security: security, account: account,
           transaction_type: purchase_type, trade_date: Date.new(2026, 3, 1),
           quantity: 6, amount_usd: 720, cost_usd: 720)
  end

  it "lets the user preview, commit, and verify cost basis is complete" do
    # 1 — Preview: returns 2 surviving lots without persisting
    expect {
      post "/api/v1/investment_lots/generate",
           params: { security_id: security.id },
           headers: auth_headers, as: :json
    }.not_to change(InvestmentLot, :count)
    expect(response).to have_http_status(:ok)
    preview = response.parsed_body
    expect(preview.length).to eq(2)
    expect(preview.map { |l| l["quantity"] }).to contain_exactly(4.0, 6.0)
    expect(preview.map { |l| l["cost_basis"] }).to contain_exactly(400.0, 720.0)

    # 2 — Before commit, /cost_basis falls back to transaction-based math
    get "/api/v1/cost_basis", headers: auth_headers
    expect(response).to have_http_status(:ok)
    pos = response.parsed_body["positions"].find { |p| p["ticker"] == "AAPL" }
    expect(pos["lots"]).to eq([])
    expect(pos["status"]).to eq("complete")
    expect(pos["computed_cost_basis"]).to eq(1120.0)

    # 3 — Commit the preview → InvestmentLots created
    expect {
      post "/api/v1/investment_lots/generate",
           params: { security_id: security.id, commit: true },
           headers: auth_headers, as: :json
    }.to change(InvestmentLot, :count).by(2)
    expect(response).to have_http_status(:created)

    # 4 — /cost_basis now uses the manual lots and reflects complete status
    get "/api/v1/cost_basis", headers: auth_headers
    pos = response.parsed_body["positions"].find { |p| p["ticker"] == "AAPL" }
    expect(pos["lots"].length).to eq(2)
    expect(pos["computed_cost_basis"]).to eq(1120.0)
    expect(pos["status"]).to eq("complete")
    expect(response.parsed_body["summary"]["complete"]).to eq(1)
  end

  it "returns 409 when re-committing without replace and lots already exist" do
    create(:investment_lot, security: security, account: account)

    post "/api/v1/investment_lots/generate",
         params: { security_id: security.id, commit: true },
         headers: auth_headers, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]).to eq("lots_exist")
  end

  it "lets the user add a manual lot and have it reflected in /cost_basis" do
    post "/api/v1/investment_lots",
         params: { security_id: security.id, account_id: account.id,
                   acquired_date: "2026-04-01", quantity: 10, cost_basis: 1000 },
         headers: auth_headers, as: :json
    expect(response).to have_http_status(:created)

    get "/api/v1/cost_basis", headers: auth_headers
    pos = response.parsed_body["positions"].find { |p| p["ticker"] == "AAPL" }
    expect(pos["lots"].length).to eq(1)
    expect(pos["computed_cost_basis"]).to eq(1000.0)
    expect(pos["status"]).to eq("complete")
  end

  it "lets the user list, update, and destroy a manual lot via /investment_lots" do
    lot = create(:investment_lot, security: security, account: account,
                 quantity: 5, cost_basis: 500)

    get "/api/v1/investment_lots", params: { security_id: security.id }, headers: auth_headers
    expect(response.parsed_body.map { |l| l["id"] }).to include(lot.id)

    patch "/api/v1/investment_lots/#{lot.id}",
          params: { cost_basis: 600 }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(lot.reload.cost_basis).to eq(600)

    delete "/api/v1/investment_lots/#{lot.id}", headers: auth_headers
    expect(response).to have_http_status(:no_content)
    expect(InvestmentLot.exists?(lot.id)).to be false
  end
end
