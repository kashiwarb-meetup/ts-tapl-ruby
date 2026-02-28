require "spec_helper"
require_relative "../lib/basic"

RSpec.describe "basic" do
  def tc(src) = Basic.typecheck_source(src)

  describe "OK cases" do
    it "integer literal" do
      expect(tc("42")).to eq({ tag: :Number })
    end

    it "boolean literal" do
      expect(tc("true")).to eq({ tag: :Boolean })
    end

    it "variable assignment and reference" do
      expect(tc("x = 1\nx")).to eq({ tag: :Number })
    end

    it "multiple assignments" do
      expect(tc("x = 1\ny = 2\nx + y")).to eq({ tag: :Number })
    end

    it "lambda with @sig and call" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        f = ->(x) { x + 1 }
        f(2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "lambda with two params" do
      src = <<~RUBY
        # @sig (Integer, Integer) -> Integer
        add = ->(x, y) { x + y }
        add(1, 2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "lambda returning boolean" do
      src = <<~RUBY
        # @sig (Boolean) -> Boolean
        neg = ->(b) { b ? false : true }
        neg(true)
      RUBY
      expect(tc(src)).to eq({ tag: :Boolean })
    end

    it "lambda with boolean param select" do
      src = <<~RUBY
        # @sig (Boolean, Integer, Integer) -> Integer
        select = ->(b, x, y) { b ? x : y }
        select(true, 1, 2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "sequencing — last expression type is returned" do
      src = <<~RUBY
        x = 1
        y = 2
        x + y
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end
  end

  describe "NG cases" do
    it "unbound variable raises" do
      expect { tc("x") }.to raise_error(Basic::TypeCheckError)
    end

    it "call unbound function raises" do
      expect { tc("f(1)") }.to raise_error(Basic::TypeCheckError)
    end

    it "wrong argument type raises" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        g = ->(x) { x + 1 }
        g(true)
      RUBY
      expect { tc(src) }.to raise_error(Basic::TypeCheckError)
    end

    it "wrong number of arguments raises" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        g = ->(x) { x + 1 }
        g(1, 2)
      RUBY
      expect { tc(src) }.to raise_error(Basic::TypeCheckError)
    end

    it "lambda without @sig raises" do
      expect { tc("f = ->(x) { x }") }.to raise_error(Basic::TypeCheckError)
    end
  end
end
