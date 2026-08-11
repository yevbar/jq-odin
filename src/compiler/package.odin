// Package compiler lowers source syntax into a compiled program.
package compiler

import "base:runtime"
import diagnostic "jq:diagnostic"
import program "jq:program"
import syntax "jq:syntax"

Lower_Error_Kind :: enum u8 {
	None,
	Invalid_AST,
	Size_Overflow,
	Resource_Failure,
}

Lower_Outcome :: struct {
	kind:           Lower_Error_Kind,
	resource_error: runtime.Allocator_Error,
}

@(private="package")
checked_count_add :: proc(total: ^u64, amount: u64) -> bool {
	if amount > u64(max(program.Count)) || total^ > u64(max(program.Count)) - amount {
		return false
	}
	total^ += amount
	return true
}

@(private="package")
literal_number_is_zero :: proc(text: string) -> bool {
	seen_digit := false
	for c in text {
		if c == 'e' || c == 'E' do break
		if c >= '0' && c <= '9' {
			seen_digit = true
			if c != '0' do return false
		}
	}
	return seen_digit
}

@(private="package")
node_reference_valid :: proc(id: syntax.Node_Id, node_count: int) -> bool {
	return int(id) >= 0 && int(id) < node_count
}

@(private="package")
binary_opcode :: proc(operator: syntax.Binary_Operator) -> (program.Opcode, bool) {
	switch operator {
	case .Add:          return .Add, true
	case .Subtract:     return .Subtract, true
	case .Multiply:     return .Multiply, true
	case .Divide:       return .Divide, true
	case .Modulo:       return .Modulo, true
	case .Equal:        return .Equal, true
	case .Not_Equal:    return .Not_Equal, true
	case .Less:         return .Less, true
	case .Less_Equal:   return .Less_Equal, true
	case .Greater:      return .Greater, true
	case .Greater_Equal: return .Greater_Equal, true
	case .Defined_Or, .Or, .And:
		return {}, false
	}
	return {}, false
}

@(private="package")
string_header_absent :: proc(text: string) -> bool {
	header := transmute(runtime.Raw_String)text
	return header.data == nil && header.len == 0
}

