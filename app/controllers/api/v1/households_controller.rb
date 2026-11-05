# typed: true

module Api
  module V1
    class HouseholdsController < BaseController
      renders_with Api::Render::Household

      # destroy checks admin on the *target* household's membership (which
      # may not be the active one), so only update uses the generic gate.
      before_action -> { require_household_admin!("Only admins can update household settings.") }, only: :update

      # GET /api/v1/households
      # Lists every household the current user is a member of, with their role.
      # Used by the household switcher in the UI.
      def index
        render json: renderer.index
      end

      # POST /api/v1/households
      # Any authenticated user can spin up a new household; the creator becomes
      # the admin. Their existing memberships are untouched.
      def create
        name = params.require(:name).to_s.strip
        household = T.let(nil, T.nilable(Household))
        ActiveRecord::Base.transaction do
          household = Household.create!(name: name)
          Households::SeedDefaultWorkflows.call(household)
          HouseholdMembership.create!(user: Current.user, household: household, role: Role::Admin)
        end
        render json: renderer.serialize(household, role: Role::Admin), status: :created
      end

      # PATCH /api/v1/households/:id
      # Rename / settings — admin-only, scoped to the active household
      # identified by the token. Updating a different household requires
      # switching first.
      def update
        return render json: { error: "Not found" }, status: :not_found unless params[:id] == Current.household.id

        updates = {}
        updates[:name] = params.require(:name).to_s.strip if params[:name].present?
        if params[:workflow_log_level].present?
          updates[:workflow_log_level] = enum_param(Workflows::LogLevel, :workflow_log_level)
        end
        unless params[:include_unvested_equity].nil?
          updates[:include_unvested_equity] = ActiveModel::Type::Boolean.new.cast(params[:include_unvested_equity])
        end
        if updates.any?
          Current.household.update!(updates)
          # Household isn't household-scoped, so it can't carry the bump
          # concern — but include_unvested_equity changes what net worth
          # (a cached endpoint) computes.
          Households::DataVersion.bump!(Current.household.id)
        end
        render json: renderer.serialize(Current.household, role: Role::Admin)
      end

      # DELETE /api/v1/households/:id
      # Permanently deletes a household and every row scoped to it. Admin-only.
      # Refuses if the caller would be left without any household — they need
      # somewhere to land. On success, mints a new (user, household) token for
      # one of the caller's remaining households and returns it so the
      # frontend can swap tokens without re-running passkey auth (the old
      # token was on the household just deleted, so it's gone via FK cascade).
      def destroy
        membership = Current.user.household_memberships.find_by(household_id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless membership
        return render json: { error: "Only admins can delete a household." }, status: :forbidden unless membership.admin?

        remaining = Current.user.household_memberships
          .where.not(household_id: params[:id]).includes(:household).order(:created_at)
        if remaining.none?
          return render json: {
            error: "You must belong to at least one other household before deleting this one. Create one first."
          }, status: :unprocessable_content
        end

        next_membership = remaining.first
        next_household  = next_membership.household
        response_body   = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))

        ActiveRecord::Base.transaction do
          # `delete_all` (vs destroy) bypasses model callbacks — including
          # Account's `dependent: :restrict_with_error` on transactions —
          # and lets the DB-level ON DELETE CASCADE on every household_id
          # FK clean up scoped rows in a single statement.
          Household.where(id: params[:id]).delete_all

          new_token = ::Auth::SessionToken.successor!(from: Current.api_token, user: Current.user, household: next_household)
          response_body = Api::Render::Session.new.serialize(
            user: Current.user, household: next_household, token: new_token, role: next_membership.role
          )
        end

        render json: response_body
      end
    end
  end
end
