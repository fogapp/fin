# typed: true

# The unique registry of external identifiers pointing at a Security
# (instrument). (scheme, value) is globally unique: an identifier can name
# exactly one instrument. Crypto symbols and exchange tickers are distinct
# schemes, so "BTC" the coin and "BTC" the NYSE ETF can never collide.
class InstrumentIdentifier < ApplicationRecord
  # Identifier namespaces, strongest first in resolver precedence. Symbol
  # schemes (ticker, crypto_symbol) are class-scoped by the resolver.
  class Scheme < T::Enum
    include ApplicationEnum

    enums do
      Cusip = new("cusip")
      Isin = new("isin")
      Figi = new("figi")
      Ticker = new("ticker")
      CryptoSymbol = new("crypto_symbol")
      PlaidSecurityId = new("plaid_security_id")
      CoinbaseCode = new("coinbase_code")
      CmcSlug = new("cmc_slug")
      CoingeckoId = new("coingecko_id")
    end
  end

  belongs_to :security

  typed_enum :scheme, Scheme
  validates :value, presence: true, uniqueness: { scope: :scheme }
end
