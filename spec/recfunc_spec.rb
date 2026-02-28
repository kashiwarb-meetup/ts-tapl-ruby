require "spec_helper"
require_relative "../lib/recfunc"

RSpec.describe "recfunc" do
  def tc(src) = Recfunc.typecheck_source(src)

  describe "OK cases" do
    it "recursive factorial" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        def factorial(n)
          n == 0 ? 1 : n * factorial(n - 1)
        end
        factorial(5)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "recursive sum accumulator" do
      src = <<~RUBY
        # @sig (Integer, Integer) -> Integer
        def sum_to(n, acc)
          n == 0 ? acc : sum_to(n - 1, acc + n)
        end
        sum_to(10, 0)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "recursive boolean function" do
      src = <<~RUBY
        # @sig (Integer) -> Boolean
        def is_zero(n)
          n == 0 ? true : false
        end
        is_zero(0)
      RUBY
      expect(tc(src)).to eq({ tag: :Boolean })
    end

    it "lambda-style (non-recursive) still works" do
      src = <<~RUBY
        # @sig (Integer, Integer) -> Integer
        add = ->(x, y) { x + y }
        add(1, 2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end
  end

  describe "NG cases" do
    it "def without @sig raises" do
      src = <<~RUBY
        def missing_sig(n)
          n
        end
      RUBY
      expect { tc(src) }.to raise_error(Recfunc::TypeCheckError)
    end

    it "def body returns wrong type raises" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        def bad_return(n)
          n == 0 ? true : n * bad_return(n - 1)
        end
      RUBY
      expect { tc(src) }.to raise_error(Recfunc::TypeCheckError)
    end

    it "calling recursive function with wrong type raises" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        def double(n)
          n == 0 ? 0 : double(n - 1) + 2
        end
        double(true)
      RUBY
      expect { tc(src) }.to raise_error(Recfunc::TypeCheckError)
    end
  end
end
