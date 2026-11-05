# typed: strict

module Api
  module Render
    class Issue < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        ::Issue.active.recent.map { |i| serialize(i) }
      end

      sig { params(issue: ::Issue).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(issue)
        {
          id:           issue.id,
          key:          issue.key,
          title:        issue.title,
          body:         issue.body,
          severity:     issue.severity,
          source:       issue.source,
          dismissed_at: issue.dismissed_at,
          created_at:   issue.created_at
        }
      end
    end
  end
end
