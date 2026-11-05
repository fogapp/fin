# typed: true

# The parts of fog-client's sign-in kit Fin calls beyond the gem's own
# typed surface (fog_client_signin.rbi, copied from the gem on every sync
# and so never edited here): the passkey check wraps the kit's Flow, and the
# passkey link ceremony opens the sealed pending sign-in itself.
module FogClient
  module Signin
    class Identity
      sig { params(kwargs: T.untyped).void }
      def initialize(**kwargs); end

      sig { returns(T.nilable(String)) }
      def acr; end

      sig { returns(T::Array[String]) }
      def amr; end
    end

    class Flow
      sig { params(kwargs: T.untyped).returns(T.untyped) }
      def start(**kwargs); end

      sig { params(params: T.untyped, binding: T.nilable(String)).returns([ FogClient::Signin::Identity, String ]) }
      def finish(params, binding:); end
    end

    module State
      sig do
        params(config: FogClient::Signin::Config, sealed: String, purpose: String).returns(T::Hash[String, T.untyped])
      end
      def self.open(config, sealed, purpose: "state"); end
    end

    module Rails
      private

      sig { returns(T.nilable(FogClient::Signin::Flow)) }
      def signin_flow; end
    end
  end
end
