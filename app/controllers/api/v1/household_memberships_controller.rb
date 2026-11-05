# typed: true

module Api
  module V1
    class HouseholdMembershipsController < BaseController
      renders_with Api::Render::HouseholdMembership

      # destroy is deliberately not gated here: non-admins may still remove
      # their own membership (leave the household), so its check stays inline.
      before_action -> { require_household_admin!("Only admins can change roles.") }, only: :update

      # GET /api/v1/household_memberships
      # Lists members of the currently-active household. Any member can see
      # who else is in the household.
      def index
        render json: renderer.index
      end

      # PATCH /api/v1/household_memberships/:id
      # Change a member's role. Admin-only. Refuses to demote the last admin.
      def update
        membership = Current.household.household_memberships.find(params[:id])
        params.require(:role)
        new_role = T.must(enum_param(Role, :role))

        if membership.admin? && new_role != Role::Admin && only_admin?(membership)
          return render json: { error: "Cannot demote the last admin." }, status: :unprocessable_content
        end

        membership.update!(role: new_role)
        render json: renderer.serialize(membership.reload)
      end

      # DELETE /api/v1/household_memberships/:id
      # Removes a member. Admins can remove anyone; non-admins can only remove
      # themselves (leaving the household). The last admin cannot leave or be
      # removed — promote someone first.
      def destroy
        membership = Current.household.household_memberships.find(params[:id])

        unless current_admin? || membership.user_id == Current.user.id
          return render json: { error: "Only admins can remove other members." }, status: :forbidden
        end
        if membership.admin? && only_admin?(membership)
          return render json: { error: "Cannot remove the last admin." }, status: :unprocessable_content
        end

        membership.destroy!
        head :no_content
      end

      private

      def only_admin?(membership)
        Current.household.household_memberships
          .where(role: Role::Admin)
          .where.not(id: membership.id)
          .none?
      end
    end
  end
end
