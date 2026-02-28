#!/usr/bin/env ruby
# demo.rb — ts-tapl-ruby の全機能を一覧するサンプル
#
# 実行: ruby demo.rb
#
# これは何か?
#   RubyコードのスニペットをPrismでパースし、型を推論・検査するツール群です。
#   型エラーがあれば実行前に検出できます。

$LOAD_PATH.unshift(__dir__ + "/lib")

require "arith"
require "basic"
require "obj"
require "recfunc"
require "sub"
require "rec"
require "poly"

SEP = "-" * 60

def ok(label, type)
  puts "  OK  #{label.ljust(40)} => #{type}"
end

def ng(label, error)
  puts "  NG  #{label.ljust(40)} !! #{error}"
end

def check(label, mod, src)
  ty = mod.typecheck_source(src)
  ok(label, ty)
rescue => e
  ng(label, e.message)
end

def expect_error(label, mod, src)
  mod.typecheck_source(src)
  ng(label, "(エラーになるはずが通ってしまった)")
rescue => e
  ng(label, e.message)
end

# ============================================================
puts SEP
puts "Chapter 2: Arith — 数値・真偽値・if式・加算"
puts SEP
# Arith はソース文字列ではなく Prism ノードを直接受け取る
def arith(label, src)
  ty = Arith.typecheck(Prism.parse(src).value)
  ok(label, ty)
rescue => e
  ng(label, e.message)
end

arith("true",              "true")
arith("42",                "42")
arith("1 + 2",             "1 + 2")
arith("true ? 1 : 2",      "true ? 1 : 2")
arith("true + 1  (NG)",    "true + 1")       # Boolean + Number → エラー
arith("1 ? 2 : 3  (NG)",   "1 ? 2 : 3")     # 条件が Number → エラー
arith("true ? 1 : false (NG)", "true ? 1 : false")  # 分岐の型が不一致 → エラー

# ============================================================
puts
puts SEP
puts "Chapter 3-4: Basic — 変数・ラムダ・関数呼び出し・let束縛"
puts SEP
# @sig コメントでラムダの引数型を宣言する

check("x = 1; x",          Basic, "x = 1\nx")
check("x = 1; y = 2; x+y", Basic, "x = 1\ny = 2\nx + y")
check("add(1, 2)", Basic, <<~RUBY)
  # @sig (Integer, Integer) -> Integer
  add = ->(x, y) { x + y }
  add(1, 2)
RUBY
check("select(true, 1, 2)", Basic, <<~RUBY)
  # @sig (Boolean, Integer, Integer) -> Integer
  select = ->(b, x, y) { b ? x : y }
  select(true, 1, 2)
RUBY
expect_error("add(1, true) (NG)", Basic, <<~RUBY)
  # @sig (Integer, Integer) -> Integer
  add = ->(x, y) { x + y }
  add(1, true)
RUBY

# ============================================================
puts
puts SEP
puts "Chapter 5: Obj — オブジェクト型・プロパティアクセス"
puts SEP
# { x: 1, y: true } のような Hash リテラルに Obj 型を割り当てる

check("{x: 1, y: true}",        Obj, "{x: 1, y: true}")
check("obj[:x]",                 Obj, "obj = {x: 1, y: true}\nobj[:x]")
check("sum_xy({x:1, y:2})",      Obj, <<~RUBY)
  # @sig ({ x: Integer, y: Integer }) -> Integer
  sum_xy = ->(obj) { obj[:x] + obj[:y] }
  sum_xy({x: 1, y: 2})
RUBY
expect_error("obj[:z] (NG)",     Obj, "obj = {x: 1}\nobj[:z]")

# ============================================================
puts
puts SEP
puts "Chapter 6: Recfunc — 再帰関数 (def)"
puts SEP
# def で定義した関数は自分自身を型環境から参照できる

check("factorial(5)", Recfunc, <<~RUBY)
  # @sig (Integer) -> Integer
  def factorial(n)
    n == 0 ? 1 : n * factorial(n - 1)
  end
  factorial(5)
RUBY
expect_error("bad_return (NG)", Recfunc, <<~RUBY)
  # @sig (Integer) -> Integer
  def bad(n)
    n == 0 ? true : n * bad(n - 1)
  end
RUBY

# ============================================================
puts
puts SEP
puts "Chapter 7: Sub — 部分型付け (幅・深さ・関数の反変)"
puts SEP
# { x:, y: } は { x: } のサブタイプ → x だけ要求する関数に渡せる

check("x:1,y:2 を {x:Integer} を受ける関数へ", Sub, <<~RUBY)
  # @sig ({ x: Integer }) -> Integer
  get_x = ->(obj) { obj[:x] }
  get_x({x: 10, y: 20})
RUBY
expect_error("{x:1} を {x:,y:} 要求の関数へ (NG)", Sub, <<~RUBY)
  # @sig ({ x: Integer, y: Integer }) -> Integer
  sum_xy = ->(obj) { obj[:x] + obj[:y] }
  sum_xy({x: 1})
RUBY
puts "  --  is_subtype({x:,y:}, {x:}) = #{Sub.is_subtype(
  {tag: :Obj, props: {x: {tag: :Number}, y: {tag: :Number}}},
  {tag: :Obj, props: {x: {tag: :Number}}}
)}  (幅サブタイプ: true が正解)"

# ============================================================
puts
puts SEP
puts "Chapter 8: Rec — 再帰型 (Mu)"
puts SEP
# Mu<X, { val: Integer, next: X }> が連結リスト型
# simplify_type で一段展開できる

list_ty = { tag: :Mu, type_var: :X,
            type: { tag: :Obj, props: {
              val:  { tag: :Number },
              next: { tag: :TypeVar, name: :X }
            }}}
unfolded = Rec.simplify_type(list_ty)
puts "  --  Mu<X,{val:Int,next:X}> を1段展開すると:"
puts "        val  の型: #{unfolded[:props][:val]}"
puts "        next の型: #{unfolded[:props][:next][:tag]}型 (元の Mu に戻る)"
check("1 + 2 (Rec モジュール)", Rec, "1 + 2")

# ============================================================
puts
puts SEP
puts "Chapter 9: Poly — ジェネリクス (型変数・単一化)"
puts SEP
# <T>(T) -> T は任意の型 T で呼べる
# 呼び出し時に型変数を実引数の型に単一化する

check("identity(42)  => Number", Poly, <<~RUBY)
  # @sig <T>(T) -> T
  identity = ->(x) { x }
  identity(42)
RUBY
check("identity(true) => Boolean", Poly, <<~RUBY)
  # @sig <T>(T) -> T
  identity = ->(x) { x }
  identity(true)
RUBY
check("first(true, 42) => Boolean", Poly, <<~RUBY)
  # @sig <T>(T, Integer) -> T
  first = ->(a, b) { a }
  first(true, 42)
RUBY
expect_error("identity(1)+identity(true) (NG)", Poly, <<~RUBY)
  # @sig <T>(T) -> T
  identity = ->(x) { x }
  identity(1) + identity(true)
RUBY

puts
puts SEP
puts "以上。型エラーは実行前に検出できます。"
puts SEP
