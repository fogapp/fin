# typed: true

module Api
  module V1
    module Tax
      # Document-checklist writes. Auto-seeded rows can't be deleted (the
      # seeder would just recreate them on the next report load) — marking
      # them n_a is the durable way to dismiss one.
      class ChecklistItemsController < BaseController
        renders_with Api::Render::Tax

        def create
          item = TaxChecklistItem.new(create_params)
          item.save!
          render json: renderer.checklist_item(item), status: :created
        end

        def update
          item = TaxChecklistItem.find(params[:id])
          item.update!(update_params)
          render json: renderer.checklist_item(item)
        end

        def destroy
          item = TaxChecklistItem.find(params[:id])
          if item.auto_seeded?
            return render json: { error: "auto-seeded items cannot be deleted; mark n_a instead" },
                          status: :unprocessable_content
          end

          item.destroy!
          head :no_content
        end

        private

        def create_params
          params.permit(:tax_year, :kind, :source_label, :status, :reference_id, :notes)
        end

        def update_params
          params.permit(:status, :notes)
        end
      end
    end
  end
end
