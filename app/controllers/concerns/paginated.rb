# typed: true

# Offset pagination shared by the API list endpoints: one definition of the
# page clamp and the { page, per_page, total } meta envelope, so every list
# paginates (and reports its pagination) identically.
module Paginated
  extend ActiveSupport::Concern
  extend T::Sig

  PER_PAGE = 50

  # limit/offset windowing for the endpoints that page by offset rather than
  # page number. Module function so renderers share the exact same clamp: a
  # blank limit takes `default`, any limit clamps into 1..max, and offset
  # never goes negative (a negative OFFSET is a Postgres error, i.e. a 500).
  sig { params(params: T.untyped, default: Integer, max: Integer).returns([ Integer, Integer ]) }
  def self.window(params, default:, max:)
    limit = params[:limit].present? ? params[:limit].to_i.clamp(1, max) : default
    [ limit, [ params[:offset].to_i, 0 ].max ]
  end

  private

  sig { params(default: Integer, max: Integer).returns([ Integer, Integer ]) }
  def window_params(default:, max:)
    Paginated.window(params, default: default, max: max)
  end

  # Pages are 1-based; anything unparsable or below 1 clamps to the first
  # page rather than producing a negative offset.
  sig { returns(Integer) }
  def page_param
    [ params[:page].to_i, 1 ].max
  end

  # Returns the requested page of `scope` plus the meta envelope the client
  # pager reads. `total` counts the full filtered scope, not the page.
  sig { params(scope: ActiveRecord::Relation, per_page: Integer).returns([ ActiveRecord::Relation, T::Hash[Symbol, Integer] ]) }
  def paginate(scope, per_page: PER_PAGE)
    page = page_param
    records = scope.offset((page - 1) * per_page).limit(per_page)
    [ records, { page: page, per_page: per_page, total: scope.count } ]
  end
end
