# typed: strict

module Api
  module Render
    class HouseholdMembership < Api::Render::Base
      extend T::Sig

      # Members of the active household, ordered by email so the roster is
      # stable across loads.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        Current.household.household_memberships
          .includes(:user).order("users.email ASC")
          .map { |m| serialize(m) }
      end

      sig { params(membership: ::HouseholdMembership).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(membership)
        {
          id:         membership.id,
          role:       membership.role,
          created_at: membership.created_at,
          user: {
            id:    membership.user.id,
            email: membership.user.email,
            name:  membership.user.name
          }
        }
      end
    end
  end
end
