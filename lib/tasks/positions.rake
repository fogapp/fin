# Recomputes the positions table from the ledger. Positions otherwise only
# rebuild when one of their transactions changes, so a change to how the
# ledger is read (share splits converted to current units) needs one pass.
# Idempotent.
#
#   bin/rails positions:rebuild
namespace :positions do
  desc "Rebuild every (account, security) position from the transaction ledger"
  task rebuild: :environment do
    pairs = InvestmentTransaction.unscoped.where.not(account_id: nil).where.not(security_id: nil)
      .distinct.pluck(:account_id, :security_id)
    pairs |= Position.unscoped.distinct.pluck(:account_id, :security_id)
    accounts   = Account.unscoped.where(id: pairs.map(&:first).uniq).index_by(&:id)
    securities = Security.where(id: pairs.map(&:last).uniq).index_by(&:id)

    rebuilt = 0
    pairs.each do |account_id, security_id|
      account, security = accounts[account_id], securities[security_id]
      next unless account && security

      Current.set(household: account.household) do
        Positions::Rebuild.call(account: account, security: security)
      end
      rebuilt += 1
    end
    puts "rebuilt #{rebuilt} positions"
  end
end
