require "spec_helper"
require_relative "../lib/arith"

RSpec.describe "arith" do
  def parse(src) = Prism.parse(src).value

  describe "OK cases" do
    it "integer literal" do
      expect(Arith.typecheck(parse("42"))).to eq({ tag: :Number })
    end

    it "true literal" do
      expect(Arith.typecheck(parse("true"))).to eq({ tag: :Boolean })
    end

    it "false literal" do
      expect(Arith.typecheck(parse("false"))).to eq({ tag: :Boolean })
    end

    it "integer addition" do
      expect(Arith.typecheck(parse("1 + 2"))).to eq({ tag: :Number })
    end

    it "nested addition" do
      expect(Arith.typecheck(parse("1 + 2 + 3"))).to eq({ tag: :Number })
    end

    it "if with boolean branches" do
      expect(Arith.typecheck(parse("true ? true : false"))).to eq({ tag: :Boolean })
    end

    it "if with integer branches" do
      expect(Arith.typecheck(parse("true ? 1 : 2"))).to eq({ tag: :Number })
    end

    it "if with false predicate" do
      expect(Arith.typecheck(parse("false ? 1 : 2"))).to eq({ tag: :Number })
    end

    it "nested if with parentheses" do
      expect(Arith.typecheck(parse("true ? (false ? 1 : 2) : 3"))).to eq({ tag: :Number })
    end
  end

  describe "NG cases" do
    it "adding integer to boolean raises" do
      expect { Arith.typecheck(parse("1 + true")) }.to raise_error(Arith::TypeCheckError)
    end

    it "adding boolean to integer raises" do
      expect { Arith.typecheck(parse("true + 1")) }.to raise_error(Arith::TypeCheckError)
    end

    it "integer predicate in if raises" do
      expect { Arith.typecheck(parse("1 ? 2 : 3")) }.to raise_error(Arith::TypeCheckError)
    end

    it "mismatched if branches raises" do
      expect { Arith.typecheck(parse("true ? 1 : false")) }.to raise_error(Arith::TypeCheckError)
    end

    it "mismatched if branches (reverse) raises" do
      expect { Arith.typecheck(parse("true ? false : 1")) }.to raise_error(Arith::TypeCheckError)
    end
  end
end
