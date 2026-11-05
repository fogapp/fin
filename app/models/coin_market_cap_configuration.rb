# typed: true

class CoinMarketCapConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  encrypts :api_key
  configured_when :api_key
end
