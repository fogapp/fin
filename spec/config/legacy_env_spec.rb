# typed: false
# frozen_string_literal: true

require "rails_helper"

# Fin was Manor: an install configured with MANOR_* keeps working.
RSpec.describe "config/legacy_env.rb" do
  it "fills each FIN_* setting from its MANOR_* name" do
    with_env("MANOR_WEBAUTHN_RP_ID" => "old.example.com", "FIN_WEBAUTHN_RP_ID" => nil) do
      expect { load Rails.root.join("config/legacy_env.rb").to_s }.to output(/MANOR_WEBAUTHN_RP_ID is deprecated/).to_stderr
      expect(ENV["FIN_WEBAUTHN_RP_ID"]).to eq("old.example.com")
    end
  end

  it "leaves a FIN_* setting that is already set" do
    with_env("MANOR_WEBAUTHN_RP_ID" => "old.example.com", "FIN_WEBAUTHN_RP_ID" => "fin.example.com") do
      expect { load Rails.root.join("config/legacy_env.rb").to_s }.not_to output.to_stderr
      expect(ENV["FIN_WEBAUTHN_RP_ID"]).to eq("fin.example.com")
    end
  end
end
