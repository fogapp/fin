# typed: strict

module Api
  module Render
    class SavedReport < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::SavedReport.order(:name).map { |r| serialize(r) }
      end

      sig { params(r: ::SavedReport).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(r)
        { id: r.id, name: r.name, config: r.config_hash, created_at: r.created_at }
      end
    end
  end
end
