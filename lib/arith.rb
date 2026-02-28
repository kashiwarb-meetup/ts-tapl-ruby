require "prism"

# Chapter 2: Booleans, Numbers, Conditionals, Addition
# Supports: true, false, 42, x + y, if/ternary expressions

module Arith
  class TypeCheckError < StandardError; end

  def self.typecheck(node)
    case node
    in Prism::TrueNode
      { tag: :Boolean }
    in Prism::FalseNode
      { tag: :Boolean }
    in Prism::IntegerNode
      { tag: :Number }
    in Prism::ParenthesesNode[body: Prism::StatementsNode[body: [inner]]]
      typecheck(inner)
    in Prism::CallNode[name: :+, receiver:, arguments: Prism::ArgumentsNode[arguments: [right]]]
      left_ty  = typecheck(receiver)
      right_ty = typecheck(right)
      raise TypeCheckError, "'+' requires Number operands, got #{left_ty} + #{right_ty}" unless left_ty == { tag: :Number } && right_ty == { tag: :Number }
      { tag: :Number }
    in Prism::IfNode[predicate:, statements:, subsequent:]
      pred_ty = typecheck(predicate)
      raise TypeCheckError, "if predicate must be Boolean, got #{pred_ty}" unless pred_ty == { tag: :Boolean }
      thn_ty = typecheck(statements.body.last)
      els_ty = typecheck(subsequent.statements.body.last)
      raise TypeCheckError, "if branches must have same type: #{thn_ty} vs #{els_ty}" unless thn_ty == els_ty
      thn_ty
    in Prism::ProgramNode[statements:]
      typecheck(statements)
    in Prism::StatementsNode[body:]
      typecheck(body.last)
    else
      raise TypeCheckError, "Unknown node: #{node.class}"
    end
  end
end

if __FILE__ == $0
  examples = ["1 + 2", "true", "false", "42", "true ? 1 : 2", "false ? true : false",
              "true ? (false ? 1 : 2) : 3"]
  examples.each do |src|
    result = Prism.parse(src)
    ty = Arith.typecheck(result.value)
    puts "#{src.ljust(30)} => #{ty}"
  end

  puts "\n--- Error cases ---"
  ["1 + true", "1 ? 2 : 3", "true ? 1 : false"].each do |src|
    Arith.typecheck(Prism.parse(src).value)
    puts "#{src}: (expected error!)"
  rescue Arith::TypeCheckError => e
    puts "#{src}: TypeCheckError: #{e.message}"
  end
end
