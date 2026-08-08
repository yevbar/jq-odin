package driver

import "base:runtime"
import "core:os"
import "core:strings"

Module_Error_Kind :: enum u8 {
	None,
	Not_Found,
	Read_Failure,
	Unsupported_Syntax,
	Import_Unsupported,
	Depth_Overflow,
	Duplicate_Definition,
	Cycle,
}

module_definition :: struct {
	name: string,
	parameters: string,
	body: string,
	active: bool,
}

Module_Outcome :: struct {
	kind: Module_Error_Kind,
	resource_error: runtime.Allocator_Error,
}

module_loader_depth :: 64

module_space :: proc(bytes: string, at: ^int) {
	for at^ < len(bytes) {
		if bytes[at^] == ' ' || bytes[at^] == '\t' || bytes[at^] == '\r' || bytes[at^] == '\n' {
			at^ += 1
			continue
		}
		if bytes[at^] == '#' {
			for at^ < len(bytes) && bytes[at^] != '\n' do at^ += 1
			continue
		}
		break
	}
}

module_word :: proc(bytes: string, at: int, word: string) -> bool {
	if at < 0 || at+len(word) > len(bytes) || bytes[at:at+len(word)] != word do return false
	if at+len(word) == len(bytes) do return true
	byte := bytes[at+len(word)]
	return !(byte >= 'a' && byte <= 'z' || byte >= 'A' && byte <= 'Z' ||
		byte >= '0' && byte <= '9' || byte == '_')
}

parse_module_include :: proc(bytes: string, at: int) -> (name: string, next: int, ok: bool, unsupported: bool) {
	if !module_word(bytes, at, "include") do return "", at, false, false
	i := at+len("include")
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != '"' do return "", at, false, true
	start := i+1
	i = start
	for i < len(bytes) && bytes[i] != '"' {
		if bytes[i] == '\\' do return "", at, false, true
		i += 1
	}
	if i >= len(bytes) do return "", at, false, true
	name = bytes[start:i]
	i += 1
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != ';' do return "", at, false, true
	return name, i+1, true, false
}

parse_module_import :: proc(bytes: string, at: int) -> (name, alias: string, next: int, ok, unsupported: bool) {
	if !module_word(bytes, at, "import") do return "", "", at, false, false
	i := at+len("import")
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != '"' do return "", "", at, false, true
	start := i+1
	i = start
	for i < len(bytes) && bytes[i] != '"' {
		if bytes[i] == '\\' do return "", "", at, false, true
		i += 1
	}
	if i >= len(bytes) do return "", "", at, false, true
	name = bytes[start:i]
	i += 1
	module_space(bytes, &i)
	if !module_word(bytes, i, "as") do return "", "", at, false, true
	i += 2
	module_space(bytes, &i)
	alias_start := i
	// jq accepts both `as name` and `as $name` spellings at the import
	// boundary.  The dollar is syntax, not part of the namespace used for
	// qualified definitions, so retain the canonical alias without it.
	if i < len(bytes) && bytes[i] == '$' do i += 1
	if i >= len(bytes) || !is_module_identifier_start(bytes[i]) do return "", "", at, false, true
	alias_start = i
	for i < len(bytes) && is_module_identifier_byte(bytes[i]) do i += 1
	alias = bytes[alias_start:i]
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != ';' do return "", "", at, false, true
	return name, alias, i+1, true, false
}

skip_module_object :: proc(bytes: string, at: ^int) -> bool {
	if at^ >= len(bytes) || bytes[at^] != '{' do return false
	depth := 0
	in_string := false
	escaped := false
	for at^ < len(bytes) {
		byte := bytes[at^]
		at^ += 1
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
			continue
		}
		if byte == '"' { in_string = true; continue }
		if byte == '{' { depth += 1 } else if byte == '}' {
			depth -= 1
			if depth == 0 do return true
		}
	}
	return false
}

read_module :: proc(name: string, paths: []string, allocator: runtime.Allocator) -> ([]byte, Module_Outcome) {
	for directory in paths {
		path, path_error := strings.concatenate([]string{directory, "/", name, ".jq"}, allocator)
		if path_error != nil do return nil, {kind = .Read_Failure, resource_error = path_error}
		data, read_error := os.read_entire_file_from_path(path, allocator)
		delete(path, allocator)
		if read_error == nil do return data, {}
		if read_error != .Not_Exist do return nil, {kind = .Read_Failure}
	}
	return nil, {kind = .Not_Found}
}

