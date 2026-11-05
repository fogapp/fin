# typed: strict

module Api
  module Render
    class Invite < Api::Render::Base
      extend T::Sig

      # Usable (unused + unexpired) invites for the current household.
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        Current.household.invite_codes.usable.order(created_at: :desc).map { |i| serialize(i) }
      end

      # The public (pre-auth) shape the register page reads — deliberately
      # smaller than the admin listing: no created_at, never an accept_url.
      sig { params(invite: ::InviteCode).returns(T::Hash[Symbol, T.untyped]) }
      def show(invite)
        {
          code:      invite.code,
          role:      invite.role,
          expires_at: invite.expires_at,
          household: { id: invite.household_id, name: T.must(invite.household).name }
        }
      end

      # base_url comes from the controller's request — renderers only see
      # params, and the accept link must match the host the admin is on.
      sig { params(invite: ::InviteCode, include_accept_url: T::Boolean, base_url: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(invite, include_accept_url: false, base_url: nil)
        {
          code:       invite.code,
          role:       invite.role,
          expires_at: invite.expires_at,
          created_at: invite.created_at,
          household:  { id: invite.household_id, name: invite.household.name },
          **(include_accept_url ? { accept_url: "#{base_url}/register?invite=#{invite.code}" } : {})
        }
      end
    end
  end
end
