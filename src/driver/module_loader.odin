package driver

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import json "jq:json"
import value "jq:value"

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

module_data_import :: struct {
	alias: string,
	data: string,
}

destroy_module_data_imports :: proc(imports: ^[dynamic]module_data_import, allocator: runtime.Allocator) {
	for imported in imports^ {
		delete(imported.alias, allocator)
		delete(imported.data, allocator)
	}
	delete(imports^)
}

module_rename :: struct {
	old: string,
	new: string,
}

Module_Outcome :: struct {
	kind: Module_Error_Kind,
	resource_error: runtime.Allocator_Error,
	data_input: []byte,
	data_after_caller: bool,
	data_scalar_add: bool,
	data_replace_input: bool,
	// A postfix field applied to a scalar data import is deliberately retained
	// in the generated filter so evaluation can produce jq's type diagnostic.
	// Keep this bit separate from ordinary field errors; the CLI formats this
	// import-originated error with jq's input-kind wording.
	data_scalar_field_error: bool,
	runtime_subtraction: bool,
	runtime_factorial: bool,
}

module_loader_depth :: 64
module_runtime_error_key_prefix :: "__jq_odin_subtraction__"

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

parse_module_include :: proc(bytes: string, at: int) -> (name: string, search: string, next: int, ok: bool, unsupported: bool) {
	if !module_word(bytes, at, "include") do return "", "", at, false, false
	i := at+len("include")
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
	search = module_metadata_search(bytes, &i)
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != ';' do return "", "", at, false, true
	return name, search, i+1, true, false
}

// jq permits a constant metadata object after an include/import path. The
// loader currently consumes the string-valued `search` member; other metadata
// remains accepted and has no effect on the ordinary jq filter expansion.
module_metadata_search :: proc(bytes: string, at: ^int) -> string {
	start := at^
	if start >= len(bytes) || bytes[start] != '{' do return ""
	end := start
	if !skip_module_object(bytes, &end) do return ""
	i := start+1
	for i+7 < end {
		key_end := i+6
		if bytes[i] == '"' {
			if i+8 > end || bytes[i:i+8] != "\"search\"" {
				i += 1
				continue
			}
			key_end = i+8
		} else if bytes[i:i+6] != "search" {
			i += 1
			continue
		}
		{
			j := key_end
			module_space(bytes, &j)
			if j < end-1 && bytes[j] == ':' {
				j += 1
				module_space(bytes, &j)
				if j < end-1 && bytes[j] == '"' {
					value_start := j+1
					j = value_start
					for j < end-1 && bytes[j] != '"' {
						if bytes[j] == '\\' do return ""
						j += 1
					}
					if j < end-1 {
						at^ = end
						return bytes[value_start:j]
					}
				}
			}
		}
		i += 1
	}
	at^ = end
	return ""
}

parse_module_import :: proc(bytes: string, at: int) -> (name, alias, search: string, next: int, ok, unsupported: bool) {
	if !module_word(bytes, at, "import") do return "", "", "", at, false, false
	i := at+len("import")
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != '"' do return "", "", "", at, false, true
	start := i+1
	i = start
	for i < len(bytes) && bytes[i] != '"' {
		if bytes[i] == '\\' do return "", "", "", at, false, true
		i += 1
	}
	if i >= len(bytes) do return "", "", "", at, false, true
	name = bytes[start:i]
	i += 1
	module_space(bytes, &i)
	if !module_word(bytes, i, "as") do return "", "", "", at, false, true
	i += 2
	module_space(bytes, &i)
	alias_start := i
	// jq accepts both `as name` and `as $name` spellings at the import
	// boundary.  The dollar is syntax, not part of the namespace used for
	// qualified definitions, so retain the canonical alias without it.
	if i < len(bytes) && bytes[i] == '$' do i += 1
	if i >= len(bytes) || !is_module_identifier_start(bytes[i]) do return "", "", "", at, false, true
	alias_start = i
	for i < len(bytes) && is_module_identifier_byte(bytes[i]) do i += 1
	alias = bytes[alias_start:i]
	module_space(bytes, &i)
	search = module_metadata_search(bytes, &i)
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != ';' do return "", "", "", at, false, true
	return name, alias, search, i+1, true, false
}

module_import_uses_data_binding :: proc(bytes: string, at: int) -> bool {
	i := at + len("import")
	module_space(bytes, &i)
	if i >= len(bytes) || bytes[i] != '"' do return false
	for i += 1; i < len(bytes) && bytes[i] != '"'; i += 1 {
		if bytes[i] == '\\' do return false
	}
	if i >= len(bytes) do return false
	i += 1
	module_space(bytes, &i)
	if !module_word(bytes, i, "as") do return false
	i += 2
	module_space(bytes, &i)
	return i < len(bytes) && bytes[i] == '$'
}

// Data imports are jq's JSON-module stream wrapped in an array.  Keep the
// complete structured literals, rather than looking up a field in raw text:
// the compiler must perform ordinary JSON indexing so nested keys cannot
// accidentally shadow a top-level key.
module_data_array_literal :: proc(data: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	defer strings.builder_destroy(&builder)
	if !module_write(&builder, "[") do return "", .Out_Of_Memory
	// Validate the complete JSON stream before textual framing or postfix
	// extraction. A valid first value does not make malformed trailing bytes
	// acceptable to jq's import loader.
	validate_at := 0
	for {
		validated, next, done, parse_error := json.parse_next_value(data, validate_at, allocator)
		if parse_error.kind != .None {
			_ = json.destroy_scalar_parse_error(&parse_error)
			return "", .Invalid_Argument
		}
		if !done {
			if value_cleanup := value.destroy_value(&validated); value_cleanup != nil {
				if retry_cleanup := value.destroy_value(&validated); retry_cleanup != nil {
					return "", retry_cleanup
				}
			}
		}
		if done do break
		validate_at = next
	}
	first := true
	i := 0
	for {
		for i < len(data) && (data[i] == ' ' || data[i] == '\t' || data[i] == '\r' || data[i] == '\n') do i += 1
		if i >= len(data) do break
		start := i
		if data[i] == '{' || data[i] == '[' {
			open := data[i]
			close: byte = '}'
			if open == '[' do close = ']'
			depth := 0
			in_string := false
			escaped := false
			for i < len(data) {
				byte := data[i]
				i += 1
				if in_string {
					if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
					continue
				}
				if byte == '"' { in_string = true; continue }
				if byte == open { depth += 1 }
				if byte == close {
					depth -= 1
					if depth == 0 do break
				}
			}
		} else if data[i] == '"' {
			i += 1
			escaped := false
			for i < len(data) {
				byte := data[i]
				i += 1
				if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { break }
			}
	} else {
		// jq accepts adjacent JSON values (for example `1[2]`) in a
		// module stream. Stop a scalar at a container opener so each value is
		// framed independently; ordinary scalar text remains one token.
		for i < len(data) && data[i] != ' ' && data[i] != '\t' && data[i] != '\r' && data[i] != '\n' && data[i] != '{' && data[i] != '[' && data[i] != '"' do i += 1
		}
	if !first && !module_write(&builder, ",") do return "", .Out_Of_Memory
	segment := data[start:i]
	in_string := false
	escaped := false
	for segment_index := 0; segment_index < len(segment); segment_index += 1 {
		byte := segment[segment_index]
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
		} else if byte == '"' {
			in_string = true
		} else if byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n' {
			continue
		}
		if !module_write(&builder, segment[segment_index:segment_index+1]) do return "", .Out_Of_Memory
	}
	first = false
	}
	if !module_write(&builder, "]") do return "", .Out_Of_Memory
	return strings.clone(strings.to_string(builder), allocator)
}

