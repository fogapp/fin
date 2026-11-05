# Idempotent seed file — safe to run multiple times.
# Creates realistic demo data so the app is fully populated after a reset.

puts "Seeding Fin..."

# ── Helpers ───────────────────────────────────────────────────────────────────

def rand_date(from:, to: Date.current)
  from + rand((to - from).to_i).days
end

def hash_for(*parts)
  Digest::SHA1.hexdigest(parts.join("-"))
end

# Seasonal multiplier — higher amounts/frequency in relevant seasons
def seasonal(date, peak_months:, peak: 1.6, off: 0.7)
  peak_months.include?(date.month) ? rand(peak * 0.85..peak * 1.15) : rand(off * 0.85..off * 1.15)
end

# ── Household + User ──────────────────────────────────────────────────────────

household = Household.find_or_create_by!(name: "Default")
user      = User.find_or_create_by!(email: "dev@fin.local") { |u| u.name = "Default User" }
HouseholdMembership.find_or_create_by!(user: user, household: household) { |m| m.role = "admin" }

# Set Current.household so the HouseholdScoped default_scope filters every
# query in this seed to the default household. Without this, the association
# proxies (e.g. household.merchants.find_or_create_by!) still work, but ad-hoc
# joins like `CashTransaction.joins(:merchant).where(merchants: {...})` lower
# in the file would scan across all households.
Current.household = household

puts "  Household: #{household.name} (#{user.email})"

# ── API Token ─────────────────────────────────────────────────────────────────

# The plaintext is fixed so docs and scripts can rely on it. ApiToken only
# stores the digest, so the constant here is the one place the value lives.
DEV_TOKEN = "dev-token-fin-local"
ApiToken.find_or_create_by!(name: "Dev Token", user: user, household: household) do |t|
  t.token_digest = Digest::SHA256.hexdigest(DEV_TOKEN)
end
puts "  API token: #{DEV_TOKEN}"

# Registration refuses to add a first passkey to an existing account without
# an invite, so hand out an admin invite for this household (single-use).
invite = InviteCode.usable.find_by(household: household, role: "admin") ||
  InviteCode.create!(household: household, role: "admin", created_by: user)
puts "  Invite code: #{invite.code}"

# Households created through registration get these; the seeded one should too.
Households::SeedDefaultWorkflows.call(household)

# ── Categories + subcategories ────────────────────────────────────────────────

categories = {
  dining:        household.categories.find_or_create_by!(name: "Dining"),
  groceries:     household.categories.find_or_create_by!(name: "Groceries"),
  transport:     household.categories.find_or_create_by!(name: "Transportation"),
  travel:        household.categories.find_or_create_by!(name: "Travel"),
  entertainment: household.categories.find_or_create_by!(name: "Entertainment"),
  health:        household.categories.find_or_create_by!(name: "Health & Fitness"),
  shopping:      household.categories.find_or_create_by!(name: "Shopping"),
  utilities:     household.categories.find_or_create_by!(name: "Utilities"),
  subscriptions: household.categories.find_or_create_by!(name: "Subscriptions"),
  income:        household.categories.find_or_create_by!(name: "Income")
}

# Subcategories
sub = {
  coffee:      household.categories.find_or_create_by!(name: "Coffee Shops",  parent: categories[:dining]),
  fast_food:   household.categories.find_or_create_by!(name: "Fast Food",     parent: categories[:dining]),
  gas:         household.categories.find_or_create_by!(name: "Gas & Fuel",    parent: categories[:transport]),
  gym:         household.categories.find_or_create_by!(name: "Gym & Fitness", parent: categories[:health]),
  pharmacy:    household.categories.find_or_create_by!(name: "Pharmacy",      parent: categories[:health]),
  electronics: household.categories.find_or_create_by!(name: "Electronics",   parent: categories[:shopping]),
  clothing:    household.categories.find_or_create_by!(name: "Clothing",      parent: categories[:shopping]),
  hotels:      household.categories.find_or_create_by!(name: "Hotels",        parent: categories[:travel]),
  flights:     household.categories.find_or_create_by!(name: "Flights",       parent: categories[:travel])
}
puts "  #{categories.size} categories + #{sub.size} subcategories"

# ── Merchants + rules ─────────────────────────────────────────────────────────