@(private="package")
node_payload_shape_valid :: proc(node: syntax.Node) -> bool {
	switch node.form {
	case .Kinded:
		if node.binary_operator != {} ||
		   node.operator_span != (diagnostic.Span{}) ||
		   node.has_operator_span {
			return false
		}
	case .Binary:
		return node.kind == .Identity &&
		       node.container_kind == .None && !node.has_next && node.next == 0 &&
		       !node.has_value && node.value == 0 && !node.has_key && node.key == 0 &&
		       !node.has_child && node.child == 0 &&
		       node.left >= 0 && node.right >= 0 &&
		       !node.has_name_span && node.name_span == (diagnostic.Span{}) &&
		       !node.boolean_value && !node.has_number_text && string_header_absent(node.number_text) &&
		       !node.has_string_text && string_header_absent(node.string_text) &&
		       node.has_operator_span
	case:
		return false
	}

	no_child := !node.has_child && node.child == 0
	no_edges := node.left == 0 && node.right == 0
	no_name := !node.has_name_span && node.name_span == diagnostic.Span{}
	no_number := !node.has_number_text && string_header_absent(node.number_text)
	no_container_links := !node.has_next && node.next == 0 && !node.has_key && node.key == 0

	switch node.kind {
	case .Identity:
		if node.container_kind == .Array || node.container_kind == .Object {
			return no_child && no_edges && no_name && no_container_links &&
			       !node.boolean_value && no_number && !node.has_string_text &&
			       string_header_absent(node.string_text) &&
			       (!node.has_value || node.value >= 0)
		}
		return no_child && no_edges && no_name && no_container_links && !node.has_value &&
		       node.value == 0 && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Null:
		return no_child && no_edges && no_name && no_container_links && !node.has_value &&
		       node.value == 0 && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal:
		return no_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text &&
			string_header_absent(node.string_text)
	case .Last:
		return no_child && no_edges && no_name && no_container_links && !node.has_value &&
			       !node.boolean_value && no_number && !node.has_string_text &&
			       string_header_absent(node.string_text)
	case .Flatten:
		return node.container_kind == .None && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && !node.has_string_text && string_header_absent(node.string_text) &&
		       (!node.has_child || node.child >= 0) && no_number
	case .Field:
		if node.container_kind == .Object_Entry {
			return no_child && no_edges && node.has_name_span && node.has_value &&
			       node.value >= 0 && node.has_key && node.key >= 0 &&
			       (!node.has_next || node.next >= 0) && !node.boolean_value && no_number &&
			       !node.has_string_text && string_header_absent(node.string_text)
		}
		return node.container_kind == .None && (node.has_child || node.child == 0) && no_edges && no_container_links && !node.has_value &&
		       node.has_name_span && !node.boolean_value && no_number &&
		       ((!node.has_string_text && string_header_absent(node.string_text) && !node.string_shorthand) ||
			        (node.has_string_text && node.string_shorthand && string_header_present(node.string_text)))
	case .Index:
		header := transmute(runtime.Raw_String)node.number_text
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && node.has_number_text && header.data != nil && header.len > 0 &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Join:
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text && string_header_absent(node.string_text)
	case .Contains:
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text && string_header_absent(node.string_text)
	case .Split:
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text && string_header_absent(node.string_text)
	case .Index_Builtin, .Rindex_Builtin, .Indices_Builtin:
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text && string_header_absent(node.string_text)
	case .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr:
		return node.container_kind == .None && node.has_child && no_edges && no_name && no_container_links && !node.has_value &&
		       !node.boolean_value && no_number && !node.has_string_text && string_header_absent(node.string_text)
	case .Variable:
		return node.container_kind == .None && no_child && no_edges && no_container_links &&
		       !node.has_value && node.has_name_span && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Binding:
		return node.container_kind == .None && no_child && no_container_links &&
		       !node.has_value && node.left >= 0 && node.right >= 0 &&
		       node.has_name_span && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Reduce:
		return node.container_kind == .None && no_child && node.left >= 0 && node.right >= 0 && node.reduce_update >= 0 && node.has_name_span
	case .Parenthesized, .Optional, .Negate:
		return node.has_child && no_edges && no_name && no_container_links && !node.has_value && node.value == 0 && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Comma, .Pipe:
		return no_child && no_name && no_container_links && !node.has_value && node.value == 0 && !node.boolean_value && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Boolean:
		return no_child && no_edges && no_name && no_container_links && !node.has_value && node.value == 0 && no_number &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .Number:
		header := transmute(runtime.Raw_String)node.number_text
		return no_child && no_edges && no_name && no_container_links && !node.has_value && node.value == 0 && !node.boolean_value &&
		       node.has_number_text && header.data != nil && header.len > 0 &&
		       !node.has_string_text && string_header_absent(node.string_text)
	case .String:
		header := transmute(runtime.Raw_String)node.string_text
		return no_child && no_edges && no_name && no_container_links && !node.has_value && node.value == 0 && !node.boolean_value && no_number &&
		       node.has_string_text && header.data != nil && header.len >= 0
	case:
		return false
	}
}

@(private="package")
string_header_present :: proc(text: string) -> bool {
	header := transmute(runtime.Raw_String)text
	return header.data != nil
}

@(private="package")
constant_non_string_key :: proc(nodes: []syntax.Node, id: syntax.Node_Id) -> bool {
	if !node_reference_valid(id, len(nodes)) do return false
	node := nodes[int(id)]
	if node.kind == .Parenthesized || node.kind == .Optional {
		if !node.has_child do return false
		return constant_non_string_key(nodes, node.child)
	}
	return node.kind == .Number || node.kind == .Boolean || node.kind == .Null
}

@(private="package")
span_to_program :: proc(
	source: diagnostic.Source,
	span: diagnostic.Span,
) -> (program.Source_Span, Lower_Error_Kind) {
	start, end, ok := diagnostic.span_offsets(source, span)
	if !ok {
		return {}, .Invalid_AST
	}
	if u64(start) > u64(max(program.Source_Offset)) ||
	   u64(end) > u64(max(program.Source_Offset)) {
		return {}, .Size_Overflow
	}
	return program.Source_Span{
		start = program.Source_Offset(start),
		end = program.Source_Offset(end),
	}, .None
}

@(private="package")
binding_name_equal :: proc(source: diagnostic.Source, left, right: diagnostic.Span) -> bool {
	ls, le, lok := diagnostic.span_offsets(source, left)
	rs, re, rok := diagnostic.span_offsets(source, right)
	if !lok || !rok || le-ls != re-rs do return false
	bytes := diagnostic.source_bytes(source)
	return bytes[ls:le] == bytes[rs:re]
}