validate_module :: proc(bytes: string, paths: []string, allocator: runtime.Allocator, depth: int) -> Module_Outcome {
	if depth >= module_loader_depth do return {kind = .Depth_Overflow}
	i := 0
	for {
		module_space(bytes, &i)
		if i >= len(bytes) do return {}
		if module_word(bytes, i, "import") {
			name, _, next, imported, import_unsupported := parse_module_import(bytes, i)
			if import_unsupported || !imported do return {kind = .Unsupported_Syntax}
			data, outcome := read_module(name, paths, allocator)
			if outcome.kind != .None do return outcome
			outcome = validate_module(transmute(string)data, paths, allocator, depth+1)
			delete(data, allocator)
			if outcome.kind != .None do return outcome
			i = next
			continue
		}
		if module_word(bytes, i, "def") {
			// Definitions are consumed by expand_filter_modules. Validation still
			// walks their body so malformed module syntax is not hidden.
			i += len("def")
			module_space(bytes, &i)
			if i >= len(bytes) || !is_module_identifier_start(bytes[i]) do return {kind = .Unsupported_Syntax}
			for i < len(bytes) && is_module_identifier_byte(bytes[i]) do i += 1
			module_space(bytes, &i)
			if i >= len(bytes) || bytes[i] != ':' do return {kind = .Unsupported_Syntax}
			in_string := false
			escaped := false
			in_comment := false
			parentheses := 0
			brackets := 0
			braces := 0
			terminated := false
			for i += 1; i < len(bytes); i += 1 {
				byte := bytes[i]
				if in_comment {
					if byte == '\n' do in_comment = false
					continue
				}
				if in_string {
					if escaped {
						escaped = false
					} else if byte == '\\' {
						escaped = true
					} else if byte == '"' {
						in_string = false
					}
					continue
				}
				if byte == '"' { in_string = true; continue }
				if byte == '#' { in_comment = true; continue }
				switch byte {
				case '(' : parentheses += 1
				case ')' :
					if parentheses == 0 do return {kind = .Unsupported_Syntax}
					parentheses -= 1
				case '[' : brackets += 1
				case ']' :
					if brackets == 0 do return {kind = .Unsupported_Syntax}
					brackets -= 1
				case '{' : braces += 1
				case '}' :
					if braces == 0 do return {kind = .Unsupported_Syntax}
					braces -= 1
				case ';' : {}
				}
				if byte == ';' && parentheses == 0 && brackets == 0 && braces == 0 {
					terminated = true
					break
				}
			}
			if in_string || !terminated || parentheses != 0 || brackets != 0 || braces != 0 do return {kind = .Unsupported_Syntax}
			i += 1
			continue
		}
		if module_word(bytes, i, "module") {
			i += len("module")
			module_space(bytes, &i)
			if !skip_module_object(bytes, &i) do return {kind = .Unsupported_Syntax}
			module_space(bytes, &i)
			if i >= len(bytes) || bytes[i] != ';' do return {kind = .Unsupported_Syntax}
			i += 1
			continue
		}
		name, next, included, unsupported := parse_module_include(bytes, i)
		if unsupported do return {kind = .Unsupported_Syntax}
		if included {
			data, outcome := read_module(name, paths, allocator)
			if outcome.kind != .None do return outcome
			outcome = validate_module(transmute(string)data, paths, allocator, depth+1)
			delete(data, allocator)
			if outcome.kind != .None do return outcome
			i = next
			continue
		}
		return {kind = .Unsupported_Syntax}
	}
}

is_module_identifier_start :: proc(byte: byte) -> bool {
	return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte == '_'
}

is_module_identifier_byte :: proc(byte: byte) -> bool {
	return is_module_identifier_start(byte) || byte >= '0' && byte <= '9'
}

module_body_has_filter :: proc(body: string) -> bool {
	i := 0
	module_space(body, &i)
	return i < len(body)
}