merchant_defs = [
  { name: "Starbucks",          category: sub[:coffee],      pattern: "STARBUCKS" },
  { name: "Blue Bottle Coffee", category: sub[:coffee],      pattern: "BLUE BOTTLE" },
  { name: "Chipotle",           category: sub[:fast_food],   pattern: "CHIPOTLE" },
  { name: "McDonald's",         category: sub[:fast_food],   pattern: "MCDONALD" },
  { name: "Whole Foods",        category: categories[:groceries],  pattern: "WHOLE FOODS" },
  { name: "Trader Joe's",       category: categories[:groceries],  pattern: "TRADER JOE" },
  { name: "Safeway",            category: categories[:groceries],  pattern: "SAFEWAY" },
  { name: "Costco",             category: categories[:groceries],  pattern: "COSTCO" },
  { name: "Uber",               category: categories[:transport],  pattern: "UBER \\*TRIP" },
  { name: "Lyft",               category: categories[:transport],  pattern: "LYFT" },
  { name: "Shell",              category: sub[:gas],         pattern: "SHELL" },
  { name: "Chevron",            category: sub[:gas],         pattern: "CHEVRON" },
  { name: "United Airlines",    category: sub[:flights],     pattern: "UNITED" },
  { name: "Delta Air Lines",    category: sub[:flights],     pattern: "DELTA" },
  { name: "Southwest Airlines", category: sub[:flights],     pattern: "SOUTHWEST" },
  { name: "Marriott",           category: sub[:hotels],      pattern: "MARRIOTT" },
  { name: "Hilton",             category: sub[:hotels],      pattern: "HILTON" },
  { name: "Netflix",            category: categories[:subscriptions], pattern: "NETFLIX" },
  { name: "Spotify",            category: categories[:subscriptions], pattern: "SPOTIFY" },
  { name: "Apple",              category: categories[:subscriptions], pattern: "APPLE\\.COM" },
  { name: "Adobe",              category: categories[:subscriptions], pattern: "ADOBE" },
  { name: "Amazon",             category: categories[:shopping],      pattern: "AMAZON" },
  { name: "REI",                category: categories[:shopping],      pattern: "REI #" },
  { name: "Target",             category: categories[:shopping],      pattern: "TARGET" },
  { name: "Macy's",             category: sub[:clothing],    pattern: "MACY" },
  { name: "Best Buy",           category: sub[:electronics], pattern: "BEST BUY" },
  { name: "Apple Store",        category: sub[:electronics], pattern: "APPLE STORE" },
  { name: "Equinox",            category: sub[:gym],         pattern: "EQUINOX" },
  { name: "CVS",                category: sub[:pharmacy],    pattern: "CVS" },
  { name: "Walgreens",          category: sub[:pharmacy],    pattern: "WALGREENS" },
  { name: "PG&E",               category: categories[:utilities], pattern: "PG&E|PACIFIC GAS" },
  { name: "Comcast",            category: categories[:utilities], pattern: "COMCAST" },
  { name: "AMC Theatres",       category: categories[:entertainment], pattern: "AMC " },
  { name: "Ticketmaster",       category: categories[:entertainment], pattern: "TICKETMASTER" },
  { name: "Employer Payroll",   category: categories[:income], pattern: "PAYROLL|DIRECT DEP" }
]

merchants = {}
merchant_defs.each do |defn|
  cat = defn[:category]
  m = household.merchants.find_or_create_by!(name: defn[:name]) { |r| r.category = cat }
  m.update!(category: cat) if m.category_id != cat.id
  household.merchant_rules.find_or_create_by!(merchant: m, pattern: defn[:pattern]) { |r| r.priority = 0 }
  merchants[defn[:name]] = m
end
puts "  #{merchants.size} merchants with rules"

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = %w[business personal joint reimbursable recurring].map do |name|
  household.tags.find_or_create_by!(name: name)
end
tag_map = tags.index_by(&:name)
puts "  #{tags.size} tags"

# ── Brokers + Accounts ────────────────────────────────────────────────────────

fidelity = household.brokers.find_or_create_by!(name: "Fidelity")
schwab   = household.brokers.find_or_create_by!(name: "Charles Schwab")
chase    = household.brokers.find_or_create_by!(name: "Chase")

inv_account = household.accounts.find_or_create_by!(broker: fidelity, account_number: "****1234") do |a|
  a.name = "Fidelity Brokerage"; a.account_type = "Invt Mgmt"
end
ira_account = household.accounts.find_or_create_by!(broker: fidelity, account_number: "****5678") do |a|
  a.name = "Fidelity IRA"; a.account_type = "IRA"
end
schwab_acct = household.accounts.find_or_create_by!(broker: schwab, account_number: "****9012") do |a|
  a.name = "Schwab Brokerage"; a.account_type = "Invt Mgmt"
end
checking    = household.accounts.find_or_create_by!(broker: chase, account_number: "****3456") do |a|
  a.name = "Chase Checking"; a.account_type = "Checking"
end
credit_card = household.accounts.find_or_create_by!(broker: chase, account_number: "****7890") do |a|
  a.name = "Chase Sapphire"; a.account_type = "Credit Card"
end
puts "  #{Account.count} accounts across #{Broker.count} brokers"

# ── Transaction Types ─────────────────────────────────────────────────────────

tts = {
  "Purchase"         => TransactionType.find_or_create_by!(code: "BUY")  { |t| t.code_description = "Bought";           t.category = "Purchase" },
  "Sale"             => TransactionType.find_or_create_by!(code: "SELL") { |t| t.code_description = "Sold";             t.category = "Sale" },
  "Dividend"         => TransactionType.find_or_create_by!(code: "DIV")  { |t| t.code_description = "Dividend";         t.category = "Dividend" },
  "Foreign Dividend" => TransactionType.find_or_create_by!(code: "FDIV") { |t| t.code_description = "Foreign Dividend"; t.category = "Foreign Dividend" },
  "Interest"         => TransactionType.find_or_create_by!(code: "INT")  { |t| t.code_description = "Interest";         t.category = "Interest" },
  "Fees"             => TransactionType.find_or_create_by!(code: "FEE")  { |t| t.code_description = "Advisory Fee";     t.category = "Fees" },
  "Transfer In"      => TransactionType.find_or_create_by!(code: "XFER-IN")  { |t| t.code_description = "Crypto transfer in";  t.category = "Transfer In" },
  "Transfer Out"     => TransactionType.find_or_create_by!(code: "XFER-OUT") { |t| t.code_description = "Crypto transfer out"; t.category = "Transfer Out" },
  "Gas"              => TransactionType.find_or_create_by!(code: "GAS")      { |t| t.code_description = "Network fees";        t.category = "Transfer Out" }
}
puts "  #{tts.size} transaction types"

# ── Securities ────────────────────────────────────────────────────────────────

