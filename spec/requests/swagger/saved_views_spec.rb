require "swagger_helper"

RSpec.describe "Saved Views", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  sort = { type: :object, properties: { field: { type: :string }, dir: { type: :string, enum: %w[asc desc] } }, nullable: true }
  view_params = {
    name:           { type: :string },
    conditions:     {
      type: :array,
      items: {
        type: :object,
        properties: { field: { type: :string }, operator: { type: :string }, value: { type: :string } }
      }
    },
    match_all:      { type: :boolean },
    group_by:       { type: :string, nullable: true },
    primary_sort:   sort,
    secondary_sort: sort
  }
  full_view = {
    name: "Big dining", match_all: true, group_by: "month",
    conditions: [ { field: "amount", operator: "less_than", value: "-100" } ],
    primary_sort: { field: "amount", dir: "asc" }, secondary_sort: { field: "date", dir: "desc" }
  }

  path "/api/v1/saved_views" do
    get "List saved views" do
      tags "Saved Views"
      produces "application/json"

      response "200", "saved views listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/SavedView" }
        before { create(:saved_view, filter_params: full_view.except(:name).to_json) }
        run_test! do |response|
          expect(response.parsed_body.first["primary_sort"]).to eq("field" => "amount", "dir" => "asc")
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end

    post "Create a saved view" do
      tags "Saved Views"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: view_params, required: %w[name] }

      response "201", "saved view created" do
        schema "$ref" => "#/components/schemas/SavedView"
        let(:body) { full_view }
        run_test!
      end

      response "400", "name missing" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { conditions: [] } }
        run_test!
      end
    end
  end

  path "/api/v1/saved_views/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Replace a saved view's filters" do
      tags "Saved Views"
      description "Replaces every filter field: omitted ones reset to their defaults. A blank name keeps the current one."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, properties: view_params }

      response "200", "saved view updated" do
        schema "$ref" => "#/components/schemas/SavedView"
        let(:id)   { create(:saved_view).id }
        let(:body) { full_view.merge(name: "Updated view") }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id)   { 0 }
        let(:body) { { name: "x" } }
        run_test!
      end
    end

    delete "Delete a saved view" do
      tags "Saved Views"
      produces "application/json"

      response "204", "saved view deleted" do
        let(:id) { create(:saved_view).id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end
  end
end
