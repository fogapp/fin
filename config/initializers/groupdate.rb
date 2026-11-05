# typed: true

# Every group_by_period call in the app groups a plain DATE column
# (transaction_date / trade_date). Those dates are already the household's
# local calendar dates — with the app time zone set to America/Los_Angeles
# (see config/application.rb), groupdate's default Time.zone conversion would
# treat them as UTC midnights and shift them back into the previous local
# day/month, corrupting every monthly series.
#
# Pinning groupdate to UTC makes date-column grouping timezone-neutral
# (a date stays on its own calendar day). If a timestamp column ever needs
# grouping, pass `time_zone: Time.zone.name` at that call site explicitly.
Groupdate.time_zone = "Etc/UTC"