security_defs = [
  { ticker: "AAPL",  name: "Apple Inc.",               cusip: "037833100", security_type: "Common Stock" },
  { ticker: "MSFT",  name: "Microsoft Corporation",    cusip: "594918104", security_type: "Common Stock" },
  { ticker: "GOOGL", name: "Alphabet Inc.",             cusip: "02079K305", security_type: "Common Stock" },
  { ticker: "AMZN",  name: "Amazon.com Inc.",           cusip: "023135106", security_type: "Common Stock" },
  { ticker: "NVDA",  name: "NVIDIA Corporation",        cusip: "67066G104", security_type: "Common Stock" },
  { ticker: "VTI",   name: "Vanguard Total Market ETF", cusip: "922908769", security_type: "ETF" },
  { ticker: "VXUS",  name: "Vanguard Total Intl ETF",   cusip: "921943858", security_type: "ETF" },
  { ticker: "BND",   name: "Vanguard Total Bond ETF",   cusip: "921937835", security_type: "ETF" },
  { ticker: "QQQ",   name: "Invesco QQQ Trust",         cusip: "46090E103", security_type: "ETF" }
]

securities = security_defs.map do |d|
  Security.find_or_create_by!(ticker: d[:ticker]) do |s|
    s.name = d[:name]; s.cusip = d[:cusip]; s.security_type = d[:security_type]
  end
end
puts "  #{securities.size} securities"

# ── Market Prices ─────────────────────────────────────────────────────────────

price_seeds = {
  "AAPL"  => { start: 175.0, drift: 0.12 }, "MSFT"  => { start: 380.0, drift: 0.15 },
  "GOOGL" => { start: 140.0, drift: 0.10 }, "AMZN"  => { start: 175.0, drift: 0.13 },
  "NVDA"  => { start: 500.0, drift: 0.40 }, "VTI"   => { start: 225.0, drift: 0.11 },
  "VXUS"  => { start: 58.0,  drift: 0.06 }, "BND"   => { start: 74.0,  drift: 0.02 },
  "QQQ"   => { start: 390.0, drift: 0.18 }
}

price_count = 0
securities.each do |sec|
  seed_data = price_seeds[sec.ticker]; next unless seed_data
  price = seed_data[:start]; daily_drift = seed_data[:drift] / 252.0

  (13 * 21).times do |i|
    date = 13.months.ago.beginning_of_month.to_date + i.days
    next if date > Date.current || date.saturday? || date.sunday?
    price *= (1 + daily_drift + rand(-0.015..0.015))
    MarketPrice.find_or_create_by!(security: sec, date: date) do |mp|
      mp.open  = (price * rand(0.995..1.005)).round(2)
      mp.high  = (price * rand(1.001..1.012)).round(2)
      mp.low   = (price * rand(0.988..0.999)).round(2)
      mp.close = price.round(2)
    end
    price_count += 1
  end
end
puts "  #{price_count} market prices"

# ── Investment Transactions ───────────────────────────────────────────────────

inv_tx_count = 0

[
  { sec: "VTI",   qty: 10, acct: inv_account,  months_ago: 24 },
  { sec: "VXUS",  qty: 20, acct: inv_account,  months_ago: 22 },
  { sec: "BND",   qty: 15, acct: inv_account,  months_ago: 20 },
  { sec: "AAPL",  qty: 5,  acct: inv_account,  months_ago: 18 },
  { sec: "MSFT",  qty: 3,  acct: inv_account,  months_ago: 16 },
  { sec: "NVDA",  qty: 4,  acct: schwab_acct,  months_ago: 15 },
  { sec: "VTI",   qty: 8,  acct: ira_account,  months_ago: 14 },
  { sec: "QQQ",   qty: 3,  acct: schwab_acct,  months_ago: 12 },
  { sec: "GOOGL", qty: 4,  acct: inv_account,  months_ago: 10 },
  { sec: "AAPL",  qty: 3,  acct: ira_account,  months_ago: 8  },
  { sec: "AMZN",  qty: 2,  acct: inv_account,  months_ago: 6  },
  { sec: "NVDA",  qty: 2,  acct: schwab_acct,  months_ago: 5  },
  { sec: "VTI",   qty: 5,  acct: inv_account,  months_ago: 3  },
  { sec: "MSFT",  qty: 2,  acct: ira_account,  months_ago: 2  },
  { sec: "BND",   qty: 10, acct: ira_account,  months_ago: 1  }
].each do |b|
  sec   = securities.find { |s| s.ticker == b[:sec] }
  price = MarketPrice.where(security: sec).order(:date).last&.close || 100.0
  cost  = -(price * b[:qty]).round(2)
  date  = (b[:months_ago].months.ago + rand(0..15).days).to_date

  household.investment_transactions.find_or_create_by!(source_row_hash: hash_for("buy", b[:sec], date, b[:acct].id)) do |t|
    t.account = b[:acct]; t.security = sec; t.transaction_type = tts["Purchase"]
    t.trade_date = date; t.quantity = b[:qty]; t.price_usd = price
    t.cost_usd = cost; t.amount_usd = cost; t.description = "Bought #{b[:qty]} #{b[:sec]}"
  end
  inv_tx_count += 1
end

[
  { sec: "NVDA", qty: 2, acct: schwab_acct, months_ago: 3, gl_long: 420.0 },
  { sec: "AAPL", qty: 2, acct: inv_account, months_ago: 5, gl_long: 85.0  },
  { sec: "GOOGL", qty: 1, acct: inv_account, months_ago: 4, gl_short: 40.0 }
].each do |s|
  sec      = securities.find { |sec| sec.ticker == s[:sec] }
  price    = MarketPrice.where(security: sec).order(:date).last&.close || 100.0
  proceeds = (price * s[:qty]).round(2)
  date     = (s[:months_ago].months.ago + rand(0..10).days).to_date

  household.investment_transactions.find_or_create_by!(source_row_hash: hash_for("sell", s[:sec], date, s[:acct].id)) do |t|
    t.account = s[:acct]; t.security = sec; t.transaction_type = tts["Sale"]
    t.trade_date = date; t.quantity = -s[:qty]; t.price_usd = price
    t.amount_usd = proceeds; t.gl_short_usd = s[:gl_short] || 0; t.gl_long_usd = s[:gl_long] || 0
    t.description = "Sold #{s[:qty]} #{s[:sec]}"
  end
  inv_tx_count += 1
