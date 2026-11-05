require "rails_helper"

RSpec.describe FogEventsClient do
  let(:fog_env) { { "FOG_API_URL" => "http://fog.test/", "FOG_API_TOKEN" => "apptok" } }

  describe ".from_env" do
    it "is nil off fog" do
      stub_const("ENV", ENV.to_h.except("FOG_API_URL", "FOG_API_TOKEN"))
      expect(described_class.from_env).to be_nil
    end

    it "is nil with only half the pair" do
      stub_const("ENV", ENV.to_h.except("FOG_API_TOKEN").merge("FOG_API_URL" => "http://fog.test"))
      expect(described_class.from_env).to be_nil
    end
  end

  describe "#publish" do
    before { stub_const("ENV", ENV.to_h.merge(fog_env)) }

    it "posts one CloudEvent with the app's bearer token" do
      stub = stub_request(:post, "http://fog.test/app/v1/events")
        .with(headers: { "Authorization" => "Bearer apptok", "Content-Type" => "application/json" },
              body: hash_including("specversion" => "1.0", "id" => "notification-1", "type" => "fin.notification",
                                   "subject" => "Budget alerts", "data" => { "title" => "Dining over budget" }))
        .to_return(status: 202, body: '{"accepted":1,"new":1}')

      described_class.from_env.publish(type: "fin.notification", id: "notification-1", subject: "Budget alerts",
                                       data: { "title" => "Dining over budget" })

      expect(stub).to have_been_requested
    end

    it "raises its own error unless fog answers 202" do
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 200, body: "{}")

      expect {
        described_class.from_env.publish(type: "fin.x", id: "a", subject: "s", data: {})
      }.to raise_error(FogEventsClient::Error, /200/)
    end

    it "raises its own error when fogd is unreachable" do
      stub_request(:post, "http://fog.test/app/v1/events").to_timeout

      expect {
        described_class.from_env.publish(type: "fin.x", id: "a", subject: "s", data: {})
      }.to raise_error(FogEventsClient::Error)
    end
  end
end
