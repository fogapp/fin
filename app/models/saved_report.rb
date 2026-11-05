# typed: true

# A named, reopenable chart-page view: which section, timeframe, scoping and
# mode toggles — the page-level counterpart of SavedView (which captures
# transaction-table filter state).
class SavedReport < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  validates :name, presence: true
  validates :config, presence: true

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def config_hash
    JSON.parse(config)
  rescue JSON::ParserError
    {}
  end
end
