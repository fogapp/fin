# typed: strict
# frozen_string_literal: true

module Auth
  # Sign in with fog — or with any OpenID provider OIDC_ISSUER names
  # (fog:docs/signin-proposal.md §15). The flow is the shared
  # FogClient::Signin::Rails; Fin supplies what an identity means for its
  # accounts (SigninAdapter). Outside the bearer-token stack: these are the
  # doors to it.
  class OidcController < ActionController::API
    extend T::Sig

    include FogClient::Signin::Rails

    # Fin holds the household's money, so fog signs people in to it only
    # with a passkey (fog.yaml signin.acr: phr). fog enforces that; once
    # Fin has proven its provider is fog it checks the ID token says so as
    # well, and refuses one that does not.
    class PasskeyRequired
      extend T::Sig

      sig { params(flow: FogClient::Signin::Flow).void }
      def initialize(flow)
        @flow = flow
      end

      sig { params(kwargs: T.untyped).returns(T.untyped) }
      def start(**kwargs) = @flow.start(**kwargs, acr: FogSignin::ACR_PASSKEY)

      sig { params(params: T.untyped, binding: T.nilable(String)).returns([ FogClient::Signin::Identity, String ]) }
      def finish(params, binding:)
        identity, return_to = @flow.finish(params, binding: binding)
        raise FogClient::Signin::Denied, "passkey_required" unless identity.acr == FogSignin::ACR_PASSKEY

        [ identity, return_to ]
      end
    end

    private

    sig { returns(SigninAdapter) }
    def signin_adapter = SigninAdapter.new

    sig { returns(T.untyped) }
    def signin_flow
      flow = super
      flow && FogSignin.fog_only? ? PasskeyRequired.new(flow) : flow
    end
  end
end
