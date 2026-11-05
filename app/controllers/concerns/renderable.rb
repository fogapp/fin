# typed: true

# Declares which Api::Render class shapes a controller's responses. Every
# renderer-backed controller used to hand-roll the same memoized accessor;
# `renders_with` keeps that wiring in one place so controllers only state
# the class.
module Renderable
  extend ActiveSupport::Concern
  extend T::Sig

  class_methods do
    extend T::Sig

    # Defines a private memoized `renderer` returning an instance of
    # `renderer_class` built from the request params — identical to the
    # hand-rolled `@renderer ||= X.new(params: params)` it replaces.
    sig { params(renderer_class: T::Class[Api::Render::Base]).void }
    def renders_with(renderer_class)
      define_method(:renderer) do
        @renderer ||= renderer_class.new(params: params)
      end
      private :renderer
    end
  end
end
