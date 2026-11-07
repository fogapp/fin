# typed: strict

module Api
  module Render
    class Base
      extend T::Sig

      sig { returns(T.untyped) }
      attr_reader :params

      sig { params(params: T.untyped).void }
      def initialize(params: {})
        @params = params
      end

      # ISO date param or nil; malformed input raises Date::Error, which the
      # base controller maps to a 400.
      sig { params(key: T.any(Symbol, String)).returns(T.nilable(Date)) }
      def date_param(key)
        value = params[key]
        value.present? ? Date.iso8601(value.to_s) : nil
      end

      private

      # Percent change from previous to current, or nil when there is no
      # meaningful denominator; absolute-value denominator so sign flips
      # read sanely.
      sig { params(current: T.untyped, previous: T.untyped).returns(T.nilable(Float)) }
      def pct_change(current, previous)
        return nil if previous.nil? || previous.to_f.zero?

        ((current.to_f - previous.to_f) / previous.to_f.abs * 100).round(2)
      end
    end
  end
end
