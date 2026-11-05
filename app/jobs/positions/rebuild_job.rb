# typed: true

module Positions
  class RebuildJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { params(account_id: String, security_id: String).void }
    def perform(account_id, security_id)
      security = Security.find_by(id: security_id)
      return unless security

      with_record(Account, account_id) do |account|
        Positions::Rebuild.call(account: account, security: security)
      end
    end
  end
end
