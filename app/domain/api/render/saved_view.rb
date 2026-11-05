# typed: strict

module Api
  module Render
    class SavedView < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::SavedView.order(:name).map { |v| serialize(v) }
      end

      sig { params(v: ::SavedView).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(v)
        # filter_params is a JSON blob written by the frontend; a corrupt row
        # degrades to defaults rather than breaking the whole listing.
        parsed = JSON.parse(v.filter_params) rescue {}
        {
          id:             v.id,
          name:           v.name,
          conditions:     parsed["conditions"] || [],
          match_all:      parsed["match_all"].nil? ? true : parsed["match_all"],
          group_by:       parsed["group_by"],
          primary_sort:   parsed["primary_sort"],
          secondary_sort: parsed["secondary_sort"],
          created_at:     v.created_at
        }
      end
    end
  end
end
