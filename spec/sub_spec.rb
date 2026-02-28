require "spec_helper"
require_relative "../lib/sub"

RSpec.describe "sub" do
  def tc(src) = Sub.typecheck_source(src)

  describe "Sub.is_subtype" do
    it "Boolean <: Boolean" do
      expect(Sub.is_subtype({ tag: :Boolean }, { tag: :Boolean })).to be true
    end

    it "Number <: Number" do
      expect(Sub.is_subtype({ tag: :Number }, { tag: :Number })).to be true
    end

    it "Boolean is not subtype of Number" do
      expect(Sub.is_subtype({ tag: :Boolean }, { tag: :Number })).to be false
    end

    it "width subtyping: extra properties ok" do
      wider    = { tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Number } } }
      narrower = { tag: :Obj, props: { x: { tag: :Number } } }
      expect(Sub.is_subtype(wider, narrower)).to be true
    end

    it "width subtyping: fewer properties not ok" do
      wider    = { tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Number } } }
      narrower = { tag: :Obj, props: { x: { tag: :Number } } }
      expect(Sub.is_subtype(narrower, wider)).to be false
    end

    it "function subtyping: covariant return" do
      f_sub = { tag: :Func, params: [{ tag: :Number }], ret_type: { tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Number } } } }
      f_sup = { tag: :Func, params: [{ tag: :Number }], ret_type: { tag: :Obj, props: { x: { tag: :Number } } } }
      expect(Sub.is_subtype(f_sub, f_sup)).to be true
    end

    it "function subtyping: contravariant param" do
      # f_sub accepts narrower input (fewer fields required) => f_sub <: f_sup
      f_sub = { tag: :Func, params: [{ tag: :Obj, props: { x: { tag: :Number } } }], ret_type: { tag: :Number } }
      f_sup = { tag: :Func, params: [{ tag: :Obj, props: { x: { tag: :Number }, y: { tag: :Number } } }], ret_type: { tag: :Number } }
      expect(Sub.is_subtype(f_sub, f_sup)).to be true
    end
  end

  describe "OK cases (subtyping used in typecheck)" do
    it "passing wider object to narrow-param function" do
      src = <<~RUBY
        # @sig ({ x: Integer }) -> Integer
        get_x = ->(obj) { obj[:x] }
        get_x({x: 10, y: 20})
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end

    it "object with many extra fields is still ok" do
      src = <<~RUBY
        # @sig ({ x: Integer }) -> Integer
        get_x = ->(obj) { obj[:x] }
        get_x({x: 1, y: 2, z: 3})
      RUBY
      expect(tc(src)).to eq({ tag: :Number })
    end
  end

  describe "NG cases" do
    it "passing narrower object (missing required field) raises" do
      src = <<~RUBY
        # @sig ({ x: Integer, y: Integer }) -> Integer
        sum_xy = ->(obj) { obj[:x] + obj[:y] }
        sum_xy({x: 1})
      RUBY
      expect { tc(src) }.to raise_error(Sub::TypeCheckError)
    end

    it "wrong primitive type still raises" do
      src = <<~RUBY
        # @sig (Integer) -> Integer
        inc = ->(n) { n + 1 }
        inc(true)
      RUBY
      expect { tc(src) }.to raise_error(Sub::TypeCheckError)
    end
  end
end
