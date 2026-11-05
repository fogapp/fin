# typed: true

module Api
  module V1
    class WebauthnCredentialsController < BaseController
      renders_with Api::Render::WebauthnCredential

      # GET /api/v1/webauthn_credentials
      def index
        render json: renderer.index
      end

      # DELETE /api/v1/webauthn_credentials/:id
      def destroy
        cred = Current.user.webauthn_credentials.find(params[:id])
        if Current.user.webauthn_credentials.count <= 1
          render json: { error: "Cannot remove your only passkey" }, status: :unprocessable_content
          return
        end
        cred.destroy!
        head :no_content
      end

      # PATCH /api/v1/webauthn_credentials/:id
      #
      # Rename only — a passkey can't be un-named. Clearing the nickname is
      # rejected rather than stored as NULL, so "Unnamed device" stays a
      # property of passkeys registered without a name, not a state you can
      # fall back into. Register a new passkey if you want a fresh label.
      def update
        cred     = Current.user.webauthn_credentials.find(params[:id])
        nickname = params[:nickname].to_s.strip

        if nickname.blank?
          return render json: { error: "Nickname can't be blank", errors: [ "Nickname can't be blank" ] },
                        status: :unprocessable_content
        end

        cred.update!(nickname: nickname)
        render json: renderer.serialize(cred)
      end
    end
  end
end
