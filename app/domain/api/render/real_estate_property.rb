# typed: strict

module Api
  module Render
    class RealEstateProperty < Api::Render::Base
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def index
        properties = ::RealEstateProperty.includes(:valuations, loans: :cash_transactions).order(:name).to_a

        {
          properties: properties.map { |property| serialize(property) },
          totals:     totals(properties),
          rentcast:   rentcast_status
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        property = ::RealEstateProperty.includes(:valuations, loans: :cash_transactions).find(params[:id])

        serialize(property).merge(
          valuations: property.valuations.chronological.map { |valuation| serialize_valuation(valuation) },
          facts:      facts(property),
          notes:      property.notes
        )
      end

      sig { params(property: ::RealEstateProperty).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(property)
        current = property.current_valuation
        value   = property.current_value

        {
          id:                property.id,
          name:              property.name,
          address_line1:     property.address_line1,
          address_line2:     property.address_line2,
          city:              property.city,
          state:             property.state,
          zip_code:          property.zip_code,
          formatted_address: property.formatted_address,
          display_address:   property.query_address,
          status:            property.status,
          purchase_date:     property.purchase_date,
          purchase_price:    property.purchase_price&.to_f,
          sold_date:         property.sold_date,
          sold_price:        property.sold_price&.to_f,
          value:             value&.to_f,
          value_source:      current&.source,
          value_as_of:       current&.as_of,
          value_low:         current&.value_low&.to_f,
          value_high:        current&.value_high&.to_f,
          mortgage_balance:  property.mortgage_balance&.to_f,
          equity:            property.equity&.to_f,
          loan_to_value:     property.loan_to_value,
          mortgages:         property.loans.map { |loan| { id: loan.id, name: loan.name, lender: loan.lender } },
          sync_enabled:      property.sync_enabled,
          last_synced_at:    property.last_synced_at,
          last_sync_error:   property.last_sync_error,
          created_at:        property.created_at,
          updated_at:        property.updated_at
        }
      end

      sig { params(valuation: ::RealEstateValuation).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_valuation(valuation)
        {
          id:         valuation.id,
          as_of:      valuation.as_of,
          amount:     valuation.amount.to_f,
          source:     valuation.source,
          value_low:  valuation.value_low&.to_f,
          value_high: valuation.value_high&.to_f
        }
      end

      private

      sig { params(property: ::RealEstateProperty).returns(T::Hash[Symbol, T.untyped]) }
      def facts(property)
        {
          property_type:  property.property_type,
          bedrooms:       property.bedrooms,
          bathrooms:      property.bathrooms&.to_f,
          square_footage: property.square_footage,
          lot_size:       property.lot_size,
          year_built:     property.year_built,
          hoa_fee:        property.hoa_fee&.to_f,
          latitude:       property.latitude&.to_f,
          longitude:      property.longitude&.to_f
        }
      end

      # Owned properties only — a sold property's value is history, not a
      # current holding.
      sig { params(properties: T::Array[::RealEstateProperty]).returns(T::Hash[Symbol, T.untyped]) }
      def totals(properties)
        owned    = properties.reject(&:sold?)
        value    = owned.sum { |property| property.current_value || 0 }
        mortgage = owned.sum { |property| property.mortgage_balance || 0 }

        {
          value:    value.to_f,
          mortgage: mortgage.to_f,
          equity:   (value - mortgage).to_f,
          count:    owned.size
        }
      end

      # Lets the UI decide between the automatic and manual-entry flows
      # without a second request.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def rentcast_status
        config = RentcastConfiguration.current
        {
          configured:      config.configured?,
          remaining_quota: config.configured? ? config.remaining_quota : nil,
          request_limit:   config.monthly_request_limit,
          last_synced_at:  config.last_synced_at
        }
      end
    end
  end
end
