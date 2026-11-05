# typed: true

module Api
  module V1
    module Tax
      # GET /api/v1/tax/report?year= — the tax center's one read endpoint:
      # the full year report (income facts, deductions, liability estimate,
      # payments + safe harbor, contributions, wash-sale flags, document
      # checklist). The checklist is seeded once here (first visit for a
      # year); after that, GETs are read-only and the weekly TaxScanJob keeps
      # the checklist current with the ledger.
      class ReportsController < BaseController
        include ::Tax::ChecklistSeeding

        def show
          household = Current.household
          seed_checklist_once(household)

          render_cached("tax_report", params: %i[year]) do
            ::Tax::YearReport.build(household: household, year: year_param)
          end
        end
      end
    end
  end
end
