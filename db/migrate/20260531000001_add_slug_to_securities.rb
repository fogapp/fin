class AddSlugToSecurities < ActiveRecord::Migration[8.1]
  def change
    add_column :securities, :slug, :string
  end
end
