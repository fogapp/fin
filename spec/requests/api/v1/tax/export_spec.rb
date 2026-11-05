require "rails_helper"

RSpec.describe "Api::V1::Tax::Exports", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/tax/export" do
    it "bundles the report with flat transaction lists" do
      create(:tax_profile, tax_year: 2026, projected_wages: 300_000)

      account  = create(:account, name: "Brokerage")
      tt_sale  = create(:transaction_type, :sale)
      security = create(:security, ticker: "AAA")
      create(:investment_transaction, account: account, transaction_type: tt_sale,
             security: security, trade_date: Date.new(2026, 2, 10),
             gl_short_usd: -500, gl_long_usd: 2_000, amount_usd: 10_000)

      giving = create(:category, charitable: true)
      create(:cash_transaction, source: "credit_card", transaction_type: "Sale",
             account: account, category: giving, amount: -300,
             transaction_date: Date.new(2026, 4, 2), description: "RED CROSS")

      create(:estimated_tax_payment, tax_year: 2026, jurisdiction: "federal",
             paid_on: Date.new(2026, 4, 10), amount: 5_000)

      get "/api/v1/tax/export", params: { year: 2026 }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include("generated_at", "report", "transactions")
      expect(body["report"]["year"]).to eq(2026)

      sale = body.dig("transactions", "realized_sales").sole
      expect(sale).to include("date" => "2026-02-10", "proceeds" => 10_000.0,
                              "st" => -500.0, "lt" => 2_000.0)
      expect(sale["security"]).to include("AAA")

      expect(body.dig("transactions", "charitable").sole).to include("amount" => 300.0)
      expect(body.dig("transactions", "estimated_payments").sole)
        .to include("amount" => 5_000.0, "quarter" => "Q1")
    end
  end
end
