# typed: true

module Api
  module V1
    module Equity
      class CompaniesController < BaseController
        renders_with Api::Render::Equity

        def create
          company = EquityCompany.new(company_params)
          ActiveRecord::Base.transaction do
            link_security(company)
            company.save!
            if params[:initial_fmv].present?
              company.fmv_entries.create!(initial_fmv_params)
            end
          end
          render json: renderer.company(company.reload), status: :created
        end

        def update
          company = EquityCompany.find(params[:id])
          company.assign_attributes(company_params)
          link_security(company)
          company.save!
          render json: renderer.company(company.reload)
        end

        def destroy
          EquityCompany.find(params[:id]).destroy!
          head :no_content
        end

        private

        # Public companies with a ticker get linked to the shared market
        # instrument, so share_price can come from live quotes.
        def link_security(company)
          return unless company.public_company? && params[:ticker].present?

          company.security = Instruments::Resolver.resolve!(
            instrument_class: Instruments::InstrumentClass::Equity,
            ticker:           params[:ticker],
            name:             company.name
          )
        end

        def company_params
          params.permit(:name, :public_company, :c_corp, :qsbs_candidate, :preferred_price, :notes)
        end

        def initial_fmv_params
          params.require(:initial_fmv).permit(:price_per_share, :effective_date, :source)
        end
      end
    end
  end
end
