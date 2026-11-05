# typed: strict

module Api
  module Render
    class SecurityConversion < Api::Render::Base
      extend T::Sig

      # Newest first; optionally one status, or conversions touching one
      # security on either side (the security detail page).
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        scope = ::SecurityConversion.includes(:from_security, :to_security).order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        if params[:security_id].present?
          scope = scope.where(from_security_id: params[:security_id])
                       .or(scope.where(to_security_id: params[:security_id]))
        end
        scope.map { |c| serialize(c) }
      end

      sig { params(conversion: ::SecurityConversion).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(conversion)
        {
          id:             conversion.id,
          from_security:  security_ref(conversion.from_security),
          to_security:    security_ref(conversion.to_security),
          effective_date: conversion.effective_date,
          ratio:          conversion.ratio.to_f,
          status:         conversion.status.serialize,
          source:         conversion.source.serialize,
          evidence:       conversion.evidence,
          confirmed_at:   conversion.confirmed_at,
          created_at:     conversion.created_at
        }
      end

      private

      sig { params(security: T.nilable(::Security)).returns(T::Hash[Symbol, T.untyped]) }
      def security_ref(security)
        { id: security&.id, ticker: security&.ticker, name: security&.name }
      end
    end
  end
end
