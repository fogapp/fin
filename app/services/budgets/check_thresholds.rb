# typed: strict

module Budgets
  # Publishes budget threshold workflow events when a transaction pushes a
  # budgeted category past 90% (approaching) or 100% (exceeded) of its
  # available amount. Edge-stamped on the line in force so each level fires
  # once a month, like monitors — a line carries forward across months, so a
  # stamp from an earlier month doesn't count.
  module CheckThresholds
    extend T::Sig

    sig { params(transaction: CashTransaction).void }
    def self.call(transaction)
      category = transaction.category
      return if category.nil? || transaction.budget_excluded

      month = transaction.transaction_date.beginning_of_month
      return if month != Date.current.beginning_of_month

      # The transaction may hit a subcategory whose budget lives on the parent.
      plan = Plan.new(through: month)
      parent_id = category.parent_id
      line = plan.line_for(category.id, month) || (parent_id && plan.line_for(parent_id, month))
      return if line.nil?

      exceeded = alerted_in?(line.exceeded_alerted_at, month)
      approaching = alerted_in?(line.approaching_alerted_at, month)
      # Both levels already edge-stamped → neither branch below can fire, so
      # skip building Month (a 13-month grouped scan) on this insert.
      # exceeded alone is not enough: a line that jumped straight past 100%
      # may still owe its approaching alert on a later transaction.
      return if exceeded && approaching

      payload = Month.new(month: month).line_payload(line)
      percent = payload[:percent_used].to_f

      if percent >= 100 && !exceeded
        line.update!(exceeded_alerted_at: Time.current)
        publish("budget.category_exceeded", line, payload)
      elsif percent >= Month::APPROACHING_THRESHOLD * 100 && !approaching
        line.update!(approaching_alerted_at: Time.current)
        publish("budget.category_approaching", line, payload)
      end
    end

    sig { params(stamp: T.nilable(ActiveSupport::TimeWithZone), month: Date).returns(T::Boolean) }
    def self.alerted_in?(stamp, month)
      !stamp.nil? && stamp.to_date >= month
    end
    private_class_method :alerted_in?

    sig { params(event: String, line: BudgetLine, payload: T::Hash[Symbol, T.untyped]).void }
    def self.publish(event, line, payload)
      Workflows::Events.publish(
        event,
        subject: line.category,
        payload: {
          "month"        => Date.current.strftime("%Y-%m"),
          "planned"      => payload[:planned],
          "actual"       => payload[:actual],
          "remaining"    => payload[:remaining],
          "percent_used" => payload[:percent_used]
        }
      )
    end
    private_class_method :publish
  end
end
