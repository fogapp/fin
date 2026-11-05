# typed: true

class SecurityNewsArticle < ApplicationRecord
  belongs_to :security

  scope :recent, -> { order(published_at: :desc) }
end