end

div_amounts = { "AAPL" => 23.0, "MSFT" => 18.0, "VTI" => 42.0, "VXUS" => 28.0, "BND" => 35.0, "QQQ" => 12.0 }
8.times do |quarter|
  date = (quarter * 3).months.ago.beginning_of_month.to_date + 14.days
  next if date > Date.current
  div_amounts.each do |ticker, base|
    sec  = securities.find { |s| s.ticker == ticker }
    acct = [ inv_account, ira_account, schwab_acct ].sample
    household.investment_transactions.find_or_create_by!(source_row_hash: hash_for("div", ticker, date, acct.id)) do |t|
      t.account = acct; t.security = sec; t.transaction_type = tts["Dividend"]
      t.trade_date = date; t.income_usd = (base + rand(-5.0..5.0)).round(2)
      t.amount_usd = t.income_usd; t.description = "#{sec.name} Dividend"
    end
    inv_tx_count += 1
  end
end
puts "  #{inv_tx_count} investment transactions"

# ── Position Snapshots ────────────────────────────────────────────────────────

snap_date = Date.current - 1.day
[
  { sec: "VTI",   qty: 23, acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 4800.0 },
  { sec: "VXUS",  qty: 20, acct: inv_account,  asset_class: "International",   cost_basis: 1150.0 },
  { sec: "BND",   qty: 15, acct: inv_account,  asset_class: "Fixed Income",    cost_basis: 1080.0 },
  { sec: "AAPL",  qty: 6,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 900.0  },
  { sec: "MSFT",  qty: 5,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 1750.0 },
  { sec: "GOOGL", qty: 3,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 400.0  },
  { sec: "AMZN",  qty: 2,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 340.0  },
  { sec: "NVDA",  qty: 4,  acct: schwab_acct,  asset_class: "Domestic Equity", cost_basis: 1950.0 },
  { sec: "QQQ",   qty: 3,  acct: schwab_acct,  asset_class: "Domestic Equity", cost_basis: 1140.0 },
  { sec: "VTI",   qty: 8,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 1680.0 },
  { sec: "AAPL",  qty: 3,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 440.0  },
  { sec: "MSFT",  qty: 2,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 690.0  },
  { sec: "BND",   qty: 10, acct: ira_account,  asset_class: "Fixed Income",    cost_basis: 730.0  }
].each do |h|
  sec  = securities.find { |s| s.ticker == h[:sec] }
  close = MarketPrice.where(security: sec).order(:date).last&.close || 100.0
  mval  = (close * h[:qty]).round(2)
  household.position_snapshots.find_or_create_by!(source_row_hash: hash_for("snap", h[:sec], snap_date, h[:acct].id)) do |s|
    s.account = h[:acct]; s.security = sec; s.as_of_date = snap_date
    s.quantity = h[:qty]; s.price = close; s.market_value = mval
    s.cost_basis = h[:cost_basis]; s.unrealized_gain_loss = (mval - h[:cost_basis]).round(2)
    s.asset_class = h[:asset_class]; s.est_annual_income = (mval * 0.015).round(2)
    s.dividend_yield = 1.5
  end
end
# Historical monthly snapshots — last 13 months so portfolio chart has a full year
historical_positions = [
  { sec: "VTI",   qty: 23, acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 4800.0 },
  { sec: "VXUS",  qty: 20, acct: inv_account,  asset_class: "International",   cost_basis: 1150.0 },
  { sec: "BND",   qty: 25, acct: inv_account,  asset_class: "Fixed Income",    cost_basis: 1810.0 },
  { sec: "AAPL",  qty: 9,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 1340.0 },
  { sec: "MSFT",  qty: 7,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 2440.0 },
  { sec: "GOOGL", qty: 3,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 400.0  },
  { sec: "AMZN",  qty: 2,  acct: inv_account,  asset_class: "Domestic Equity", cost_basis: 340.0  },
  { sec: "NVDA",  qty: 6,  acct: schwab_acct,  asset_class: "Domestic Equity", cost_basis: 2970.0 },
  { sec: "QQQ",   qty: 3,  acct: schwab_acct,  asset_class: "Domestic Equity", cost_basis: 1140.0 },
  { sec: "VTI",   qty: 8,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 1680.0 },
  { sec: "AAPL",  qty: 3,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 440.0  },
  { sec: "MSFT",  qty: 2,  acct: ira_account,  asset_class: "Domestic Equity", cost_basis: 690.0  },
  { sec: "BND",   qty: 10, acct: ira_account,  asset_class: "Fixed Income",    cost_basis: 730.0  }
]

