# typed: strict

class SecurityNewsSyncer
  extend T::Sig

  KEEP_DAYS = 30

  sig { params(security: Security).void }
  def initialize(security)
    @security = security
    @client   = T.let(AlphaVantage::Client.new, T.untyped)
  end

  sig { returns(Integer) }
  def call
    articles = @client.news_sentiment(@security.ticker, limit: 50)

    articles.each do |a|
      next if a[:url].blank? || a[:title].blank?

      published = parse_time(a[:published_at])

      SecurityNewsArticle.upsert(
        {
          security_id:     @security.id,
          title:           a[:title],
          url:             a[:url],
          source:          a[:source],
          published_at:    published,
          summary:         a[:summary],
          sentiment:       a[:sentiment],
          sentiment_score: a[:sentiment_score]
        },
        unique_by: :url,
        update_only: %i[title source published_at summary sentiment sentiment_score]
      )
    end

    # Prune old articles for this security
    @security.news_articles.where("published_at < ?", KEEP_DAYS.days.ago).delete_all

    articles.length
  end

  private

  sig { params(str: String).returns(T.nilable(Time)) }
  def parse_time(str)
    return nil if str.blank?
    # AlphaVantage format: "20240501T120000"
    DateTime.strptime(str, "%Y%m%dT%H%M%S").utc
  rescue Date::Error, ArgumentError
    nil
  end
end
