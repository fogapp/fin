# typed: false
# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # Requires a blank line after `extend T::Sig` so the Sorbet sig helper
      # is visually separated from the rest of the class body.
      #
      # @example
      #   # bad
      #   class Foo
      #     extend T::Sig
      #     def bar; end
      #   end
      #
      #   # good
      #   class Foo
      #     extend T::Sig
      #
      #     def bar; end
      #   end
      class EmptyLineAfterExtendTSig < RuboCop::Cop::Base
        extend AutoCorrector
        include RangeHelp

        MSG = "Add an empty line after `extend T::Sig`."

        def on_send(node)
          return unless extend_t_sig?(node)

          next_line = processed_source.lines[node.loc.line] # loc.line is 1-based; index gives the *next* line
          return if next_line.nil? || next_line.strip.empty? || next_line.strip == "end"

          add_offense(node) do |corrector|
            corrector.insert_after(range_by_whole_lines(node.source_range), "\n")
          end
        end

        private

        def extend_t_sig?(node)
          return false unless node.send_type? && node.method_name == :extend && node.arguments.one?

          arg = node.first_argument
          return false unless arg.const_type? && arg.short_name == :Sig

          ns = arg.namespace
          ns&.const_type? && ns.short_name == :T
        end
      end
    end
  end
end
