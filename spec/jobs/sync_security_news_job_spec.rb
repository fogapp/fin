require "rails_helper"

RSpec.describe SyncSecurityNewsJob, type: :job do
  let(:syncer) { instance_double(SecurityNewsSyncer, call: 3) }

  before do
    allow(SecurityNewsSyncer).to receive(:new).and_return(syncer)
    ENV["ALPHA_VANTAGE_API_KEY"] = "test-key"
  end

  after do
    ENV.delete("ALPHA_VANTAGE_API_KEY")
  end

  describe "with no security_id (sync all watched securities with tickers)" do
    it "calls SecurityNewsSyncer#call for each watched security with a ticker" do
      sec1 = create(:security, ticker: "COIN", watched: true)
      sec2 = create(:security, ticker: "MSFT", watched: true)

      described_class.perform_now

      expect(SecurityNewsSyncer).to have_received(:new).with(sec1)
      expect(SecurityNewsSyncer).to have_received(:new).with(sec2)
      expect(syncer).to have_received(:call).twice
    end

    it "skips non-watched securities" do
      create(:security, ticker: "UNWATCHED", watched: false)

      described_class.perform_now

      expect(SecurityNewsSyncer).not_to have_received(:new)
    end

    it "skips watched securities without a ticker" do
      create(:security, :without_ticker, watched: true)

      described_class.perform_now

      expect(SecurityNewsSyncer).not_to have_received(:new)
    end
  end

  describe "with a security_id" do
    it "calls syncer only for that security" do
      target  = create(:security, ticker: "COIN", watched: true)
      other   = create(:security, ticker: "MSFT", watched: true)

      described_class.perform_now(target.id)

      expect(SecurityNewsSyncer).to have_received(:new).with(target)
      expect(SecurityNewsSyncer).not_to have_received(:new).with(other)
    end
  end

  describe "when ALPHA_VANTAGE_API_KEY is blank" do
    it "skips all processing" do
      ENV["ALPHA_VANTAGE_API_KEY"] = ""
      create(:security, ticker: "COIN", watched: true)

      described_class.perform_now

      expect(SecurityNewsSyncer).not_to have_received(:new)
    end
  end

  describe "rate limit handling" do
    it "stops processing further securities when RateLimitError is raised" do
      # Ensure AlphaVantage module is loaded
      AlphaVantage::Client # force autoload

      sec1 = create(:security, ticker: "AAAARATE", watched: true)
      sec2 = create(:security, ticker: "ZZZZRATE", watched: true)

      rate_limited_syncer = instance_double(SecurityNewsSyncer)
      allow(rate_limited_syncer).to receive(:call).and_raise(AlphaVantage::RateLimitError, "rate limited")
      ok_syncer = instance_double(SecurityNewsSyncer, call: 0)

      # Stub the Security scope to return sec1 before sec2 deterministically
      ordered_scope = [ sec1, sec2 ]
      allow(Security).to receive(:watched_by_anyone).and_return(
        double(with_ticker: ordered_scope)
      )

      allow(SecurityNewsSyncer).to receive(:new).with(sec1).and_return(rate_limited_syncer)
      allow(SecurityNewsSyncer).to receive(:new).with(sec2).and_return(ok_syncer)

      described_class.perform_now

      expect(rate_limited_syncer).to have_received(:call).once
      expect(ok_syncer).not_to have_received(:call)
    end
  end
end
