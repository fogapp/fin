require "rails_helper"

RSpec.describe Api::Render::Import do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#serialize" do
    it "includes all expected fields" do
      import = create(:csv_import)
      result = renderer.serialize(import)
      expect(result.keys).to match_array(%i[
        id source_filename status kind broker_name target_account_id
        imported_count skipped_count error_count error_log
        started_at finished_at created_at
      ])
    end
  end
end
