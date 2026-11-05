# typed: true

# A registered Alchemy Address Activity webhook for one network. The inbound
# receiver looks rows up unscoped by external_id (no Current.household on a
# webhook request) and verifies the payload against signing_key.
class AlchemyWebhook < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  encrypts :signing_key

  class Status < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Active = new("active")
      Error  = new("error")
    end
  end

  typed_enum :status, Status

  validates :network, presence: true,
                      inclusion: { in: AlchemyWallet::SUPPORTED_NETWORKS },
                      uniqueness: { scope: :household_id }
  validates :external_id, presence: true, uniqueness: true
  validates :url, presence: true
end
