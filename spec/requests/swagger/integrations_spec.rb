require "swagger_helper"

RSpec.describe "Integration Configurations", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # CoinbaseClient#initialize parses the Ed25519 keypair from the stored
  # secret, so configured-Coinbase examples need a structurally valid one.
  def configure_coinbase!
    seed   = SecureRandom.bytes(32)
    secret = Base64.strict_encode64(seed + SecureRandom.bytes(32))
    CoinbaseConfiguration.create!(api_key_id: "key-id", api_key_secret: secret)
  end

  let(:coinbase_raw_accounts) do
    [
      { "id" => "acct-1", "name" => "BTC Wallet", "type" => "wallet",
        "balance" => { "amount" => "0.5", "currency" => "BTC" } }
    ]
  end

  # The CoinMarketCap / Alpha Vantage / Tiingo configuration endpoints share
  # one shape: show, update (api_key) and a connection test.
  def self.api_key_provider(slug, tag, params_key, stub_success:)
    path "/api/v1/#{slug}/configuration" do
      get "#{tag} API key status" do
        tags tag
        produces "application/json"

        response "200", "configuration returned" do
          schema "$ref" => "#/components/schemas/ApiKeyConfiguration"
          run_test!
        end
      end

      patch "Save the #{tag} API key" do
        tags tag
        consumes "application/json"
        produces "application/json"
        parameter name: :body, in: :body, schema: {
          type: :object,
          properties: {
            params_key => { type: :object, properties: { api_key: { type: :string } }, required: %w[api_key] }
          },
          required: [ params_key.to_s ]
        }

        response "200", "API key saved" do
          schema "$ref" => "#/components/schemas/ApiKeyConfiguration"
          let(:body) { { params_key => { api_key: "key-abc123" } } }
          run_test! do |response|
            expect(response.parsed_body).to include("api_key_set" => true, "configured" => true)
          end
        end
      end
    end

    path "/api/v1/#{slug}/configuration/test" do
      post "Test the #{tag} connection" do
        tags tag
        produces "application/json"

        response "200", "connection succeeded" do
          schema "$ref" => "#/components/schemas/ConnectionTestResult"
          before { instance_exec(&stub_success) }
          run_test!
        end
      end
    end
  end

  # ── Coinbase ──────────────────────────────────────────────────────────────────

  path "/api/v1/coinbase/configuration" do
    get "Coinbase credentials status" do
      tags "Coinbase"
      produces "application/json"

      response "200", "configuration returned" do
        schema "$ref" => "#/components/schemas/CoinbaseConfiguration"
        run_test!
      end
    end

    patch "Save Coinbase credentials" do
      tags "Coinbase"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          coinbase_configuration: {
            type: :object,
            properties: {
              api_key_id:     { type: :string },
              api_key_secret: { type: :string }
            }
          }
        },
        required: %w[coinbase_configuration]
      }

      response "200", "credentials saved" do
        schema "$ref" => "#/components/schemas/CoinbaseConfiguration"
        let(:body) { { coinbase_configuration: { api_key_id: "key-id", api_key_secret: "key-secret" } } }
        run_test!
      end
    end
  end

  path "/api/v1/coinbase/configuration/test" do
    post "Test the Coinbase connection" do
      tags "Coinbase"
      produces "application/json"

      response "200", "connection succeeded" do
        schema "$ref" => "#/components/schemas/ConnectionTestResult"
        before do
          configure_coinbase!
          allow_any_instance_of(CoinbaseClient).to receive(:accounts).and_return(coinbase_raw_accounts)
        end
        run_test!
      end

      response "422", "connection failed" do
        schema "$ref" => "#/components/schemas/ConnectionTestResult"
        before do
          configure_coinbase!
          allow_any_instance_of(CoinbaseClient).to receive(:accounts).and_raise(CoinbaseClient::Error, "401 Unauthorized")
        end
        run_test! do |response|
          expect(response.parsed_body).to include("ok" => false, "error" => "401 Unauthorized")
        end
      end
    end
  end

  path "/api/v1/coinbase/accounts" do
    get "List Coinbase accounts (calls live API)" do
      tags "Coinbase"
      produces "application/json"

      response "200", "Coinbase accounts listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/CoinbaseAccount" }
        before do
          configure_coinbase!
          allow_any_instance_of(CoinbaseClient).to receive(:accounts).and_return(coinbase_raw_accounts)
        end
        run_test!
      end

      response "422", "Coinbase not configured" do
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/coinbase/sync" do
    post "Enqueue a Coinbase sync job" do
      tags "Coinbase"
      produces "application/json"

      response "202", "sync queued" do
        schema "$ref" => "#/components/schemas/Queued"
        before { configure_coinbase! }
        run_test!
      end

      response "422", "Coinbase not configured" do
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  # ── API-key providers ─────────────────────────────────────────────────────────

  api_key_provider "coin_market_cap", "CoinMarketCap", :coin_market_cap_configuration,
                   stub_success: -> {
                     CoinMarketCapConfiguration.create!(api_key: "cmc-key")
                     allow_any_instance_of(CoinMarketCap::Client).to receive(:quotes).and_return({ "BTC" => 65_000.0 })
                   }

  api_key_provider "alpha_vantage", "Alpha Vantage", :alpha_vantage_configuration,
                   stub_success: -> {
                     AlphaVantageConfiguration.create!(api_key: "av-key")
                     allow_any_instance_of(AlphaVantage::Client).to receive(:symbol_search).and_return([ { ticker: "AAPL" } ])
                   }

  api_key_provider "tiingo", "Tiingo", :tiingo_configuration,
                   stub_success: -> {
                     TiingoConfiguration.create!(api_key: "tiingo-key")
                     allow_any_instance_of(Tiingo::Client).to receive(:test_connection).and_return(true)
                   }

  path "/api/v1/tiingo/configuration" do
    delete "Remove the Tiingo API key" do
      tags "Tiingo"

      response "204", "API key removed" do
        before { TiingoConfiguration.create!(api_key: "tiingo-key") }
        run_test!
      end
    end
  end

  # ── Plaid ─────────────────────────────────────────────────────────────────────

  path "/api/v1/plaid/configuration" do
    get "Plaid credentials status" do
      tags "Plaid"
      produces "application/json"

      response "200", "Plaid configuration returned" do
        schema "$ref" => "#/components/schemas/PlaidConfiguration"
        run_test!
      end
    end

    patch "Save Plaid credentials" do
      tags "Plaid"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          plaid_configuration: {
            type: :object,
            properties: {
              client_id:   { type: :string },
              secret:      { type: :string },
              environment: { type: :string, enum: %w[sandbox production] }
            }
          }
        },
        required: %w[plaid_configuration]
      }

      response "200", "configuration updated" do
        schema "$ref" => "#/components/schemas/PlaidConfiguration"
        let(:body) { { plaid_configuration: { client_id: "cid", secret: "sec", environment: "sandbox" } } }
        run_test! do |response|
          expect(response.parsed_body).to include("configured" => true, "source" => "database")
        end
      end
    end
  end

  # ── Alchemy ───────────────────────────────────────────────────────────────────

  path "/api/v1/alchemy/configuration" do
    get "Alchemy configuration and webhook status" do
      tags "Alchemy"
      produces "application/json"

      response "200", "configuration returned" do
        schema "$ref" => "#/components/schemas/AlchemyConfiguration"
        before do
          create(:alchemy_configuration, auth_token: "notify-token", transactions_enabled: true)
          AlchemyWebhook.create!(network: "eth-mainnet", external_id: "wh_1", url: "https://fin.test/webhooks/alchemy",
                                 status: "active", last_received_at: 5.minutes.ago)
        end
        run_test!
      end
    end

    patch "Save Alchemy settings" do
      tags "Alchemy"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          alchemy_configuration: {
            type: :object,
            properties: {
              api_key:              { type: :string },
              auth_token:           { type: :string },
              webhook_base_url:     { type: :string },
              transactions_enabled: { type: :boolean },
              sync_frequency:       { type: :string, enum: %w[realtime every_5_minutes every_15_minutes hourly every_6_hours daily] }
            }
          }
        },
        required: %w[alchemy_configuration]
      }

      response "200", "settings saved" do
        schema "$ref" => "#/components/schemas/AlchemyConfiguration"
        let(:body) { { alchemy_configuration: { api_key: "alchemy-key", sync_frequency: "hourly" } } }
        run_test!
      end

      response "422", "unknown sync frequency" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { alchemy_configuration: { sync_frequency: "weekly" } } }
        run_test!
      end
    end
  end

  path "/api/v1/alchemy/configuration/test" do
    post "Test the Alchemy connection" do
      tags "Alchemy"
      produces "application/json"

      response "200", "connection succeeded" do
        schema "$ref" => "#/components/schemas/ConnectionTestResult"
        before do
          create(:alchemy_configuration)
          allow_any_instance_of(AlchemyClient).to receive(:test_connection!).and_return(true)
        end
        run_test!
      end
    end
  end

  path "/api/v1/alchemy/wallets" do
    get "List tracked wallets" do
      tags "Alchemy"
      produces "application/json"

      response "200", "wallets listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/AlchemyWallet" }
        before do
          wallet = create(:alchemy_wallet, name: "Cold storage", account: create(:account, balance: 1234.5))
          AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet", backfill_status: "completed",
                                    backfill_transfer_count: 42, last_synced_at: 1.hour.ago)
        end
        run_test!
      end
    end

    post "Track a wallet" do
      tags "Alchemy"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          alchemy_wallet: {
            type: :object,
            properties: {
              address:    { type: :string },
              name:       { type: :string },
              active:     { type: :boolean },
              account_id: { type: :string, format: :uuid },
              networks:   { type: :array, items: { type: :string } }
            },
            required: %w[address]
          }
        },
        required: %w[alchemy_wallet]
      }

      response "201", "wallet tracked" do
        schema "$ref" => "#/components/schemas/AlchemyWallet"
        let(:body) { { alchemy_wallet: { address: format("0x%040x", 7), name: "Hot wallet", networks: [ "eth-mainnet" ] } } }
        run_test!
      end
    end
  end

  path "/api/v1/alchemy/wallets/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update a wallet" do
      tags "Alchemy"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          alchemy_wallet: {
            type: :object,
            properties: {
              name:     { type: :string },
              active:   { type: :boolean },
              networks: { type: :array, items: { type: :string } }
            }
          }
        },
        required: %w[alchemy_wallet]
      }

      response "200", "wallet updated" do
        schema "$ref" => "#/components/schemas/AlchemyWallet"
        let(:id)   { create(:alchemy_wallet).id }
        let(:body) { { alchemy_wallet: { active: false } } }
        run_test!
      end
    end

    delete "Stop tracking a wallet" do
      tags "Alchemy"

      response "204", "wallet removed" do
        let(:id) { create(:alchemy_wallet).id }
        run_test!
      end
    end
  end

  path "/api/v1/alchemy/wallets/{id}/backfill" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Re-run the transaction backfill for a wallet" do
      tags "Alchemy"
      produces "application/json"

      response "202", "backfill queued" do
        schema "$ref" => "#/components/schemas/Queued"
        before { create(:alchemy_configuration, auth_token: "notify-token", transactions_enabled: true) }
        let(:id) { create(:alchemy_wallet).id }
        run_test!
      end

      response "422", "transaction sync not enabled" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { create(:alchemy_wallet).id }
        run_test!
      end
    end
  end

  path "/api/v1/alchemy/sync" do
    post "Enqueue an Alchemy balance sync" do
      tags "Alchemy"
      produces "application/json"

      response "202", "sync queued" do
        schema "$ref" => "#/components/schemas/Queued"
        before { create(:alchemy_configuration) }
        run_test!
      end

      response "422", "Alchemy not configured" do
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