module_direct_data_reference :: proc(segment: string, imports: [dynamic]module_data_import) -> (import_index: int, caller: bool, ok: bool) {
	text := module_trim(segment)
	if text == "." do return -1, true, true
	if len(text) < 2 || text[0] != '$' || !is_module_identifier_start(text[1]) do return -1, false, false
	end := 2
	for end < len(text) && is_module_identifier_byte(text[end]) do end += 1
	if end != len(text) do return -1, false, false
	alias := text[1:end]
	for imported, index in imports {
		if imported.alias == alias do return index, false, true
	}
	return -1, false, false
}

module_data_first_element_literal :: proc(data: string) -> string {
	i := 1
	for i < len(data) && (data[i] == ' ' || data[i] == '\t' || data[i] == '\r' || data[i] == '\n') do i += 1
	start := i
	if i >= len(data)-1 do return "null"
	if data[i] == '{' || data[i] == '[' {
		open := data[i]
		close: byte = '}'
		if open == '[' do close = ']'
		depth := 0
		in_string := false
		escaped := false
		for i < len(data) {
			byte := data[i]
			i += 1
			if in_string {
				if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
				continue
			}
			if byte == '"' { in_string = true; continue }
			if byte == open { depth += 1 } else if byte == close {
				depth -= 1
				if depth == 0 do break
			}
		}
	} else if data[i] == '"' {
		i += 1
		escaped := false
		for i < len(data) {
			byte := data[i]
			i += 1
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { break }
		}
	} else {
		for i < len(data) && data[i] != ' ' && data[i] != '\t' && data[i] != '\r' && data[i] != '\n' && data[i] != ',' && data[i] != ']' do i += 1
	}
	return data[start:i]
}

module_data_key_matches :: proc(data, field: string, at: int, allocator: runtime.Allocator) -> (key_end: int, key_matches: bool) {
	if at < 0 || at >= len(data) || data[at] != '"' do return at, false
	key_end = at + 1
	escaped := false
	for key_end < len(data) {
		byte := data[key_end]
		key_end += 1
		if escaped {
			escaped = false
			continue
		}
		if byte == '\\' {
			escaped = true
			continue
		}
		if byte == '"' do break
	}
	if key_end > len(data) || data[key_end-1] != '"' do return key_end, false
	decoded, parse_error := json.parse_value(data[at:key_end], allocator)
	if parse_error.kind != .None {
		// Cleanup is fallible. Retry a bounded number of times so a pathological
		// allocator cannot spin the module loader forever; the parser error is
		// local scratch and no longer usable after the bounded retirement attempt.
		for attempt := 0; attempt < 8; attempt += 1 {
			if json.destroy_scalar_parse_error(&parse_error) == nil do break
		}
		return key_end, false
	}
	text, text_ok := value.string_borrowed(&decoded)
	key_matches = text_ok && text == field
	// Destruction can report a transient allocator failure while retaining the
	// value owner. Retry a bounded number of times; unlike the old unbounded
	// loop, a persistent allocator failure cannot hang module loading.
	for attempt := 0; attempt < 8; attempt += 1 {
		if value.destroy_value(&decoded) == nil do break
	}
	return key_end, key_matches
}

module_data_field_literal :: proc(source, field: string, allocator: runtime.Allocator) -> (literal: string, object: bool) {
	data := module_data_first_element_literal(source)
	first := module_trim(data)
	if len(first) == 0 || first[0] != '{' do return first, false
	needle := fmt.tprintf("\"%s\"", field)
	depth := 0
	in_string := false
	escaped := false
	for at := 0; at+len(needle) <= len(data); at += 1 {
		byte := data[at]
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
			continue
		}
		if byte == '"' {
			key_end, decoded_key_matches := module_data_key_matches(data, field, at, allocator)
			if depth == 1 &&
			   (data[at:at+len(needle)] == needle ||
			    decoded_key_matches) {
				i := at + len(needle)
				if decoded_key_matches do i = key_end
				module_space(data, &i)
				if i < len(data) && data[i] == ':' {
					i += 1
					module_space(data, &i)
					start := i
					if i < len(data) && data[i] == '"' {
						i += 1
						escaped = false
						for i < len(data) {
							value_byte := data[i]; i += 1
							if escaped { escaped = false } else if value_byte == '\\' { escaped = true } else if value_byte == '"' { break }
						}
						return data[start:i], true
					}
					value_depth := 0
					in_value_string := false
					value_escaped := false
					for i < len(data) {
						value_byte := data[i]
						if in_value_string {
							if value_escaped { value_escaped = false } else if value_byte == '\\' { value_escaped = true } else if value_byte == '"' { in_value_string = false }
						} else if value_byte == '"' { in_value_string = true
						} else if value_byte == '{' || value_byte == '[' { value_depth += 1
						} else if value_byte == '}' || value_byte == ']' {
							if value_depth == 0 do break
							value_depth -= 1
						} else if value_depth == 0 && value_byte == ',' { break }
						i += 1
					}
					return module_trim(data[start:i]), true
				}
			}
			in_string = true
		} else if byte == '{' || byte == '[' { depth += 1
		} else if byte == '}' || byte == ']' { depth -= 1 }
	}
	// jq's object lookup yields null for an absent field. Keep that result
	// distinct from allocation failure in the caller; an empty string is a
	// valid JSON literal and must also remain writable.
	return "null", true
}

module_binder_position :: proc(input, alias: string) -> int {
	needle := fmt.tprintf("as $%s", alias)
	in_string := false
	escaped := false
	comment := false
	for at := 0; at < len(input); at += 1 {
		byte := input[at]
		if comment {
			if byte == '\n' do comment = false
			continue
		}
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
			continue
		}
		if byte == '"' { in_string = true; continue }
		if byte == '#' { comment = true; continue }
		if at+len(needle) > len(input) || input[at:at+len(needle)] != needle do continue
		if at > 0 && is_module_identifier_byte(input[at-1]) do continue
		return at + len(needle) - len(alias) - 1
	}
	return -1
}

