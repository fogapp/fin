# The demo data itself lives in db/seeds/demo.rb; this file only sets up the
# conditions it runs under.
#
# Seeding is a bulk import, not user activity. Every cash transaction commits
# an after_commit that enqueues a payment probe and (when categorized) a
# budget-threshold check, so a seed of ~2,200 transactions enqueued ~4,200
# jobs: minutes of ActiveJob log noise during install, thousands of
# solid_queue inserts, and a worker churning through per-row work for
# backdated history it has nothing useful to say about.
#
# Suppressing workflow events skips all of that (the same lever Alchemy's
# backfill and reconciliation use). The one part that actually shapes the
# finished demo data — pairing the credit-card autopay legs — runs once in
# bulk at the end of demo.rb instead. Budget thresholds are deliberately not
# re-checked: they would fire notifications about months of history that just
# appeared.
#
# Production never gets the demo household unless asked for: `db:prepare` on an
# empty database runs this file, and the demo carries a well-known admin token
# (dev-token-fin-local). FIN_SEED_DEMO=1 loads it anyway, for a demo instance.
if Rails.env.production? && ENV["FIN_SEED_DEMO"] != "1"
  puts "Skipping demo seed in production (set FIN_SEED_DEMO=1 to load it)."
  return
end

Workflows::Events.suppress do
  load Rails.root.join("db/seeds/demo.rb").to_s
end
