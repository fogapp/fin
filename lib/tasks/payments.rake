# Historical sweep for the credit-card-payments rollout
# (docs/credit-card-payments.md §F).
#
#   bin/rails payments:backfill
#
# Then recompute the precomputed stats store, since the spend/income scope
# change shifts historical series:
#
#   bin/rails metrics:backfill_all
namespace :payments do
  desc "Classify transfers, normalize payment rows, auto-confirm payment pairs across history"
  task backfill: :environment do
    Household.find_each do |household|
      stats = Current.set(household: household) do
        Transfers::PaymentBackfill.new.call
      end
      puts "household=#{household.id}"
      stats.each { |k, v| puts "  #{k}: #{v}" }
    end
    puts "\nNow run: bin/rails metrics:backfill_all"
  end
end
