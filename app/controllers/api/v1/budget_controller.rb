# typed: true

module Api
  module V1
    class BudgetController < BaseController
      # GET /budget?month=YYYY-MM
      def show
        render_cached("budget", params: %i[month]) { Budgets::Month.new(month: month_param).call }
      end

      # GET /budget/calendar?year=YYYY — the year-at-a-glance grid.
      def calendar
        year = (params[:year].presence || Date.current.year).to_i
        raise ActionController::BadRequest, "year out of range" unless year.between?(2000, 2100)

        render_cached("budget_calendar", params: %i[year]) { Budgets::Calendar.new(year: year).call }
      end

      # GET /budget/line_history?month=YYYY-MM&category_id=...&months=6
      # Trailing planned-vs-actual for one category, for drill-down context.
      def line_history
        category_id = params.require(:category_id)
        months      = (params[:months].presence || 6).to_i.clamp(1, 12)
        render_cached("budget_line_history", params: %i[month category_id months]) do
          { category_id: category_id,
            months:      Budgets::Month.new(month: month_param).line_history(category_id, months: months) }
        end
      end

      # GET /budget/suggestions?month=YYYY-MM — typical spend per category,
      # for setting amounts.
      def suggestions
        render_cached("budget_suggestions", params: %i[month]) { Budgets::Suggestions.new(month: month_param).call }
      end

      # PUT /budget/line — set one category's amount from this month on
      # (mode ongoing, the default) or for this month only (month_only).
      # Omitted fields keep the plan's current values.
      def upsert_line
        category = Category.find(params.require(:category_id))
        line = Budgets::SetLine.set(
          category: category,
          month:    month_param,
          planned:  params.key?(:planned) ? params[:planned].to_d : nil,
          rollover: params.key?(:rollover) ? ActiveModel::Type::Boolean.new.cast(params[:rollover]) : nil,
          period:   enum_param(BudgetLine::Period, :period),
          mode:     enum_param(BudgetLine::Mode, :mode) || BudgetLine::Mode::Ongoing
        )
        render json: Budgets::Month.new(month: month_param).line_payload(line)
      end

      # DELETE /budget/line — stop budgeting the category from this month on,
      # or (month_only: true) drop just this month's one-month amount.
      def destroy_line
        category = Category.find(params.require(:category_id))
        if ActiveModel::Type::Boolean.new.cast(params[:month_only])
          Budgets::SetLine.clear_override(category: category, month: month_param)
        else
          Budgets::SetLine.stop(category: category, month: month_param)
        end
        head :no_content
      end

      # PUT /budget/period — the income target and/or the "everything else"
      # amount, from this month on. null clears a value from this month on.
      def upsert_period
        month = month_param
        fields = BudgetPeriod::FIELDS.select { |f| params.key?(f) }
        raise ActionController::BadRequest, "income_planned or other_planned is required" if fields.empty?

        BudgetPeriod.set!(month, fields.to_h { |f| [ f, params[f].nil? ? nil : params[f].to_d ] })
        data = Budgets::Month.new(month: month).call
        render json: { month: month.strftime("%Y-%m"), income_planned: data[:income][:planned],
                       other_planned: data[:everything_else][:planned] }
      end

      # POST /budget/autofill — a starter plan: the few categories that make
      # up most spending, at their suggested amounts, plus "everything else".
      def autofill
        render json: { filled: Budgets::Autofill.call(month: month_param) }
      end
    end
  end
end
