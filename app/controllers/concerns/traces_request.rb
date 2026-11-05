# typed: true

# One trace per request: anything the request enqueues (workflow dispatches,
# syncs) inherits the trace id through the job graph. Included by every
# token-authenticated entry point — Api::V1::BaseController and McpController —
# ahead of authentication, so even a rejected request is traced.
module TracesRequest
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ActionController::API }

  included do
    T.bind(self, T.class_of(ActionController::API))
    before_action :set_trace_id
  end

  private

  def set_trace_id
    Current.trace_id = request.request_id
  end
end
