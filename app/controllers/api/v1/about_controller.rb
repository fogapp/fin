# typed: true

module Api
  module V1
    class AboutController < BaseController
      def show
        sha = (ENV["GIT_REV"] || ENV["GIT_SHA"]).presence
        render json: {
          rails_version: Rails::VERSION::STRING,
          ruby_version:  RUBY_VERSION,
          rails_env:     Rails.env,
          git_sha:       sha,
          git_sha_short: sha&.first(7),
          hostname:      Socket.gethostname
        }
      end
    end
  end
end
