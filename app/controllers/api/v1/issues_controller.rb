# typed: true

module Api
  module V1
    class IssuesController < BaseController
      renders_with Api::Render::Issue

      def index
        render json: renderer.index
      end

      # Bulk dismiss. Dismissed issues re-raise on the next audit only if
      # their condition is still true — clearing is honest, not permanent.
      def dismiss_all
        scope = Issue.active
        scope = scope.where(source: params[:source]) if params[:source].present?
        count = scope.update_all(dismissed_at: Time.current)
        render json: { dismissed: count }
      end

      def destroy
        issue = Issue.find(params[:id])
        issue.dismiss!
        render json: renderer.serialize(issue)
      end
    end
  end
end
