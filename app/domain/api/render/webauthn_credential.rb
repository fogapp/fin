# typed: strict

module Api
  module Render
    class WebauthnCredential < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        Current.user.webauthn_credentials.order(created_at: :asc).map { |c| serialize(c) }
      end

      sig { params(cred: ::WebauthnCredential).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(cred)
        {
          id:          cred.id,
          nickname:    cred.nickname,
          created_at:  cred.created_at,
          last_used_at: cred.last_used_at
        }
      end
    end
  end
end