find_module_definitions :: proc(bytes: string, definitions: ^[dynamic]module_definition, allocator: runtime.Allocator) -> Module_Outcome {
	i := 0
	for i < len(bytes) {
		module_space(bytes, &i)
		if i >= len(bytes) do break
		if module_word(bytes, i, "module") {
			i += len("module")
			module_space(bytes, &i)
			if !skip_module_object(bytes, &i) do return {kind = .Unsupported_Syntax}
			module_space(bytes, &i)
			if i >= len(bytes) || bytes[i] != ';' do return {kind = .Unsupported_Syntax}
			i += 1
			continue
		}
		if module_word(bytes, i, "def") {
			i += 3
			module_space(bytes, &i)
			if i >= len(bytes) || !is_module_identifier_start(bytes[i]) do return {kind = .Unsupported_Syntax}
			name_start := i
			for i < len(bytes) && is_module_identifier_byte(bytes[i]) do i += 1
			name_end := i
			module_space(bytes, &i)
			parameters_start := i
			parameters_end := i
			if i < len(bytes) && bytes[i] == '(' {
				parameters_start = i+1
				depth := 1
				i += 1
				for i < len(bytes) && depth > 0 {
					if bytes[i] == '(' do depth += 1
					if bytes[i] == ')' {
						depth -= 1
						if depth == 0 do break
					}
					i += 1
				}
				if depth != 0 do return {kind = .Unsupported_Syntax}
				parameters_end = i
				i += 1
				module_space(bytes, &i)
			}
			if i >= len(bytes) || bytes[i] != ':' do return {kind = .Unsupported_Syntax}
			i += 1
			body_start := i
			in_string := false
			escaped := false
			in_comment := false
			parentheses := 0
			brackets := 0
			braces := 0
			for i < len(bytes) {
				byte := bytes[i]
				i += 1
				if in_comment {
					if byte == '\n' do in_comment = false
					continue
				}
				if in_string {
					if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
					continue
				}
				if byte == '"' { in_string = true; continue }
				if byte == '#' { in_comment = true; continue }
				switch byte {
				case '(' : parentheses += 1
				case ')' :
					if parentheses == 0 do return {kind = .Unsupported_Syntax}
					parentheses -= 1
				case '[' : brackets += 1
				case ']' :
					if brackets == 0 do return {kind = .Unsupported_Syntax}
					brackets -= 1
				case '{' : braces += 1
				case '}' :
					if braces == 0 do return {kind = .Unsupported_Syntax}
					braces -= 1
				case ';' : {}
				}
				if byte == ';' && parentheses == 0 && brackets == 0 && braces == 0 do break
			}
			if in_string || i > len(bytes) || i == len(bytes) && (len(bytes) == 0 || bytes[i-1] != ';') || parentheses != 0 || brackets != 0 || braces != 0 do return {kind = .Unsupported_Syntax}
			body := bytes[body_start:i-1]
			if !module_body_has_filter(body) do return {kind = .Unsupported_Syntax}
			owned_name, name_error := strings.clone(bytes[name_start:name_end], allocator)
			if name_error != nil do return {kind = .Read_Failure, resource_error = name_error}
			owned_body, body_error := strings.clone(body, allocator)
			if body_error != nil {
				delete(owned_name, allocator)
				return {kind = .Read_Failure, resource_error = body_error}
			}
			owned_parameters, parameters_error := strings.clone(bytes[parameters_start:parameters_end], allocator)
			if parameters_error != nil {
				delete(owned_name, allocator)
				delete(owned_body, allocator)
				return {kind = .Read_Failure, resource_error = parameters_error}
			}
			// jq resolves duplicate module definitions deterministically to the
			// last definition, including references from earlier definitions.
			for index := len(definitions^)-1; index >= 0; index -= 1 {
				if definitions^[index].name == owned_name {
					definitions^[index].active = false
					break
				}
			}
			_, append_error := append(definitions, module_definition{name = owned_name, parameters = owned_parameters, body = owned_body, active = true})
			if append_error != nil {
				delete(owned_name, allocator); delete(owned_parameters, allocator); delete(owned_body, allocator)
				return {kind = .Read_Failure, resource_error = append_error}
			}
			continue
		}
		// A module file may contain only supported directives and definitions.
		// Do not silently leave trailing filter/text for the caller to accept.
		return {kind = .Unsupported_Syntax}
	}
	return {}
}

destroy_module_definitions :: proc(definitions: ^[dynamic]module_definition, allocator: runtime.Allocator) {
	for definition in definitions^ {
		delete(definition.name, allocator)
		delete(definition.parameters, allocator)
		delete(definition.body, allocator)
	}
	delete(definitions^)
}