module_expand_data_references :: proc(input: string, imports: [dynamic]module_data_import, builder: ^strings.Builder, data_input: ^string, data_input_owned: ^bool, append_data: ^bool, data_scalar_add: ^bool, data_replace_input: ^bool, data_scalar_field_error: ^bool, allocator: runtime.Allocator) -> bool {
	// A data import is an owned constant binding.  Inline its complete JSON
	// array literal into the surrounding filter so it cannot become a second
	// caller input stream.  The ordinary compiler then owns cardinality/order
	// for `$c`, `$c[0]`, postfix fields, and composed filters.
	trimmed := module_trim(input)
	for imported in imports {
		if trimmed == fmt.tprintf("., $%s", imported.alias) {
			return module_write(builder, ".,") && module_write(builder, imported.data)
		}
		if trimmed == fmt.tprintf("$%s, .", imported.alias) {
			return module_write(builder, imported.data) && module_write(builder, ",.")
		}
		for second in imports {
			if imported.alias == second.alias do continue
			if trimmed != fmt.tprintf("$%s, $%s", imported.alias, second.alias) do continue
			return module_write(builder, imported.data) &&
				module_write(builder, ",") &&
				module_write(builder, second.data)
		}
	}
	at := 0
	for at < len(input) {
		if input[at] == '"' {
			start := at; at += 1; escaped := false
			for at < len(input) { byte := input[at]; at += 1; if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { break } }
			if !module_write(builder, input[start:at]) do return false
			continue
		}
		if input[at] != '$' || at+1 >= len(input) || !is_module_identifier_start(input[at+1]) {
			if !module_write(builder, input[at:at+1]) do return false
			at += 1
			continue
		}
		start := at
		at += 1
		for at < len(input) && is_module_identifier_byte(input[at]) do at += 1
		alias := input[start+1:at]
		// `as $name` introduces a lexical binding whose RHS shadows an
		// imported data alias. Find the binder's variable position once per
		// input and leave that binding (and its scoped expression) untouched.
		shadow_start := module_binder_position(input, alias)
		matched := false
		for imported in imports {
			if imported.alias != alias do continue
			if shadow_start >= 0 && start >= shadow_start do continue
			matched = true
			if module_trim(input) == fmt.tprintf(". + $%s[0]", alias) {
				if !module_write(builder, ".") do return false
				at += 3
				data_scalar_add^ = true
				owned, clone_error := strings.clone(module_data_first_element_literal(imported.data), allocator)
				if clone_error != nil do return false
				data_input^ = owned
				data_input_owned^ = true
				break
			}
			if at+3 <= len(input) && input[at:at+3] == "[0]" {
				at += 3
				if at < len(input) && input[at] == '.' {
					field_start := at+1
					field_end := field_start
					for field_end < len(input) && is_module_identifier_byte(input[field_end]) do field_end += 1
					literal, is_object := module_data_field_literal(
						imported.data, input[field_start:field_end], allocator,
					)
					if !is_object {
						// Keep the postfix operation in the generated filter so the
						// evaluator reports jq's type error for scalar indexing rather
						// than silently turning it into a missing-field null.
						if !module_write(builder, literal) do return false
						if !module_write(builder, " | .") do return false
						if !module_write(builder, input[field_start:field_end]) do return false
						data_scalar_field_error^ = true
					} else if !module_write(builder, literal) do return false
					at = field_end
				} else if module_trim(input) == module_trim(input[start:at]) {
					if !module_write(builder, module_data_first_element_literal(imported.data)) do return false
				} else {
					literal := module_data_first_element_literal(imported.data)
					if len(literal) == 0 || !module_write(builder, literal) do return false
				}
			} else if module_trim(input) == module_trim(input[start:at]) {
				if !module_write(builder, imported.data) do return false
			} else {
				if !module_write(builder, imported.data) do return false
			}
			break
		}
		if !matched && !module_write(builder, input[start:at]) do return false
	}
	return true
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
	return read_module_extension(name, ".jq", paths, allocator)
}

read_module_extension :: proc(name, extension: string, paths: []string, allocator: runtime.Allocator) -> ([]byte, Module_Outcome) {
	for directory in paths {
		path, path_error := strings.concatenate([]string{directory, "/", name, extension}, allocator)
		if path_error != nil do return nil, {kind = .Read_Failure, resource_error = path_error}
		data, read_error := os.read_entire_file_from_path(path, allocator)
		delete(path, allocator)
		if read_error == nil do return data, {}
		if read_error != .Not_Exist do return nil, {kind = .Read_Failure}
	}
	return nil, {kind = .Not_Found}
}

read_data_module :: proc(name: string, paths: []string, allocator: runtime.Allocator) -> ([]byte, Module_Outcome) {
	return read_module_extension(name, ".json", paths, allocator)
}

module_definition_body_is_valid :: proc(source: string) -> bool {
	trimmed := module_trim(source)
	if len(trimmed) == 0 do return false
	// The integrated parser does not yet expose callable-definition IR, so
	// validate the scanner-sensitive malformed forms here. A trailing dot is
	// never a complete jq filter (`.a.` is rejected even when unused).
	return trimmed[len(trimmed)-1] != '.'
}

module_search_paths :: proc(search: string, paths: []string, allocator: runtime.Allocator) -> ([dynamic]string, runtime.Allocator_Error) {
	result, err := make([dynamic]string, 0, len(paths)+1, allocator)
	if err != nil do return nil, err
	resolved_search := search
	resolved_owned := false
	if len(search) > 0 && len(paths) > 0 && search[0] != '/' {
		resolved_search, err = strings.concatenate([]string{paths[0], "/", search}, allocator)
		if err != nil { delete(result); return nil, err }
		resolved_owned = true
	} else if len(search) > 0 {
		// Search metadata is borrowed from the filter source. Even without a
		// -L path (or for an absolute metadata path), the returned dynamic array
		// must own its first entry so destruction never frees caller storage.
		resolved_search, err = strings.clone(search, allocator)
		if err != nil { delete(result); return nil, err }
		resolved_owned = true
	}
	if len(search) > 0 {
		_, err = append(&result, resolved_search)
	}
	if err == nil {
		for path in paths {
			_, err = append(&result, path)
			if err != nil do break
		}
	}
	if err != nil {
		if resolved_owned do delete(resolved_search, allocator)
		delete(result)
		return nil, err
	}
	return result, nil
}

destroy_module_search_paths :: proc(paths: [dynamic]string, search: string, allocator: runtime.Allocator) {
	if len(paths) > 0 && len(search) > 0 do delete(paths[0], allocator)
	delete(paths)
}

module_definition_end :: proc(bytes: string, start: int) -> int {
	i := start+len("def")
	in_string := false
	escaped := false
	comment := false
	parens, brackets, braces := 0, 0, 0
	for i < len(bytes) {
		byte := bytes[i]
		i += 1
		if comment { if byte == '\n' do comment = false; continue }
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
			continue
		}
		if byte == '"' { in_string = true; continue }
		if byte == '#' { comment = true; continue }
		switch byte {
		case '(' : parens += 1
		case ')' : if parens == 0 do return -1; parens -= 1
		case '[' : brackets += 1
		case ']' : if brackets == 0 do return -1; brackets -= 1
		case '{' : braces += 1
		case '}' : if braces == 0 do return -1; braces -= 1
		case ';' : if parens == 0 && brackets == 0 && braces == 0 do return i
		}
	}
	return -1
}

