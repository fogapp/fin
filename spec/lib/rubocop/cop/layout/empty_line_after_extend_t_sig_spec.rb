require "rails_helper"
require "rubocop"
require "rubocop/rspec/expect_offense"
require "rubocop/rspec/support"
require_relative "../../../../../lib/rubocop/cop/layout/empty_line_after_extend_t_sig"

RSpec.describe RuboCop::Cop::Layout::EmptyLineAfterExtendTSig do
  include RuboCop::RSpec::ExpectOffense

  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::Config.new({}, "") }

  it "registers no offense when a blank line follows extend T::Sig" do
    expect_no_offenses(<<~RUBY)
      class Foo
        extend T::Sig

        def bar; end
      end
    RUBY
  end

  it "registers an offense when no blank line follows extend T::Sig" do
    expect_offense(<<~RUBY)
      class Foo
        extend T::Sig
        ^^^^^^^^^^^^^ Add an empty line after `extend T::Sig`.
        def bar; end
      end
    RUBY
  end

  it "registers an offense when a constant follows extend T::Sig without a blank line" do
    expect_offense(<<~RUBY)
      class Foo
        extend T::Sig
        ^^^^^^^^^^^^^ Add an empty line after `extend T::Sig`.
        CONST = "value"
      end
    RUBY
  end

  it "does not flag extend with other arguments" do
    expect_no_offenses(<<~RUBY)
      class Foo
        extend Comparable
        def bar; end
      end
    RUBY
  end

  it "does not flag extend T::Sig at the end of a class body" do
    expect_no_offenses(<<~RUBY)
      class Foo
        def bar; end
        extend T::Sig
      end
    RUBY
  end

  it "autocorrects by inserting a blank line after extend T::Sig" do
    expect_offense(<<~RUBY)
      class Foo
        extend T::Sig
        ^^^^^^^^^^^^^ Add an empty line after `extend T::Sig`.
        def bar; end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo
        extend T::Sig

        def bar; end
      end
    RUBY
  end
end
