# typed: true

module Api
  module V1
    class NotificationsController < BaseController
      renders_with Api::Render::Notification

      def index
        render json: renderer.index
      end

      def read
        notification = Notification.find(params[:id])
        notification.update!(read_at: Time.current) if notification.read_at.nil?
        render json: renderer.serialize(notification)
      end

      def read_all
        Notification.unread.update_all(read_at: Time.current)
        head :no_content
      end
    end
  end
end
