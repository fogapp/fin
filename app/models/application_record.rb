# typed: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # ActiveModel type that casts a string column to a T::Enum instance.
  # Unknown raw values pass through as strings so the paired inclusion
  # validation rejects them with the same error the old %w[] pattern gave,
  # instead of raising mid-assignment.
  # Inherits from Value rather than Type::String: tapioca's column-type
  # helper hard-maps any ActiveRecord::Type::String descendant to ::String,
  # which would make the generated RBIs lie about enum-typed readers.
  class EnumType < ActiveModel::Type::Value
    def initialize(enum_class)
      @enum_class = enum_class
      super()
    end

    def type
      :string
    end

    def cast(value)
      case value
      when nil, @enum_class then value
      when String, Symbol then @enum_class.try_deserialize(value.to_s) || value.to_s
      else value
      end
    end

    def serialize(value)
      value.is_a?(T::Enum) ? value.serialize : super
    end

    # Tapioca reads this when generating DSL RBIs, so enum-typed columns are
    # typed as their enum instead of String.
    def __tapioca_type
      @enum_class
    end
  end

  # Declares a string column as a typed enum: readers return enum instances,
  # writers accept enums or raw strings, queries serialize enums back to the
  # stored string, and validation rejects values outside the enum.
  #
  #   typed_enum :status, Status
  #   typed_enum :severity, Severity, allow_nil: true
  def self.typed_enum(name, enum_class, allow_nil: false)
    attribute(name, EnumType.new(enum_class))
    validates name, inclusion: { in: enum_class.values }, allow_nil: allow_nil
  end
end
