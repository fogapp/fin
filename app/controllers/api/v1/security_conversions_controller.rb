# typed: true

module Api
  module V1
    # Conversions the ledger never recorded (SMNEY -> SMERY). Detection
    # suggests them via Settings -> Issues; confirming makes valuation treat
    # the two instruments as one holding changing lines on effective_date.
    class SecurityConversionsController < BaseController
      def index
        render json: renderer.index
      end

      # A manual conversion is the user's own statement, so it starts
      # confirmed.
      def create
        conversion = SecurityConversion.create!(
          from_security_id: params.require(:from_security_id),
          to_security_id:   params.require(:to_security_id),
          effective_date:   Date.iso8601(params.require(:effective_date).to_s),
          ratio:            params.require(:ratio),
          status:           SecurityConversion::Status::Confirmed,
          source:           SecurityConversion::Source::Manual,
          confirmed_at:     Time.current
        )
        conversion.refresh_portfolio_metric
        render json: renderer.serialize(conversion), status: :created
      end

      def confirm
        conversion = SecurityConversion.find(params[:id])
        conversion.confirm!
        render json: renderer.serialize(conversion)
      end

      def dismiss
        conversion = SecurityConversion.find(params[:id])
        conversion.dismiss!
        render json: renderer.serialize(conversion)
      end

      # Deleting a confirmed conversion changes history back, so the stored
      # metric is recomputed; deleting a suggestion lets detection propose it
      # again (dismiss is the permanent "no").
      def destroy
        conversion = SecurityConversion.find(params[:id])
        was_confirmed = conversion.status == SecurityConversion::Status::Confirmed
        conversion.destroy!
        conversion.refresh_portfolio_metric if was_confirmed
        head :no_content
      end

      private

      def renderer
        @renderer ||= Api::Render::SecurityConversion.new(params: params)
      end
    end
  end
end
