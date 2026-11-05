# Temporarily sets (or, with nil, unsets) ENV keys for the duration of a
# block, restoring the originals afterwards.
#
#   with_env("COINMARKETCAP_API_KEY" => "k") { ... }
module EnvHelper
  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original&.each { |key, value| ENV[key] = value }
  end
end

RSpec.configure { |config| config.include EnvHelper }
