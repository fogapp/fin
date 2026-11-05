# typed: true

# A rejected transfer-candidate pair. Detection consults these so a
# dismissed suggestion never comes back; manually linking the same pair
# deletes the record (an explicit link outranks a past dismissal).
class TransferDismissal < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  validates :from_transaction_type, :to_transaction_type,
            inclusion: { in: Transfer::TRANSACTION_TYPES }
  validates :from_transaction_id, :to_transaction_id, presence: true

  # Orientation-insensitive lookup — detection normalizes from=outflow, but
  # manual links can arrive either way around.
  scope :for_pair, ->(id_a, id_b) {
    where(from_transaction_id: [ id_a, id_b ], to_transaction_id: [ id_a, id_b ])
  }

  sig { params(transfer: Transfer).returns(TransferDismissal) }
  def self.record_for!(transfer)
    create!(
      from_transaction_type: transfer.from_transaction_type,
      from_transaction_id:   transfer.from_transaction_id,
      to_transaction_type:   transfer.to_transaction_type,
      to_transaction_id:     transfer.to_transaction_id
    )
  end
end
