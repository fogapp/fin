# Recurring series: the subscription lifecycle store (docs/subscriptions-redesign.md).
#
# recurring_series is the stream entity — one row per detected-or-manual
# recurring charge stream. Detection proposes rows as status "suggested"; user
# decisions (accept/dismiss/end) are durable, so the detector never overwrites
# or resurfaces a row the user has acted on. Accepted rows are maintained by
# Recurring::Matcher (attaching new transactions to expected occurrences), not
# by re-derivation.
#
# - series_key is the detection fingerprint (merchant or normalized
#   description + account + amount bucket), unique per household. One row per
#   stream forever: a re-detected stream on an ended series re-suggests that
#   row rather than duplicating it, preserving occurrence history.
# - cadence is granularity ("week"|"month"|"year") + quantity (every N) +
#   anchor (jsonb: {"day_of_month": 15}, {"day_of_month": "last"},
#   {"weekday": 5}, {"nth_weekday": [3, 5]}, {"month": 11, "day": 3}).
# - kind separates fixed-price subscriptions from variable bills; it widens
#   amount_tolerance (fraction of average_amount accepted when matching).
# - misses_streak counts consecutive missed occurrences; 1 = "at risk"
#   badge, 2 = auto-lapse.
#
# recurring_occurrences is evidence + forecast + monitoring in one table: one
# row per expected or observed charge. paid/paid_amount_changed rows link the
# matching cash_transaction; upcoming/due/missed rows are the forecast and
# the missed-payment signal. skipped is a user action ("one-off gap, don't
# count it against the series").
class CreateRecurringSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_series, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :household_id, null: false
      t.string  :series_key,   null: false
      t.string  :status,       null: false, default: "suggested"
      t.string  :source,       null: false, default: "detected"

      t.uuid    :merchant_id
      t.uuid    :account_id
      t.string  :description_pattern
      t.string  :name, null: false
      t.string  :kind, null: false, default: "subscription"

      t.string  :granularity, null: false
      t.integer :quantity,    null: false, default: 1
      t.jsonb   :anchor,      null: false, default: {}

      t.decimal :average_amount,   precision: 10, scale: 2, null: false
      t.decimal :last_amount,      precision: 10, scale: 2
      t.decimal :min_amount,       precision: 10, scale: 2
      t.decimal :max_amount,       precision: 10, scale: 2
      t.decimal :amount_tolerance, precision: 4,  scale: 3, null: false, default: 0.075

      t.float   :confidence, null: false, default: 0.0
      t.date    :first_charge_date
      t.date    :last_charge_date
      t.date    :next_expected_date
      t.integer :occurrences_count, null: false, default: 0
      t.integer :misses_streak,     null: false, default: 0

      t.datetime :accepted_at
      t.datetime :dismissed_at
      t.datetime :ended_at
      t.datetime :last_price_change_at
      t.text     :notes

      t.timestamps
      t.index %i[household_id series_key], unique: true
      t.index %i[household_id status]
      t.index :merchant_id
      t.index :next_expected_date
    end
    add_foreign_key :recurring_series, :households, on_delete: :cascade
    add_foreign_key :recurring_series, :merchants
    add_foreign_key :recurring_series, :accounts

    create_table :recurring_occurrences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :recurring_series_id, null: false
      t.uuid    :household_id,        null: false
      t.date    :expected_date,       null: false
      t.string  :status,              null: false, default: "upcoming"
      t.uuid    :cash_transaction_id
      t.date    :charged_date
      t.decimal :amount,          precision: 10, scale: 2
      t.decimal :expected_amount, precision: 10, scale: 2

      t.timestamps
      t.index %i[recurring_series_id expected_date], unique: true
      t.index :cash_transaction_id, unique: true, where: "cash_transaction_id IS NOT NULL"
      t.index %i[household_id status expected_date]
    end
    add_foreign_key :recurring_occurrences, :recurring_series, on_delete: :cascade
    add_foreign_key :recurring_occurrences, :households, on_delete: :cascade
    add_foreign_key :recurring_occurrences, :cash_transactions, on_delete: :nullify
  end
end
