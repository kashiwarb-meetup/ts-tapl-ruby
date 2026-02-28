require "prism"

# Chapter 9: Generics (Parametric Polymorphism)
# Extends basic.rb with: PolyType and TypeVar.
# @sig annotation: "# @sig <T>(T) -> T" for generic functions.
# Type application happens at call sites via unification.

module Poly
  class TypeCheckError < StandardError; end

  SIG_TYPE_MAP = {
    "Integer" => { tag: :Number },
    "Boolean" => { tag: :Boolean },
  }

  def self.parse_sig_type(str, type_vars = [])
    str = str.strip
    if type_vars.include?(str.to_sym) || (str =~ /\A[A-Z]\z/)
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
    type_params = []
    if sig_str.start_with?("<")
      close = sig_str.index(">")
      raise TypeCheckError, "Missing '>' in type params" unless close
      type_params = sig_str[1...close].split(",").map { |s| s.strip.to_sym }
      sig_str = sig_str[close + 1..].strip
    end
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
    params = param_str.empty? ? [] : split_sig_types(param_str).map { |s| parse_sig_type(s, type_params) }
    ret_type = parse_sig_type(ret_str, type_params)
    { type_params: type_params, params: params, ret_type: ret_type }
  end

  def self.find_sig_comment(comments, node_line)
    comments.each do |comment|
      next unless comment.location.start_line == node_line - 1
      text = comment.location.slice
      return text.sub(/\A#\s*@sig\s*/, "") if text.include?("@sig")
    end
    nil
  end

  def self.type_subst(ty, var_name, subst_ty)
    case ty[:tag]
    when :TypeVar
      ty[:name] == var_name ? subst_ty : ty
    when :Obj
      { tag: :Obj, props: ty[:props].transform_values { |v| type_subst(v, var_name, subst_ty) } }
    when :Func
      { tag: :Func, params: ty[:params].map { |p| type_subst(p, var_name, subst_ty) }, ret_type: type_subst(ty[:ret_type], var_name, subst_ty) }
    when :PolyType
      if ty[:type_params].include?(var_name)
        ty
      else
        { tag: :PolyType, type_params: ty[:type_params], params: ty[:params].map { |p| type_subst(p, var_name, subst_ty) }, ret_type: type_subst(ty[:ret_type], var_name, subst_ty) }
      end
    else
      ty
    end
  end

  def self.apply_subst(ty, subst)
    return ty if subst.empty?
    case ty[:tag]
    when :TypeVar
      subst.key?(ty[:name]) ? apply_subst(subst[ty[:name]], subst) : ty
    when :Obj
      { tag: :Obj, props: ty[:props].transform_values { |v| apply_subst(v, subst) } }
    when :Func
      { tag: :Func, params: ty[:params].map { |p| apply_subst(p, subst) }, ret_type: apply_subst(ty[:ret_type], subst) }
    when :PolyType
      { tag: :PolyType, type_params: ty[:type_params], params: ty[:params].map { |p| apply_subst(p, subst) }, ret_type: apply_subst(ty[:ret_type], subst) }
    else
      ty
    end
  end

  def self.occurs?(var_name, ty)
    case ty[:tag]
    when :TypeVar then ty[:name] == var_name
    when :Obj then ty[:props].values.any? { |v| occurs?(var_name, v) }
    when :Func then ty[:params].any? { |p| occurs?(var_name, p) } || occurs?(var_name, ty[:ret_type])
    else false
    end
  end

  def self.unify(ty, expected, subst = {})
    ty       = apply_subst(ty, subst)
    expected = apply_subst(expected, subst)
    return subst if ty == expected

    if ty[:tag] == :TypeVar
      raise TypeCheckError, "Occurs check: #{ty[:name]} in #{expected}" if occurs?(ty[:name], expected)
      return subst.merge(ty[:name] => expected)
    elsif expected[:tag] == :TypeVar
      raise TypeCheckError, "Occurs check: #{expected[:name]} in #{ty}" if occurs?(expected[:name], ty)
      return subst.merge(expected[:name] => ty)
    end

    case [ty[:tag], expected[:tag]]
    when [:Obj, :Obj]
      raise TypeCheckError, "Object shape mismatch: #{ty} vs #{expected}" unless ty[:props].keys.sort == expected[:props].keys.sort
      ty[:props].reduce(subst) { |s, (k, v)| unify(v, expected[:props][k], s) }
    when [:Func, :Func]
      raise TypeCheckError, "Func arity mismatch" unless ty[:params].length == expected[:params].length
      s = ty[:params].each_with_index.reduce(subst) { |s, (p, i)| unify(p, expected[:params][i], s) }
      unify(ty[:ret_type], expected[:ret_type], s)
    else
      raise TypeCheckError, "Cannot unify #{ty} with #{expected}"
    end
  end

  def self.type_eq(a, b)
    return false unless a[:tag] == b[:tag]
    case a[:tag]
    when :Boolean, :Number then true
    when :TypeVar then a[:name] == b[:name]
    when :Obj
      return false unless a[:props].keys.sort == b[:props].keys.sort
      a[:props].all? { |k, v| type_eq(v, b[:props][k]) }
    when :Func
      return false unless a[:params].length == b[:params].length
      a[:params].each_with_index.all? { |p, i| type_eq(p, b[:params][i]) } && type_eq(a[:ret_type], b[:ret_type])
    when :PolyType
      return false unless a[:type_params] == b[:type_params]
      return false unless a[:params].length == b[:params].length
      a[:params].each_with_index.all? { |p, i| type_eq(p, b[:params][i]) } && type_eq(a[:ret_type], b[:ret_type])
    else
      a == b
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
      raise TypeCheckError, "Property access requires Obj type, got #{obj_ty}" unless obj_ty[:tag] == :Obj
      key = prop_name.to_sym
      obj_ty[:props].fetch(key) { raise TypeCheckError, "Property #{key} not found" }
    in Prism::CallNode[receiver: nil, name:, arguments: args_node]
      func_ty = ty_env.fetch(name) { raise TypeCheckError, "Unbound function: #{name}" }
      args = args_node ? args_node.arguments : []

      if func_ty[:tag] == :PolyType
        # Freshen type vars to avoid capture
        fresh_vars = {}
        func_ty[:type_params].each { |tv| fresh_vars[tv] = { tag: :TypeVar, name: :"#{tv}_#{object_id}_#{rand(9999)}" } }
        fresh_params   = func_ty[:params].map   { |p| apply_subst(p, fresh_vars) }
        fresh_ret_type = apply_subst(func_ty[:ret_type], fresh_vars)
        raise TypeCheckError, "Argument count mismatch" unless fresh_params.length == args.length
        subst = {}
        args.each_with_index do |arg, i|
          arg_ty = typecheck(arg, ty_env, comments)
          subst = unify(fresh_params[i], arg_ty, subst)
        end
        apply_subst(fresh_ret_type, subst)
      elsif func_ty[:tag] == :Func
        raise TypeCheckError, "Argument count mismatch" unless func_ty[:params].length == args.length
        args.each_with_index do |arg, i|
          arg_ty = typecheck(arg, ty_env, comments)
          raise TypeCheckError, "Argument #{i + 1} type mismatch: expected #{func_ty[:params][i]}, got #{arg_ty}" unless type_eq(arg_ty, func_ty[:params][i])
        end
        func_ty[:ret_type]
      else
        raise TypeCheckError, "#{name} is not a function, got #{func_ty}"
      end
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

            if parsed[:type_params].empty?
              func_ty = { tag: :Func, params: parsed[:params], ret_type: parsed[:ret_type] }
              inner_env = current_env.merge({ name => func_ty })
              param_names.each_with_index { |pname, i| inner_env[pname] = parsed[:params][i] }
              body_ty = typecheck(value.body, inner_env, comments)
              raise TypeCheckError, "Lambda body type #{body_ty} != @sig return type #{parsed[:ret_type]}" unless type_eq(body_ty, parsed[:ret_type])
              current_env[name] = func_ty
            else
              poly_ty = { tag: :PolyType, type_params: parsed[:type_params], params: parsed[:params], ret_type: parsed[:ret_type] }
              inner_env = current_env.merge({ name => poly_ty })
              param_names.each_with_index { |pname, i| inner_env[pname] = parsed[:params][i] }
              typecheck(value.body, inner_env, comments)
              current_env[name] = poly_ty
            end
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
    "# @sig <T>(T) -> T\nidentity = ->(x) { x }\nidentity(42)",
    "# @sig <T>(T) -> T\nidentity = ->(x) { x }\nidentity(true)",
  ].each do |src|
    ty = Poly.typecheck_source(src)
    puts "=> #{ty}"
  rescue Poly::TypeCheckError => e
    puts "ERROR: #{e.message}"
  end
end
