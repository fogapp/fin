# typed: strong

# Hand-authored shim for the vendored `lucid` agent (vendor/gems/lucid,
# synced from lucid:clients/ruby).
#
# vendor/ is ignored by sorbet/config and the gem is a path gem, so neither
# Sorbet nor `tapioca gem` sees it. Only the public API Fin calls is
# declared (Activity, HttpJson, the backup milestones); add a sig here when a
# caller starts using more of it. Every method is a no-op without LUCID_URL
# and LUCID_API_KEY and never raises into the caller.
module Lucid
  class << self
    sig { params(name: String, by: Numeric, tags: T::Hash[Symbol, String]).void }
    def increment(name, by = 1, tags: {}); end

    sig { params(title: String, tags: T::Hash[Symbol, String], kind: String).void }
    def event(title, tags: {}, kind: "event"); end
  end
end
