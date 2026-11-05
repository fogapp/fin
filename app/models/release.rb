# typed: true

# A deployed build of Fin, keyed by its git SHA. Instance-wide rather than
# household-scoped: one row per release, recorded the first time a worker
# boots on it (see AnnounceReleaseJob).
class Release < ApplicationRecord
  validates :git_sha, presence: true
end
