# typed: strict

module Workflows
  # Schedule-trigger math and validation. trigger_config shape:
  #   {"frequency" => "hourly",  "every_hours" => 4}
  #   {"frequency" => "daily",   "at" => "05:30"}
  #   {"frequency" => "weekly",  "at" => "05:30", "day_of_week" => 1}  (1=Mon..7=Sun)
  #   {"frequency" => "monthly", "at" => "05:30", "day_of_month" => 1}
  module Schedule
    extend T::Sig

    # Schedule cadences; trigger_config stores the serialized value under
    # "frequency" and each read boundary deserializes it.
    class Frequency < T::Enum
      include ApplicationEnum

      enums do
        Hourly = new("hourly")
        Daily = new("daily")
        Weekly = new("weekly")
        Monthly = new("monthly")
      end
    end

    sig { params(config: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
    def self.validation_error(config)
      frequency = Frequency.try_deserialize(config["frequency"].to_s)
      if frequency.nil?
        return "schedule needs a frequency (#{Frequency.values.map(&:serialize).join('/')})"
      end

      if frequency == Frequency::Hourly
        hours = config["every_hours"].to_i
        return "hourly schedule needs every_hours between 1 and 24" unless hours.between?(1, 24)
      else
        return "schedule needs a valid at time (HH:MM)" unless config["at"].to_s.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
      end
      if frequency == Frequency::Weekly && !config["day_of_week"].to_i.between?(1, 7)
        return "weekly schedule needs day_of_week 1-7 (Monday=1)"
      end
      if frequency == Frequency::Monthly && !config["day_of_month"].to_i.between?(1, 28)
        return "monthly schedule needs day_of_month 1-28"
      end

      nil
    end

    # The next time this schedule fires strictly after `from`.
    sig { params(config: T::Hash[T.untyped, T.untyped], from: ActiveSupport::TimeWithZone).returns(ActiveSupport::TimeWithZone) }
    def self.next_occurrence(config, from: Time.current)
      case Frequency.try_deserialize(config["frequency"].to_s)
      when Frequency::Hourly
        from + config["every_hours"].to_i.hours
      when Frequency::Daily
        at_time(from, config) > from ? at_time(from, config) : at_time(from + 1.day, config)
      when Frequency::Weekly
        target = config["day_of_week"].to_i
        days_ahead = (target - from.to_date.cwday) % 7
        candidate = at_time(from + days_ahead.days, config)
        candidate > from ? candidate : at_time(from + 7.days, config)
      when Frequency::Monthly
        day = config["day_of_month"].to_i
        this_month = at_time(from.change(day: day), config)
        this_month > from ? this_month : at_time((from + 1.month).change(day: day), config)
      else
        raise ArgumentError, "unknown frequency #{config['frequency'].inspect}"
      end
    end

    sig { params(config: T::Hash[T.untyped, T.untyped]).returns(String) }
    def self.describe(config)
      at = config["at"]
      case Frequency.try_deserialize(config["frequency"].to_s)
      when Frequency::Hourly  then "every #{config['every_hours'].to_i} hour#{config['every_hours'].to_i == 1 ? '' : 's'}"
      when Frequency::Daily   then "daily at #{at}"
      when Frequency::Weekly  then "weekly on #{Date::DAYNAMES.fetch(config['day_of_week'].to_i % 7)} at #{at}"
      when Frequency::Monthly then "monthly on day #{config['day_of_month'].to_i} at #{at}"
      else "unscheduled"
      end
    end

    sig { params(base: ActiveSupport::TimeWithZone, config: T::Hash[T.untyped, T.untyped]).returns(ActiveSupport::TimeWithZone) }
    def self.at_time(base, config)
      hour, minute = config["at"].to_s.split(":").map(&:to_i)
      base.change(hour: hour, min: minute)
    end
    private_class_method :at_time
  end
end
