# typed: true

module Api
  module V1
    module Tax
      # GET /api/v1/tax/export?year= — the CPA bundle; see
      # Api::Render::TaxExport.
      class ExportsController < BaseController
        include ::Tax::ChecklistSeeding

        def show
          household = Current.household
          seed_checklist_once(household)
          report = ::Tax::YearReport.build(household: household, year: year_param)

          render json: Api::Render::TaxExport.new.export(report: report, year: year_param)
        end
      end
    end
  end
end
