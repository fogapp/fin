require "swagger_helper"

RSpec.describe "Categories & Tags", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── Categories ───────────────────────────────────────────────────────────────

  path "/api/v1/categories" do
    get "List categories" do
      tags "Categories"
      produces "application/json"

      response "200", "categories listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/CategoryWithStats" }
        before { rich_cash_transaction }
        run_test! do |response|
          expect(response.parsed_body.pluck("parent_id").compact).to be_present
        end
      end
    end

    post "Create a category" do
      tags "Categories"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:       { type: :string },
          parent_id:  { type: :string, format: :uuid, nullable: true, description: "Makes this a subcategory (one level deep)" },
          charitable: { type: :boolean }
        },
        required: %w[name]
      }

      response "201", "category created" do
        schema "$ref" => "#/components/schemas/Category"
        let(:body) { { name: "Dining", parent_id: create(:category).id } }
        run_test!
      end

      response "422", "duplicate name" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        before     { create(:category, name: "Dining") }
        let(:body) { { name: "Dining" } }
        run_test!
      end
    end
  end

  path "/api/v1/categories/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a category with spend totals" do
      tags "Categories"
      produces "application/json"
      description "Totals roll up the category's subcategories and use the same spend definition as the cashflow page."

      response "200", "category found" do
        schema "$ref" => "#/components/schemas/CategoryDetail"
        # The rich row is a confirmed transfer leg (out of spend); a plain
        # debit in the same subcategory gives the spend totals something to sum.
        let(:id) do
          txn = rich_cash_transaction
          create(:cash_transaction, :bank, :debit, category: txn.category, merchant: txn.merchant)
          txn.category.parent_id
        end
        run_test! do |response|
          expect(response.parsed_body["subcategories"]).to be_present
          expect(response.parsed_body["by_merchant"]).to be_present
        end
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update a category" do
      tags "Categories"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:        { type: :string },
          parent_id:   { type: :string, format: :uuid, nullable: true },
          budget_kind: { type: :string, enum: %w[fixed flex non_monthly] },
          charitable:  { type: :boolean }
        }
      }

      response "200", "category updated" do
        schema "$ref" => "#/components/schemas/Category"
        let(:id)   { create(:category).id }
        let(:body) { { name: "Groceries", budget_kind: "fixed" } }
        run_test!
      end
    end

    delete "Delete a category" do
      tags "Categories"

      response "204", "category deleted" do
        let(:id) { create(:category).id }
        run_test!
      end
    end
  end

  # ── Tags ─────────────────────────────────────────────────────────────────────

  path "/api/v1/tags" do
    get "List tags with spend totals" do
      tags "Tags"
      produces "application/json"

      response "200", "tags listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/TagWithStats" }
        before { rich_cash_transaction }
        run_test! do |response|
          expect(response.parsed_body.first["transaction_count"]).to eq(1)
        end
      end
    end

    post "Create a tag" do
      tags "Tags"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { name: { type: :string } },
        required: %w[name]
      }

      response "201", "tag created" do
        schema "$ref" => "#/components/schemas/Tag"
        let(:body) { { name: "travel" } }
        run_test!
      end

      response "422", "blank name" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { name: " " } }
        run_test!
      end
    end
  end

  path "/api/v1/tags/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a tag with spend totals" do
      tags "Tags"
      produces "application/json"

      response "200", "tag found" do
        schema "$ref" => "#/components/schemas/TagDetail"
        let(:id) do
          txn = rich_cash_transaction
          tag = txn.tags.first
          create(:cash_transaction, :bank, :debit, category: txn.category).tags << tag
          tag.id
        end
        run_test! do |response|
          expect(response.parsed_body["by_category"]).to be_present
          expect(response.parsed_body["monthly_spend"]).to be_present
        end
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    delete "Delete a tag" do
      tags "Tags"

      response "204", "tag deleted" do
        let(:id) { create(:tag).id }
        run_test!
      end
    end
  end
end
