FactoryBot.define do
  factory :candle do
    security
    sequence(:date) { |n| Date.current - n.days }
    granularity { Candle::GRANULARITY_DAILY }
    open  { 100.0 }
    high  { 105.0 }
    low   { 99.0 }
    close { 102.5 }
    adjusted_close { 102.5 }
    volume { 1_000_000 }
    currency { "USD" }
    source { "alpha_vantage" }
  end

  factory :instrument_quote do
    security
    price { 100.0 }
    currency { "USD" }
    change_pct_24h { 1.5 }
    as_of { Time.current }
    source { "coin_market_cap" }
  end

  factory :corporate_action do
    security
    kind { "dividend" }
    ex_date { Date.current }
    amount { 0.25 }
    currency { "USD" }
    source { "alpha_vantage" }

    trait :split do
      kind { "split" }
      ratio { 4.0 }
      amount { nil }
    end
  end

  factory :security_news_article do
    security
    sequence(:title) { |n| "Market news #{n}" }
    sequence(:url)   { |n| "https://news.example.com/articles/#{n}" }
    source { "Newswire" }
    published_at { Time.current }
    summary { "Something happened in the markets." }
    sentiment { "Neutral" }
    sentiment_score { 0.1 }
  end
end
