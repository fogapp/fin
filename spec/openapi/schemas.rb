# Component schemas for swagger/v1/swagger.yaml, split by domain so each
# file can grow independently. Every file under spec/openapi/schemas/
# registers its hash with OpenapiSchemas.register; swagger_helper merges
# them into components.schemas.
module OpenapiSchemas
  @registry = {}

  def self.register(schemas)
    duplicates = @registry.keys & schemas.keys
    raise ArgumentError, "duplicate OpenAPI schemas: #{duplicates.join(', ')}" if duplicates.any?

    @registry.merge!(schemas)
  end

  def self.all = @registry
end

Dir[File.join(__dir__, "schemas", "*.rb")].sort.each { |f| require f }
