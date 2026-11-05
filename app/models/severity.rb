# typed: strict

# Shared severity vocabulary for the activity feed, issues, and
# notifications. Historically Notification validated against "critical"
# where Issue/ActivityEntry used "error" — the union is accepted everywhere
# now, ordered so callers can rank or threshold entries.
class Severity < T::Enum
  extend T::Sig

  include ApplicationEnum

  enums do
    Info = new("info")
    Warning = new("warning")
    Error = new("error")
    Critical = new("critical")
  end

  # Declaration order is rank order. (No Comparable — the repo's rubocop
  # forbids it on T::Enum; compare ranks at call sites instead.)
  sig { returns(Integer) }
  def rank
    T.must(Severity.values.index(self))
  end

  sig { params(other: Severity).returns(T::Boolean) }
  def at_least?(other)
    rank >= other.rank
  end
end