hist_snap_count = 0
13.times do |months_ago|
  next if months_ago == 0  # skip today — already covered by the current snapshot above
  as_of = (months_ago.months.ago.end_of_month).to_date
  as_of = [ as_of, Date.current - 1.day ].min

  historical_positions.each do |h|
    sec   = securities.find { |s| s.ticker == h[:sec] }
    price = MarketPrice.where(security: sec).where("date <= ?", as_of).order(:date).last&.close
    next unless price

    mval = (price * h[:qty]).round(2)
    household.position_snapshots.find_or_create_by!(source_row_hash: hash_for("hist-snap", h[:sec], as_of, h[:acct].id)) do |s|
      s.account = h[:acct]; s.security = sec; s.as_of_date = as_of
      s.quantity = h[:qty]; s.price = price; s.market_value = mval
      s.cost_basis = h[:cost_basis]; s.unrealized_gain_loss = (mval - h[:cost_basis]).round(2)
      s.asset_class = h[:asset_class]; s.est_annual_income = (mval * 0.015).round(2)
      s.dividend_yield = 1.5
    end
    hist_snap_count += 1
  end
end
puts "  #{PositionSnapshot.count} position snapshots (#{hist_snap_count} historical)"

# ── Cash Transactions ─────────────────────────────────────────────────────────

cc_tx_count   = 0
bank_tx_count = 0

# Credit card spending — 24 months of history with seasonal variation
#  [ description_variants, base_range, cat_key, merchant_name, base_freq, peak_months ]
cc_spending = [
  # Coffee — year-round but higher in colder months
  [ [ "STARBUCKS #4521 SAN FRANCISCO CA", "STARBUCKS #0832 SF CA", "STARBUCKS DRIVE THRU" ],
    -9..-4, sub[:coffee], "Starbucks", 14, [ 11, 12, 1, 2, 3 ] ],

  [ [ "BLUE BOTTLE COFFEE HAYES VALLEY", "BLUE BOTTLE COFFEE SFJFK" ],
    -7..-4, sub[:coffee], "Blue Bottle Coffee", 4, [ 11, 12, 1, 2 ] ],

  # Fast food — steady
  [ [ "CHIPOTLE ONLINE ORDER", "CHIPOTLE MEXICAN GRILL #1234" ],
    -15..-10, sub[:fast_food], "Chipotle", 6, [ 5, 6, 7, 8 ] ],

  [ [ "MCDONALD'S F23456", "MCDONALD'S #8765 SAN FRANCISCO" ],
    -12..-6, sub[:fast_food], "McDonald's", 3, [ 6, 7, 8 ] ],

  # Groceries — higher in summer (more cooking/entertaining)
  [ [ "WHOLE FOODS MARKET #0987", "WHOLE FOODS MKT POTRERO" ],
    -140..-65, categories[:groceries], "Whole Foods", 4, [ 6, 7, 8, 11, 12 ] ],

  [ [ "TRADER JOE'S #123", "TRADER JOE'S #456 SAN FRANCISCO" ],
    -85..-40, categories[:groceries], "Trader Joe's", 4, [ 6, 7, 8 ] ],

  [ [ "SAFEWAY #0987 SAN FRANCISCO CA", "SAFEWAY #1234" ],
    -95..-40, categories[:groceries], "Safeway", 3, [ 1, 2, 3 ] ],

  [ [ "COSTCO WHSE #1234", "COSTCO GAS #1234" ],
    -180..-90, categories[:groceries], "Costco", 2, [ 11, 12 ] ],

  # Transport — steady
  [ [ "UBER *TRIP HELP.UBER.COM", "UBER* TRIP" ],
    -28..-8, categories[:transport], "Uber", 8, [ 6, 7, 8 ] ],

  [ [ "LYFT *RIDE SAN FRANCISCO", "LYFT *1RIDE" ],
    -22..-8, categories[:transport], "Lyft", 4, [ 6, 7, 8 ] ],

  [ [ "SHELL OIL 12345678 SAN FRANCISCO", "SHELL SERVICE STATION" ],
    -65..-40, sub[:gas], "Shell", 3, [ 6, 7, 8 ] ],

  [ [ "CHEVRON 0094817 SAN FRANCISCO CA" ],
    -60..-38, sub[:gas], "Chevron", 2, [ 6, 7, 8 ] ],

  # Shopping — peak in November/December holidays
  [ [ "AMAZON.COM*1A2B3C4D5", "AMZN MKTP US*2B3C4D5E", "AMAZON.COM*AMZN" ],
    -75..-18, categories[:shopping], "Amazon", 6, [ 11, 12 ] ],

  [ [ "TARGET 00123 SAN FRANCISCO CA", "TARGET T- 1234567" ],
    -95..-25, categories[:shopping], "Target", 4, [ 11, 12, 1 ] ],

  [ [ "MACY'S #0123", "MACYS COM" ],
    -120..-40, sub[:clothing], "Macy's", 1, [ 11, 12 ] ],

  [ [ "BEST BUY #1234 SAN FRANCISCO CA" ],
    -180..-60, sub[:electronics], "Best Buy", 1, [ 11, 12 ] ],

  [ [ "REI #42 SAN FRANCISCO CA", "REI CO-OP #0042" ],
    -135..-35, categories[:shopping], "REI", 1, [ 3, 4, 5, 6 ] ],

  # Subscriptions — flat monthly
  [ [ "APPLE.COM/BILL" ],   -15..-15, categories[:subscriptions], "Apple",   1, [] ],
  [ [ "NETFLIX.COM" ],      -17..-17, categories[:subscriptions], "Netflix", 1, [] ],
  [ [ "SPOTIFY USA" ],      -11..-11, categories[:subscriptions], "Spotify", 1, [] ],
  [ [ "ADOBE CREATIVE CL", "ADOBE SYSTEMS INC" ], -60..-55, categories[:subscriptions], "Adobe", 1, [] ],

  # Health — gym higher in Jan (new year), pharmacy higher in winter
  [ [ "EQUINOX SAN FRANCISCO", "EQUINOX FITNESS" ],
    -185..-175, sub[:gym], "Equinox", 1, [] ],

  [ [ "CVS PHARMACY #8765", "CVS/PHARMACY #01234" ],
    -40..-8, sub[:pharmacy], "CVS", 3, [ 11, 12, 1, 2 ] ],

  [ [ "WALGREENS #12345", "WALGREENS DRUG STORE" ],
    -35..-8, sub[:pharmacy], "Walgreens", 2, [ 11, 12, 1, 2 ] ],

  # Entertainment — higher summer + holiday season
  [ [ "AMC THEATRES #0341", "AMC DINE-IN #0123" ],
    -28..-14, categories[:entertainment], "AMC Theatres", 2, [ 6, 7, 8, 12 ] ],

  [ [ "TICKETMASTER*CONCERT", "TICKETMASTER* EVENT" ],
    -150..-40, categories[:entertainment], "Ticketmaster", 1, [ 5, 6, 7, 8 ] ],

  # Utilities — flat
  [ [ "COMCAST CALIFORNIA" ],
    -88..-88, categories[:utilities], "Comcast", 1, [] ]
]

