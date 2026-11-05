# typed: strict

module Api
  module Render
    # The { token, user, household } envelope every endpoint that mints a
    # session token returns — passkey login/registration, household switch,
    # and household delete (which lands the caller in another household) —
    # plus GET /me, which shares the user and household blocks. One shape, so
    # the frontend's auth store can't be handed a variant.
    class Session < Api::Render::Base
      extend T::Sig

      sig do
        params(user: ::User, household: ::Household, token: T.untyped, role: T.nilable(::Role))
          .returns(T::Hash[Symbol, T.untyped])
      end
      def serialize(user:, household:, token:, role:)
        {
          token:     token.raw_token,
          user:      user_payload(user),
          household: household_payload(household, role: role)
        }
      end

      # GET /me: no token, and the household block carries the settings the
      # app shell reads on boot.
      sig { params(user: ::User, household: ::Household, role: T.nilable(::Role)).returns(T::Hash[Symbol, T.untyped]) }
      def me(user:, household:, role:)
        {
          user:      user_payload(user),
          household: household_payload(household, role: role).merge(
            workflow_log_level:      household.workflow_log_level,
            include_unvested_equity: household.include_unvested_equity
          )
        }
      end

      private

      sig { params(user: ::User).returns(T::Hash[Symbol, T.untyped]) }
      def user_payload(user)
        { id: user.id, email: user.email, name: user.name }
      end

      sig { params(household: ::Household, role: T.nilable(::Role)).returns(T::Hash[Symbol, T.untyped]) }
      def household_payload(household, role:)
        { id: household.id, name: household.name, role: role }
      end
    end
  end
end
