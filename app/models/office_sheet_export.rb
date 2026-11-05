# typed: true

# A Fin datatable linked to one spreadsheet in Office. Created by the
# first export, then reused: refreshing rewrites the same Office document
# rather than minting another one, so a sheet someone has formatted,
# charted, or linked from elsewhere keeps its identity.
class OfficeSheetExport < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  belongs_to :user, optional: true

  validates :dataset, presence: true, inclusion: { in: ->(_) { Office::Datasets.keys } }
  validates :title, presence: true
  validates :document_id, presence: true, uniqueness: { scope: :household_id }

  scope :for_dataset, ->(dataset) { where(dataset: dataset) }
  scope :recent_first, -> { order(Arel.sql("COALESCE(last_exported_at, created_at) DESC")) }

  sig { returns(Office::Datasets::Dataset) }
  def definition
    Office::Datasets.fetch(dataset)
  end

  # The filters the sheet was built from, as a plain symbol-keyed hash the
  # dataset's row builder can take (jsonb hands them back as strings).
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def filter_params
    (filters || {}).symbolize_keys
  end
end
