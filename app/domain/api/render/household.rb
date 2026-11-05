# typed: strict

module Api
  module Render
    class Household < Api::Render::Base
      extend T::Sig

      # Every household the current user belongs to, with their role — the
      # household switcher's data source.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        memberships = Current.user.household_memberships.includes(:household).order(:created_at)
        memberships.map { |m| serialize_membership(m) }
      end

      sig { params(membership: ::HouseholdMembership).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_membership(membership)
        serialize(membership.household, role: membership.role)
      end

      sig { params(household: ::Household, role: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(household, role:)
        {
          id:     household.id,
          name:   household.name,
          role:   role,
          # "active" is relative to the token's household, not a column —
          # the switcher highlights the one the caller is currently in.
          active: household.id == Current.household&.id,
          workflow_log_level: household.workflow_log_level,
          include_unvested_equity: household.include_unvested_equity
        }
      end
    end
  end
end
