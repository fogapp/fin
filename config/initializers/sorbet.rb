# typed: false

# T::Struct subclasses cannot themselves be subclassed, so we cannot create
# an ApplicationStruct base class. Instead, extend T::Sig directly onto
# T::Struct so that all subclasses inherit `sig` as a class method without
# needing to declare `extend T::Sig` individually.
T::Struct.extend(T::Sig)
