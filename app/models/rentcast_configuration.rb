# typed: true

class RentcastConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  # Raised when a request would exceed the plan's monthly allowance. Every
  # RentCast call goes through consume_quota!, so no call site can slip past
  # the counter and blow the free tier mid-month.
  class QuotaExceeded < StandardError; end

  encrypts :api_key
  configured_when :api_key

  # Requests still available this calendar month.
  sig { returns(Integer) }
  def remaining_quota
    roll_period!
    [ monthly_request_limit - requests_used, 0 ].max
  end

  # Reserves one request, or raises. Persisted immediately: a crash
  # mid-refresh must not hand the quota back, since RentCast counted the
  # call regardless.
  sig { params(count: Integer).void }
  def consume_quota!(count = 1)
    roll_period!
    if requests_used + count > monthly_request_limit
      raise QuotaExceeded,
            "RentCast monthly request limit reached (#{requests_used}/#{monthly_request_limit})"
    end

    increment!(:requests_used, count)
  end

  sig { returns(Date) }
  def current_period_start
    Date.current.beginning_of_month
  end

  private

  # Zeroes the counter when the calendar month rolls over. Called on read as
  # well as write so a stale count never blocks the first sync of a month.
  sig { void }
  def roll_period!
    period = current_period_start
    return if quota_period_start == period

    if persisted?
      update_columns(requests_used: 0, quota_period_start: period)
    else
      assign_attributes(requests_used: 0, quota_period_start: period)
    end
  end
end
