# frozen_string_literal: true

# Continuous profiling stays off here whatever Lucid's console directs (a
# local kill switch wins over directives). With Vernier sampling every
# thread, each Solid Queue process — even the near-idle dispatcher and
# scheduler — grew by hundreds of MB within minutes, until the host's OOM
# killer took the worker down for good (2026-10-02). Everything else Lucid
# reports is unaffected.
Lucid.configure do |config|
  config.enabled[:profiling] = false
end
