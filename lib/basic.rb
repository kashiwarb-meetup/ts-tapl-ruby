require "prism"

# Chapter 3-4: Functions, Variables, Let bindings, Sequencing
# Type annotations via "# @sig (Type, ...) -> Type" comments.

module Basic
  class TypeCheckError < StandardError; end

  SIG_TYPE_MAP = {
    "Integer" => { tag: :Number },
    "Boolean" => { tag: :Boolean },
  }

  def self.parse_sig_type(str)
    str = str.strip
    SIG_TYPE_MAP.fetch(str) { raise TypeCheckError, "Unknown type in @sig: #{str}" }
  end

  def self.parse_sig(sig_str)
    sig_str = sig_str.strip
    unless sig_str =~ /\A\(([^)]*)\)\s*->\s*(.+)\z/
      raise TypeCheckError, "Invalid @sig format: #{sig_str}"
    end
    params   = $1.strip.empty? ? [] : $1.strip.split(",").map { |s| parse_sig_type(s) }
    ret_type = parse_sig_type($2.strip)
    { params: params, ret_type: ret_type }
  end

  def self.find_sig_comment(comments, node_line)
    comments.each do |comment|
      next unless comment.location.start_line == node_line - 1
      text = comment.location.slice
      return text.sub(/\A#\s*@sig\s*/, "") if text.include?("@sig")
    end
    nil
  end

  def self.typecheck(node, ty_env = {}, comments = [])
    case node
    in Prism::TrueNode
      { tag: :Boolean }
    in Prism::FalseNode
      { tag: :Boolean }
    in Prism::IntegerNode
      { tag: :Number }
    in Prism::ParenthesesNode[body: Prism::StatementsNode[body: [inner]]]
      typecheck(inner, ty_env, comments)
    in Prism::CallNode[name: :+, receiver:, arguments: Prism::ArgumentsNode[arguments: [right]]]
      left_ty  = typecheck(receiver, ty_env, comments)
      right_ty = typecheck(right, ty_env, comments)
      raise TypeCheckError, "'+' requires Number" unless left_ty == { tag: :Number } && right_ty == { tag: :Number }
      { tag: :Number }
    in Prism::IfNode[predicate:, statements:, subsequent:]
      pred_ty = typecheck(predicate, ty_env, comments)
      raise TypeCheckError, "if predicate must be Boolean, got #{pred_ty}" unless pred_ty == { tag: :Boolean }
      thn_ty = typecheck(statements.body.last, ty_env, comments)
      els_ty = typecheck(subsequent.statements.body.last, ty_env, comments)
      raise TypeCheckError, "if branches must have same type: #{thn_ty} vs #{els_ty}" unless thn_ty == els_ty
      thn_ty
    in Prism::LocalVariableReadNode[name:]
      ty_env.fetch(name) { raise TypeCheckError, "Unbound variable: #{name}" }
    in Prism::LambdaNode
      raise TypeCheckError, "Lambda requires @sig annotation (handle in StatementsNode)"
    in Prism::CallNode[receiver: nil, name:, arguments: args_node]
      func_ty = ty_env.fetch(name) { raise TypeCheckError, "Unbound function: #{name}" }
      raise TypeCheckError, "#{name} is not a function, got #{func_ty}" unless func_ty[:tag] == :Func
      args = args_node ? args_node.arguments : []
      raise TypeCheckError, "Argument count mismatch: expected #{func_ty[:params].length}, got #{args.length}" unless func_ty[:params].length == args.length
      args.each_with_index do |arg, i|
        arg_ty = typecheck(arg, ty_env, comments)
        raise TypeCheckError, "Argument #{i + 1} type mismatch: expected #{func_ty[:params][i]}, got #{arg_ty}" unless arg_ty == func_ty[:params][i]
      end
      func_ty[:ret_type]
    in Prism::LocalVariableWriteNode
      raise TypeCheckError, "LocalVariableWriteNode must be handled in StatementsNode"
    in Prism::ProgramNode[statements:]
      typecheck(statements, ty_env, comments)
    in Prism::StatementsNode[body:]
      current_env = ty_env.dup
      last_ty = { tag: :Boolean }
      body.each do |stmt|
        case stmt
        in Prism::LocalVariableWriteNode[name:, value:] => write_node
          if value.is_a?(Prism::LambdaNode)
            sig_text = find_sig_comment(comments, write_node.location.start_line)
            raise TypeCheckError, "Lambda '#{name}' requires @sig annotation" unless sig_text
            parsed = parse_sig(sig_text)
            param_names = value.parameters&.parameters&.requireds&.map(&:name) || []
            raise TypeCheckError, "@sig param count mismatch" unless param_names.length == parsed[:params].length
            func_ty = { tag: :Func, params: parsed[:params], ret_type: parsed[:ret_type] }
            inner_env = current_env.merge({ name => func_ty })
            param_names.each_with_index { |pname, i| inner_env[pname] = parsed[:params][i] }
            body_ty = typecheck(value.body, inner_env, comments)
            raise TypeCheckError, "Lambda body type #{body_ty} != @sig return type #{parsed[:ret_type]}" unless body_ty == parsed[:ret_type]
            current_env[name] = func_ty
          else
            val_ty = typecheck(value, current_env, comments)
            current_env[name] = val_ty
          end
          last_ty = current_env[name]
        else
          last_ty = typecheck(stmt, current_env, comments)
        end
      end
      last_ty
    else
      raise TypeCheckError, "Unknown node: #{node.class}"
    end
  end

  def self.typecheck_source(src)
    result = Prism.parse(src)
    typecheck(result.value, {}, result.comments)
  end
end

if __FILE__ == $0
  examples = [
    "1 + 2",
    "true ? 1 : 2",
    "# @sig (Integer) -> Integer\nf = ->(x) { x + 1 }\nf(2)",
    "x = 1\ny = 2\nx + y",
  ]
  examples.each do |src|
    ty = Basic.typecheck_source(src)
    puts "#{src.strip.split("\n").last.ljust(20)} => #{ty}"
  rescue Basic::TypeCheckError => e
    puts "ERROR: #{e.message}"
  end
end
