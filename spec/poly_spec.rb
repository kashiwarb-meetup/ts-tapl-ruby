require "spec_helper"
require_relative "../lib/poly"

RSpec.describe "poly" do
  def tc(src) = Poly.typecheck_source(src)

  describe "Poly.type_subst" do
    it "substitutes TypeVar with concrete type" do
      ty = { tag: :TypeVar, name: :T }
      expect(Poly.type_subst(ty, :T, { tag: :Number })).to eq({ tag: :Number })
    end

    it "does not substitute unrelated TypeVar" do
      ty = { tag: :TypeVar, name: :U }
      expect(Poly.type_subst(ty, :T, { tag: :Number })).to eq(ty)
    end

    it "substitutes inside Func" do
      ty = { tag: :Func, params: [{ tag: :TypeVar, name: :T }], ret_type: { tag: :TypeVar, name: :T } }
      result = Poly.type_subst(ty, :T, { tag: :Number })
      expect(result).to eq({ tag: :Func, params: [{ tag: :Number }], ret_type: { tag: :Number } })
    end
  end

  describe "Poly.unify" do
    it "unifies TypeVar with concrete type" do
      subst = Poly.unify({ tag: :TypeVar, name: :T }, { tag: :Number }, {})
      expect(subst[:T]).to eq({ tag: :Number })
    end

    it "unifies identical concrete types" do
      subst = Poly.unify({ tag: :Number }, { tag: :Number }, {})
      expect(subst).to eq({})
    end

    it "raises on mismatched concrete types" do
      expect {
        Poly.unify({ tag: :Boolean }, { tag: :Number }, {})
      }.to raise_error(Poly::TypeCheckError)
    end
  end

  describe "OK cases" do
    it "identity function with Number argument" do
      src = <<~RUBY
        # @sig <T>(T) -> T
        identity = ->(x) { x }
        identity(42)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "identity function with Boolean argument" do
      src = <<~RUBY
        # @sig <T>(T) -> T
        identity = ->(x) { x }
        identity(true)
      RUBY
      expect(tc(src)).to eq({ tag: :Boolean })
    end

    it "identity result assigned then referenced" do
      src = <<~RUBY
        # @sig <T>(T) -> T
        identity = ->(x) { x }
        x = identity(42)
        x
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "monomorphic function still works" do
      src = <<~RUBY
        # @sig (Integer, Integer) -> Integer
        add = ->(x, y) { x + y }
        add(1, 2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "two-param generic — first returns T" do
      src = <<~RUBY
        # @sig <T>(T, Integer) -> T
        first = ->(a, b) { a }
        first(true, 42)
      RUBY
      expect(tc(src)).to eq({ tag: :Boolean })
    end
  end

  describe "NG cases" do
    it "adding results of identity with incompatible types raises" do
      src = <<~RUBY
        # @sig <T>(T) -> T
        identity = ->(x) { x }
        identity(1) + identity(true)
      RUBY
      expect { tc(src) }.to raise_error(Poly::TypeCheckError)
    end

    it "wrong argument count for polymorphic function raises" do
      src = <<~RUBY
        # @sig <T>(T) -> T
        identity = ->(x) { x }
        identity(1, 2)
      RUBY
      expect { tc(src) }.to raise_error(Poly::TypeCheckError)
    end
  end
end
