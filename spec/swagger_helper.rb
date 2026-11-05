require "rails_helper"
require_relative "openapi/schemas"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Fin API",
        version: "v1",
        description: "Personal finance API — investments, spending, merchant rules, and Plaid sync."
      },
      servers: [ { url: "/", description: "Current host" } ],
      components: {
        securitySchemes: {
          bearerAuth: { type: :http, scheme: :bearer, description: "API token issued from the admin panel" }
        },
        schemas: {
          Error: {
            type: :object,
            properties: { error: { type: :string } },
            required: [ "error" ]
          },
          ValidationErrors: {
            type: :object,
            properties: {
              error:  { type: :string, description: "The first validation message" },
              errors: { type: :array, items: { type: :string } }
            },
            required: %w[error errors]
          },
          Security: {
            type: :object,
            properties: {
              id:            { type: :string, format: :uuid },
              ticker:        { type: :string, nullable: true },
              name:          { type: :string, nullable: true },
              cusip:         { type: :string, nullable: true },
              security_type: { type: :string, nullable: true },
              display_name:  { type: :string }
            },
            required: %w[id display_name]
          },
          Import: {
            type: :object,
            properties: {
              id:                { type: :string, format: :uuid },
              source_filename:   { type: :string },
              status:            { type: :string, enum: %w[pending processing completed failed] },
              kind:              { type: :string, enum: %w[transactions holdings unknown credit_card checking spreadsheet], nullable: true },
              broker_name:       { type: :string, nullable: true },
              target_account_id: { type: :string, format: :uuid, nullable: true },
              imported_count:    { type: :integer, nullable: true },
              skipped_count:     { type: :integer, nullable: true },
              error_count:       { type: :integer, nullable: true },
              error_log:         { type: :string, nullable: true },
              started_at:        { type: :string, format: "date-time", nullable: true },
              finished_at:       { type: :string, format: "date-time", nullable: true },
              created_at:        { type: :string, format: "date-time" }
            },
            required: %w[id source_filename status kind broker_name target_account_id imported_count skipped_count
                         error_count error_log started_at finished_at created_at]
          },
          ImportPreview: {
            type: :object,
            description: "A dry read of a file or sheet: its format, whether it can be imported, and what's wrong if not",
            properties: {
              format:       { type: :string, enum: %w[transactions holdings unknown credit_card checking spreadsheet] },
              format_label: { type: :string },
              ready:        { type: :boolean, description: "Whether importing now would bring in at least one row" },
              headers:      { type: :array, items: { type: :string }, description: "Row 1 as the file has it" },
              row_count:    { type: :integer, description: "Non-blank rows under the header" },
              invalid_row_count: { type: :integer, description: "Rows that won't import (spreadsheet format only)" },
              imports_as:   { type: :string, enum: %w[bank credit_card], nullable: true },
              columns: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    name:     { type: :string },
                    required: { type: :boolean },
                    found:    { type: :string, nullable: true, description: "The header that supplies this column" }
                  },
                  required: %w[name required found]
                }
              },
              suggestions: {
                type: :array,
                items: {
                  type: :object,
                  properties: { from: { type: :string }, to: { type: :string } },
                  required: %w[from to]
                }
              },
              problems: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    row:     { type: :integer, nullable: true, description: "The sheet's row number; null for the file as a whole" },
                    message: { type: :string }
                  },
                  required: %w[row message]
                }
              },
              sample: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    row:         { type: :integer },
                    date:        { type: :string, format: :date, nullable: true },
                    description: { type: :string },
                    amount:      { type: :number },
                    type:        { type: :string }
                  },
                  required: %w[row date description amount type]
                }
              }
            },
            required: %w[format format_label ready headers row_count invalid_row_count imports_as columns suggestions problems sample]
          },
          SpreadsheetFormat: {
            type: :object,
            properties: {
              columns: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    name:        { type: :string },
                    required:    { type: :boolean },
                    description: { type: :string },
                    example:     { type: :string }
                  },
                  required: %w[name required description example]
                }
              },
              split_amount: { type: :string },
              notes:        { type: :array, items: { type: :string } }
            },
            required: %w[columns split_amount notes]
          },
          InvestmentSummary: {
            type: :object,
            properties: {
              totals:  { type: :object, additionalProperties: { type: :number } },
              recent:  { type: :array, items: { type: :object } }
            }
          },
          ApiToken: {
            type: :object,
            properties: {
              id:           { type: :string, format: :uuid },
              name:         { type: :string, nullable: true },
              scope:        { type: :string, enum: %w[full read], description: "full does whatever its user can; read answers GET, HEAD and the MCP tools only" },
              last_used_at: { type: :string, format: "date-time", nullable: true },
              expires_at:   { type: :string, format: "date-time", nullable: true },
              created_at:   { type: :string, format: "date-time" }
            },
            required: %w[id name scope last_used_at expires_at created_at]
          },
          Issue: {
            type: :object,
            properties: {
              id:           { type: :string, format: :uuid },
              key:          { type: :string, nullable: true, description: "Stable dedup key, e.g. reconciliation:<account>:<security>" },
              title:        { type: :string },
              body:         { type: :string, nullable: true },
              severity:     { type: :string, enum: %w[info warning error] },
              source:       { type: :string, nullable: true },
              dismissed_at: { type: :string, format: "date-time", nullable: true },
              created_at:   { type: :string, format: "date-time" }
            },
            required: %w[id key title body severity source dismissed_at created_at]
          },
          Household: {
            type: :object,
            properties: {
              id:     { type: :string, format: :uuid },
              name:   { type: :string },
              role:   { type: :string, enum: %w[admin member] },
              active: { type: :boolean },
              workflow_log_level:      { type: :string, enum: %w[none info debug] },
              include_unvested_equity: { type: :boolean }
            },
            required: %w[id name role active workflow_log_level include_unvested_equity]
          },
          HouseholdMembership: {
            type: :object,
            properties: {
              id:         { type: :string, format: :uuid },
              role:       { type: :string, enum: %w[admin member] },
              created_at: { type: :string, format: "date-time" },
              user:       { "$ref" => "#/components/schemas/SessionUser" }
            },
            required: %w[id role created_at user]
          },
          Invite: {
            type: :object,
            properties: {
              code:       { type: :string },
              role:       { type: :string, enum: %w[admin member] },
              expires_at: { type: :string, format: "date-time", nullable: true },
              created_at: { type: :string, format: "date-time" },
              household: {
                type: :object,
                properties: {
                  id:   { type: :string, format: :uuid },
                  name: { type: :string }
                },
                required: %w[id name]
              }
            },
            required: %w[code role expires_at created_at household]
          }
        }.merge(OpenapiSchemas.all)
      },
      security: [ { bearerAuth: [] } ]
    }
  }

  config.openapi_format = :yaml

  # Fail a swagger spec when a response carries a field its schema doesn't
  # declare — the frontend's types are generated from this document, so
  # undeclared fields are drift, not harmless extras.
  config.openapi_no_additional_properties = true
end
