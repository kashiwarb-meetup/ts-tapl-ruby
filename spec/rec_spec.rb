require "spec_helper"
require_relative "../lib/rec"

RSpec.describe "rec" do
  describe "Rec.simplify_type (Mu unfolding)" do
    let(:list_type) do
      { tag: :Mu, type_var: :X,
        type: { tag: :Obj, props: {
          val:  { tag: :Number },
          next: { tag: :TypeVar, name: :X }
        } } }
    end

    it "unfolds Mu one level" do
      unfolded = Rec.simplify_type(list_type)
      expect(unfolded[:tag]).to eq(:Obj)
      expect(unfolded[:props][:val]).to eq({ tag: :Number })
      # next should fold back to the Mu type
      expect(unfolded[:props][:next]).to eq(list_type)
    end

    it "non-Mu type is returned unchanged" do
      ty = { tag: :Number }
      expect(Rec.simplify_type(ty)).to equal(ty)
    end
  end

  describe "Rec.type_subst" do
    it "substitutes TypeVar" do
      ty = { tag: :TypeVar, name: :X }
      expect(Rec.type_subst(ty, :X, { tag: :Number })).to eq({ tag: :Number })
    end

    it "does not substitute different TypeVar" do
      ty = { tag: :TypeVar, name: :Y }
      expect(Rec.type_subst(ty, :X, { tag: :Number })).to eq(ty)
    end

    it "substitutes inside Obj" do
      ty = { tag: :Obj, props: { x: { tag: :TypeVar, name: :X } } }
      result = Rec.type_subst(ty, :X, { tag: :Number })
      expect(result).to eq({ tag: :Obj, props: { x: { tag: :Number } } })
    end

    it "does not substitute bound variable in Mu" do
      ty = { tag: :Mu, type_var: :X, type: { tag: :TypeVar, name: :X } }
      result = Rec.type_subst(ty, :X, { tag: :Number })
      expect(result).to eq(ty)
    end
  end

  describe "Rec.type_eq on recursive types" do
    let(:list_x) do
      { tag: :Mu, type_var: :X,
        type: { tag: :Obj, props: { val: { tag: :Number }, next: { tag: :TypeVar, name: :X } } } }
    end

    it "a type is equal to itself" do
      expect(Rec.type_eq(list_x, list_x)).to be true
    end

    it "Number equals Number" do
      expect(Rec.type_eq({ tag: :Number }, { tag: :Number })).to be true
    end

    it "Number does not equal Boolean" do
      expect(Rec.type_eq({ tag: :Number }, { tag: :Boolean })).to be false
    end
  end

  describe "Rec.typecheck_source OK cases" do
    def tc(src) = Rec.typecheck_source(src)

    it "integer literal" do
      expect(tc("42")).to eq({ tag: :Number })
    end

    it "boolean literal" do
      expect(tc("true")).to eq({ tag: :Boolean })
    end

    it "addition" do
      expect(tc("1 + 2")).to eq({ tag: :Number })
    end

    it "simple function" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        f = ->(x) { x + 1 }
        f(2)
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "object creation and property access" do
      src = <<~RUBY
        obj = {x: 1, y: true}
        obj[:x]
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end
  end

  describe "Rec.typecheck_source NG cases" do
    def tc(src) = Rec.typecheck_source(src)

    it "type mismatch in addition raises" do
      expect { tc("true + 1") }.to raise_error(Rec::TypeCheckError)
    end

    it "accessing missing property raises" do
      expect { tc("obj = {x: 1}\nobj[:y]") }.to raise_error(Rec::TypeCheckError)
    end
  end
end
