require "rails_helper"

RSpec.describe "RSpec setup" do
  it "loads the Rails environment" do
    expect(Rails.env).to eq("test")
  end

  it "connects to the test database" do
    expect(ActiveRecord::Base.connection.current_database).to match(/test/)
  end

  it "loads FactoryBot" do
    expect(defined?(FactoryBot)).to be_truthy
  end

  it "loads Shoulda Matchers" do
    expect(defined?(Shoulda::Matchers)).to be_truthy
  end

  it "blocks external HTTP" do
    expect { Net::HTTP.get(URI("http://example.com")) }
      .to raise_error(WebMock::NetConnectNotAllowedError)
  end
end
