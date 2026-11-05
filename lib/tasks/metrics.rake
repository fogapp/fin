# Maintenance tasks for the Stats system's precomputed metric_points store.
#
#   bin/rails metrics:backfill[cc_transaction_count]  # one metric, all households (reset)
#   bin/rails metrics:backfill_all                    # every metric, all households (reset)
#
# Use after deploying a new metric definition (for instant history instead of
# waiting for the nightly refresh) or after changing a formula (reset clears
# periods the new formula no longer produces).
namespace :metrics do
  desc "Recompute full history for one metric across all households (resets existing points)"
  task :backfill, [ :key ] => :environment do |_t, args|
    definition = Metrics::Registry.find(args[:key].to_s)
    abort "Unknown metric key #{args[:key].inspect}. Known: #{Metrics::Registry.all.map(&:key).join(', ')}" if definition.nil?

    Household.find_each do |household|
      count = Current.set(household: household) do
        Metrics::Backfill.new.call(definition, reset: true)
      end
      puts "#{definition.key} household=#{household.id}: #{count} points"
    end
  end

  desc "Recompute full history for every registered metric across all households (resets existing points)"
  task backfill_all: :environment do
    Household.find_each do |household|
      Current.set(household: household) do
        Metrics::Registry.all.each do |definition|
          count = Metrics::Backfill.new.call(definition, reset: true)
          puts "#{definition.key} household=#{household.id}: #{count} points"
        end
      end
    end
  end
end
