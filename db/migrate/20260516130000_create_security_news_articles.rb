class CreateSecurityNewsArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :security_news_articles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :security, null: false, foreign_key: true, type: :uuid
      t.string  :title,           null: false
      t.string  :url,             null: false
      t.string  :source
      t.datetime :published_at
      t.text    :summary
      t.string  :sentiment
      t.decimal :sentiment_score, precision: 6, scale: 4
      t.timestamps
    end

    add_index :security_news_articles, :url, unique: true
    add_index :security_news_articles, [ :security_id, :published_at ]
  end
end
