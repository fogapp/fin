# typed: true

class CsvImport < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  has_one_attached :file
  belongs_to :target_account, class_name: "Account", optional: true

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  enum :kind,   { transactions: 0, holdings: 1, unknown: 2, credit_card: 3, checking: 4, spreadsheet: 5 }

  validates :source_filename, presence: true

  scope :recent, -> { order(created_at: :desc) }

  sig { returns(T.nilable(Float)) }
  def duration_seconds
    return nil unless started_at && finished_at
    (T.must(finished_at) - started_at).round(2)
  end
end
