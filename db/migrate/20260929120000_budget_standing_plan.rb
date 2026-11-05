# Budgets become a standing plan: a line applies from its month onward until
# a later line supersedes it (mode "ongoing"), or to its month alone
# ("month_only"), or ends the category's budget ("stopped"). Lines may be
# yearly amounts. Periods carry forward the same way and gain an
# "everything else" amount for spend in categories without a line. A
# transaction can be excluded from budgets (one-off purchases).
class BudgetStandingPlan < ActiveRecord::Migration[8.1]
  def change
    change_table :budget_lines, bulk: true do |t|
      t.string :mode, null: false, default: "ongoing"
      t.string :period, null: false, default: "monthly"
    end

    add_column :budget_periods, :other_planned, :decimal, precision: 14, scale: 2

    add_column :cash_transactions, :budget_excluded, :boolean, null: false, default: false
  end
end
