# typed: true

module Api
  module V1
    # Subscription lifecycle API over RecurringSeries
    # (docs/subscriptions-redesign.md §8). The index summary is always
    # computed across the household regardless of the status filter, so the
    # page header and review badge don't need extra requests.
    class SubscriptionsController < BaseController
      renders_with Api::Render::Subscription

      before_action :set_series, except: %i[index create upcoming calendar]

      # Every key Recurring::Schedule reads from an anchor
      # ({ day_of_month: 15 }, { nth_weekday: [2, 3] }, { month: 4, day: 15 } …).
      ANCHOR_KEYS = T.let([ :weekday, :month, :day, :day_of_month, { nth_weekday: [] } ].freeze, T::Array[T.untyped])

      # A disallowed lifecycle move is the client's error, not a 500.
      rescue_from RecurringSeries::InvalidTransition do |e|
        render json: { error: e.message, errors: [ e.message ] }, status: :unprocessable_content
      end

      def index
        status = enum_param(RecurringSeries::Status, :status, default: RecurringSeries::Status::Active)

        series = RecurringSeries.where(status: status)
                                .includes(:merchant)
                                .order(average_amount: :desc)
                                .to_a

        render json: {
          summary: Recurring::SeriesSummary.call,
          series: renderer.index(series)
        }
      end

      def show
        render json: renderer.detail(@series)
      end

      def create
        params.require(:granularity)
        schedule = Recurring::Schedule.new(
          granularity: T.must(enum_param(Recurring::Schedule::Granularity, :granularity)),
          quantity: (params[:quantity] || 1).to_i,
          anchor: params.permit(anchor: ANCHOR_KEYS).fetch(:anchor, {}).to_h
        )
        adopted = params[:cash_transaction_id].present? ? CashTransaction.find(params[:cash_transaction_id]) : nil
        # Earlier charges of the same stream (the transaction page's detected
        # cadence) become the series' paid history. A charge already tracked
        # by another series stays with it.
        history = CashTransaction.where(id: Array(params[:history_transaction_ids]).map(&:to_s))
          .where.not(id: RecurringOccurrence.where.not(cash_transaction_id: nil).select(:cash_transaction_id))
          .to_a

        series = Recurring::CreateManualSeries.call(attributes: series_params.to_h, schedule: schedule,
                                                    adopted: adopted, history: history)
        render json: renderer.detail(series.reload), status: :created
      end

      def update
        cadence_changed = %w[granularity quantity anchor].any? { |k| params.key?(k) }
        @series.update!(series_params)
        @series.reset_pending_schedule! if cadence_changed
        render json: renderer.detail(@series.reload)
      end

      def destroy
        @series.destroy!
        head :no_content
      end

      def accept
        @series.accept!
        render json: renderer.detail(@series.reload)
      end

      def dismiss
        @series.dismiss!
        render json: renderer.detail(@series.reload)
      end

      def restore
        @series.restore!
        render json: renderer.detail(@series.reload)
      end

      def end_subscription
        @series.mark_ended!
        render json: renderer.detail(@series.reload)
      end

      def detach_occurrence
        @series.recurring_occurrences.find(params[:occurrence_id]).detach!
        render json: renderer.detail(@series.reload)
      end

      def skip_occurrence
        @series.recurring_occurrences.find(params[:occurrence_id]).skip!
        render json: renderer.detail(@series.reload)
      end

      # One month of recurring charges across every tracked series — history
      # included (paid / amount-changed / missed / skipped), unlike #upcoming,
      # which is forward-only. Backs the subscriptions calendar view.
      def calendar
        month = month_param

        occurrences = RecurringOccurrence
          .joins(:recurring_series)
          .merge(RecurringSeries.tracking)
          .where(expected_date: month..month.end_of_month)
          .includes(:recurring_series)
          .chronological

        render json: renderer.calendar(month, occurrences)
      end

      def upcoming
        days = (params[:days] || 30).to_i.clamp(1, 365)
        occurrences = RecurringOccurrence
          .pending
          .joins(:recurring_series)
          .where(recurring_series: { status: RecurringSeries::Status::Active })
          .where(expected_date: Date.current..(Date.current + days))
          .includes(:recurring_series)
          .chronological

        render json: renderer.upcoming(occurrences)
      end

      private

      def set_series
        @series = RecurringSeries.find(params[:id])
      end

      def series_params
        permitted = params.permit(
          :name, :kind, :notes, :merchant_id, :description_pattern,
          :granularity, :quantity, :average_amount, :amount_tolerance, anchor: ANCHOR_KEYS
        ).merge(account_reference)
        raise ActionController::BadRequest, "unknown kind" if permitted[:kind] && !RecurringSeries::Kind.try_deserialize(permitted[:kind].to_s)

        permitted
      end
    end
  end
end