# Travel — seasonal: summer + winter holidays only
travel_trips = [
  # Summer trips
  { descs: [ "UNITED AIRLINES 016-1234567", "UNITED 016 TICKET" ],
    merchant: "United Airlines", months_ago: 3,  amount_range: -450..-280 },
  { descs: [ "DELTA AIR LINES ATLANTA GA", "DELTA 006 TICKET" ],
    merchant: "Delta Air Lines", months_ago: 3,  amount_range: -390..-220 },
  { descs: [ "MARRIOTT SAN DIEGO CA", "MARRIOTT HOTELS" ],
    merchant: "Marriott",        months_ago: 3,  amount_range: -680..-320 },
  # Winter holiday travel
  { descs: [ "SOUTHWEST AIRLINES", "SOUTHWEST 526 TICKET" ],
    merchant: "Southwest Airlines", months_ago: 5, amount_range: -310..-180 },
  { descs: [ "HILTON CHICAGO IL", "HILTON HOTEL" ],
    merchant: "Hilton",          months_ago: 5,  amount_range: -520..-280 },
  # Prior year summer
  { descs: [ "DELTA AIR LINES SFO", "DELTA 006 TICKET" ],
    merchant: "Delta Air Lines", months_ago: 15, amount_range: -420..-240 },
  { descs: [ "MARRIOTT HAWAII", "MARRIOTT WAIKIKI" ],
    merchant: "Marriott",        months_ago: 14, amount_range: -1200..-800 },
  # Prior year winter
  { descs: [ "UNITED AIRLINES 016-9876543" ],
    merchant: "United Airlines", months_ago: 17, amount_range: -480..-280 }
]

travel_trips.each do |trip|
  date = (trip[:months_ago].months.ago + rand(0..12).days).to_date
  desc = trip[:descs].sample
  merchant = merchants[trip[:merchant]]
  cat = merchant&.category
  household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("travel", desc, trip[:months_ago])) do |t|
    t.source = "credit_card"; t.transaction_date = date; t.post_date = date + rand(1..3).days
    t.description = desc; t.amount = rand(trip[:amount_range]).to_f
    t.transaction_type = "Sale"; t.category = cat; t.merchant = merchant; t.account = credit_card
  end
  cc_tx_count += 1
end

# Unrecognized transactions — no merchant or category (as if rules haven't matched them)
unrecognized = [
  [ "FOG CITY DINER SF CA",      -45..-22,  "Sale" ],
  [ "ZAZIE BISTRO #4521",         -65..-38,  "Sale" ],
  [ "PHILZ COFFEE #0832",         -8..-4,    "Sale" ],
  [ "BOBA GUYS 123 MISSION",      -9..-5,    "Sale" ],
  [ "NOPA RESTAURANT SF",         -95..-48,  "Sale" ],
  [ "LOCAL CORNER MARKET",        -32..-14,  "Sale" ],
  [ "PARK GROCERY & DELI",        -45..-18,  "Sale" ],
  [ "SF FARMERS MARKET",          -55..-20,  "Sale" ],
  [ "CLIPPER CARD AUTOLOAD",      -50..-50,  "Debit" ],
  [ "BART CLIPPER SFO",           -12..-3,   "Sale" ],
  [ "PARKING GARAGE DOWNTOWN SF", -35..-12,  "Sale" ],
  [ "SFMTA METER PAYMENT",        -8..-2,    "Sale" ],
  [ "URBAN OUTFITTERS #0042",     -85..-30,  "Sale" ],
  [ "AESOP 1234 HAYES ST",        -55..-28,  "Sale" ],
  [ "BOOK INC SAN FRANCISCO",     -28..-12,  "Sale" ],
  [ "ACE HARDWARE #4321",         -45..-15,  "Sale" ],
  [ "ANNUAL MEMBERSHIP FEE",      -99..-99,  "Sale" ],
  [ "ONLINE TRANSFER OUT",        -500..-200, "Debit" ],
  [ "MISC VENDOR 00123",          -38..-12,  "Sale" ],
  [ "SQUARE *FOOD TRUCK",         -18..-6,   "Sale" ]
]

24.times do |months_ago|
  # 3-5 unrecognized transactions per month
  rand(3..5).times do
    row = unrecognized.sample
    desc, range, type = row
    date = (months_ago.months.ago.beginning_of_month.to_date + rand(0..27).days)
    next if date > Date.current

    household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("unrec", desc, months_ago, rand(9999))) do |t|
      t.source = "credit_card"; t.transaction_date = date; t.post_date = date + rand(1..3).days
      t.description = desc; t.amount = rand(range).to_f; t.transaction_type = type; t.account = credit_card
      # Intentionally no merchant or category set
    end
    cc_tx_count += 1
  end
