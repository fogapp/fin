# typed: true

class CoinbaseConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  encrypts :api_key_id, :api_key_secret
  configured_when :api_key_id, :api_key_secret
end
