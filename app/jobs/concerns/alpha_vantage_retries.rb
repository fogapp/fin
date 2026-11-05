# typed: true

# Shared rescue policy for jobs whose perform is one Alpha Vantage call
# chain: missing key warns and skips (retrying can't conjure a key), a 429
# retries with a bounded wait (a persistent 429 — e.g. an expired plan —
# used to re-enqueue the job forever), any other AlphaVantage::Error is
# logged and dropped. SyncSecurityNewsJob keeps its own per-security policy
# — it breaks out of a loop on rate limit instead of retrying the job.
module AlphaVantageRetries
  extend T::Sig

  MAX_RATE_LIMIT_ATTEMPTS = 5
  RATE_LIMIT_WAIT = 60.seconds

  sig { params(label: T.untyped, blk: T.proc.returns(T.untyped)).void }
  def with_alpha_vantage(label, &blk)
    yield
  rescue AlphaVantage::MissingKeyError => e
    Rails.logger.warn("[#{self.class.name}] skipping #{label}: #{e.message}")
  rescue AlphaVantage::RateLimitError => e
    if executions < MAX_RATE_LIMIT_ATTEMPTS
      Rails.logger.warn("[#{self.class.name}] rate limited for #{label}, retrying in 60s (attempt #{executions}/#{MAX_RATE_LIMIT_ATTEMPTS})")
      retry_job wait: RATE_LIMIT_WAIT
    else
      Rails.logger.error("[#{self.class.name}] rate limited for #{label}; giving up after #{executions} attempts: #{e.message}")
    end
  rescue AlphaVantage::Error => e
    Rails.logger.error("[#{self.class.name}] #{label} failed: #{e.message}")
  end
end
