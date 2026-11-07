# typed: strong

# Hand-authored shim for the vendored `glass` agent (vendor/gems/glass,
# synced from glass:clients/ruby).
#
# vendor/ is ignored by sorbet/config and the gem is a path gem, so neither
# Sorbet nor `tapioca gem` sees it. Only the public API Fin calls is
# declared (Activity, HttpJson, the backup milestones); add a sig here when a
# caller starts using more of it. Every method is a no-op without GLASS_URL
# and GLASS_API_KEY and never raises into the caller.
module Glass
  class << self
    sig { params(name: String, by: Numeric, tags: T::Hash[Symbol, String]).void }
    def increment(name, by = 1, tags: {}); end

    sig { params(title: String, tags: T::Hash[Symbol, String], kind: String).void }
    def event(title, tags: {}, kind: "event"); end
  end
end
