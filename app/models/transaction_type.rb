# typed: true

class TransactionType < ApplicationRecord
  # The transaction_types.category values code branches on. The column is an
  # open reference vocabulary (brokers bring their own rows), not an owned
  # enum, so these are plain constants: naming the ones we depend on without
  # rejecting the ones we don't.
  module Category
    PURCHASE                  = "Purchase"
    SALE                      = "Sale"
    TRANSFER_IN               = "Transfer In"
    TRANSFER_OUT              = "Transfer Out"
    DIVIDEND                  = "Dividend"
    FOREIGN_DIVIDEND          = "Foreign Dividend"
    INTEREST                  = "Interest"
    MUNICIPAL_INTEREST        = "Municipal Interest"
    ACCRUED_INTEREST_PAID     = "Accrued Int Pd"
    ACCRUED_INTEREST_RECEIVED = "Accrued Int Rcv"
    FEES                      = "Fees"
    COMMISSIONS               = "Commissions"
  end

  has_many :investment_transactions, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true
end
