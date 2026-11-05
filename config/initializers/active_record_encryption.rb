# Active Record Encryption keys come from env (fog injects them), never
# from credentials.yml — hub removed its credentials file for exactly this
# deploy shape.
#
# Production REQUIRES all three: the old `if present?` guard meant a missing
# key booted fine and failed only on the first encrypted read — every
# provider credential (Plaid, Alchemy, Coinbase…) silently unreadable, which
# is the nastiest possible failure mode for a restore. Fail at boot instead;
# the fog-backup preflight additionally fingerprints these keys so a
# restore with the wrong ones is refused before any data is touched.
if Rails.env.production?
  Rails.application.configure do
    config.active_record.encryption.primary_key         = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY")
    config.active_record.encryption.deterministic_key   = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT")
  end
elsif ENV["AR_ENCRYPTION_PRIMARY_KEY"].present?
  Rails.application.configure do
    config.active_record.encryption.primary_key         = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key   = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
  end
end
