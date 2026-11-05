# frozen_string_literal: true

# Fin was called Manor until 2026-11, and its settings were MANOR_*. An
# install still configured that way keeps working: each MANOR_X fills the
# FIN_X it was renamed to, unless FIN_X is set too. Loaded before the app
# (config/application.rb) so database.yml and initializers see the new names.
ENV.keys.grep(/\AMANOR_/).each do |legacy|
  current = legacy.sub(/\AMANOR_/, "FIN_")
  next if ENV.key?(current)

  ENV[current] = ENV[legacy]
  warn "[config] #{legacy} is deprecated: rename it #{current}"
end