end

# Main spending loop — 24 months with seasonal variation
24.times do |months_ago|
  cc_spending.each do |descs, amount_range, cat_or_sub, merchant_name, base_freq, peak_months|
    multiplier = peak_months.empty? ? 1.0 : seasonal(months_ago.months.ago.to_date, peak_months: peak_months)
    freq = [ 1, (base_freq * multiplier).round ].max

    freq.times do
      date = (months_ago.months.ago.beginning_of_month.to_date + rand(0..26).days)
      next if date > Date.current

      desc = descs.is_a?(Array) ? descs.sample : descs
      household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("cc", desc, months_ago, rand(9999))) do |t|
        t.source = "credit_card"; t.transaction_date = date; t.post_date = date + rand(1..3).days
        t.description = desc; t.amount = rand(amount_range).to_f; t.transaction_type = "Sale"
        t.category = cat_or_sub; t.merchant = merchants[merchant_name]; t.account = credit_card
      end
      cc_tx_count += 1
    end
  end

  # Occasional returns/refunds (about once every other month)
  if rand < 0.5
    return_descs = [
      [ "AMAZON.COM REFUND", categories[:shopping], "Amazon" ],
      [ "TARGET RETURN", categories[:shopping], "Target" ],
      [ "COSTCO RETURN", categories[:groceries], "Costco" ],
      [ "REI RETURN", categories[:shopping], "REI" ],
      [ "APPLE.COM REFUND", categories[:subscriptions], "Apple" ]
    ]
    ret = return_descs.sample
    date = (months_ago.months.ago.beginning_of_month.to_date + rand(0..26).days)
    if date <= Date.current
      household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("return", ret[0], months_ago)) do |t|
        t.source = "credit_card"; t.transaction_date = date
        t.description = ret[0]; t.amount = rand(15..80).to_f; t.transaction_type = "Return"
        t.category = ret[1]; t.merchant = merchants[ret[2]]; t.account = credit_card
      end
      cc_tx_count += 1
    end
  end
end

# Larger annual / irregular purchases
[
  { desc: "APPLE STORE SAN FRANCISCO", amount: -1299.0, merchant: "Apple Store",  cat: sub[:electronics], months_ago: 8  },
  { desc: "BEST BUY ONLINE",           amount: -849.0,  merchant: "Best Buy",     cat: sub[:electronics], months_ago: 14 },
  { desc: "REI CO-OP ANNUAL DIVIDEND", amount: 45.0,    merchant: "REI",          cat: categories[:income], months_ago: 4, type: "Return" },
  { desc: "TICKETMASTER* SF GIANTS",   amount: -220.0,  merchant: "Ticketmaster", cat: categories[:entertainment], months_ago: 6 },
  { desc: "TICKETMASTER* CONCERT SF",  amount: -175.0,  merchant: "Ticketmaster", cat: categories[:entertainment], months_ago: 18 },
  { desc: "AMAZON ANNUAL PRIME",       amount: -139.0,  merchant: "Amazon",       cat: categories[:subscriptions], months_ago: 10 },
  { desc: "MACY'S HOLIDAY SALE",       amount: -380.0,  merchant: "Macy's",       cat: sub[:clothing], months_ago: 5 }
].each do |p|
  date = (p[:months_ago].months.ago + rand(0..10).days).to_date
  household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("oneoff", p[:desc], p[:months_ago])) do |t|
    t.source = "credit_card"; t.transaction_date = date
    t.description = p[:desc]; t.amount = p[:amount]; t.transaction_type = p[:type] || "Sale"
    t.category = p[:cat]; t.merchant = merchants[p[:merchant]]; t.account = credit_card
  end
  cc_tx_count += 1
end

# Credit card payments. The amount of each is kept so the bank-side autopay
# debit below can mirror it — a payment only pairs when the two legs agree to
# the cent, and demo data with no linked pairs shows nothing of the
# credit-card payments feature.
cc_payment_amounts = {}
8.times do |i|
  date = (i * 3).months.ago.beginning_of_month.to_date + 15.days
  payment = household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("cc-payment", date)) do |t|
    t.source = "credit_card"; t.transaction_date = date
    t.description = "AUTOPAY PAYMENT THANK YOU"; t.amount = rand(1400..3200).to_f
    t.transaction_type = "Payment"; t.account = credit_card
  end
  cc_payment_amounts[date.beginning_of_month] = payment.amount.to_f
  cc_tx_count += 1
end

# Bank transactions — 24 months of payroll, rent, bills
balance = 22_500.0