module_definition_at :: proc(input: string, at: int, definitions: [dynamic]module_definition, namespace: string = "") -> int {
	// A bare identifier is a callable filter only when it is not part of a
	// jq variable, field, or format directive. The scanner has already removed
	// strings and comments, but these contexts still contain identifier-shaped
	// text that must remain source-exact.
	dollar_qualified := at > 0 && input[at-1] == '$'
	if at > 0 && (input[at-1] == '.' || input[at-1] == '@') do return -1
	name_end := at
	for name_end < len(input) && is_module_identifier_byte(input[name_end]) do name_end += 1
	qualified_end := name_end
	qualified := false
	for qualified_end+2 < len(input) && input[qualified_end:qualified_end+2] == "::" {
		segment_start := qualified_end+2
		segment_end := segment_start
		for segment_end < len(input) && is_module_identifier_byte(input[segment_end]) do segment_end += 1
		if segment_end == segment_start do break
		qualified = true
		qualified_end = segment_end
	}
	if qualified && dollar_qualified {
		// `$alias::name` uses the same canonical namespace as `alias::name`.
		// A plain `$variable` remains a normal jq variable and is never a
		// module definition.
		for index := len(definitions)-1; index >= 0; index -= 1 {
			if definitions[index].active && definitions[index].name == input[at:qualified_end] do return index
		}
		return -1
	}
	if qualified {
		for index := len(definitions)-1; index >= 0; index -= 1 {
			if definitions[index].active && definitions[index].name == input[at:qualified_end] do return index
		}
		if len(namespace) > 0 {
			qualified_length := qualified_end-at
			for index := len(definitions)-1; index >= 0; index -= 1 {
				definition_name := definitions[index].name
				if len(definition_name) == len(namespace)+2+qualified_length &&
					definition_name[:len(namespace)] == namespace &&
					definition_name[len(namespace):len(namespace)+2] == "::" &&
					definition_name[len(namespace)+2:] == input[at:qualified_end] && definitions[index].active {
					return index
				}
			}
		}
		return -1
	}
	next := name_end
	for next < len(input) && (input[next] == ' ' || input[next] == '\t' || input[next] == '\r' || input[next] == '\n') do next += 1
	if next < len(input) && input[next] == ':' do return -1
	// Imported definitions retain their external namespace, but references in
	// their bodies resolve sibling definitions in that module unqualified.
	if len(namespace) > 0 {
		for index := len(definitions)-1; index >= 0; index -= 1 {
			definition_name := definitions[index].name
			separator := len(namespace)
			if separator+2+len(input[at:name_end]) == len(definition_name) &&
				definition_name[:separator] == namespace &&
				definition_name[separator:separator+2] == "::" &&
				definition_name[separator+2:] == input[at:name_end] && definitions[index].active {
				return index
			}
		}
	}
	for index := len(definitions)-1; index >= 0; index -= 1 {
		if definitions[index].active && definitions[index].name == input[at:name_end] do return index
	}
	return -1
}

module_trim :: proc(text: string) -> string {
	start := 0
	for start < len(text) && (text[start] == ' ' || text[start] == '\t' || text[start] == '\r' || text[start] == '\n') do start += 1
	end := len(text)
	for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\r' || text[end-1] == '\n') do end -= 1
	return text[start:end]
}

module_call_arguments :: proc(input: string, open: int, args: ^[16]string) -> (close: int, count: int, ok: bool) {
	depth := 1
	start := open+1
	in_string := false
	escaped := false
	count = 0
	for at := open+1; at < len(input); at += 1 {
		byte := input[at]
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
			continue
		}
		if byte == '"' { in_string = true; continue }
		if byte == '(' { depth += 1; continue }
		if byte == ')' {
			depth -= 1
			if depth == 0 {
				if count >= len(args^) do return 0, 0, false
				argument := module_trim(input[start:at])
				if len(argument) == 0 do return 0, 0, false
				args^[count] = argument
				return at, count+1, true
			}
			continue
		}
		if byte == ';' && depth == 1 {
			if count >= len(args^) do return 0, 0, false
			args^[count] = module_trim(input[start:at])
			count += 1
			start = at+1
		}
	}
	return 0, 0, false
}