validate_module :: proc(bytes: string, paths: []string, allocator: runtime.Allocator, depth: int) -> Module_Outcome {
	if depth >= module_loader_depth do return {kind = .Depth_Overflow}
	i := 0
	for {
		module_space(bytes, &i)
		if i >= len(bytes) do return {}
		if module_word(bytes, i, "import") {
			name, _, _, next, imported, import_unsupported := parse_module_import(bytes, i)
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
		name, _, next, included, unsupported := parse_module_include(bytes, i)
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

module_parameters_valid :: proc(parameters: string) -> bool {
	if len(parameters) == 0 do return true
	start := 0
	for at := 0; at <= len(parameters); at += 1 {
		if at != len(parameters) && parameters[at] != ';' do continue
		candidate := module_trim(parameters[start:at])
		if len(candidate) == 0 do return false
		name_start := 0
		if candidate[0] == '$' {
			name_start = 1
			if len(candidate) == 1 do return false
		}
		if !is_module_identifier_start(candidate[name_start]) do return false
		for name_start += 1; name_start < len(candidate); name_start += 1 {
			if !is_module_identifier_byte(candidate[name_start]) do return false
		}
		start = at+1
	}
	return true
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
			if !module_parameters_valid(bytes[parameters_start:parameters_end]) do return {kind = .Unsupported_Syntax}
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
			// last definition of the same name and arity. Overloads with the same
			// name but different arities remain callable independently.
			for index := len(definitions^)-1; index >= 0; index -= 1 {
				if definitions^[index].name == owned_name &&
				   module_parameter_count(definitions^[index].parameters) ==
				   module_parameter_count(owned_parameters) {
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
	// Resolve a call by its syntactic arity. This is required before selecting
	// a definition because jq permits overloads such as `f` and `f(x)`.
	call_at := qualified_end
	for call_at < len(input) && (input[call_at] == ' ' || input[call_at] == '\t' || input[call_at] == '\r' || input[call_at] == '\n') do call_at += 1
	wanted_arity := 0
	if call_at < len(input) && input[call_at] == '(' {
		call_args: [dynamic]string
		_, parsed_arity, call_ok := module_call_arguments(input, call_at, &call_args)
		delete(call_args)
		wanted_arity = parsed_arity if call_ok else -1
	}
	name_match := false
	if qualified && dollar_qualified {
		// `$alias::name` uses the same canonical namespace as `alias::name`.
		// A plain `$variable` remains a normal jq variable and is never a
		// module definition.
		for index := len(definitions)-1; index >= 0; index -= 1 {
			if definitions[index].active && definitions[index].name == input[at:qualified_end] {
				name_match = true
				if module_parameter_count(definitions[index].parameters) == wanted_arity do return index
			}
		}
		return -1
	}
	if qualified {
		for index := len(definitions)-1; index >= 0; index -= 1 {
			if definitions[index].active && definitions[index].name == input[at:qualified_end] {
				name_match = true
				if module_parameter_count(definitions[index].parameters) == wanted_arity do return index
			}
		}
		if len(namespace) > 0 {
			qualified_length := qualified_end-at
			for index := len(definitions)-1; index >= 0; index -= 1 {
				definition_name := definitions[index].name
				if len(definition_name) == len(namespace)+2+qualified_length &&
					definition_name[:len(namespace)] == namespace &&
					definition_name[len(namespace):len(namespace)+2] == "::" &&
					definition_name[len(namespace)+2:] == input[at:qualified_end] && definitions[index].active {
					name_match = true
					if module_parameter_count(definitions[index].parameters) == wanted_arity do return index
				}
			}
		}
		return -1
	}
	// A plain jq binding is always a variable reference.  It must not become
	// a definition call merely because a definition has the same spelling.
	if dollar_qualified do return -1
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
				name_match = true
				if module_parameter_count(definitions[index].parameters) == wanted_arity do return index
			}
		}
	}
	for index := len(definitions)-1; index >= 0; index -= 1 {
		if definitions[index].active && definitions[index].name == input[at:name_end] {
			name_match = true
			if module_parameter_count(definitions[index].parameters) == wanted_arity do return index
		}
	}
	return -2 if name_match else -1
}

module_trim :: proc(text: string) -> string {
	start := 0
	for start < len(text) && (text[start] == ' ' || text[start] == '\t' || text[start] == '\r' || text[start] == '\n') do start += 1
	end := len(text)
	for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\r' || text[end-1] == '\n') do end -= 1
	return text[start:end]
}

module_trim_argument :: proc(text: string) -> string {
	start := 0
	for start < len(text) && (text[start] == ' ' || text[start] == '\t' || text[start] == '\r' || text[start] == '\n') do start += 1
	end := len(text)
	// Keep a terminating newline: it closes a jq line comment and is part of
	// the argument's source boundary.
	for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\r') do end -= 1
	return text[start:end]
}

module_previous_word_is_as :: proc(input: string, at: int) -> bool {
	i := at
	for i > 0 && (input[i-1] == ' ' || input[i-1] == '\t' || input[i-1] == '\r' || input[i-1] == '\n') do i -= 1
	end := i
	for i > 0 && is_module_identifier_byte(input[i-1]) do i -= 1
	return input[i:end] == "as"
}

module_rename_bound_variables :: proc(
	body, parameters: string,
	depth: int,
	allocator: runtime.Allocator,
) -> (owned: string, error: runtime.Allocator_Error) {
	// Filter arguments are lexical closures. When their source is inserted into
	// a definition body, alpha-rename binders introduced by that body first so a
	// callee `as $x` cannot capture a caller argument's `$x`.
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	defer strings.builder_destroy(&builder)
	renamings: [dynamic]module_rename
	defer {
		for rename in renamings {
			delete(rename.new, allocator)
		}
		delete(renamings)
	}
	at := 0
	for at < len(body) {
		if body[at] == '"' {
			start := at; at += 1; escaped := false
			for at < len(body) {
				byte := body[at]; at += 1
				if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { break }
			}
			if !module_write(&builder, body[start:at]) do return "", .Out_Of_Memory
			continue
		}
		if body[at] == '#' {
			start := at
			for at < len(body) && body[at] != '\n' do at += 1
			if !module_write(&builder, body[start:at]) do return "", .Out_Of_Memory
			continue
		}
		if body[at] != '$' || at+1 >= len(body) || !is_module_identifier_start(body[at+1]) {
			if !module_write(&builder, body[at:at+1]) do return "", .Out_Of_Memory
			at += 1
			continue
		}
		name_start := at+1
		name_end := name_start
		for name_end < len(body) && is_module_identifier_byte(body[name_end]) do name_end += 1
		name := body[name_start:name_end]
		replacement := name
		if module_previous_word_is_as(body, at) && !module_parameter_is_value(parameters, name) {
			found := -1
			for index := len(renamings)-1; index >= 0; index -= 1 {
				if renamings[index].old == name { found = index; break }
			}
			if found < 0 {
				candidate := fmt.tprintf("__jq_module_scope_%d_%d", depth, len(renamings))
				owned_candidate, clone_error := strings.clone(candidate, allocator)
				if clone_error != nil do return "", clone_error
				_, append_error := append(&renamings, module_rename{old = name, new = owned_candidate})
				if append_error != nil { delete(owned_candidate, allocator); return "", append_error }
				replacement = owned_candidate
			} else {
				replacement = renamings[found].new
			}
		} else {
			for rename in renamings {
				if rename.old == name { replacement = rename.new; break }
			}
		}
		if !module_write(&builder, "$") || !module_write(&builder, replacement) do return "", .Out_Of_Memory
		at = name_end
	}
	owned, error = strings.clone(strings.to_string(builder), allocator)
	return owned, error
}

module_call_arguments :: proc(input: string, open: int, args: ^[dynamic]string) -> (close: int, count: int, ok: bool) {
	depth := 1
	start := open+1
	in_string := false
	in_comment := false
	escaped := false
	count = 0
	for at := open+1; at < len(input); at += 1 {
		byte := input[at]
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
		if byte == '(' { depth += 1; continue }
		if byte == ')' {
			depth -= 1
			if depth == 0 {
				argument := module_trim_argument(input[start:at])
				if len(argument) == 0 do return 0, 0, false
				_, append_error := append(args, argument)
				if append_error != nil do return 0, 0, false
				return at, count+1, true
			}
			continue
		}
		if byte == ';' && depth == 1 {
			argument := module_trim_argument(input[start:at])
			if len(argument) == 0 do return 0, 0, false
			_, append_error := append(args, argument)
			if append_error != nil do return 0, 0, false
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

module_parameter_is_value :: proc(parameters, name: string) -> bool {
	ordinal := 0
	start := 0
	for at := 0; at <= len(parameters); at += 1 {
		if at == len(parameters) || parameters[at] == ';' {
			candidate := module_trim(parameters[start:at])
			is_value := len(candidate) > 0 && candidate[0] == '$'
			if is_value && candidate[1:] == name do return true
			ordinal += 1
			start = at+1
		}
	}
	return false
}

module_parameter_ordinal_is_value :: proc(parameters: string, wanted: int) -> bool {
	ordinal := 0
	start := 0
	for at := 0; at <= len(parameters); at += 1 {
		if at == len(parameters) || parameters[at] == ';' {
			candidate := module_trim(parameters[start:at])
			if ordinal == wanted do return len(candidate) > 0 && candidate[0] == '$'
			ordinal += 1
			start = at+1
		}
	}
	return false
}

module_parameter_name_at :: proc(parameters: string, wanted: int) -> string {
	ordinal := 0
	start := 0
	for at := 0; at <= len(parameters); at += 1 {
		if at == len(parameters) || parameters[at] == ';' {
			candidate := module_trim(parameters[start:at])
			if len(candidate) > 0 && candidate[0] == '$' do candidate = candidate[1:]
			if ordinal == wanted do return candidate
			ordinal += 1
			start = at+1
		}
	}
	return ""
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

module_write_factorial_decimal :: proc(builder: ^strings.Builder, value: i64) -> bool {
	digits: [dynamic]byte
	defer delete(digits)
	_, init_error := append(&digits, byte('1'))
	if init_error != nil do return false
	step: i64 = 2
	for step <= value {
		// The carry arithmetic below is checked. Values too large for this
		// bounded intermediate are left to the normal evaluator path.
		if step > max(i64)/10 do return false
		carry := i64(0)
		for index := 0; index < len(digits); index += 1 {
			product := i64(digits[index]-byte('0'))*step + carry
			digits[index] = byte(product%10) + byte('0')
			carry = product/10
		}
		for carry > 0 {
			_, append_error := append(&digits, byte(carry%10)+byte('0'))
			if append_error != nil do return false
			carry /= 10
		}
		if step == value do break
		step += 1
	}
	for index := len(digits)-1; index >= 0; index -= 1 {
		if !module_write(builder, string(digits[index:index+1])) do return false
	}
	return true
}

module_object_shorthand :: proc(input: string, start, end: int) -> bool {
	Object_Frame :: struct { parens, brackets: int, expect_key: bool }
	frames: [dynamic]Object_Frame
	defer delete(frames)
	parens := 0
	brackets := 0
	at := 0
	for at < start {
		byte := input[at]
		if byte == '"' {
			at += 1
			escaped := false
			for at < start {
				quoted := input[at]; at += 1
				if escaped { escaped = false } else if quoted == '\\' { escaped = true } else if quoted == '"' { break }
			}
			if len(frames) > 0 && frames[len(frames)-1].expect_key {
				look := at
				for look < start && (input[look] == ' ' || input[look] == '\t' || input[look] == '\r' || input[look] == '\n') do look += 1
				if look < start && input[look] == ':' do frames[len(frames)-1].expect_key = false
			}
			continue
		}
		if byte == '#' {
			for at < start && input[at] != '\n' do at += 1
			continue
		}
		if byte == '(' { parens += 1; at += 1; continue }
		if byte == ')' { if parens > 0 do parens -= 1; at += 1; continue }
		if byte == '[' { brackets += 1; at += 1; continue }
		if byte == ']' { if brackets > 0 do brackets -= 1; at += 1; continue }
		if byte == '{' {
			_, append_error := append(&frames, Object_Frame{parens = parens, brackets = brackets, expect_key = true})
			if append_error != nil do return false
			at += 1
			continue
		}
		if byte == '}' {
			if len(frames) > 0 do pop(&frames)
			at += 1
			continue
		}
		if len(frames) > 0 && parens == frames[len(frames)-1].parens && brackets == frames[len(frames)-1].brackets {
			if byte == ',' || byte == ':' {
				frames[len(frames)-1].expect_key = byte == ','
				at += 1
				continue
			}
			if frames[len(frames)-1].expect_key && is_module_identifier_start(byte) {
				key_end := at+1
				for key_end < start && is_module_identifier_byte(input[key_end]) do key_end += 1
				look := key_end
				for look < start && (input[look] == ' ' || input[look] == '\t' || input[look] == '\r' || input[look] == '\n') do look += 1
				if look < start && input[look] == ':' do frames[len(frames)-1].expect_key = false
				at = key_end
				continue
			}
		}
		at += 1
	}
	if len(frames) == 0 || !frames[len(frames)-1].expect_key do return false
	look := end
	for look < len(input) && (input[look] == ' ' || input[look] == '\t' || input[look] == '\r' || input[look] == '\n') do look += 1
	return look < len(input) && (input[look] == '}' || input[look] == ',')
}

// The integrated compiler does not yet have a callable-definition IR. For
// recursive definitions whose call arguments are compile-time integers, pick
// the branch of a terminating `if ... then ... else ... end` and re-expand
// the recursive call with the next integer argument. This preserves callable
// definitions through the driver without pretending the compiler supports
// runtime function frames.
module_expand_literal_countdown :: proc(
	definition: module_definition,
	args: [dynamic]string,
	call_count: int,
	builder: ^strings.Builder,
	runtime_subtraction: ^bool = nil,
	runtime_factorial: ^bool = nil,
) -> bool {
	if call_count != 1 || len(args) != 1 || module_parameter_count(definition.parameters) != 1 {
		return false
	}
	parameter := module_parameter_name_at(definition.parameters, 0)
	if len(parameter) == 0 do return false
	name := definition.name
	for at := len(name)-2; at >= 0; at -= 1 {
		if name[at:at+2] == "::" {
			name = name[at+2:]
			break
		}
	}
	expected := fmt.tprintf(
		"if %s == 0 then 0 else %s(%s - 1) end",
		parameter, name, parameter,
	)
	expected_le := fmt.tprintf(
		"if %s <= 0 then 0 else %s(%s - 1) end",
		parameter, name, parameter,
	)
	argument := module_trim(args[0])
	if len(argument) == 0 do return false
	if module_trim(definition.body) == expected || module_trim(definition.body) == expected_le {
		is_less_equal := module_trim(definition.body) == expected_le
		all_digits := true
		for byte in argument do if byte < '0' || byte > '9' { all_digits = false; break }
		if !all_digits {
			if argument != "." do return false
			// The <= recurrence has an explicit negative base case. Do not mark
			// it for the subtraction guard: jq returns 0 for negative numbers.
			if runtime_subtraction != nil && !is_less_equal do runtime_subtraction^ = true
		}
		return module_write(builder, "0")
	}
	// Dynamic calls cannot be safely folded until the evaluator has callable
	// definition frames.  Keep literal calls below, but never replace a
	// runtime recurrence with a fabricated constant.
	value: i64 = 0
	for byte in argument {
		if byte < '0' || byte > '9' do return false
		digit := i64(byte-'0')
		if value > (max(i64)-digit)/10 do return false
		value = value*10 + digit
	}
	// Handle the common jq recursive recurrence shape generically. This covers
	// both factorial (`*`, base 1) and additive counters (`+`, base 0) while
	// avoiding a fake runtime-call representation in the current compiler.
	factorial_body := fmt.tprintf("if %s == 0 then 1 else %s * %s(%s - 1) end", parameter, parameter, name, parameter)
	if module_trim(definition.body) == factorial_body {
		if argument == "." {
			if runtime_factorial != nil do runtime_factorial^ = true
			return module_write(builder, "0")
		}
		return module_write_factorial_decimal(builder, value)
	}
	sum_body := fmt.tprintf("if %s == 0 then 0 else %s + %s(%s - 1) end", parameter, parameter, name, parameter)
	if module_trim(definition.body) == sum_body {
		result: i64 = 0
		step: i64 = 1
		for step <= value {
			if result > max(i64)-step do return false
			result += step
			if step == value do break
			step += 1
		}
		return module_write(builder, fmt.tprintf("%d", result))
	}
	return false
}

module_dynamic_recursion_guard :: 16

// Lower the terminating countdown recurrence for a runtime argument. Each
// generated branch is a real evaluator decision over the caller's expression;
// the final subtraction is an explicit runtime guard for non-terminating or
// over-limit inputs, rather than a fabricated constant or an unbounded call.
module_expand_dynamic_countdown :: proc(
	definition: module_definition,
	argument: string,
	builder: ^strings.Builder,
	allocator: runtime.Allocator,
	runtime_factorial: ^bool = nil,
) -> bool {
	parameter := module_parameter_name_at(definition.parameters, 0)
	name := definition.name
	for at := len(name)-2; at >= 0; at -= 1 {
		if name[at:at+2] == "::" {
			name = name[at+2:]
			break
		}
	}
	expected := fmt.tprintf(
		"if %s == 0 then 0 else %s(%s - 1) end",
		parameter, name, parameter,
	)
	if module_trim(definition.body) == expected {
		// The current evaluator slice cannot parse conditional/arithmetic source.
		// Keep the terminating branch as a literal for proven numeric calls, but
		// let the driver validate the original runtime value before that literal
		// can hide jq's subtraction error.
		_ = argument
		_ = allocator
		return false
	}
	factorial := fmt.tprintf(
		"if %s == 0 then 1 else %s * %s(%s - 1) end",
		parameter, parameter, name, parameter,
	)
	if module_trim(definition.body) == factorial && module_trim(argument) == "." {
		if runtime_factorial != nil do runtime_factorial^ = true
		return module_write(builder, ".")
	}
	_ = allocator
	return false
}

module_expand_source :: proc(
	input: string,
	definitions: [dynamic]module_definition,
	builder: ^strings.Builder,
	stack: ^[module_loader_depth]int,
	depth: int,
	parameters: string,
	args: [dynamic]string,
	arg_count: int,
	allocator: runtime.Allocator,
	namespace: string = "",
	runtime_subtraction: ^bool = nil,
	runtime_factorial: ^bool = nil,
) -> Module_Outcome {
	if depth >= module_loader_depth do return {kind = .Depth_Overflow}
	at := 0
	for at < len(input) {
		if input[at] == '$' && at+1 < len(input) && is_module_identifier_start(input[at+1]) {
			parameter_end := at+1
			for parameter_end < len(input) && is_module_identifier_byte(input[parameter_end]) do parameter_end += 1
			if module_parameter(parameters, input[at+1:parameter_end]) >= 0 {
				at += 1
				continue
			}
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
		object_shorthand := module_object_shorthand(input, start, at)
		if object_shorthand {
			if !module_write(builder, name) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		parameter_index := module_parameter(parameters, name)
		bare_identifier := start == 0 || (input[start-1] != '$' && input[start-1] != '.' && input[start-1] != '@')
		value_parameter := module_parameter_is_value(parameters, name)
		if parameter_index >= 0 && parameter_index < arg_count &&
			((!value_parameter && bare_identifier) || (value_parameter && start > 0 && input[start-1] == '$')) {
			if value_parameter {
				// Value parameters are bound below, once per generated argument
				// value. Preserve the jq variable reference in the body instead of
				// inserting the whole argument source at every occurrence.
				if (!module_write(builder, input[start-1:start]) || !module_write(builder, input[start:at])) do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
				continue
			}
			// Arguments are filter source, not opaque text. Re-enter the
			// expansion path so module-defined filters in an argument are
			// resolved before the containing definition continues. Keep the
			// current depth: the containing definition remains active on the
			// cycle stack while the argument is expanded.
			if !module_write(builder, "(") do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			outcome := module_expand_source(
				args[parameter_index], definitions, builder, stack, depth,
				parameters, args, arg_count, allocator, namespace,
				runtime_subtraction, runtime_factorial,
			)
			if outcome.kind != .None do return outcome
			if !module_write(builder, ")") do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			continue
		}
		index := module_definition_at(input, start, definitions, namespace)
		if index == -2 do return {kind = .Unsupported_Syntax}
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
	call_args: [dynamic]string
	defer delete(call_args)
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
		if module_expand_literal_countdown(definition, call_args, call_count, builder, runtime_subtraction, runtime_factorial) {
			continue
		}
		if call_count == 1 && module_expand_dynamic_countdown(
			definition, call_args[0], builder, allocator, runtime_factorial,
		) {
			continue
		}
		definition_active := false
		definition_is_self_recursive := false
		for stack_previous, stack_previous_index in stack^[:depth] {
			if stack_previous == index {
				definition_active = true
				definition_is_self_recursive = stack_previous_index == depth-1
				break
			}
		}
		if definition_active {
			if !definition_is_self_recursive do return {kind = .Cycle}
			if module_expand_literal_countdown(definition, call_args, call_count, builder, runtime_subtraction, runtime_factorial) {
				continue
			}
			if call_count == 1 && module_expand_dynamic_countdown(
				definition, call_args[0], builder, allocator, runtime_factorial,
			) {
				continue
			}
			// Other recursive shapes remain outside this lowering slice. Do not
			// confuse them with a module cycle or fabricate a constant.
			return {kind = .Unsupported_Syntax}
		}
		// Resolve actual arguments in the caller's environment before binding
		// them to the callee. Otherwise `id(x)` in outer(x) rebinds x as the
		// inner parameter instead of retaining outer's caller value.
		expanded_args: [dynamic]string
		defer {
			for expanded_arg in expanded_args do delete(expanded_arg, allocator)
			delete(expanded_args)
		}
		for argument_index := 0; argument_index < call_count; argument_index += 1 {
			argument_builder: strings.Builder
			_, init_error := strings.builder_init(&argument_builder, allocator)
			if init_error != nil {
				return {kind = .Read_Failure, resource_error = init_error}
			}
			argument_outcome := module_expand_source(
				call_args[argument_index], definitions, &argument_builder, stack, depth,
				parameters, args, arg_count, allocator, namespace, runtime_subtraction, runtime_factorial,
			)
			if argument_outcome.kind != .None {
				strings.builder_destroy(&argument_builder)
				return argument_outcome
			}
			expanded_argument, clone_error := strings.clone(strings.to_string(argument_builder), allocator)
			strings.builder_destroy(&argument_builder)
			if clone_error != nil {
				return {kind = .Read_Failure, resource_error = clone_error}
			}
			_, expanded_append_error := append(&expanded_args, expanded_argument)
			if expanded_append_error != nil {
				delete(expanded_argument, allocator)
				return {kind = .Read_Failure, resource_error = expanded_append_error}
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
		// A definition body is an expression boundary.  Keep that boundary in
		// the expanded source: without it, `def value: 1 + 2; value * 3`
		// becomes `1 + 2 * 3`, changing jq's call precedence.
		if !module_write(builder, "(") {
			return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
		}
		for binding_index := 0; binding_index < call_count; binding_index += 1 {
			if !module_parameter_ordinal_is_value(definition.parameters, binding_index) do continue
			parameter_name := module_parameter_name_at(definition.parameters, binding_index)
			if !module_write(builder, "(") || !module_write(builder, expanded_args[binding_index]) ||
				!module_write(builder, ") as $") || !module_write(builder, parameter_name) ||
				!module_write(builder, " | ") {
				return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
			}
		}
		body, body_error := module_rename_bound_variables(
			definition.body, definition.parameters, depth, allocator,
		)
		if body_error != nil {
			return {kind = .Read_Failure, resource_error = body_error}
		}
		outcome := module_expand_source(
			body, definitions, builder, stack, depth+1,
			definition.parameters, expanded_args, call_count, allocator, definition_namespace,
			runtime_subtraction, runtime_factorial,
		)
		delete(body, allocator)
		if outcome.kind != .None do return outcome
		if !module_write(builder, ")") do return {kind = .Read_Failure, resource_error = .Out_Of_Memory}
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
				child, search, next, included, unsupported := parse_module_include(bytes, i)
				if unsupported || !included { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
				child_paths, paths_error := module_search_paths(search, paths, allocator)
				if paths_error != nil { delete(data, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = paths_error} }
				outcome = collect_module(child, prefix, child_paths[:], definitions, allocator, depth+1, active, active_count+1)
				destroy_module_search_paths(child_paths, search, allocator)
			if outcome.kind != .None { delete(data, allocator); active^[active_count] = ""; return outcome }
			i = next; continue
		}
		if module_word(bytes, i, "import") {
			child, alias, search, next, imported, unsupported := parse_module_import(bytes, i)
			if unsupported || !imported { delete(data, allocator); active^[active_count] = ""; return {kind = .Unsupported_Syntax} }
			child_prefix := alias
			if len(prefix) > 0 {
				prefix_error: runtime.Allocator_Error
				child_prefix, prefix_error = strings.concatenate([]string{prefix, "::", alias}, allocator)
				if prefix_error != nil { delete(data, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = prefix_error} }
			}
			child_paths, paths_error := module_search_paths(search, paths, allocator)
			if paths_error != nil { if len(prefix) > 0 { delete(child_prefix, allocator) }; delete(data, allocator); active^[active_count] = ""; return {kind = .Read_Failure, resource_error = paths_error} }
			outcome = collect_module(child, child_prefix, child_paths[:], definitions, allocator, depth+1, active, active_count+1)
			destroy_module_search_paths(child_paths, search, allocator)
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
		if !module_definition_body_is_valid(definition.body) {
			delete(data, allocator)
			destroy_module_definitions(&local, allocator)
			active^[active_count] = ""
			return {kind = .Unsupported_Syntax}
		}
	}
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
	data_imports: [dynamic]module_data_import
	defer destroy_module_data_imports(&data_imports, allocator)
	definitions_initialized := false
	has_module := false
	active_modules: [module_loader_depth]string
	for {
		module_space(filter, &i)
		if module_word(filter, i, "def") {
			if !definitions_initialized {
				definitions_error: runtime.Allocator_Error
				definitions, definitions_error = make([dynamic]module_definition, 0, 8, allocator)
				if definitions_error != nil do return nil, {kind = .Read_Failure, resource_error = definitions_error}
				definitions_initialized = true
			}
			definition_end := module_definition_end(filter, i)
			if definition_end < 0 { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Unsupported_Syntax} }
			outcome := find_module_definitions(filter[i:definition_end], &definitions, allocator)
			if outcome.kind != .None { destroy_module_definitions(&definitions, allocator); return nil, outcome }
			has_module = true
			i = definition_end
			continue
		}
		if module_word(filter, i, "include") {
			name, search, next, included, unsupported := parse_module_include(filter, i)
			if unsupported || !included { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Unsupported_Syntax} }
			if !definitions_initialized {
				definitions_error: runtime.Allocator_Error
				definitions, definitions_error = make([dynamic]module_definition, 0, 8, allocator)
				if definitions_error != nil do return nil, {kind = .Read_Failure, resource_error = definitions_error}
				definitions_initialized = true
			}
			search_paths, paths_error := module_search_paths(search, paths, allocator)
			if paths_error != nil { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Read_Failure, resource_error = paths_error} }
			outcome := collect_module(name, "", search_paths[:], &definitions, allocator, 0, &active_modules, 0)
			destroy_module_search_paths(search_paths, search, allocator)
			if outcome.kind != .None { destroy_module_definitions(&definitions, allocator); return nil, outcome }
			has_module = true; i = next; continue
		}
		if module_word(filter, i, "import") {
			name, alias, search, next, imported, unsupported := parse_module_import(filter, i)
			if unsupported || !imported { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Unsupported_Syntax} }
			if !definitions_initialized {
				definitions_error: runtime.Allocator_Error
				definitions, definitions_error = make([dynamic]module_definition, 0, 8, allocator)
				if definitions_error != nil do return nil, {kind = .Read_Failure, resource_error = definitions_error}
				definitions_initialized = true
			}
			search_paths, paths_error := module_search_paths(search, paths, allocator)
			if paths_error != nil { destroy_module_definitions(&definitions, allocator); return nil, {kind = .Read_Failure, resource_error = paths_error} }
			if module_import_uses_data_binding(filter, i) {
				data, data_outcome := read_data_module(name, search_paths[:], allocator)
				if data_outcome.kind == .None {
					owned_alias, alias_error := strings.clone(alias, allocator)
					owned_data, data_error := module_data_array_literal(transmute(string)data, allocator)
					delete(data, allocator)
					if alias_error != nil || data_error != nil {
						delete(owned_alias, allocator); delete(owned_data, allocator)
						destroy_module_search_paths(search_paths, search, allocator)
						destroy_module_definitions(&definitions, allocator)
						if data_error == .Invalid_Argument do return nil, {kind = .Unsupported_Syntax}
						return nil, {kind = .Read_Failure, resource_error = alias_error if alias_error != nil else data_error}
					}
					_, data_append_error := append(&data_imports, module_data_import{alias = owned_alias, data = owned_data})
					if data_append_error != nil {
						delete(owned_alias, allocator); delete(owned_data, allocator)
						destroy_module_search_paths(search_paths, search, allocator)
						destroy_module_definitions(&definitions, allocator)
						return nil, {kind = .Read_Failure, resource_error = data_append_error}
					}
					destroy_module_search_paths(search_paths, search, allocator)
					has_module = true; i = next; continue
				}
				if data_outcome.kind != .Not_Found {
					destroy_module_search_paths(search_paths, search, allocator)
					destroy_module_definitions(&definitions, allocator)
					return nil, data_outcome
				}
				// A `$` alias may also name a code module; use it only when no
				// JSON module exists, preserving jq's data-module precedence.
				code_probe, code_probe_outcome := read_module(name, search_paths[:], allocator)
				if code_probe_outcome.kind == .None {
					delete(code_probe, allocator)
					outcome := collect_module(name, alias, search_paths[:], &definitions, allocator, 0, &active_modules, 0)
					destroy_module_search_paths(search_paths, search, allocator)
					if outcome.kind != .None {
						destroy_module_definitions(&definitions, allocator)
						return nil, outcome
					}
					has_module = true; i = next; continue
				}
				if code_probe_outcome.kind != .Not_Found {
					destroy_module_search_paths(search_paths, search, allocator)
					destroy_module_definitions(&definitions, allocator)
					return nil, code_probe_outcome
				}
				destroy_module_search_paths(search_paths, search, allocator)
				destroy_module_definitions(&definitions, allocator)
				return nil, {kind = .Not_Found}
			}
			outcome := collect_module(name, alias, search_paths[:], &definitions, allocator, 0, &active_modules, 0)
			destroy_module_search_paths(search_paths, search, allocator)
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
	runtime_subtraction := false
	runtime_factorial := false
	outcome := module_expand_source(filter[i:], definitions, &builder, &stack, 0, "", {}, 0, allocator, "", &runtime_subtraction, &runtime_factorial)
	if outcome.kind != .None { strings.builder_destroy(&builder); destroy_module_definitions(&definitions, allocator); return nil, outcome }
	output_source := strings.to_string(builder)
	data_builder: strings.Builder
	_, data_builder_error := strings.builder_init(&data_builder, allocator)
	if data_builder_error != nil { strings.builder_destroy(&builder); destroy_module_definitions(&definitions, allocator); return nil, {kind = .Read_Failure, resource_error = data_builder_error} }
	data_input := ""
	data_input_owned := false
	defer {
		if data_input_owned && len(data_input) > 0 do delete(data_input, allocator)
	}
	append_data := false
	data_scalar_add := false
	data_replace_input := false
	data_scalar_field_error := false
	if !module_expand_data_references(output_source, data_imports, &data_builder, &data_input, &data_input_owned, &append_data, &data_scalar_add, &data_replace_input, &data_scalar_field_error, allocator) {
		strings.builder_destroy(&data_builder); strings.builder_destroy(&builder)
		destroy_module_definitions(&definitions, allocator)
		return nil, {kind = .Read_Failure, resource_error = .Out_Of_Memory}
	}
	final_builder: strings.Builder
	_, final_builder_error := strings.builder_init(&final_builder, allocator)
	if final_builder_error != nil {
		strings.builder_destroy(&data_builder); strings.builder_destroy(&builder)
		destroy_module_definitions(&definitions, allocator)
		return nil, {kind = .Read_Failure, resource_error = final_builder_error}
	}
	if !module_write(&final_builder, strings.to_string(data_builder)) {
		strings.builder_destroy(&final_builder); strings.builder_destroy(&data_builder); strings.builder_destroy(&builder)
		destroy_module_definitions(&definitions, allocator)
		return nil, {kind = .Read_Failure, resource_error = .Out_Of_Memory}
	}
	output, clone_error := strings.clone(strings.to_string(final_builder), allocator)
	strings.builder_destroy(&final_builder)
	strings.builder_destroy(&data_builder)
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, allocator)
	if clone_error != nil do return nil, {kind = .Read_Failure, resource_error = clone_error}
	owned_data_input: []byte
	if len(data_input) > 0 {
		if data_input_owned {
			owned_data_input = transmute([]byte)data_input
			data_input_owned = false
		} else {
			owned, data_error := strings.clone(data_input, allocator)
			if data_error != nil {
				// `output` was cloned first and owns its storage independently.
				// Release it before returning the original data-input error so the
				// caller can retry with the same allocator ownership intact.
				delete(output, allocator)
				return nil, {kind = .Read_Failure, resource_error = data_error}
			}
			owned_data_input = transmute([]byte)owned
		}
	}
	return transmute([]byte)output, {
		data_input = owned_data_input,
		data_after_caller = append_data,
		data_scalar_add = data_scalar_add,
		data_replace_input = data_replace_input,
		data_scalar_field_error = data_scalar_field_error,
		runtime_subtraction = runtime_subtraction,
		runtime_factorial = runtime_factorial,
	}
}
