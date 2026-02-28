require "spec_helper"
require_relative "../lib/obj"

RSpec.describe "obj" do
  def tc(src) = Obj.typecheck_source(src)

  describe "OK cases" do
    it "object literal" do
      expect(tc("{x: 1, y: true}")).to eq({ tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Boolean } } })
    end

    it "single-property object" do
      expect(tc("{n: 42}")).to eq({ tag: :Obj, props: { n: { tag: :Number } } })
    end

    it "property access on variable" do
      src = <<~RUBY
        obj = {x: 1, y: 2}
        obj[:x]
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "property access returns correct type" do
      src = <<~RUBY
        obj = {x: 1, y: true}
        obj[:y]
      RUBY
      expect(tc(src)).to eq({ tag: :Boolean })
    end

    it "function taking object param" do
      src = <<~RUBY
        # @sig ({ x: Integer, y: Integer }) -> Integer
        sum_xy = ->(obj) { obj[:x] + obj[:y] }
        sum_xy({x: 1, y: 2})
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "function returning object" do
      src = <<~RUBY
        # @sig (Integer, Boolean) -> { x: Integer, y: Boolean }
        make = ->(n, b) { {x: n, y: b} }
        make(1, true)
      RUBY
      expect(tc(src)).to eq({ tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Boolean } } })
    end
  end

  describe "NG cases" do
    it "accessing missing property raises" do
      src = <<~RUBY
        obj = {x: 1}
        obj[:y]
      RUBY
      expect { tc(src) }.to raise_error(Obj::TypeCheckError)
    end

    it "property access on non-object raises" do
      expect { tc("x = 1\nx[:y]") }.to raise_error(Obj::TypeCheckError)
    end

    it "passing object with wrong property type raises" do
      src = <<~RUBY
        # @sig ({ x: Integer }) -> Integer
        get_x = ->(obj) { obj[:x] }
        get_x({x: true})
      RUBY
      expect { tc(src) }.to raise_error(Obj::TypeCheckError)
    end
  end
end
