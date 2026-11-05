# Instrument lifecycle schemas: conversions the ledger never recorded
# (an ADR line swapped for another, a ticker change, a stock-for-stock
# merger).
module OpenapiSchemas
  module Instruments
    UUID = { type: :string, format: :uuid }.freeze

    OpenapiSchemas.register(
      SecurityConversionSecurity: {
        type: :object,
        properties: {
          id:     UUID,
          ticker: { type: :string, nullable: true },
          name:   { type: :string, nullable: true }
        },
        required: %w[id ticker name]
      },
      SecurityConversionStatus: { type: :string, enum: ::SecurityConversion::Status.values.map(&:serialize) },
      SecurityConversion: {
        type: :object,
        properties: {
          id:             UUID,
          from_security:  { "$ref" => "#/components/schemas/SecurityConversionSecurity" },
          to_security:    { "$ref" => "#/components/schemas/SecurityConversionSecurity" },
          effective_date: { type: :string, format: :date },
          ratio:          { type: :number, format: :float,
                            description: "to_security shares per from_security share, both in current split-adjusted units" },
          status:         { "$ref" => "#/components/schemas/SecurityConversionStatus" },
          source:         { type: :string, enum: ::SecurityConversion::Source.values.map(&:serialize) },
          evidence:       { type: :object, additionalProperties: true,
                            description: "What detection saw: quantities, closes, dates, account, shared name words" },
          confirmed_at:   { type: :string, format: "date-time", nullable: true },
          created_at:     { type: :string, format: "date-time" }
        },
        required: %w[id from_security to_security effective_date ratio status source evidence confirmed_at created_at]
      }
    )
  end
end
