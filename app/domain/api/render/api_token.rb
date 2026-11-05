# typed: strict

module Api
  module Render
    class ApiToken < Api::Render::Base
      extend T::Sig

      # This user's non-session tokens in this household only — scoping by
      # both keys is what keeps one member from seeing another's tokens.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        Current.user.api_tokens.where(
          household_id: Current.household.id, session: false
        ).order(created_at: :desc).map { |t| serialize(t) }
      end

      # include_token: the raw secret is shown exactly once, on create.
      sig { params(t: ::ApiToken, include_token: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(t, include_token: false)
        h = {
          id:           t.id,
          name:         t.name,
          scope:        t.scope,
          last_used_at: t.last_used_at,
          expires_at:   t.expires_at,
          created_at:   t.created_at
        }
        h[:token] = t.raw_token if include_token
        h
      end
    end
  end
end
