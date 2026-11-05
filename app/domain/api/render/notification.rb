# typed: strict

module Api
  module Render
    class Notification < Api::Render::Base
      extend T::Sig

      # The list envelope always carries the global unread count so the badge
      # stays right even when the list itself is filtered to unread.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def index
        scope = ::Notification.recent
        scope = scope.unread if params[:unread] == "true"
        {
          notifications: scope.limit(100).map { |n| serialize(n) },
          unread_count:  ::Notification.unread.count
        }
      end

      sig { params(n: ::Notification).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(n)
        {
          id:           n.id,
          title:        n.title,
          body:         n.body,
          severity:     n.severity,
          href:         n.href,
          subject_type: n.subject_type,
          subject_id:   n.subject_id,
          read_at:      n.read_at&.iso8601,
          created_at:   n.created_at.iso8601
        }
      end
    end
  end
end
