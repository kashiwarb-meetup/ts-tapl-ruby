require "prism"

# Chapter 8: Recursive Types (iso-recursive, with Mu/TypeVar)
# Extends obj.rb with: Mu types and TypeVar.
# simplify_type() unfolds one level: Mu<X, T> => T[X := Mu<X,T>]

module Rec
  class TypeCheckError < StandardError; end

  SIG_TYPE_MAP = {
    "Integer" => { tag: :Number },
    "Boolean" => { tag: :Boolean },
  }

  # Type substitution: replace var_name with subst_ty in ty
  def self.type_subst(ty, var_name, subst_ty)
    case ty[:tag]
    when :TypeVar
      ty[:name] == var_name ? subst_ty : ty
    when :Mu
      if ty[:type_var] == var_name
        ty # bound variable
      else
        { tag: :Mu, type_var: ty[:type_var], type: type_subst(ty[:type], var_name, subst_ty) }
      end
    when :Obj
      { tag: :Obj, props: ty[:props].transform_values { |v| type_subst(v, var_name, subst_ty) } }
    when :Func
      { tag: :Func,
        params:   ty[:params].map { |p| type_subst(p, var_name, subst_ty) },
        ret_type: type_subst(ty[:ret_type], var_name, subst_ty) }
    else
      ty
    end
  end

  # Unfold Mu one level: Mu<X, T> becomes T[X := Mu<X,T>]
  def self.simplify_type(ty)
    return ty unless ty[:tag] == :Mu
    type_subst(ty[:type], ty[:type_var], ty)
  end

  def self.type_eq(a, b, seen = [])
    pair = [a.object_id, b.object_id]
    return true if seen.include?(pair)
    seen = seen + [pair]
    a = simplify_type(a) if a[:tag] == :Mu
    b = simplify_type(b) if b[:tag] == :Mu
    return false unless a[:tag] == b[:tag]
    case a[:tag]
    when :Boolean, :Number then true
    when :TypeVar then a[:name] == b[:name]
    when :Obj
      return false unless a[:props].keys.sort == b[:props].keys.sort
      a[:props].all? { |k, v| type_eq(v, b[:props][k], seen) }
    when :Func
      return false unless a[:params].length == b[:params].length
      a[:params].each_with_index.all? { |p, i| type_eq(p, b[:params][i], seen) } &&
        type_eq(a[:ret_type], b[:ret_type], seen)
    else
      a == b
    end
  end

  def self.parse_sig_type(str, type_vars = [])
    str = str.strip
    if str =~ /\AMu<(\w+),\s*(.+)>\z/m
      var_name = $1.to_sym
      inner_ty = parse_sig_type($2.strip, type_vars + [var_name])
      return { tag: :Mu, type_var: var_name, type: inner_ty }
    end
    if type_vars.include?(str.to_sym)
      return { tag: :TypeVar, name: str.to_sym }
    end
    if str.start_with?("{") && str.end_with?("}")
      inner = str[1..-2].strip
      props = {}
      split_sig_types(inner).each do |pair|
        colon_idx = pair.index(":")
        key_str = pair[0...colon_idx].strip
        val_str = pair[colon_idx + 1..].strip
        props[key_str.to_sym] = parse_sig_type(val_str, type_vars)
      end
      return { tag: :Obj, props: props }
    end
    SIG_TYPE_MAP.fetch(str) { raise TypeCheckError, "Unknown type in @sig: #{str}" }
  end

  def self.split_sig_types(str)
    parts = []
    depth_brace = 0
    depth_angle = 0
    current = ""
    str.chars.each do |ch|
      case ch
      when "{" then depth_brace += 1; current << ch
      when "}" then depth_brace -= 1; current << ch
      when "<" then depth_angle += 1; current << ch
      when ">" then depth_angle -= 1; current << ch
      when ","
        if depth_brace == 0 && depth_angle == 0
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
      raise TypeCheckError, "'+' requires Number" unless type_eq(left_ty, { tag: :Number }) && type_eq(right_ty, { tag: :Number })
      { tag: :Number }
    in Prism::IfNode[predicate:, statements:, subsequent:]
      pred_ty = typecheck(predicate, ty_env, comments)
      raise TypeCheckError, "if predicate must be Boolean" unless type_eq(pred_ty, { tag: :Boolean })
      thn_ty = typecheck(statements.body.last, ty_env, comments)
      els_ty = typecheck(subsequent.statements.body.last, ty_env, comments)
      raise TypeCheckError, "if branches must have same type" unless type_eq(thn_ty, els_ty)
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
      obj_ty = simplify_type(obj_ty) if obj_ty[:tag] == :Mu
      raise TypeCheckError, "Property access requires Obj type, got #{obj_ty}" unless obj_ty[:tag] == :Obj
      key = prop_name.to_sym
      obj_ty[:props].fetch(key) { raise TypeCheckError, "Property #{key} not found" }
    in Prism::CallNode[receiver: nil, name:, arguments: args_node]
      func_ty = ty_env.fetch(name) { raise TypeCheckError, "Unbound function: #{name}" }
      func_ty = simplify_type(func_ty) if func_ty[:tag] == :Mu
      raise TypeCheckError, "#{name} is not a function, got #{func_ty}" unless func_ty[:tag] == :Func
      args = args_node ? args_node.arguments : []
      raise TypeCheckError, "Argument count mismatch" unless func_ty[:params].length == args.length
      args.each_with_index do |arg, i|
        arg_ty = typecheck(arg, ty_env, comments)
        raise TypeCheckError, "Argument #{i + 1} type mismatch" unless type_eq(arg_ty, func_ty[:params][i])
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
            raise TypeCheckError, "Lambda body type #{body_ty} != @sig return type #{parsed[:ret_type]}" unless type_eq(body_ty, parsed[:ret_type])
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
  list_type = { tag: :Mu, type_var: :X, type: { tag: :Obj, props: { val: { tag: :Number }, next: { tag: :TypeVar, name: :X } } } }
  puts "List type: #{list_type}"
  unfolded = Rec.simplify_type(list_type)
  puts "Unfolded:  #{unfolded}"
  puts "val type:  #{unfolded[:props][:val]}"
  puts "next type: #{unfolded[:props][:next][:tag]}"

  ty = Rec.typecheck_source("1 + 2")
  puts "1 + 2 => #{ty}"
end
