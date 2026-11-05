# typed: true

module Api
  module V1
    module Auth
      # Passkey (WebAuthn) authentication endpoints. These run without an
      # authenticated token — they're the path by which a user obtains one.
      #
      # Flow is two-phase (begin / finish) because WebAuthn ceremonies require
      # a fresh challenge from the server which the authenticator signs. We
      # avoid server-side session storage by signing the challenge into a
      # short-lived token and round-tripping it through the client.
      class PasskeysController < ActionController::API
        include WebauthnRelyingParty

        rescue_from ActiveRecord::RecordNotFound, with: -> { send(:render_error, "Not found", :not_found) }
        rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: -> { send(:render_error, "Challenge expired or invalid", :unauthorized) }
        rescue_from ::Auth::DeviceInvite::Rejected, with: ->(e) { send(:render_error, e.message, :forbidden) }

        # Once Fin has proven it runs on fog (FogSignin), fog signs people
        # in: Fin's own registration and passkey sign-in are closed,
        # whatever FIN_OPEN_REGISTRATION says. What stays is the link
        # ceremony, which signs no one in.
        FOG_ONLY_ACTIONS = %i[register_begin register_finish login_begin login_finish
          device_invite_begin device_invite_finish].freeze
        before_action :refuse_when_fog_only, only: FOG_ONLY_ACTIONS

        # POST /api/v1/auth/passkey/register/begin
        # Params: email, [name], [invite_code]
        # Returns: { options: <PublicKeyCredentialCreationOptions>, challenge_token }
        def register_begin
          email   = params.require(:email).to_s.downcase.strip
          invite  = params[:invite_code].present? ? InviteCode.find_by(code: params[:invite_code]) : nil
          return render_error("Invite code is invalid or already used", :unprocessable_content) if params[:invite_code].present? && !invite&.usable?

          user = User.find_by("LOWER(email) = ?", email)

          if user && user.passkey_enrolled?
            return render_error("That email already has a passkey — sign in instead.", :conflict)
          end

          if user.nil?
            unless open_registration? || invite
              return render_error("Registration is closed. Use an invite code.", :forbidden)
            end
            user = User.new(email: email, name: params[:name].to_s.presence)
          else
            # An existing user with no passkey must prove more than knowledge
            # of the email — otherwise anyone could enroll a credential and
            # take over the account. Require an invite code (the signed
            # device-invite link flow covers adding devices).
            unless invite
              return render_error("This account needs an invite code or device link to add its first passkey.", :forbidden)
            end
            user.name = params[:name].to_s.presence if params[:name].present? && user.name.blank?
          end

          # Validate without persisting — we only create the user after the
          # client successfully completes the ceremony in /finish.
          unless user.valid?
            return render_error(user.errors.full_messages.join(", "), :unprocessable_content)
          end

          options = creation_options_for(
            user, email: email,
            exclude: user.persisted? ? user.webauthn_credentials.pluck(:external_id) : []
          )

          render json: {
            options:         options.as_json,
            challenge_token: sign_challenge(
              intent:        "register",
              challenge:     options.challenge,
              email:         email,
              name:          user.name,
              invite_code:   invite&.code,
              existing_user: user.persisted?
            )
          }
        end

        # POST /api/v1/auth/passkey/register/finish
        # Params: credential (the attestation response), challenge_token, [nickname]
        # Returns: { token, user, household }
        def register_finish
          payload = read_challenge(intent: "register")

          webauthn_credential = WebAuthn::Credential.from_create(params.require(:credential), relying_party: webauthn_relying_party)
          webauthn_credential.verify(payload["challenge"])

          email = payload["email"]
          user  = User.find_or_initialize_by(email: email) { |u| u.name = payload["name"] }

          invite = payload["invite_code"].present? ? InviteCode.usable.find_by(code: payload["invite_code"]) : nil
          if payload["invite_code"].present? && invite.nil?
            return render_error("Invite code was used or expired between begin and finish.", :unprocessable_content)
          end

          # Re-enforce the begin-phase rule in case of a forged/stale token:
          # enrolling the first passkey on an existing account requires an invite.
          if user.persisted? && !user.passkey_enrolled? && invite.nil?
            return render_error("This account needs an invite code or device link to add its first passkey.", :forbidden)
          end

          household = T.let(nil, T.nilable(Household))
          token     = T.let(nil, T.nilable(ApiToken))
          ActiveRecord::Base.transaction do
            user.save! if user.new_record?

            household = resolve_registration_household(user: user, invite: invite)

            user.webauthn_credentials.create!(
              external_id: webauthn_credential.id,
              public_key:  webauthn_credential.public_key,
              sign_count:  webauthn_credential.sign_count,
              nickname:    params[:nickname].presence,
            )
            invite&.consume!(user)

            token = ::Auth::SessionToken.mint!(user: user, household: T.must(household))
          end

          render json: session_response(user: user, household: T.must(household), token: T.must(token)), status: :created
        rescue WebAuthn::Error => e
          render_error("Passkey verification failed: #{e.message}", :unprocessable_content)
        end

        # POST /api/v1/auth/passkey/login/begin
        # Params: [email] (optional — when omitted, browser shows conditional UI passkey picker)
        # Returns: { options: <PublicKeyCredentialRequestOptions>, challenge_token }
        def login_begin
          email = params[:email].to_s.downcase.strip.presence
          user  = email ? User.find_by("LOWER(email) = ?", email) : nil

          allowed = user ? user.webauthn_credentials.pluck(:external_id) : []
          options = WebAuthn::Credential.options_for_get(
            allow: allowed,
            user_verification: "preferred",
            relying_party: webauthn_relying_party
          )

          render json: {
            options:         options.as_json,
            challenge_token: sign_challenge(
              intent:    "login",
              challenge: options.challenge,
              email:     email
            )
          }
        end

        # POST /api/v1/auth/passkey/login/finish
        # Params: credential (the assertion response), challenge_token
        # Returns: { token, user, household }
        def login_finish
          payload = read_challenge(intent: "login")

          user = verify_assertion(payload)
          return render_error("Passkey not recognized", :unauthorized) if user.nil?

          household = resolve_login_household(user)

          return render_error("This user has no household memberships.", :forbidden) if household.nil?

          token = ::Auth::SessionToken.mint!(user: user, household: household)

          render json: session_response(user: user, household: household, token: token)
        rescue WebAuthn::Error => e
          render_error("Passkey verification failed: #{e.message}", :unauthorized)
        end

        # The link page (fog:docs/signin-proposal.md §15): fog signed someone
        # in whose fog identity no Fin account is connected to yet. They
        # prove an existing account is theirs by signing in to it with its
        # passkey; the answer is not a session but a short-lived proof, bound
        # to that one pending fog sign-in, which POST /auth/oidc/link takes as
        # its bearer (SigninAdapter#account_from_request). Open in fog-only
        # mode too: without it, nobody could bring their account across.
        #
        # POST /api/v1/auth/passkey/link/begin
        # Params: pending (the sealed fog sign-in from /auth/link), [email]
        # Returns: { options, challenge_token }
        def link_begin
          pending = params.require(:pending).to_s
          return render_error("This fog sign-in has expired. Sign in with fog again.", :unprocessable_content) unless SigninAdapter.pending_valid?(pending)

          email = params[:email].to_s.downcase.strip.presence
          user  = email ? User.find_by("LOWER(email) = ?", email) : nil
          options = WebAuthn::Credential.options_for_get(
            allow: user ? user.webauthn_credentials.pluck(:external_id) : [],
            user_verification: "preferred",
            relying_party: webauthn_relying_party
          )

          render json: {
            options:         options.as_json,
            challenge_token: sign_challenge(
              intent:    "link",
              challenge: options.challenge,
              pending:   SigninAdapter.pending_digest(pending)
            )
          }
        end

        # POST /api/v1/auth/passkey/link/finish
        # Params: credential, challenge_token, pending
        # Returns: { link_token }
        def link_finish
          payload = read_challenge(intent: "link")
          pending = params.require(:pending).to_s
          unless ActiveSupport::SecurityUtils.secure_compare(payload["pending"].to_s, SigninAdapter.pending_digest(pending)) &&
                 SigninAdapter.pending_valid?(pending)
            return render_error("This fog sign-in has expired. Sign in with fog again.", :unprocessable_content)
          end

          user = verify_assertion(payload)
          return render_error("Passkey not recognized", :unauthorized) if user.nil?

          render json: { link_token: SigninAdapter.issue_link_proof(user, pending) }
        rescue WebAuthn::Error => e
          render_error("Passkey verification failed: #{e.message}", :unauthorized)
        end

        # POST /api/v1/auth/passkey/device_invite/begin
        # Params: invite_token
        # Returns: { options, challenge_token }
        def device_invite_begin
          payload = read_device_invite_token
          user = User.find(payload["user_id"])

          options = creation_options_for(
            user, email: user.email,
            exclude: user.webauthn_credentials.pluck(:external_id)
          )

          render json: {
            options:         options.as_json,
            challenge_token: sign_challenge(
              intent:    "device_invite_finish",
              challenge: options.challenge,
              user_id:   user.id
            )
          }
        rescue ActiveRecord::RecordNotFound
          render_error("User not found", :not_found)
        end

        # POST /api/v1/auth/passkey/device_invite/finish
        # Params: credential, challenge_token, [nickname]
        # Returns: { token, user, household }
        def device_invite_finish
          payload = read_challenge(intent: "device_invite_finish")
          user = User.find(payload["user_id"])

          webauthn_credential = WebAuthn::Credential.from_create(params.require(:credential), relying_party: webauthn_relying_party)
          webauthn_credential.verify(payload["challenge"])

          cred = user.webauthn_credentials.create!(
            external_id: webauthn_credential.id,
            public_key:  webauthn_credential.public_key,
            sign_count:  webauthn_credential.sign_count,
            nickname:    params[:nickname].presence
          )

          household = resolve_login_household(user)
          return render_error("This user has no household memberships.", :forbidden) if household.nil?

          token = ::Auth::SessionToken.mint!(
            user: user, household: household,
            label: "Passkey session (#{cred.nickname.presence || 'new device'})",
          )

          render json: session_response(user: user, household: household, token: token), status: :created
        rescue ActiveRecord::RecordNotFound
          render_error("User not found", :not_found)
        rescue WebAuthn::Error => e
          render_error("Passkey verification failed: #{e.message}", :unprocessable_content)
        end

        private

        def refuse_when_fog_only
          render_error("Fin signs people in with fog.", :forbidden) if FogSignin.fog_only?
        end

        # Verifies a sign-in assertion against the stored credential and
        # returns its user, or nil for a passkey Fin does not know. A bad
        # signature raises WebAuthn::Error.
        def verify_assertion(payload)
          webauthn_credential = WebAuthn::Credential.from_get(params.require(:credential), relying_party: webauthn_relying_party)
          stored = WebauthnCredential.find_by(external_id: webauthn_credential.id)
          return nil if stored.nil?

          webauthn_credential.verify(
            payload["challenge"],
            public_key: stored.public_key,
            sign_count: stored.sign_count
          )

          stored.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
          stored.user
        end

        def open_registration?
          ActiveModel::Type::Boolean.new.cast(ENV.fetch("FIN_OPEN_REGISTRATION", "true"))
        end

        # webauthn_user_handle / sign_challenge / read_challenge live in
        # WebauthnRelyingParty.

        def resolve_registration_household(user:, invite:)
          if invite
            invite.household.tap do |h|
              HouseholdMembership.find_or_create_by!(user: user, household: h) { |m| m.role = invite.role }
            end
          elsif user.households.exists?
            user.households.first
          else
            display_name = user.name.presence || user.email
            household = Household.create!(name: "#{display_name}'s Household")
            Households::SeedDefaultWorkflows.call(household)
            HouseholdMembership.create!(user: user, household: household, role: Role::Admin)
            household
          end
        end

        # On login the user may have multiple households. For Phase 2 we use
        # the first one they joined; a household switcher comes in Phase 3.
        def resolve_login_household(user)
          user.household_memberships.order(:created_at).first&.household
        end

        def session_response(user:, household:, token:)
          Api::Render::Session.new.serialize(
            user: user, household: household, token: token,
            role: user.household_memberships.find_by(household_id: household.id)&.role
          )
        end

        # An invalid/expired signature raises InvalidSignature, handled by the
        # class-level rescue_from as a clean 401. (A previous local rescue
        # rendered and returned nil, and the action then crashed on
        # payload["user_id"] after the response was already committed.)
        # A link issued for another address, or one already used, raises
        # DeviceInvite::Rejected — a 403 carrying the reason.
        def read_device_invite_token
          ::Auth::DeviceInvite.verify!(params.require(:invite_token).to_s, request_host: request.host)
        end

        def render_error(message, status)
          render json: { error: message }, status: status
        end
      end
    end
  end
end
