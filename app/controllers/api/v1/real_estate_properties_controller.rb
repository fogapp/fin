# typed: true

module Api
  module V1
    class RealEstatePropertiesController < BaseController
      renders_with Api::Render::RealEstateProperty

      def index
        render json: renderer.index
      end

      def show
        render json: renderer.show
      end

      # Creating a property resolves its address against RentCast inline
      # (rather than offering a separate preview endpoint, which would
      # double the quota cost of adding one) so the first render already has
      # a value, the facts, and the seeded assessment/sale history.
      #
      # A lookup failure never fails the create — the property falls back to
      # manual valuation with the reason recorded.
      def create
        property = ::RealEstateProperty.new(property_params)
        property.save!
        seed_from_rentcast(property)
        record_manual_value(property)

        render json: renderer.serialize(property.reload), status: :created
      end

      def update
        property = ::RealEstateProperty.find(params[:id])
        property.update!(property_params)
        record_manual_value(property)

        render json: renderer.serialize(property.reload)
      end

      def destroy
        ::RealEstateProperty.find(params[:id]).destroy!
        head :no_content
      end

      # POST /real_estate_properties/:id/refresh — spends quota immediately
      # rather than enqueueing, so the response can report what happened.
      def refresh
        property = ::RealEstateProperty.find(params[:id])
        return render json: { error: "RentCast is not configured" }, status: :unprocessable_content unless
          RentcastConfiguration.current.configured?

        RealEstate::PropertyRefresher.new(property, force_facts: params[:force_facts].present?).call
        render json: renderer.serialize(property.reload)
      rescue RentcastConfiguration::QuotaExceeded, ::Rentcast::Client::Error => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # POST /real_estate_properties/:id/valuations — a value you type in.
      # Newest as_of wins, with manual beating an automatic estimate written
      # the same day.
      def create_valuation
        property = ::RealEstateProperty.find(params[:id])
        valuation = property.record_valuation!(
          source: ::RealEstateValuation::Source::Manual,
          as_of:  valuation_date,
          amount: params.require(:amount)
        )

        render json: renderer.serialize_valuation(valuation), status: :created
      end

      def destroy_valuation
        property = ::RealEstateProperty.find(params[:id])
        property.valuations.find(params[:valuation_id]).destroy!
        head :no_content
      end

      private

      def property_params
        params.permit(
          :name, :address_line1, :address_line2, :city, :state, :zip_code,
          :purchase_date, :purchase_price, :status, :sold_date, :sold_price,
          :sync_enabled, :notes
        )
      end

      def valuation_date
        params[:as_of].present? ? Date.iso8601(params[:as_of].to_s) : Date.current
      end

      def seed_from_rentcast(property)
        return unless property.sync_enabled? && RentcastConfiguration.current.configured?

        RealEstate::PropertyRefresher.new(property, force_facts: true).call
      rescue RentcastConfiguration::QuotaExceeded, ::Rentcast::Client::Error, ArgumentError => e
        # The property exists and is usable manually; surface the reason on
        # the record instead of rejecting the request.
        Rails.logger.warn("[RealEstateProperties#create] RentCast seed failed: #{e.class}: #{e.message}")
        property.update(last_sync_error: e.message)
      end

      # A value supplied alongside the property itself (the manual path, and
      # the fallback when RentCast can't price an address).
      def record_manual_value(property)
        return if params[:value].blank?

        property.record_valuation!(
          source: ::RealEstateValuation::Source::Manual,
          as_of:  valuation_date,
          amount: params[:value]
        )
      end
    end
  end
end
