require "rails_helper"

RSpec.describe PlaidClient do
  describe "#initialize" do
    before do
      allow(PlaidConfiguration).to receive(:current).and_return(PlaidConfiguration.new(environment: "production"))
    end

    it "raises NotConfigured when neither the configuration nor ENV has credentials" do
      stub_const("ENV", ENV.to_h.except("PLAID_CLIENT_ID", "PLAID_SECRET"))
      expect { described_class.new }.to raise_error(described_class::NotConfigured, /Settings → Integrations → Plaid/)
    end

    it "falls back to ENV credentials" do
      stub_const("ENV", ENV.to_h.merge("PLAID_CLIENT_ID" => "cid", "PLAID_SECRET" => "sec"))
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#create_link_token" do
    # A partial double on a real PlaidApi, not an instance_double: the
    # constructor's `T.let(..., Plaid::PlaidApi)` runtime check rejects a
    # verifying double.
    let(:api) { Plaid::PlaidApi.new }

    before do
      allow(PlaidConfiguration).to receive(:current).and_return(
        PlaidConfiguration.new(environment: "production", client_id: "cid", secret: "sec")
      )
      allow(Plaid::PlaidApi).to receive(:new).and_return(api)
    end

    # Regression: `investments` used to sit in `products`, which Plaid treats
    # as a hard requirement on the accounts the user selects. Linking a
    # credit-card-only item (e.g. a Chase card) then failed in Link with
    # "No investment accounts" AFTER the bank had already granted access.
    it "requires only transactions and leaves investments optional" do
      captured = nil
      allow(api).to receive(:link_token_create) { |req| captured = req; double(link_token: "lt") }

      described_class.new.create_link_token(user_id: "42")

      expect(captured.products).to eq([ "transactions" ])
      expect(captured.optional_products).to eq([ "investments" ])
    end
  end
end