module_parameter :: proc(parameters, name: string) -> int {
	ordinal := 0
	start := 0
	for at := 0; at <= len(parameters); at += 1 {
		if at == len(parameters) || parameters[at] == ';' {
			candidate := module_trim(parameters[start:at])
			if len(candidate) > 0 && candidate[0] == '$' do candidate = candidate[1:]
			if candidate == name do return ordinal
			ordinal += 1
			start = at+1
		}
	}
	return -1
}

module_parameter_count :: proc(parameters: string) -> int {
	if len(parameters) == 0 do return 0
	count := 1
	for byte in parameters {
		if byte == ';' do count += 1
	}
	return count
}

module_write :: proc(builder: ^strings.Builder, text: string) -> bool {
	return strings.write_string(builder, text) == len(text)
}

module_expand_source :: proc(
	input: string,
	definitions: [dynamic]module_definition,
	builder: ^strings.Builder,
	stack: ^[module_loader_depth]int,
	depth: int,
	parameters: string,
	args: [16]string,
	arg_count: int,
	allocator: runtime.Allocator,
	namespace: string = "",
) -> Module_Outcome {
	if depth >= module_loader_depth do return {kind = .Depth_Overflow}
	at := 0
	for at < len(input) {
		if input[at] == '$' && at+1 < len(input) && is_module_identifier_start(input[at+1]) {
			// Defer the dollar while scanning a qualified module reference.  If
			// it is not a module reference, write it as the ordinary variable
			// token and let the next iteration preserve the source exactly.
			qualified_index := module_definition_at(input, at+1, definitions, namespace)
			if qualified_index >= 0 {
				at += 1
				continue
			}
		}
		if input[at] == '"' {
			start := at; at += 1; escaped := false
			for at < len(input) { byte := input[at]; at += 1; if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { break } }
			if !module_write(builder, input[start:at]) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		if input[at] == '#' {
			start := at
			for at < len(input) && input[at] != '\n' do at += 1
			if !module_write(builder, input[start:at]) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		if !is_module_identifier_start(input[at]) {
			if !module_write(builder, input[at:at+1]) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			at += 1
			continue
		}
		start := at
		for at < len(input) && is_module_identifier_byte(input[at]) do at += 1
		name := input[start:at]
		previous := start-1
		for previous >= 0 && (input[previous] == ' ' || input[previous] == '\t' || input[previous] == '\r' || input[previous] == '\n') do previous -= 1
		next := at
		for next < len(input) && (input[next] == ' ' || input[next] == '\t' || input[next] == '\r' || input[next] == '\n') do next += 1
		object_shorthand := previous >= 0 && (input[previous] == '{' || input[previous] == ',') &&
			next < len(input) && (input[next] == '}' || input[next] == ',')
		if object_shorthand {
			if !module_write(builder, name) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		parameter_index := module_parameter(parameters, name)
		bare_identifier := start == 0 || (input[start-1] != '$' && input[start-1] != '.' && input[start-1] != '@')
		if bare_identifier && parameter_index >= 0 && parameter_index < arg_count {
			// Arguments are filter source, not opaque text. Re-enter the
			// expansion path so module-defined filters in an argument are
			// resolved before the containing definition continues. Keep the
			// current depth: the containing definition remains active on the
			// cycle stack while the argument is expanded.
			outcome := module_expand_source(
				args[parameter_index], definitions, builder, stack, depth,
				parameters, args, arg_count, allocator, namespace,
			)
			if outcome.kind != .None do return outcome
			continue
		}
		index := module_definition_at(input, start, definitions, namespace)
		if index < 0 {
			if !module_write(builder, input[start:at]) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		definition := definitions[index]
		for at+2 < len(input) && input[at:at+2] == "::" {
			segment_start := at+2
			segment_end := segment_start
			for segment_end < len(input) && is_module_identifier_byte(input[segment_end]) do segment_end += 1
			if segment_end == segment_start do break
			at = segment_end
		}
		call_args: [16]string
		call_count := 0
		if len(definition.parameters) > 0 {
			call_next := at
			for call_next < len(input) && (input[call_next] == ' ' || input[call_next] == '\t' || input[call_next] == '\r' || input[call_next] == '\n') do call_next += 1
			if call_next >= len(input) || input[call_next] != '(' do return {kind = .Unsupported_Syntax}
			close, parsed_count, call_ok := module_call_arguments(input, call_next, &call_args)
			if !call_ok do return {kind = .Unsupported_Syntax}
			at = close+1
			call_count = parsed_count
		}
		if call_count != module_parameter_count(definition.parameters) do return {kind = .Unsupported_Syntax}
		// Resolve actual arguments in the caller's environment before binding
		// them to the callee. Otherwise `id(x)` in outer(x) rebinds x as the
		// inner parameter instead of retaining outer's caller value.
		expanded_args: [16]string
		expanded_arg_count := 0
		for argument_index := 0; argument_index < call_count; argument_index += 1 {
			argument_builder: strings.Builder
			_, init_error := strings.builder_init(&argument_builder, allocator)
			if init_error != nil {
				for expanded_arg in expanded_args[:expanded_arg_count] do delete(expanded_arg, allocator)
				return {kind = .Read_Failure, resource_error = init_error}
			}
			argument_outcome := module_expand_source(
				call_args[argument_index], definitions, &argument_builder, stack, depth,
				parameters, args, arg_count, allocator, namespace,
			)
			if argument_outcome.kind != .None {
				strings.builder_destroy(&argument_builder)
				for expanded_arg in expanded_args[:expanded_arg_count] do delete(expanded_arg, allocator)
				return argument_outcome
			}
			expanded_argument, clone_error := strings.clone(strings.to_string(argument_builder), allocator)
			strings.builder_destroy(&argument_builder)
			if clone_error != nil {
				for expanded_arg in expanded_args[:expanded_arg_count] do delete(expanded_arg, allocator)
				return {kind = .Read_Failure, resource_error = clone_error}
			}
			expanded_args[argument_index] = expanded_argument
			expanded_arg_count += 1
		}
		for stack_previous in stack^[:depth] {
			if stack_previous == index {
				for expanded_arg in expanded_args[:expanded_arg_count] do delete(expanded_arg, allocator)
				return {kind = .Cycle}
			}
		}
		stack^[depth] = index
		definition_namespace := ""
		for separator := len(definition.name)-2; separator >= 0; separator -= 1 {
			if definition.name[separator:separator+2] == "::" {
				definition_namespace = definition.name[:separator]
				break
			}
		}
		outcome := module_expand_source(
			definition.body, definitions, builder, stack, depth+1,
			definition.parameters, expanded_args, call_count, allocator, definition_namespace,
		)
		for expanded_arg in expanded_args[:expanded_arg_count] do delete(expanded_arg, allocator)
		if outcome.kind != .None do return outcome
	}
	return {}
}

collect_module :: proc(name, prefix: string, paths: []string, definitions: ^[dynamic]module_definition, allocator: runtime.Allocator, depth: int, active: ^[module_loader_depth]string, active_count: int) -> Module_Outcome {
	if depth >= module_loader_depth do return {kind = .Depth_Overflow}
	for previous in active^[:active_count] {
		if previous == name do return {kind = .Cycle}
	}
	active^[active_count] = name
	data, outcome := read_module(name, paths, allocator)
	if outcome.kind != .None {
		active^[active_count] = ""
		return outcome
	}
	bytes := transmute(string)data
	i := 0
	for {
		module_space(bytes, &i)
		if i >= len(bytes) do break
		if module_word(bytes, i, "include") {
			child, next, included, unsupported := parse_module_include(bytes, i)
			if unsupported || !included { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
			outcome = collect_module(child, prefix, paths, definitions, allocator, depth+1, active, active_count+1)
			if outcome.kind != .None { delete(data, allocator); active^[active_count] = ""; return outcome }
			i = next; continue
		}
		if module_word(bytes, i, "import") {
			child, alias, next, imported, unsupported := parse_module_import(bytes, i)
			if unsupported || !imported { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
			child_prefix := alias
			if len(prefix) > 0 {
				prefix_error: runtime.Allocator_Error
				child_prefix, prefix_error = strings.concatenate([]string{prefix, "::", alias}, allocator)
				if prefix_error != nil { delete(data, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = prefix_error} }
			}
			outcome = collect_module(child, child_prefix, paths, definitions, allocator, depth+1, active, active_count+1)
			if len(prefix) > 0 { delete(child_prefix, allocator) }
			if outcome.kind != .None { delete(data, allocator); active^[active_count] = ""; return outcome }
			i = next; continue
		}
		if module_word(bytes, i, "module") {
			i += len("module"); module_space(bytes, &i)
			if !skip_module_object(bytes, &i) { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
			module_space(bytes, &i)
			if i >= len(bytes) || bytes[i] != ';' { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
			i += 1; continue
		}
		break
	}
	local: [dynamic]module_definition
	outcome = find_module_definitions(bytes[i:], &local, allocator)
	if outcome.kind != .None { delete(data, allocator); destroy_module_definitions(&local, allocator); active^[active_count] = ""; return outcome }
	for definition in local {
		owned_name, name_error := strings.clone(definition.name, allocator)
		if len(prefix) > 0 {
			delete(owned_name, allocator)
			owned_name, name_error = strings.concatenate([]string{prefix, "::", definition.name}, allocator)
		}
		if name_error != nil { delete(data, allocator); destroy_module_definitions(&local, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = name_error} }
		owned_parameters, parameters_error := strings.clone(definition.parameters, allocator)
		owned_body, body_error := strings.clone(definition.body, allocator)
		if parameters_error != nil || body_error != nil {
			delete(owned_name, allocator); delete(owned_parameters, allocator); delete(owned_body, allocator)
			delete(data, allocator); destroy_module_definitions(&local, allocator)
			active^[active_count] = ""
			return {kind = .Read_Failure, resource_error = parameters_error if parameters_error != nil else body_error}
		}
		_, append_error := append(definitions, module_definition{name = owned_name, parameters = owned_parameters, body = owned_body, active = true})
		if append_error != nil { delete(owned_name, allocator); delete(owned_parameters, allocator); delete(owned_body, allocator); delete(data, allocator); destroy_module_definitions(&local, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = append_error} }
	}
	delete(data, allocator)
	destroy_module_definitions(&local, allocator)
	active^[active_count] = ""
	return {}
}

// load_filter_modules removes leading include/import directives after resolving
// their complete transitive dependency trees.
load_filter_modules :: proc(filter: string, paths: []string, allocator: runtime.Allocator) -> ([]byte, Module_Outcome) {
	 i := 0
	definitions: [dynamic]module_definition
	definitions_initialized := false
	has_module := false
	active_modules: [module_loader_depth]string
	for {
		module_space(filter, &i)
		if module_word(filter, i, "include") {
			name, next, included, unsupported := parse_module_include(filter, i)
			if unsupported || !included { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Unsupported_Syntax} }
			if !definitions_initialized {
				definitions_error: runtime.Allocator_Error
				definitions, definitions_error = make([dynamic]module_definition, 0, 8, allocator)
				if definitions_error != nil do return nil, {kind = .Read_Failure, resource_error = definitions_error}
				definitions_initialized = true
			}
			outcome := collect_module(name, "", paths, &definitions, allocator, 0, &active_modules, 0)
			if outcome.kind != .None { destroy_module_definitions(&definitions, allocator); return nil, outcome }
			has_module = true; i = next; continue
		}
		if module_word(filter, i, "import") {
			name, alias, next, imported, unsupported := parse_module_import(filter, i)
			if unsupported || !imported { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Unsupported_Syntax} }
			if !definitions_initialized {
				definitions_error: runtime.Allocator_Error
				definitions, definitions_error = make([dynamic]module_definition, 0, 8, allocator)
				if definitions_error != nil do return nil, {kind = .Read_Failure, resource_error = definitions_error}
				definitions_initialized = true
			}
			outcome := collect_module(name, alias, paths, &definitions, allocator, 0, &active_modules, 0)
			if outcome.kind != .None { destroy_module_definitions(&definitions, allocator); return nil, outcome }
			has_module = true; i = next; continue
		}
		break
	}
	if !has_module { destroy_module_definitions(&definitions, allocator); return nil, {} }
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Read_Failure, resource_error = init_error} }
	stack: [module_loader_depth]int
	outcome := module_expand_source(filter[i:], definitions, &builder, &stack, 0, "", {}, 0, allocator)
	if outcome.kind != .None { strings.builder_destroy(&builder); destroy_module_definitions(&definitions, allocator); return nil, outcome }
	output, clone_error := strings.clone(strings.to_string(builder), allocator)
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, allocator)
	if clone_error != nil do return nil, {kind = .Read_Failure, resource_error = clone_error}
	return transmute([]byte)output, {}
}
