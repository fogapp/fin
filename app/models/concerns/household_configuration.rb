# typed: true

# Shared shape of the per-household provider credential rows (Plaid,
# Coinbase, Alchemy, Alpha Vantage, …): one row per household, looked up
# with `.current` and asked `configured?` before a client is built.
#
#   class TiingoConfiguration < ApplicationRecord
#     include HouseholdScoped
#     include HouseholdConfiguration
#     configured_when :api_key
#   end
#
# Includers that resolve credentials some other way (OfficeConfiguration
# falls back to ENV) define their own `configured?` instead.
module HouseholdConfiguration
  extend T::Sig

  extend T::Helpers

  module ClassMethods
    extend T::Sig

    extend T::Generic

    has_attached_class!(:out)

    # The current household's row (HouseholdScoped's default_scope filters
    # by Current.household), built but unsaved when the household has none.
    # Callers outside a request/job household context must scope explicitly
    # (household.<provider>_configurations) or use the provider module's
    # credential lookup, which also covers ENV.
    sig { returns(T.attached_class) }
    def current
      Current.household!
      T.unsafe(self).first_or_initialize(**configuration_defaults)
    end

    # Attributes a newly built row starts with.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def configuration_defaults
      {}
    end

    # The credential attributes that must all be present for `configured?`.
    sig { params(attributes: Symbol).void }
    def configured_when(*attributes)
      @configured_attributes = T.let(attributes.freeze, T.nilable(T::Array[Symbol]))
    end

    sig { returns(T::Array[Symbol]) }
    def configured_attributes
      @configured_attributes || Kernel.raise("#{T.unsafe(self).name} must declare configured_when or define configured?")
    end
  end

  mixes_in_class_methods(ClassMethods)

  sig { returns(T::Boolean) }
  def configured?
    T.unsafe(self).class.configured_attributes.all? { |attribute| T.unsafe(self).public_send(attribute).present? }
  end
end
