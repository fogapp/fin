# typed: true
# frozen_string_literal: true

class CashTransactionTag < ApplicationRecord
  include BumpsHouseholdDataVersion

  belongs_to :cash_transaction
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :cash_transaction_id }

  # No household_id column — bump through the transaction. Without this,
  # add_tag/remove_tag never invalidate the tag-filtered /cashflow cache.
  bumps_data_version_via :cash_transaction
end
