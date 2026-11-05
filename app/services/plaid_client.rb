# typed: strict

class PlaidClient
  extend T::Sig

  ENVIRONMENTS = T.let({
    "sandbox"    => Plaid::Configuration::Environment["sandbox"],
    "production" => Plaid::Configuration::Environment["production"]
  }.freeze, T::Hash[String, T.untyped])

  # Neither the household's stored credentials nor the deployment-wide
  # PLAID_CLIENT_ID / PLAID_SECRET fallback is set. Its message is written
  # for the person linking a bank, so controllers show it as is.
  class NotConfigured < StandardError
    extend T::Sig

    sig { void }
    def initialize
      super("Plaid isn't set up for this household yet. Add your Plaid client ID and secret in Settings → Integrations → Plaid.")
    end
  end

  sig { void }
  def initialize
    db_config = PlaidConfiguration.current

    # environment reads back as a PlaidConfiguration::Environment enum;
    # ENVIRONMENTS is string-keyed, so serialize before the lookup.
    plaid_env = db_config.environment.to_s.presence || PlaidConfiguration.default_environment
    client_id = db_config.client_id.presence  || ENV["PLAID_CLIENT_ID"].presence
    secret    = db_config.secret.presence     || ENV["PLAID_SECRET"].presence
    raise NotConfigured unless client_id && secret

    configuration = Plaid::Configuration.new
    configuration.server_index = ENVIRONMENTS.fetch(plaid_env) { raise ArgumentError, "unknown Plaid environment #{plaid_env.inspect}; use sandbox or production" }
    configuration.api_key["PLAID-CLIENT-ID"] = client_id
    configuration.api_key["PLAID-SECRET"]    = secret
    @client = T.let(Plaid::PlaidApi.new(Plaid::ApiClient.new(configuration)), Plaid::PlaidApi)
  end

  sig { params(user_id: String).returns(T.untyped) }
  def create_link_token(user_id:)
    # Only `transactions` is required. Anything in `products` must be
    # supported by BOTH the institution and at least one account the user
    # selects, so listing `investments` here made Link reject a credit-card
    # -only selection with "No investment accounts" after the bank had
    # already granted access. As an optional product, investments is still
    # extracted (and billed) whenever the chosen accounts support it.
    request = Plaid::LinkTokenCreateRequest.new(
      user:               Plaid::LinkTokenCreateRequestUser.new(client_user_id: user_id.to_s),
      client_name:        "Fin",
      products:           [ "transactions" ],
      optional_products:  [ "investments" ],
      country_codes:      [ "US" ],
      language:           "en"
    )
    @client.link_token_create(request)
  end

  sig { params(public_token: String).returns(T.untyped) }
  def exchange_public_token(public_token)
    request = Plaid::ItemPublicTokenExchangeRequest.new(public_token: public_token)
    @client.item_public_token_exchange(request)
  end

  sig { params(access_token: String).returns(T.untyped) }
  def get_item(access_token)
    request = Plaid::ItemGetRequest.new(access_token: access_token)
    @client.item_get(request)
  end

  sig { params(access_token: String).returns(T.untyped) }
  def get_accounts(access_token)
    request = Plaid::AccountsGetRequest.new(access_token: access_token)
    @client.accounts_get(request)
  end

  sig { params(institution_id: String).returns(T.untyped) }
  def get_institution(institution_id)
    request = Plaid::InstitutionsGetByIdRequest.new(
      institution_id: institution_id,
      country_codes:  [ "US" ]
    )
    @client.institutions_get_by_id(request)
  end

  sig { params(access_token: String).returns(T.untyped) }
  def get_investment_holdings(access_token)
    request = Plaid::InvestmentsHoldingsGetRequest.new(access_token: access_token)
    @client.investments_holdings_get(request)
  end

  sig { params(access_token: String, start_date: Date, end_date: Date, offset: Integer).returns(T.untyped) }
  def get_investment_transactions(access_token, start_date:, end_date:, offset: 0)
    request = Plaid::InvestmentsTransactionsGetRequest.new(
      access_token: access_token,
      start_date:   start_date,
      end_date:     end_date,
      options:      Plaid::InvestmentsTransactionsGetRequestOptions.new(count: 100, offset: offset)
    )
    @client.investments_transactions_get(request)
  end

  sig { params(access_token: String, cursor: T.nilable(String)).returns(T.untyped) }
  def sync_transactions(access_token, cursor: nil)
    request = Plaid::TransactionsSyncRequest.new(
      access_token: access_token,
      cursor:       cursor
    )
    @client.transactions_sync(request)
  end
end