24.times do |months_ago|
  base_date = Date.current - months_ago.months

  [ 1, 15 ].each do |day|
    pay_date = Date.new(base_date.year, base_date.month, day)
    next if pay_date > Date.current
    balance += 4800.0
    household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("payroll", pay_date)) do |t|
      t.source = "bank"; t.transaction_date = pay_date
      t.description = "EMPLOYER PAYROLL DIRECT DEP"; t.amount = 4800.0
      t.transaction_type = "Credit"; t.category = categories[:income]
      t.merchant = merchants["Employer Payroll"]; t.account = checking; t.balance = balance.round(2)
    end
    bank_tx_count += 1
  end

  rent_date = Date.new(base_date.year, base_date.month, 1)
  next if rent_date > Date.current
  balance -= 2800.0
  household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("rent", rent_date)) do |t|
    t.source = "bank"; t.transaction_date = rent_date
    t.description = "ONLINE PAYMENT RENT"; t.amount = -2800.0
    t.transaction_type = "Debit"; t.category = categories[:utilities]
    t.account = checking; t.balance = balance.round(2)
  end
  bank_tx_count += 1

  # PG&E — higher in summer/winter (AC/heating)
  pge_date   = Date.new(base_date.year, base_date.month, 8)
  base_pge   = [ 6, 7, 8, 12, 1, 2 ].include?(pge_date.month) ? rand(140..220) : rand(70..110)
  balance   -= base_pge.to_f
  household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("pge", pge_date)) do |t|
    t.source = "bank"; t.transaction_date = pge_date
    t.description = "PG&E ELECTRIC PAYMENT"; t.amount = -base_pge.to_f
    t.transaction_type = "Debit"; t.category = categories[:utilities]
    t.merchant = merchants["PG&E"]; t.account = checking; t.balance = balance.round(2)
  end
  bank_tx_count += 1

  # Quarters with a card-side payment reuse its amount so the pair links
  # (the 16th and the 18th are inside the 4-day candidate window); the other
  # months stay unpaired, which is also what real statements look like.
  cc_date   = Date.new(base_date.year, base_date.month, 18)
  cc_amount = cc_payment_amounts[cc_date.beginning_of_month] || rand(1400..3200).to_f
  balance  -= cc_amount
  household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("cc-autopay-bank", cc_date)) do |t|
    t.source = "bank"; t.transaction_date = cc_date
    t.description = "CHASE CREDIT CARD AUTOPAY"; t.amount = -cc_amount
    t.transaction_type = "Debit"; t.account = checking; t.balance = balance.round(2)
  end
  bank_tx_count += 1

  # Occasional Zelle / transfers / misc bank debits (no category)
  if rand < 0.4
    zelle_date = Date.new(base_date.year, base_date.month, rand(2..27))
    next if zelle_date > Date.current
    balance -= 150.0
    household.cash_transactions.find_or_create_by!(source_row_hash: hash_for("zelle", zelle_date, months_ago)) do |t|
      t.source = "bank"; t.transaction_date = zelle_date
      t.description = [ "ZELLE PAYMENT TO FRIEND", "VENMO CASHOUT", "TRANSFER TO SAVINGS" ].sample
      t.amount = -rand(50..300).to_f; t.transaction_type = "Debit"
      t.account = checking; t.balance = balance.round(2)
    end
    bank_tx_count += 1
  end
end

puts "  #{cc_tx_count} credit card transactions"
puts "  #{bank_tx_count} bank transactions"

# ── Apply tags to a sample of transactions ────────────────────────────────────

# Mark subscription transactions as recurring
CashTransaction.joins(:merchant)
               .where(merchants: { name: [ "Netflix", "Spotify", "Apple", "Adobe", "Equinox", "Comcast" ] })
               .limit(60).each do |tx|
  tx.tags << tag_map["recurring"] unless tx.tags.include?(tag_map["recurring"])
end

# Mark travel transactions as personal
CashTransaction.joins(:category)
               .where(categories: { name: "Flights" })
               .limit(20).each do |tx|
  tx.tags << tag_map["personal"] unless tx.tags.include?(tag_map["personal"])
end

# Mark a few transactions as business / reimbursable
CashTransaction.joins(:merchant)
               .where(merchants: { name: [ "Adobe", "Ticketmaster", "United Airlines" ] })
               .order(Arel.sql("RANDOM()")).limit(8).each do |tx|
  tx.tags << tag_map["business"] unless tx.tags.include?(tag_map["business"])
  tx.tags << tag_map["reimbursable"] unless tx.tags.include?(tag_map["reimbursable"])
end

puts "  Tags applied"

# Apply merchant rules to any unmatched transactions
print "  Running merchant rule matching... "
result = Merchants::RuleMatcher.rematch_all
puts "matched #{result[:matched]}, unmatched #{result[:unmatched]}"

# Pair the credit-card autopay legs. Per-row payment probes are suppressed
# during seeding (see db/seeds.rb), so this stands in for the ~2,200
# Transfers::PaymentMatchJob enqueues the same work used to cost — the
# matcher pre-filters, and each pair links on whichever leg probes first.
print "  Matching credit-card payments... "
payment_candidates = CashTransaction.payment_suspects.or(
  CashTransaction.source_credit_card
                 .where("amount > 0")
                 .where(transaction_type: CashTransaction::TransactionType::Payment.serialize)
                 .where(transfer_id: nil)
)
linked = 0
payment_candidates.find_each do |txn|
  linked += 1 if Transfers::PaymentMatcher.new(txn).match!&.confirmed?
end
puts "#{linked} pairs linked"

# ── Summary ───────────────────────────────────────────────────────────────────

puts ""
puts "Done! Fin is seeded with:"
puts "  #{Broker.count} brokers, #{Account.count} accounts"
puts "  #{Security.count} securities, #{MarketPrice.count} market prices"
puts "  #{InvestmentTransaction.count} investment transactions, #{PositionSnapshot.count} position snapshots"
puts "  #{Merchant.count} merchants, #{MerchantRule.count} rules, #{Category.count} categories (#{Category.where.not(parent_id: nil).count} subcategories), #{Tag.count} tags"
puts "  #{CashTransaction.count} cash transactions (#{CashTransaction.source_credit_card.count} CC, #{CashTransaction.source_bank.count} bank)"
puts "  Unmatched: #{CashTransaction.where(merchant_id: nil).count} without merchant, #{CashTransaction.where(category_id: nil).count} without category"
puts ""
puts "  API token (for scripts/integrations): #{DEV_TOKEN}"
puts ""
puts "  Web UI: open /register?invite=#{invite.code} and enroll a passkey"
puts "          for #{user.email} (passkey-only sign-in after enrollment)."