@(private="package")
validate_binding_scopes :: proc(nodes: []syntax.Node, id: syntax.Node_Id, source: diagnostic.Source, scopes: []diagnostic.Span, depth, budget: int) -> bool {
	// A malformed syntax arena may contain cycles. Bound the non-allocating
	// scope walk before following any edge so invalid cyclic input cannot
	// overflow the host stack.
	if budget <= 0 || !node_reference_valid(id, len(nodes)) do return false
	next_budget := budget - 1
	node := nodes[int(id)]
	if node.form == .Binary {
		return validate_binding_scopes(nodes, node.left, source, scopes, depth, next_budget) && validate_binding_scopes(nodes, node.right, source, scopes, depth, next_budget)
	}
	switch node.kind {
	case .Last:
		return true
	case .Variable:
		for index := depth-1; index >= 0; index -= 1 {
			if binding_name_equal(source, node.name_span, scopes[index]) do return true
		}
		return false
	case .Binding:
		if !validate_binding_scopes(nodes, node.left, source, scopes, depth, next_budget) do return false
		if depth >= len(scopes) do return false
		scopes[depth] = node.name_span
		return validate_binding_scopes(nodes, node.right, source, scopes, depth+1, next_budget)
	case .Reduce:
		if !validate_binding_scopes(nodes, node.left, source, scopes, depth, next_budget) || !validate_binding_scopes(nodes, node.right, source, scopes, depth, next_budget) do return false
		if depth >= len(scopes) do return false
		scopes[depth] = node.name_span
		return validate_binding_scopes(nodes, node.reduce_update, source, scopes, depth+1, next_budget)
	case .Parenthesized, .Optional, .Negate:
		return validate_binding_scopes(nodes, node.child, source, scopes, depth, next_budget)
	case .Comma, .Pipe:
		return validate_binding_scopes(nodes, node.left, source, scopes, depth, next_budget) && validate_binding_scopes(nodes, node.right, source, scopes, depth, next_budget)
	case .Field:
		if node.container_kind == .Object_Entry {
			return validate_binding_scopes(nodes, node.key, source, scopes, depth, next_budget) && validate_binding_scopes(nodes, node.value, source, scopes, depth, next_budget)
		}
		if node.has_child do return validate_binding_scopes(nodes, node.child, source, scopes, depth, next_budget)
	case .Index:
		return validate_binding_scopes(nodes, node.child, source, scopes, depth, next_budget)
	case .Flatten:
		if node.has_child do return validate_binding_scopes(nodes, node.child, source, scopes, depth, next_budget)
	case .Join, .Contains, .Split, .Index_Builtin, .Rindex_Builtin, .Indices_Builtin, .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr:
		return validate_binding_scopes(nodes, node.child, source, scopes, depth, next_budget)
	case .Identity:
		if node.container_kind == .Array && node.has_value do return validate_binding_scopes(nodes, node.value, source, scopes, depth, next_budget)
		if node.container_kind == .Object && node.has_value {
			current := node.value
			for {
				if !validate_binding_scopes(nodes, current, source, scopes, depth, next_budget) do return false
				entry := nodes[int(current)]
				if !entry.has_next do break
				current = entry.next
			}
		}
	case .Null, .Boolean, .Number, .String, .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal:
		return true
	}
	return true
}

