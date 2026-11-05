# frozen_string_literal: true

# The instance time zone (Settings → Household → Time zone, stored on
# InstanceSetting) applies per request and per job; config.time_zone in
# config/application.rb is only the boot default that console and rake run
# in. Defined here rather than under app/ because they are mixed into
# framework classes, which must not hold a reloadable constant.

# Requests: every controller — the REST API, MCP, setup, sign-in, fog and
# webhook controllers, the SPA — runs in the instance zone without each one
# opting in. As a base-class callback it wraps everything a controller
# declares, authentication included.
module InstanceTimeZone
  extend ActiveSupport::Concern

  included do
    around_action :use_instance_time_zone
  end

  private

  def use_instance_time_zone(&block)
    Time.use_zone(InstanceSetting.time_zone, &block)
  end
end

ActiveSupport.on_load(:action_controller_base) { include InstanceTimeZone }
ActiveSupport.on_load(:action_controller_api)  { include InstanceTimeZone }

# Jobs: ApplicationJob wraps perform in Time.use_zone.
#
# Recurring schedules: Solid Queue resolves config/recurring.yml's cron
# times with Fugit, which reads Time.zone — on the scheduler's own timer
# threads that is the boot default. Resolve them in the instance zone
# instead. Each task computes its next run when it schedules itself (at
# boot, then after every firing), so after a change a task fires once more
# at its old time and follows the new zone from then on; restarting the
# worker applies it at once.
module InstanceTimeZoneRecurringTask
  def next_time
    Time.use_zone(InstanceSetting.time_zone) { super }
  end

  def previous_time
    Time.use_zone(InstanceSetting.time_zone) { super }
  end
end

Rails.application.config.to_prepare do
  unless SolidQueue::RecurringTask <= InstanceTimeZoneRecurringTask
    SolidQueue::RecurringTask.prepend(InstanceTimeZoneRecurringTask)
  end
end
