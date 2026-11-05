# typed: true

module Api
  module V1
    class StatsController < BaseController
      renders_with Api::Render::Stat

      def index
        render_cached("stats") { renderer.index }
      end

      def show
        # Registry lookup is a hash read — cheap enough to gate the 404 before
        # touching the cache, so an unknown key never caches a null payload.
        return render json: { error: "Unknown stat" }, status: :not_found if Metrics::Registry.find(params[:key].to_s).nil?

        render_cached("stat:#{params[:key]}", params: %i[from to]) { renderer.show }
      end
    end
  end
end
