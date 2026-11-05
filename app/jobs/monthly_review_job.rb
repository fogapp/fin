# typed: true

# First-of-the-month sweep: tells each household its previous month's review
# is ready. The notification itself comes from the seeded "Monthly review"
# workflow (Households::SeedDefaultWorkflows), so the wording, severity, and
# any extra steps stay user-editable; this job only publishes the event with
# a payload rich enough for {{month}}/{{spend}}-style templating.
class MonthlyReviewJob < ApplicationJob
  extend T::Sig

  queue_as :default

  sig { void }
  def perform
    month = Date.current.prev_month.beginning_of_month
    range = month..month.end_of_month

    each_household do |household|
      income = CashTransaction.income_like.where(transaction_date: range).sum(:amount).to_f.round(2)
      spend  = (-CashTransaction.spend_like.where(transaction_date: range).sum(:amount).to_f).round(2)

      Workflows::Events.publish(
        "review.month_ready",
        subject:  household,
        payload:  {
          "month"       => month.strftime("%Y-%m"),
          "month_label" => month.strftime("%B %Y"),
          "income"      => income,
          "spend"       => spend,
          "net"         => (income - spend).round(2)
        }
      )
    end
  end
end
