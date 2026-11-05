# typed: strict
# frozen_string_literal: true

# Whether Fin signs people in through an OpenID provider, and whether it
# does so exclusively (fog:docs/signin-proposal.md §15, §23.2).
#
# Fog-only is earned, not configured: Fin turns its own passkey sign-in
# and registration off only after proving it runs on fog — the fog that
# recognises Fin's own FOG_API_TOKEN signs, with the key that signs
# Fin's ID tokens, the issuer and client Fin is configured with. Once
# proven it stays on: a later failure to reach fog never re-opens local
# sign-in, or blocking fogd would be a way to switch it back. It ends only
# when the FOG_* variables are gone (Fin was taken off fog) — and
# bin/rails fin:recovery_link is always there for a broken fog.
#
# Fin's passkeys outlive fog-only in one place: proving an existing
# account is yours, once, to connect it to fog (SigninAdapter).
module FogSignin
  extend T::Sig

  # fog asks for a phishing-resistant sign-in (a passkey) for Fin
  # (fog.yaml signin.acr: phr); on a provably-fog Fin, the ID token must
  # say it got one (OidcController).
  ACR_PASSKEY = "urn:fog:acr:phr"

  sig { returns(T::Boolean) }
  def self.enabled? = FogClient::Signin.enabled?

  sig { returns(T::Boolean) }
  def self.fog_only?
    enabled? && ENV["FOG_API_URL"].present? && InstanceSetting.current.fog_attested_at.present?
  end

  # Prove it now if it has not been proven yet. Cheap once proven; called
  # where the console asks how to sign in.
  sig { void }
  def self.attest_if_needed
    return if !enabled? || ENV["FOG_API_URL"].blank?

    setting = InstanceSetting.current
    return if setting.fog_attested_at.present?

    config = FogClient::Signin.config
    return if config.nil?
    return unless FogClient::Signin::Proof.check(FogClient::Signin::Rails.provider_for(config))

    setting.update!(fog_attested_at: Time.current)
  end
end
