require "prism"

# Chapter 7: Subtyping
# Extends obj.rb with is_subtype(s, t) replacing type_eq for compatibility checks.
# Object subtyping: structural (width & depth). Function: contravariant params, covariant return.

module Sub
  class TypeCheckError < StandardError; end

  SIG_TYPE_MAP = {
    "Integer" => { tag: :Number },
    "Boolean" => { tag: :Boolean },
  }

  def self.parse_sig_type(str)
    str = str.strip
    if str.start_with?("{") && str.end_with?("}")
      inner = str[1..-2].strip
      props = {}
      split_sig_types(inner).each do |pair|
        colon_idx = pair.index(":")
        key_str = pair[0...colon_idx].strip
        val_str = pair[colon_idx + 1..].strip
        props[key_str.to_sym] = parse_sig_type(val_str)
      end
      return { tag: :Obj, props: props }
    end
    SIG_TYPE_MAP.fetch(str) { raise TypeCheckError, "Unknown type in @sig: #{str}" }
  end

  def self.split_sig_types(str)
    parts = []
    depth = 0
    current = ""
    str.chars.each do |ch|
      case ch
      when "{" then depth += 1; current << ch
      when "}" then depth -= 1; current << ch
      when ","
        if depth == 0
          parts << current.strip
          current = ""
        else
          current << ch
        end
      else
        current << ch
      end
    end
    parts << current.strip unless current.strip.empty?
    parts
  end

  def self.parse_sig(sig_str)
    sig_str = sig_str.strip
    raise TypeCheckError, "Invalid @sig format: #{sig_str}" unless sig_str.start_with?("(")
    depth = 0
    close_idx = nil
    sig_str.chars.each_with_index do |ch, i|
      case ch
      when "(" then depth += 1
      when ")"
        depth -= 1
        if depth == 0
          close_idx = i
          break
        end
      end
    end
    raise TypeCheckError, "Unmatched parenthesis in @sig: #{sig_str}" unless close_idx
    param_str = sig_str[1...close_idx].strip
    rest = sig_str[close_idx + 1..].strip
    raise TypeCheckError, "Missing '->' in @sig: #{sig_str}" unless rest.start_with?("->")
    ret_str = rest[2..].strip
    params = param_str.empty? ? [] : split_sig_types(param_str).map { |s| parse_sig_type(s) }
    ret_type = parse_sig_type(ret_str)
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

  def self.is_subtype(s, t)
    return true if s == t
    case [s[:tag], t[:tag]]
    when [:Boolean, :Boolean], [:Number, :Number]
      true
    when [:Obj, :Obj]
      t[:props].all? do |key, t_prop_ty|
        s_prop_ty = s[:props][key]
        s_prop_ty && is_subtype(s_prop_ty, t_prop_ty)
      end
    when [:Func, :Func]
      return false unless s[:params].length == t[:params].length
      params_ok = s[:params].each_with_index.all? { |s_param, i| is_subtype(t[:params][i], s_param) }
      ret_ok    = is_subtype(s[:ret_type], t[:ret_type])
      params_ok && ret_ok
    else
      false
    end
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
      raise TypeCheckError, "'+' requires Number" unless is_subtype(left_ty, { tag: :Number }) && is_subtype(right_ty, { tag: :Number })
      { tag: :Number }
    in Prism::CallNode[name: :==, receiver:, arguments: Prism::ArgumentsNode[arguments: [_right]]]
      typecheck(receiver, ty_env, comments)
      { tag: :Boolean }
    in Prism::IfNode[predicate:, statements:, subsequent:]
      pred_ty = typecheck(predicate, ty_env, comments)
      raise TypeCheckError, "if predicate must be Boolean, got #{pred_ty}" unless is_subtype(pred_ty, { tag: :Boolean })
      thn_ty = typecheck(statements.body.last, ty_env, comments)
      els_ty = typecheck(subsequent.statements.body.last, ty_env, comments)
      raise TypeCheckError, "if branches must have same type: #{thn_ty} vs #{els_ty}" unless is_subtype(thn_ty, els_ty) && is_subtype(els_ty, thn_ty)
      thn_ty
    in Prism::LocalVariableReadNode[name:]
      ty_env.fetch(name) { raise TypeCheckError, "Unbound variable: #{name}" }
    in Prism::HashNode[elements:]
      props = {}
      elements.each do |assoc|
        key = assoc.key.unescaped.to_sym
        val_ty = typecheck(assoc.value, ty_env, comments)
        props[key] = val_ty
      end
      { tag: :Obj, props: props }
    in Prism::CallNode[name: :[], receiver:, arguments: Prism::ArgumentsNode[arguments: [Prism::SymbolNode[unescaped: prop_name]]]]
      obj_ty = typecheck(receiver, ty_env, comments)
      raise TypeCheckError, "Property access requires Obj type, got #{obj_ty}" unless obj_ty[:tag] == :Obj
      key = prop_name.to_sym
      obj_ty[:props].fetch(key) { raise TypeCheckError, "Property #{key} not found" }
    in Prism::CallNode[receiver: nil, name:, arguments: args_node]
      func_ty = ty_env.fetch(name) { raise TypeCheckError, "Unbound function: #{name}" }
      raise TypeCheckError, "#{name} is not a function, got #{func_ty}" unless func_ty[:tag] == :Func
      args = args_node ? args_node.arguments : []
      raise TypeCheckError, "Argument count mismatch" unless func_ty[:params].length == args.length
      args.each_with_index do |arg, i|
        arg_ty = typecheck(arg, ty_env, comments)
        raise TypeCheckError, "Argument #{i + 1}: #{arg_ty} is not a subtype of #{func_ty[:params][i]}" unless is_subtype(arg_ty, func_ty[:params][i])
      end
      func_ty[:ret_type]
    in Prism::LambdaNode
      raise TypeCheckError, "Lambda requires @sig annotation"
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
            raise TypeCheckError, "Lambda body type #{body_ty} not subtype of @sig return type #{parsed[:ret_type]}" unless is_subtype(body_ty, parsed[:ret_type])
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
  [
    "# @sig ({ x: Integer }) -> Integer\nget_x = ->(obj) { obj[:x] }\nget_x({x: 10, y: 20})",
  ].each do |src|
    ty = Sub.typecheck_source(src)
    puts "=> #{ty}"
  rescue Sub::TypeCheckError => e
    puts "ERROR: #{e.message}"
  end
end
