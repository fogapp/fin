# InstanceSetting memoizes the instance time zone per process. Transactional
# examples roll a changed setting back without its after_commit running, so
# drop the memo before each example rather than let one leak into the next.
RSpec.configure do |config|
  config.before { InstanceSetting.reset_time_zone_cache! }
end
