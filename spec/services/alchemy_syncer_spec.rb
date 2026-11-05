require "rails_helper"

RSpec.describe AlchemySyncer do
  let(:client) { instance_double(AlchemyClient) }
  let!(:wallet) { create(:alchemy_wallet, address: "0xabc0000000000000000000000000000000006354") }

  before do
    create(:alchemy_configuration)
    allow(AlchemyClient).to receive(:new).and_return(client)
  end

  def token_entry(network:, token_address:, balance:, symbol: nil, name: nil, decimals: nil, price: nil, error: nil)
    {
      "network"       => network,
      "tokenAddress"  => token_address,
      "tokenBalance"  => balance,
      "tokenMetadata" => { "symbol" => symbol, "name" => name, "decimals" => decimals },
      "tokenPrices"   => price ? [ { "currency" => "usd", "value" => price } ] : [],
      "error"         => error
    }
  end

  # 4 ETH on mainnet (hex wei), 0.5 ETH on Base, 56 USDC on Base.
  def default_tokens
    [
      token_entry(network: "eth-mainnet", token_address: nil,
                  balance: "0x#{(4 * 10**18).to_s(16)}", price: "1800.0"),
      token_entry(network: "base-mainnet", token_address: nil,
                  balance: "0x#{(5 * 10**17).to_s(16)}", price: "1800.0"),
      token_entry(network: "base-mainnet", token_address: "0xusdc", balance: "0x#{(56 * 10**6).to_s(16)}",
                  symbol: "USDC", name: "USD Coin", decimals: 6, price: "1.0")
    ]
  end

  it "aggregates native balances across networks into one position" do
    allow(client).to receive(:tokens_by_address)
      .with(wallet.address, networks: wallet.networks)
      .and_return(default_tokens)

    result = described_class.new.call
    expect(result.wallets).to eq(1)
    expect(result.errors).to be_empty

    account = wallet.reload.account
    eth = PositionSnapshot.find_by!(account_id: account.id, security: Security.find_by!(ticker: "ETH"))
    expect(eth.quantity.to_f).to eq(4.5)
    expect(eth.price.to_f).to eq(1800.0)
    expect(eth.market_value.to_f).to eq(8100.0)
    expect(eth.cost_basis).to be_nil

    usdc = PositionSnapshot.find_by!(account_id: account.id, security: Security.find_by!(ticker: "USDC"))
    expect(usdc.quantity.to_f).to eq(56.0)
    expect(usdc.market_value.to_f).to eq(56.0)
  end

  it "derives the account balance from total holdings and records a snapshot" do
    allow(client).to receive(:tokens_by_address).and_return(default_tokens)

    described_class.new.call

    account = wallet.reload.account
    expect(account.balance.to_f).to eq(8156.0)
    expect(account.balance_usd.to_f).to eq(8156.0)
    expect(account.account_type).to eq("Crypto")
    snap = AccountBalanceSnapshot.find_by!(account_id: account.id)
    expect(snap.balance.to_f).to eq(8156.0)
    expect(snap.source).to eq(AccountBalanceSnapshot::Source::AlchemySync)
    expect(wallet.last_synced_at).to be_present
    expect(wallet.last_error).to be_nil
  end

  it "skips unpriced tokens (airdrop spam) and tallies them" do
    spam = token_entry(network: "eth-mainnet", token_address: "0xspam",
                       balance: "0x#{(888_888 * 10**18).to_s(16)}",
                       symbol: "FREE-MONEY", name: "Claim at scam.site", decimals: 18, price: nil)
    allow(client).to receive(:tokens_by_address).and_return(default_tokens + [ spam ])

    result = described_class.new.call

    expect(result.skipped).to eq("FREE-MONEY" => 1)
    expect(Security.find_by(ticker: "FREE-MONEY")).to be_nil
    expect(PositionSnapshot.joins(:security).where(securities: { ticker: "FREE-MONEY" })).to be_empty
    warning = ActivityEntry.find_by(event: "sync.tokens_skipped")
    expect(warning).to be_present
    expect(warning.severity).to eq(Severity::Warning)
  end

  it "skips zero balances and errored entries" do
    tokens = [
      token_entry(network: "eth-mainnet", token_address: nil, balance: "0x0", price: "1800.0"),
      token_entry(network: "base-mainnet", token_address: "0xbad", balance: nil,
                  symbol: "BAD", decimals: 18, price: "1.0", error: "unsupported")
    ]
    allow(client).to receive(:tokens_by_address).and_return(tokens)

    result = described_class.new.call
    expect(result.positions).to eq(0)
    expect(result.skipped).to be_empty
  end

  it "records the error on the wallet and continues when a wallet fails" do
    other = create(:alchemy_wallet)
    allow(client).to receive(:tokens_by_address)
      .with(wallet.address, networks: wallet.networks)
      .and_raise(AlchemyClient::Error, "rate limited")
    allow(client).to receive(:tokens_by_address)
      .with(other.address, networks: other.networks)
      .and_return(default_tokens)

    result = described_class.new.call

    expect(result.errors.size).to eq(1)
    expect(wallet.reload.last_error).to eq("rate limited")
    expect(other.reload.last_synced_at).to be_present
  end

  it "skips inactive wallets" do
    wallet.update!(active: false)
    expect(client).not_to receive(:tokens_by_address)

    result = described_class.new.call
    expect(result.wallets).to eq(0)
  end

  it "records priced ERC-20 contracts per network as the transfer allowlist" do
    tokens = default_tokens + [
      token_entry(network: "base-mainnet", token_address: "0xSPAM", balance: "0x64",
                  symbol: "USDC", name: "Fake USDC", decimals: 6, price: nil)
    ]
    allow(client).to receive(:tokens_by_address).and_return(tokens)

    described_class.new.call

    contracts = wallet.reload.known_token_contracts
    expect(contracts["base-mainnet"]).to eq([ "0xusdc" ])   # priced → allowlisted, downcased
    expect(contracts["base-mainnet"]).not_to include("0xspam") # unpriced spam stays out
    expect(contracts["eth-mainnet"]).to be_nil               # no ERC-20 seen there
  end

  it "updates the same snapshot row on resync rather than duplicating" do
    allow(client).to receive(:tokens_by_address).and_return(default_tokens)
    described_class.new.call
    expect {
      described_class.new.call
    }.not_to change(PositionSnapshot, :count)
  end

  it "zero-stamps snapshots for tokens the wallet no longer holds" do
    allow(client).to receive(:tokens_by_address).and_return(default_tokens)
    account = wallet.ensure_account!
    gone = create(:security, ticker: "GONE", security_type: "Crypto")
    stale = create(:position_snapshot, account: account, security: gone,
                   source_row_hash: "alchemy_wallet:#{wallet.id}:#{gone.id}",
                   quantity: 3, market_value: 300.0, as_of_date: Date.current - 1)

    described_class.new.call

    stale.reload
    expect(stale.quantity).to eq(0)
    expect(stale.market_value).to eq(0)
    expect(stale.as_of_date).to eq(Date.current)
    # Still-held tokens keep their quantities.
    eth = PositionSnapshot.find_by!(source_row_hash: "alchemy_wallet:#{wallet.id}:#{Security.find_by!(ticker: 'ETH').id}")
    expect(eth.quantity).to eq(4.5)
  end

  describe "when one token in a wallet fails to sync" do
    # Resolving USDC blows up; the two native ETH entries are fine.
    before do
      allow(client).to receive(:tokens_by_address).and_return(default_tokens)
      allow(Instruments::Resolver).to receive(:resolve!).and_wrap_original do |orig, **kwargs|
        raise ActiveRecord::RecordInvalid, Security.new if kwargs[:ticker] == "USDC"

        orig.call(**kwargs)
      end
    end

    it "still writes the positions that did resolve" do
      described_class.new.call

      eth = Security.find_by!(ticker: "ETH")
      expect(PositionSnapshot.find_by(source_row_hash: "alchemy_wallet:#{wallet.id}:#{eth.id}")).to be_present
    end

    it "reports the failure on the wallet and in the result" do
      result = described_class.new.call

      expect(result.errors.map { |e| e[:token] }).to include("USDC")
      expect(wallet.reload.last_error).to include("USDC")
    end

    # A partial read must not be mistaken for "the wallet sold everything
    # else" — zero-stamping on incomplete data erases live positions.
    it "does not zero-stamp other holdings from the partial picture" do
      account = wallet.ensure_account!
      gone = create(:security, ticker: "GONE", security_type: "Crypto")
      stale = create(:position_snapshot, account: account, security: gone,
                     source_row_hash: "alchemy_wallet:#{wallet.id}:#{gone.id}",
                     quantity: 3, market_value: 300.0, as_of_date: Date.current - 1)

      described_class.new.call

      expect(stale.reload.quantity).to eq(3)
    end

    # `total` is short by the failed token, so writing it would understate
    # net worth. Leaving the old balance reads as stale, which is honest.
    it "does not write an understated account balance" do
      account = wallet.ensure_account!
      account.update_columns(balance: 9_999.0, balance_usd: 9_999.0)

      described_class.new.call

      expect(account.reload.balance_usd).to eq(9_999.0)
    end
  end

  it "truncates the persisted error breadcrumb when a wallet fails" do
    allow(client).to receive(:tokens_by_address).and_raise(AlchemyClient::Error, "x" * 400)

    described_class.new.call

    expect(wallet.reload.last_error.length).to be <= 255
  end
end
