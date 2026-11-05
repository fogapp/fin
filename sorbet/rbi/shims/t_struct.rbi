# typed: true

# Shim to teach Sorbet that T::Struct has T::Sig extended at runtime
# (via config/initializers/sorbet.rb), so subclasses inherit `sig`
# without needing to declare `extend T::Sig` individually.
class T::Struct
  extend T::Sig
end
