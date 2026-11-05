# frozen_string_literal: true

# The instance's time zone — what "today", month boundaries, cron schedules
# and market-sync days are computed in. It used to be hard-coded in
# config/application.rb; that value stays the default (and the boot zone
# for console and rake), and this column lets an admin change it.
class AddTimeZoneToInstanceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :instance_settings, :time_zone, :string, null: false, default: "America/Los_Angeles"
  end
end
