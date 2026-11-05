# typed: true

module Api
  module V1
    class InvitesController < BaseController
      renders_with Api::Render::Invite

      # Public — no auth required so the register page can display the
      # inviting household name before the user creates an account.
      skip_before_action :authenticate_with_token!, only: :show

      # Every authenticated action is admin-only; each keeps its own wording.
      ADMIN_MESSAGES = {
        "index"   => "Only admins can view invites.",
        "create"  => "Only admins can create invites.",
        "destroy" => "Only admins can revoke invites."
      }.freeze
      before_action -> { require_household_admin!(ADMIN_MESSAGES.fetch(action_name)) },
                    only: [ :index, :create, :destroy ]

      # GET /api/v1/invites
      # Lists usable (unused + unexpired) invites for the current household.
      # Admin-only.
      def index
        render json: renderer.index
      end

      # GET /api/v1/invites/:code
      def show
        invite = InviteCode.find_by(code: params[:code])
        return render json: { error: "Invite not found" }, status: :not_found if invite.nil?
        return render json: { error: "Invite already used" }, status: :gone     if invite.used?
        return render json: { error: "Invite expired" }, status: :gone          if invite.expired?

        render json: renderer.show(invite)
      end

      # POST /api/v1/invites
      # Body: { role: "member" | "admin", expires_in_days: 7 }
      # Creates an invite into the current household (caller must be admin).
      def create
        invite = InviteCode.create!(
          household:   Current.household,
          created_by:  Current.user,
          role:        enum_param(Role, :role, default: Role::Member),
          expires_at:  params[:expires_in_days].to_i.positive? ? params[:expires_in_days].to_i.days.from_now : 7.days.from_now,
        )

        render json: renderer.serialize(invite, include_accept_url: true, base_url: request.base_url), status: :created
      end

      # DELETE /api/v1/invites/:code
      # Revoke an unused invite. Admin-only. Used invites are not deleted —
      # they remain as an audit trail of who joined when.
      def destroy
        invite = Current.household.invite_codes.find_by(code: params[:code])
        return render json: { error: "Invite not found" }, status: :not_found if invite.nil?
        return render json: { error: "Used invites cannot be revoked." }, status: :unprocessable_content if invite.used?

        invite.destroy!
        head :no_content
      end
    end
  end
end
