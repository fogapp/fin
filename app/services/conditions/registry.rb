# typed: strict

module Conditions
  module Registry
    extend T::Sig

    # Operator lists are enum instances; they JSON-encode as their serialized
    # strings (ApplicationEnum#as_json), so the catalog wire format is
    # unchanged. `values:` lists stay plain strings — `source` mirrors
    # CashTransaction's Rails `enum source` keys and `transaction_type` has
    # no typed enum yet.
    RESOURCES = T.let({
      "CashTransaction" => {
        fields: {
          "description"               => { type: :string,  operators: [ Operator::Matches, Operator::Equals, Operator::NotEquals, Operator::Contains, Operator::Blank, Operator::Present ] },
          "amount"                    => { type: :numeric, operators: [ Operator::Equals, Operator::GreaterThan, Operator::LessThan ] },
          "source"                    => { type: :enum,    operators: [ Operator::Equals, Operator::NotEquals, Operator::In ], values: %w[bank credit_card] },
          "transaction_type"          => { type: :enum, operators: [ Operator::Equals, Operator::NotEquals, Operator::In, Operator::Blank, Operator::Present ], values: %w[Sale Payment Return Account\ Transfer] },
          "merchant_id"               => { type: :integer, operators: [ Operator::Equals, Operator::Blank, Operator::Present ] },
          "category_id"               => { type: :integer, operators: [ Operator::Equals, Operator::Blank, Operator::Present ] },
          "account_id"                => { type: :integer, operators: [ Operator::Equals, Operator::Blank, Operator::Present ] },
          "memo"                      => { type: :string,  operators: [ Operator::Equals, Operator::Contains, Operator::Blank, Operator::Present ] },
          "transfer_counterpart_count" => { type: :numeric, operators: [ Operator::Equals, Operator::GreaterThan, Operator::LessThan ] }
        }
      },
      "InvestmentTransaction" => {
        fields: {
          "description" => { type: :string,  operators: [ Operator::Matches, Operator::Equals, Operator::NotEquals, Operator::Contains, Operator::Blank, Operator::Present ] },
          "amount_usd"  => { type: :numeric, operators: [ Operator::Equals, Operator::GreaterThan, Operator::LessThan ] },
          "income_usd"  => { type: :numeric, operators: [ Operator::Equals, Operator::GreaterThan, Operator::LessThan ] },
          "quantity"    => { type: :numeric, operators: [ Operator::Equals, Operator::GreaterThan, Operator::LessThan ] }
        }
      }
    }.freeze, T::Hash[String, T.untyped])

    sig { params(resource: String).returns(T::Hash[String, T.untyped]) }
    def self.fields_for(resource)
      RESOURCES.dig(resource, :fields) || {}
    end

    sig { params(resource: String).returns(T::Boolean) }
    def self.valid_resource?(resource)
      RESOURCES.key?(resource)
    end

    sig { params(resource: String, field: String).returns(T::Boolean) }
    def self.valid_field?(resource, field)
      fields_for(resource).key?(field)
    end
  end
end
