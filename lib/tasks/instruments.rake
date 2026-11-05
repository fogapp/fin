# Cleanup for the Plaid securities forked by the resolver cutover
# (see Instruments::PlaidDuplicates).
#
#   bin/rails instruments:plaid_duplicates              # dry run, prints the plan
#   APPLY=1 bin/rails instruments:plaid_duplicates      # merge them
namespace :instruments do
  desc "Merge securities Plaid forked in two (dry run unless APPLY=1)"
  task plaid_duplicates: :environment do
    # Accounts whose ledger mentions the security — they need a position
    # rebuild once its transactions are repointed at the keeper.
    affected_accounts = lambda do |security|
      ids = InvestmentTransaction.unscoped.where(security_id: security.id).distinct.pluck(:account_id)
      ids |= Position.unscoped.where(security_id: security.id).distinct.pluck(:account_id)
      Account.unscoped.where(id: ids).to_a
    end

    apply  = ENV["APPLY"].present?
    finder = Instruments::PlaidDuplicates.new
    plans  = finder.plans

    puts "#{apply ? 'MERGING' : 'DRY RUN —'} #{plans.size} duplicate row(s) across " \
         "#{finder.pairs.size} holding(s), #{finder.skipped.size} skipped\n\n"

    plans.each do |plan|
      accounts = Account.unscoped.where(id: plan.account_ids).pluck(:name)
      puts "#{plan.keep.name}"
      puts "  accounts  #{accounts.inspect}"
      puts "  keep      #{plan.keep.id} (#{plan.keep.instrument_class})"
      puts "  remove    #{plan.remove.id} (#{plan.remove.instrument_class}, " \
           "#{ActiveSupport::NumberHelper.number_to_currency(plan.stale_market_value)} double-counted)"

      next unless apply

      rebuild_in = affected_accounts.call(plan.remove)
      Instruments::Merge.call(keep: plan.keep, remove: plan.remove)
      # The repointed transactions change the keeper's ledger, and any
      # position row the duplicate owned was dropped by the merge.
      rebuild_in.each { |a| Positions::Rebuild.call(account: a, security: plan.keep) }
      puts "  merged    ✓"
    end

    finder.skipped.each do |skip|
      puts "SKIPPED #{skip.name} (#{skip.reason}) — #{skip.security_ids.join(', ')}"
    end

    stale_total = plans.sum(&:stale_market_value)
    puts "\ndouble-counted market value#{apply ? ' removed' : ''}: " \
         "#{ActiveSupport::NumberHelper.number_to_currency(stale_total)}"
    puts "\nRe-run with APPLY=1 to merge." unless apply
  end

  # Runs the conversion half of the system audit now instead of waiting for
  # the scheduled sweep. Suggestions are confirmed or dismissed from
  # Settings -> Issues; nothing affects valuation until confirmed.
  desc "Detect instrument conversions the ledger never recorded and raise them as issues to confirm"
  task detect_conversions: :environment do
    Household.find_each do |household|
      Current.set(household: household) do
        before = SecurityConversion.pluck(:id).to_set
        Audits::SecurityConversions.new.call
        created = SecurityConversion.includes(:from_security, :to_security).reject { |c| before.include?(c.id) }
        created.each do |c|
          puts "#{household.name}: suggested #{c.from_security.display_name} -> #{c.to_security.display_name} " \
               "ratio=#{c.ratio.to_f} effective=#{c.effective_date} (confirm under Settings -> Issues)"
        end
        puts "#{household.name}: no new conversions" if created.empty?
      end
    end
  end
end
