# typed: strict

# Mixin for Sorbet enums backing string-valued columns and params.
# (T::Enum prohibits subclassing its children, so this is a module rather
# than a base class.) Instances JSON-encode and interpolate as their
# serialized value, so serializers, log lines, and cache payloads keep
# emitting the exact strings the database stores.
module ApplicationEnum
  extend T::Sig

  extend T::Helpers

  requires_ancestor { T::Enum }

  sig { returns(String) }
  def to_s
    # T.cast: requires_ancestor is not enforced without sorbet's
    # experimental flag, so serialize isn't statically visible here.
    T.cast(self, T::Enum).serialize.to_s
  end

  sig { params(_options: T.untyped).returns(String) }
  def as_json(_options = nil)
    to_s
  end
end