// lower_filter translates a complete borrowed syntax arena into one owned,
// source-independent Program. It performs a non-allocating validation/counting
// pass before Program's single exact allocation, then fills storage in arena
// order. On ordinary failure output remains inert. If retiring a malformed
// allocator result itself fails, output is Cleanup_Failed and must be passed to
// program.destroy_program until cleanup succeeds.
lower_filter :: proc(
	output: ^program.Program,
	nodes: []syntax.Node,
	root: syntax.Node_Id,
	source: diagnostic.Source,
	allocator: runtime.Allocator,
) -> Lower_Outcome {
	if output == nil || program.program_is_active(output) || program.program_is_building(output) ||
	   len(nodes) == 0 ||
	   !node_reference_valid(root, len(nodes)) {
		return Lower_Outcome{kind = .Invalid_AST}
	}
	if u64(len(nodes)) > u64(max(program.Count)) {
		return Lower_Outcome{kind = .Size_Overflow}
	}
	scope_stack: [1024]diagnostic.Span

	operand_count: u64
	text_count: u64
	has_unlowered_node := false
	for node in nodes {
		switch node.form {
		case .Kinded:
		case .Binary:
		case:
			return Lower_Outcome{kind = .Invalid_AST}
		}
		_, span_error := span_to_program(source, node.span)
		if span_error != .None {
			return Lower_Outcome{kind = span_error}
		}
		if !node_payload_shape_valid(node) {
			return Lower_Outcome{kind = .Invalid_AST}
		}
		if node.form == .Binary {
			_, operator_error := span_to_program(source, node.operator_span)
			if operator_error != .None {
				return Lower_Outcome{kind = operator_error}
			}
			node_start, node_end, node_ok := diagnostic.span_offsets(source, node.span)
			operator_start, operator_end, operator_ok := diagnostic.span_offsets(source, node.operator_span)
			_, supported := binary_opcode(node.binary_operator)
			if !node_ok || !operator_ok || operator_start >= operator_end ||
			   operator_start < node_start || operator_end > node_end || !supported ||
			   !node_reference_valid(node.left, len(nodes)) ||
			   !node_reference_valid(node.right, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 2) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
			continue
		}

		switch node.kind {
		case .Identity:
			if node.container_kind == .Array {
				if node.has_value {
					if !node_reference_valid(node.value, len(nodes)) do return Lower_Outcome{kind = .Invalid_AST}
					if !checked_count_add(&operand_count, 1) do return Lower_Outcome{kind = .Size_Overflow}
				}
			} else if node.container_kind == .Object {
				current := node.value
				if node.has_value {
					for {
						if !node_reference_valid(current, len(nodes)) do return Lower_Outcome{kind = .Invalid_AST}
						entry := nodes[int(current)]
						if entry.kind != .Field || entry.container_kind != .Object_Entry ||
						   !entry.has_value || !entry.has_key || !node_reference_valid(entry.value, len(nodes)) ||
						   !node_reference_valid(entry.key, len(nodes)) {
							return Lower_Outcome{kind = .Invalid_AST}
						}
						key_node := nodes[int(entry.key)]
						key_bytes: u64
						if key_node.kind == .String && key_node.has_string_text {
							key_bytes = u64(len(key_node.string_text))
						} else if key_node.kind == .Field && key_node.has_name_span {
							key_start, key_end, key_ok := diagnostic.span_offsets(source, key_node.name_span)
							if !key_ok || key_end < key_start do return Lower_Outcome{kind = .Invalid_AST}
							key_bytes = u64(key_end-key_start)
						} else {
							if constant_non_string_key(nodes, entry.key) {
								return Lower_Outcome{kind = .Invalid_AST}
							}
							key_bytes = 0
						}
						if !checked_count_add(&operand_count, 2) ||
						   !checked_count_add(&text_count, key_bytes) {
							return Lower_Outcome{kind = .Invalid_AST}
						}
						if !entry.has_next do break
						current = entry.next
					}
				}
			}
		case .Field:
			if node.container_kind == .Object_Entry {
				// Entry nodes are owned by their Object constructor and are not
				// emitted as standalone instructions.
				break
			}
			if node.has_child && !node_reference_valid(node.child, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			if !name_ok || name_end < name_start ||
				(node.string_shorthand && (!node.has_string_text || !string_header_present(node.string_text))) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 1 + u64(node.has_child)) ||
				!checked_count_add(&text_count, u64(len(node.string_text) if node.string_shorthand else name_end-name_start)) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Index:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) ||
			   !checked_count_add(&operand_count, 2) ||
			   !checked_count_add(&text_count, u64(len(node.number_text))) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Flatten:
			if node.has_child && (!node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Join:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Contains:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Split:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Index_Builtin, .Rindex_Builtin, .Indices_Builtin:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr:
			if !node.has_child || !node_reference_valid(node.child, len(nodes)) || !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Variable:
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			if !name_ok || name_end < name_start do return Lower_Outcome{kind = .Invalid_AST}
			if !checked_count_add(&operand_count, 1) || !checked_count_add(&text_count, u64(name_end-name_start)) do return Lower_Outcome{kind = .Size_Overflow}
		case .Binding:
			if !node_reference_valid(node.left, len(nodes)) || !node_reference_valid(node.right, len(nodes)) do return Lower_Outcome{kind = .Invalid_AST}
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			if !name_ok || name_end < name_start do return Lower_Outcome{kind = .Invalid_AST}
			if !checked_count_add(&operand_count, 3) || !checked_count_add(&text_count, u64(name_end-name_start)) do return Lower_Outcome{kind = .Size_Overflow}
		case .Reduce:
			if !node_reference_valid(node.left, len(nodes)) || !node_reference_valid(node.right, len(nodes)) || !node_reference_valid(node.reduce_update, len(nodes)) do return Lower_Outcome{kind=.Invalid_AST}
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			if !name_ok || !checked_count_add(&operand_count, 4) || !checked_count_add(&text_count, u64(name_end-name_start)) do return Lower_Outcome{kind=.Invalid_AST}
		case .Parenthesized, .Optional:
			if !node_reference_valid(node.child, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Comma, .Pipe:
			if !node_reference_valid(node.left, len(nodes)) ||
			   !node_reference_valid(node.right, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 2) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Negate:
			if !node_reference_valid(node.child, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			child := nodes[int(node.child)]
			if child.kind == .Number && !child.has_child && !child.has_value {
				prefix_bytes := 1 if !literal_number_is_zero(child.number_text) else 0
				if !checked_count_add(&operand_count, 1) || !checked_count_add(&text_count, u64(len(child.number_text) + prefix_bytes)) do return Lower_Outcome{kind = .Size_Overflow}
			} else {
				has_unlowered_node = true
			}
		case .Null, .Boolean:
		case .Number:
			if !checked_count_add(&text_count, u64(len(node.number_text))) ||
			   !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .String:
			if !checked_count_add(&text_count, u64(len(node.string_text))) ||
			   !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Last:
			// Last is an operand-free builtin.
	case .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal:
			// Builtin filters are operand-free instructions.
		case:
			return Lower_Outcome{kind = .Invalid_AST}
		}
	}
	if !validate_binding_scopes(nodes, root, source, scope_stack[:], 0, len(nodes)+1) {
		return Lower_Outcome{kind = .Invalid_AST}
	}
	if has_unlowered_node {
		return Lower_Outcome{kind = .Invalid_AST}
	}

	init_error := program.init_program(
		output,
		program.Count(len(nodes)),
		program.Count(operand_count),
		program.Count(text_count),
		allocator,
	)
	if init_error.kind != .None {
		kind := Lower_Error_Kind.Resource_Failure
		if init_error.kind == .Size_Overflow {
			kind = .Size_Overflow
		}
		return Lower_Outcome{kind = kind, resource_error = init_error.resource_error}
	}

	operand_at: u32
	text_at: u32
	bytes := diagnostic.source_bytes(source)
	for node, node_at in nodes {
		switch node.form {
		case .Kinded:
		case .Binary:
		case:
			cleanup_error := program.destroy_program(output)
			if cleanup_error != nil {
				return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
			}
			return Lower_Outcome{kind = .Invalid_AST}
		}
		if !node_payload_shape_valid(node) {
			cleanup_error := program.destroy_program(output)
			if cleanup_error != nil {
				return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
			}
			return Lower_Outcome{kind = .Invalid_AST}
		}
		span, span_error := span_to_program(source, node.span)
		assert(span_error == .None)
		instruction := program.Instruction{
			operands_start = program.Operand_Index(operand_at),
			span = span,
		}
		if node.form == .Binary {
			opcode, supported := binary_opcode(node.binary_operator)
			assert(supported)
			instruction.opcode = opcode
			instruction.has_operator_span = true
			operator_span, operator_error := span_to_program(source, node.operator_span)
			assert(operator_error == .None)
			instruction.operator_span = operator_span
			instruction.operands_count = 2
			children := [2]syntax.Node_Id{node.left, node.right}
			for child in children {
				write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
					kind = .Instruction,
					instruction = program.Instruction_Index(child),
				})
				assert(write_ok)
				operand_at += 1
			}
		} else {
		switch node.kind {
		case .Identity:
			if node.container_kind == .Array {
				instruction.opcode = .Array
				if node.has_value {
					write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
						kind = .Instruction,
						instruction = program.Instruction_Index(node.value),
					})
					assert(write_ok)
					operand_at += 1
					instruction.operands_count = 1
				}
			} else if node.container_kind == .Object {
				instruction.opcode = .Object
				if node.has_value {
					current := node.value
					for {
						entry := nodes[int(current)]
						key_node := nodes[int(entry.key)]
						if key_node.kind == .String && key_node.has_string_text {
							key := key_node.string_text
							text_ok := program.set_text(output, program.Byte_Offset(text_at), key)
							assert(text_ok)
							key_operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
								kind = .Text,
								text_start = program.Byte_Offset(text_at),
								text_count = program.Count(len(key)),
							})
							assert(key_operand_ok)
							operand_at += 1
							text_at += u32(len(key))
						} else if key_node.kind == .Field && key_node.has_name_span {
							key_start, key_end, key_ok := diagnostic.span_offsets(source, key_node.name_span)
							assert(key_ok)
							key := bytes[key_start:key_end]
							text_ok := program.set_text(output, program.Byte_Offset(text_at), key)
							assert(text_ok)
							key_operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
								kind = .Text,
								text_start = program.Byte_Offset(text_at),
								text_count = program.Count(len(key)),
							})
							assert(key_operand_ok)
							operand_at += 1
							text_at += u32(len(key))
						} else {
							key_operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
								kind = .Instruction,
								instruction = program.Instruction_Index(entry.key),
							})
							assert(key_operand_ok)
							operand_at += 1
						}
						value_operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
							kind = .Instruction,
							instruction = program.Instruction_Index(entry.value),
						})
						assert(value_operand_ok)
						operand_at += 1
						if !entry.has_next do break
						current = entry.next
					}
				}
				instruction.operands_count = program.Count(operand_at - u32(instruction.operands_start))
			} else {
				instruction.opcode = .Identity
			}
		case .Field:
			if node.container_kind == .Object_Entry {
				// Keep the arena index addressable for graph validation; object
				// constructors reference the entry value directly.
				instruction.opcode = .Identity
				break
			}
			instruction.opcode = .Field
			if node.has_child {
				write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
					kind = .Instruction,
					instruction = program.Instruction_Index(node.child),
				})
				assert(write_ok)
				operand_at += 1
			}
			name_start, name_end, _ := diagnostic.span_offsets(source, node.name_span)
			name := node.string_text if node.string_shorthand else bytes[name_start:name_end]
			text_ok := program.set_text(output, program.Byte_Offset(text_at), name)
			assert(text_ok)
			operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Text,
				text_start = program.Byte_Offset(text_at),
				text_count = program.Count(len(name)),
			})
			assert(operand_ok)
			operand_at += 1
			text_at += u32(len(name))
			instruction.operands_count = program.Count(1 + u32(node.has_child))
		case .Index:
			instruction.opcode = .Index
			instruction.operands_count = 2
			child_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.child),
			})
			assert(child_ok)
			operand_at += 1
			text_ok := program.set_text(output, program.Byte_Offset(text_at), node.number_text)
			assert(text_ok)
			index_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Text,
				text_start = program.Byte_Offset(text_at),
				text_count = program.Count(len(node.number_text)),
			})
			assert(index_ok)
			operand_at += 1
			text_at += u32(len(node.number_text))
		case .Flatten:
			instruction.opcode = .Flatten
			instruction.operands_count = 0
			if node.has_child {
				child_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
					kind = .Instruction,
					instruction = program.Instruction_Index(node.child),
				})
				assert(child_ok)
				operand_at += 1
				instruction.operands_count = 1
			}
		case .Join, .Contains, .Split, .Index_Builtin, .Rindex_Builtin, .Indices_Builtin, .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr:
			instruction.opcode = .Join
			if node.kind == .Contains do instruction.opcode = .Contains
			if node.kind == .Split do instruction.opcode = .Split
			if node.kind == .Index_Builtin do instruction.opcode = .Index_Builtin
			if node.kind == .Rindex_Builtin do instruction.opcode = .Rindex_Builtin
			if node.kind == .Indices_Builtin do instruction.opcode = .Indices_Builtin
			if node.kind == .Startswith do instruction.opcode = .Startswith
			if node.kind == .Endswith do instruction.opcode = .Endswith
			if node.kind == .Has do instruction.opcode = .Has
			if node.kind == .Bsearch do instruction.opcode = .Bsearch
			if node.kind == .Ltrimstr do instruction.opcode = .Ltrimstr
			if node.kind == .Rtrimstr do instruction.opcode = .Rtrimstr
			if node.kind == .Trimstr do instruction.opcode = .Trimstr
			instruction.operands_count = 1
			child_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.child),
			})
			assert(child_ok)
			operand_at += 1
		case .Variable:
			instruction.opcode = .Variable
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			assert(name_ok)
			name := bytes[name_start:name_end]
			assert(program.set_text(output, program.Byte_Offset(text_at), name))
			assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Text, text_start = program.Byte_Offset(text_at), text_count = program.Count(len(name)),
			}))
			text_at += u32(len(name)); operand_at += 1; instruction.operands_count = 1
		case .Binding:
			instruction.opcode = .Binding
			children := [2]syntax.Node_Id{node.left, node.right}
			for child in children {
				assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{kind = .Instruction, instruction = program.Instruction_Index(child)}))
				operand_at += 1
			}
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			assert(name_ok)
			name := bytes[name_start:name_end]
			assert(program.set_text(output, program.Byte_Offset(text_at), name))
			assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{kind = .Text, text_start = program.Byte_Offset(text_at), text_count = program.Count(len(name))}))
			text_at += u32(len(name)); operand_at += 1; instruction.operands_count = 3
		case .Reduce:
			instruction.opcode = .Reduce
			children := [3]syntax.Node_Id{node.left, node.right, node.reduce_update}
			for child in children {
				assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{kind=.Instruction, instruction=program.Instruction_Index(child)})); operand_at += 1
			}
			name_start, name_end, _ := diagnostic.span_offsets(source, node.name_span); name := bytes[name_start:name_end]
			assert(program.set_text(output, program.Byte_Offset(text_at), name)); assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{kind=.Text,text_start=program.Byte_Offset(text_at),text_count=program.Count(len(name))})); text_at += u32(len(name)); operand_at += 1; instruction.operands_count = 4
		case .Last:
			instruction.opcode = .Last
	case .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Transpose, .Unique, .Sort, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode:
			#partial switch node.kind {
			case .Length: instruction.opcode = .Length
			case .Keys: instruction.opcode = .Keys
			case .Keys_Unsorted: instruction.opcode = .Keys_Unsorted
			case .Tostring: instruction.opcode = .Tostring
			case .Tonumber: instruction.opcode = .Tonumber
			case .Min: instruction.opcode = .Min
			case .Max: instruction.opcode = .Max
			case .Toboolean: instruction.opcode = .Toboolean
			case .Base64: instruction.opcode = .Base64
			case .Base64d: instruction.opcode = .Base64d
			case .Uri: instruction.opcode = .Uri
			case .Urid: instruction.opcode = .Urid
			case .Html: instruction.opcode = .Html
			case .Text: instruction.opcode = .Text
			case .Json: instruction.opcode = .Json
			case .Csv: instruction.opcode = .Csv
			case .Tsv: instruction.opcode = .Tsv
			case .Sh: instruction.opcode = .Sh
			case .Tojson: instruction.opcode = .Tojson
			case .Fromjson: instruction.opcode = .Fromjson
			case .Log: instruction.opcode = .Log
			case .From_Entries: instruction.opcode = .From_Entries
			case .To_Entries: instruction.opcode = .To_Entries
			case .Isnan: instruction.opcode = .Isnan
			case .Utf8bytelength: instruction.opcode = .Utf8bytelength
			case .Not_Builtin: instruction.opcode = .Not_Builtin
			case .Empty: instruction.opcode = .Empty
			case .Values: instruction.opcode = .Values
			case .Arrays: instruction.opcode = .Arrays
			case .Objects: instruction.opcode = .Objects
			case .Iterables: instruction.opcode = .Iterables
			case .Scalars: instruction.opcode = .Scalars
			case .Booleans: instruction.opcode = .Booleans
			case .Nulls: instruction.opcode = .Nulls
			case .Numbers: instruction.opcode = .Numbers
			case .Strings: instruction.opcode = .Strings
			case .Finites: instruction.opcode = .Finites
			case .Normals: instruction.opcode = .Normals
			case .Floor: instruction.opcode = .Floor
			case .Round: instruction.opcode = .Round
			case .Transpose: instruction.opcode = .Transpose
			case .Unique: instruction.opcode = .Unique
			case .Ceil: instruction.opcode = .Ceil
			case .Nan: instruction.opcode = .Nan
			case .Infinite: instruction.opcode = .Infinite
			case .Any: instruction.opcode = .Any
			case .All: instruction.opcode = .All
			case .Isfinite: instruction.opcode = .Isfinite
			case .Isnormal: instruction.opcode = .Isnormal
			case .Sort: instruction.opcode = .Sort
			case .Flatten: instruction.opcode = .Flatten
			case .Type: instruction.opcode = .Type
			case .Abs: instruction.opcode = .Abs
			case .Sqrt: instruction.opcode = .Sqrt
			case .Fabs: instruction.opcode = .Fabs
			case .Add_Builtin: instruction.opcode = .Add_Builtin
			case .Trim: instruction.opcode = .Trim
			case .Ltrim: instruction.opcode = .Ltrim
			case .Rtrim: instruction.opcode = .Rtrim
			case .Atan: instruction.opcode = .Atan
			case .Ascii_Downcase: instruction.opcode = .Ascii_Downcase
			case .Ascii_Upcase: instruction.opcode = .Ascii_Upcase
			case .Reverse: instruction.opcode = .Reverse
			case .Implode: instruction.opcode = .Implode
			case .Explode: instruction.opcode = .Explode
			}
			instruction.operands_count = 0
		case .Parenthesized, .Optional:
			instruction.opcode = .Parenthesized if node.kind == .Parenthesized else .Optional
			instruction.operands_count = 1
			write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.child),
			})
			assert(write_ok)
			operand_at += 1
		case .Comma, .Pipe:
			instruction.opcode = .Fork if node.kind == .Comma else .Sequence
			instruction.operands_count = 2
			left_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.left),
			})
			assert(left_ok)
			operand_at += 1
			right_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.right),
			})
			assert(right_ok)
			operand_at += 1
		case .Null, .Boolean, .Number, .String:
			instruction.opcode = .Identity
			instruction.has_literal = true
			if node.kind == .Boolean do instruction.literal_kind = .Boolean
			if node.kind == .Number do instruction.literal_kind = .Number
			if node.kind == .String do instruction.literal_kind = .String
			instruction.literal_boolean = node.boolean_value
			if node.kind == .Number || node.kind == .String {
				literal := node.number_text if node.kind == .Number else node.string_text
				text_ok := program.set_text(output, program.Byte_Offset(text_at), literal)
				assert(text_ok)
				operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
					kind = .Text,
					text_start = program.Byte_Offset(text_at),
					text_count = program.Count(len(literal)),
				})
				assert(operand_ok)
				operand_at += 1
				text_at += u32(len(literal))
				instruction.operands_count = 1
			}
		case .Negate:
			child := nodes[int(node.child)]
			if child.kind != .Number || child.has_child || child.has_value {
				cleanup_error := program.destroy_program(output)
				if cleanup_error != nil { return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error} }
				return Lower_Outcome{kind = .Invalid_AST}
			}
			instruction.opcode = .Identity
			instruction.has_literal = true
			instruction.literal_kind = .Number
			prefix_bytes := 1 if !literal_number_is_zero(child.number_text) else 0
			if prefix_bytes == 1 do assert(program.set_text(output, program.Byte_Offset(text_at), "-"))
			assert(program.set_text(output, program.Byte_Offset(text_at + u32(prefix_bytes)), child.number_text))
			assert(program.set_operand(output, program.Operand_Index(operand_at), program.Operand{kind=.Text, text_start=program.Byte_Offset(text_at), text_count=program.Count(len(child.number_text)+prefix_bytes)}))
			instruction.operands_count = 1
			operand_at += 1
			text_at += u32(len(child.number_text) + prefix_bytes)
		case:
			cleanup_error := program.destroy_program(output)
			if cleanup_error != nil {
				return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
			}
			return Lower_Outcome{kind = .Invalid_AST}
		}
		}
		instruction_ok := program.set_instruction(output, program.Instruction_Index(node_at), instruction)
		assert(instruction_ok)
	}
	assert(operand_at == u32(operand_count) && text_at == u32(text_count))
	root_ok := program.set_root(output, program.Instruction_Index(root))
	sealed := program.finalize_program(output)
	if !root_ok || !sealed {
		cleanup_error := program.destroy_program(output)
		if cleanup_error != nil {
			return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
		}
		return Lower_Outcome{kind = .Invalid_AST}
	}
	return {}
}
