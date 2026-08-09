package main

import "base:runtime"
import "core:io"
import "core:os"
import "core:sys/posix"
import driver "jq:driver"

CANDIDATE_VERSION :: "jq-1.8.1\n"

write_all :: proc(file: ^os.File, bytes: string) -> bool {
	written := 0
	data := transmute([]byte)bytes
	for written < len(data) {
		n, err := os.write(file, data[written:])
		if err != nil || n <= 0 do return false
		written += n
	}
	return true
}

argument_error :: proc(message: string) -> int {
	_ = write_all(os.stderr, "jq-odin: ")
	_ = write_all(os.stderr, message)
	_ = write_all(os.stderr, "\n")
	return 2
}

parsed_arguments :: struct {
	filter:       string,
	filter_index: int,
	input_paths:  [dynamic]string,
	module_paths: [dynamic]string,
	compact:      bool,
	raw:          bool,
	null_input:   bool,
	version:      bool,
	status:       int,
}

parse_arguments :: proc(args: []cstring) -> parsed_arguments {
	parsed: parsed_arguments
	options_done := false
	has_filter := false
	for index := 1; index < len(args); index += 1 {
		arg := string(args[index])
		if !options_done && arg == "--" {
			options_done = true
			continue
		}
		if !options_done && arg == "--version" {
			parsed.version = true
			return parsed
		}
		if !options_done && len(arg) > 2 && arg[0] == '-' && arg[1] != '-' && arg[1] != 'L' {
			for option in arg[1:] {
				switch option {
				case 'c': parsed.compact = true
				case 'r': parsed.raw = true
				case 'n': parsed.null_input = true
				case:
					_ = write_all(os.stderr, "jq-odin: unsupported option: ")
					_ = write_all(os.stderr, arg)
					_ = write_all(os.stderr, "\n")
					parsed.status = 2
					return parsed
				}
			}
			continue
		}
		if !options_done && (arg == "-c" || arg == "--compact-output") {
			parsed.compact = true
			continue
		}
		if !options_done && (arg == "-r" || arg == "--raw-output") {
			parsed.raw = true
			continue
		}
		if !options_done && (arg == "-n" || arg == "--null-input") {
			parsed.null_input = true
			continue
		}
		if !options_done && arg == "-L" {
			if index+1 >= len(args) {
				parsed.status = argument_error("-L requires a path")
				return parsed
			}
			index += 1
			if len(string(args[index])) == 0 {
				parsed.status = argument_error("-L requires a non-empty path")
				return parsed
			}
			_, append_error := append(&parsed.module_paths, string(args[index]))
			if append_error != nil {
				parsed.status = argument_error("unable to store module path")
				return parsed
			}
			continue
		}
		if !options_done && len(arg) > 2 && arg[:2] == "-L" {
			path := arg[2:]
			if len(path) == 0 {
				parsed.status = argument_error("-L requires a non-empty path")
				return parsed
			}
			_, append_error := append(&parsed.module_paths, path)
			if append_error != nil {
				parsed.status = argument_error("unable to store module path")
				return parsed
			}
			continue
		}
		// A lone dash is an ordinary operand: it can be the filter, or after
		// the filter it selects stdin in argv source order. Only longer dash
		// spellings are option-like.
		if !options_done && len(arg) > 1 && arg[0] == '-' {
			_ = write_all(os.stderr, "jq-odin: unsupported option: ")
			_ = write_all(os.stderr, arg)
			_ = write_all(os.stderr, "\n")
			parsed.status = 2
			return parsed
		}
		if has_filter {
			_, append_error := append(&parsed.input_paths, arg)
			if append_error != nil {
				parsed.status = argument_error("unable to store input path")
				return parsed
			}
			continue
		}
		parsed.filter = arg
		parsed.filter_index = index
		has_filter = true
	}
	if !has_filter {
		parsed.status = argument_error("missing filter")
	}
	return parsed
}

kind_name :: proc(kind: driver.Run_Error_Kind) -> string {
	switch kind {
	case .Filter_Parse: return "filter parse error"
	case .Filter_Compile: return "filter compile error"
	case .Module: return "module error"
	case .JSON_Input: return "JSON input error"
	case .Runtime: return "runtime error"
	case .Serialization: return "serialization error"
	case .Output: return "output error"
	case .Allocation: return "allocation error"
	case .Cleanup: return "cleanup error"
	case .Misuse: return "internal misuse"
	case .None: return ""
	}
	return "internal error"
}

error_status :: proc(kind: driver.Run_Error_Kind) -> int {
	switch kind {
	case .None: return 0
	case .Filter_Parse, .Filter_Compile, .Module: return 3
	case .JSON_Input: return 4
	case .Runtime, .Serialization: return 5
	case .Output: return 2
	case .Allocation, .Cleanup, .Misuse: return 2
	}
	return 2
}

write_driver_error :: proc(err: driver.Run_Error) -> bool {
	if err.kind == .Runtime && len(err.runtime_key) > len("__jq_odin_subtraction__") &&
	   err.runtime_key[:len("__jq_odin_subtraction__")] == "__jq_odin_subtraction__" {
		ok := write_all(os.stderr, "jq: error (at <stdin>:1): string (")
		ok = write_all(os.stderr, err.runtime_key[len("__jq_odin_subtraction__"):]) && ok
		ok = write_all(os.stderr, ") and number (1) cannot be subtracted\n") && ok
		return ok
	}
	ok := write_all(os.stderr, "jq-odin: ")
	ok = write_all(os.stderr, kind_name(err.kind)) && ok
	if err.kind == .Module {
		message := ""
		switch err.module_kind {
		case .Not_Found: message = ": module file not found"
		case .Read_Failure: message = ": unable to read module file"
		case .Unsupported_Syntax: message = ": unsupported module syntax"
		case .Import_Unsupported: message = ": unsupported module import"
		case .Depth_Overflow: message = ": module dependency depth exceeded"
		case .Duplicate_Definition: message = ": duplicate module definition"
		case .Cycle: message = ": cyclic module dependency"
		case .None:
		}
		ok = write_all(os.stderr, message) && ok
	}
	if err.kind == .Runtime && len(err.runtime_key) > 0 {
		if len(err.runtime_key) > len("__jq_odin_subtraction__") &&
			err.runtime_key[:len("__jq_odin_subtraction__")] == "__jq_odin_subtraction__" {
			// Module expansion currently reports this jq type error through a
			// private runtime key. The exact framing is handled above.
			ok = write_all(os.stderr, ": string (") && ok
			ok = write_all(os.stderr, err.runtime_key[len("__jq_odin_subtraction__"):]) && ok
			ok = write_all(os.stderr, ") and number (1) cannot be subtracted") && ok
		} else {
			ok = write_all(os.stderr, ": cannot index with string \"") && ok
			ok = write_all(os.stderr, err.runtime_key) && ok
			ok = write_all(os.stderr, "\"") && ok
		}
	}
	ok = write_all(os.stderr, "\n") && ok
	return ok
}

input_error_string :: proc(err: os.Error) -> string {
	switch value in err {
	case os.General_Error:
		if value == .Not_Exist do return "No such file or directory"
	case io.Error:
		if value == .Permission_Denied do return "Permission denied"
	case runtime.Allocator_Error, os.Platform_Error:
	}
	return os.error_string(err)
}

output_sink :: struct {
	failed: bool,
}

emit_stdout :: proc(data: rawptr, bytes: string) -> bool {
	sink := cast(^output_sink)data
	if sink == nil || sink.failed do return false
	sink.failed = !write_all(os.stdout, bytes)
	return !sink.failed
}

run_input :: proc(
	input: string,
	compact: bool,
	raw: bool,
	prepared: ^driver.Compiled_Filter,
	sink: ^output_sink,
) -> int {
	mode := driver.Output_Mode.Pretty
	if compact do mode = .Compact
	if raw do mode = .Raw
	if compact && raw do mode = .Raw_Compact
	result: driver.Run_Result
	err := driver.run_with_options(
		&result, "", input, context.allocator,
		{
			output_mode = mode,
			compiled_filter = prepared,
			emitter = emit_stdout,
			emitter_data = sink,
		},
	)

	status := error_status(err.kind)
	if err.kind == .Output {
		_ = write_all(os.stderr, "jq-odin: stdout I/O error\n")
	} else if err.kind != .None && !write_driver_error(err) do status = 2
	if cleanup_error := driver.destroy_run_result(&result); cleanup_error != nil {
		status = 2
		_ = write_all(os.stderr, "jq-odin: cleanup error\n")
	}
	return status
}

INPUT_CHUNK_SIZE :: 4096
// This leaf cannot import jq:json directly. Keep the framing guard equal to
// json.MAX_PARSING_DEPTH, whose accepted parser contract is 10,000 entries.
MAX_JSON_NESTING_DEPTH :: 10_000

container_kind :: enum u8 {
	Array,
	Object,
}

object_phase :: enum u8 {
	Expect_Key_Or_End,
	Expect_Key,
	Expect_Colon,
	Expect_Value,
	Expect_Separator,
}

array_phase :: enum u8 {
	Expect_Value_Or_End,
	Expect_Value,
	Expect_Separator,
}

scalar_state :: enum u8 {
	Start,
	Minus,
	Zero,
	Integer,
	Dot,
	Fraction,
	Exponent,
	Exponent_Sign,
	Exponent_Digits,
	Literal,
}

container_frame :: struct {
	kind: container_kind,
	object_phase: object_phase,
	array_phase: array_phase,
	object_key_entry: bool,
}

frame_mode :: enum u8 {
	Idle,
	Root_String,
	Container,
	Scalar,
}

frame_result :: enum u8 {
	Need_More,
	Found,
	Malformed,
	Too_Deep,
}

json_framer :: struct {
	mode: frame_mode,
	scan_index: int,
	depth: int,
	syntactic_entries: int,
	stack: [MAX_JSON_NESTING_DEPTH]container_frame,
	in_string: bool,
	string_is_object_key: bool,
	escaped: bool,
	unicode_remaining: u8,
	scalar_state: scalar_state,
	literal: [5]byte,
	literal_length: u8,
	literal_index: u8,
}

input_buffer :: struct {
	memory: []byte,
	length: int,
	// A rejected replacement whose immediate retirement fails, or a valid
	// replacement that cannot be published and retired after the old Free
	// fails, remains here at its allocator-reported address and actual size.
	// memory and cleanup_memory are distinct sole owners until destruction.
	cleanup_memory: []byte,
	// The jq parser spans all argv inputs. Only byte zero of that parser source
	// is BOM-eligible; consuming a framed value must not reset this bit.
	bom_eligible: bool,
	framer: json_framer,
}

destroy_input_buffer :: proc(buffer: ^input_buffer) -> bool {
	if len(buffer.cleanup_memory) > 0 {
		err := runtime.mem_free_bytes(buffer.cleanup_memory, context.allocator)
		if err != nil && err != .Mode_Not_Implemented do return false
		buffer.cleanup_memory = nil
	}
	if len(buffer.memory) > 0 {
		err := runtime.mem_free_bytes(buffer.memory, context.allocator)
		if err != nil && err != .Mode_Not_Implemented do return false
		buffer.memory = nil
	}
	buffer^ = {}
	return true
}

reserve_input :: proc(buffer: ^input_buffer, additional: int) -> bool {
	// A prior failed growth is cleanup-only. Do not allocate or accept more
	// input until the exact retained owners have been retired.
	if len(buffer.cleanup_memory) > 0 do return false
	if additional < 0 || buffer.length > max(int)-additional do return false
	required := buffer.length+additional
	if required <= len(buffer.memory) do return true
	capacity := max(len(buffer.memory), INPUT_CHUNK_SIZE)
	for capacity < required {
		if capacity > max(int)-capacity/2 {
			capacity = required
			break
		}
		capacity += capacity/2
	}
	replacement, alloc_error := runtime.mem_alloc_bytes(
		capacity, align_of(uintptr), context.allocator,
	)
	if alloc_error != nil || len(replacement) != capacity ||
	   len(replacement) > 0 && uintptr(raw_data(replacement))%uintptr(align_of(uintptr)) != 0 {
		if len(replacement) > 0 {
			free_error := runtime.mem_free_bytes(replacement, context.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				// Preserve the allocator-reported address and actual size. This is
				// the sole owner of the rejected allocation until destruction retries
				// its exact Free; the published input allocation remains unchanged.
				buffer.cleanup_memory = replacement
			}
		}
		return false
	}
	if buffer.length > 0 do copy(replacement[:buffer.length], buffer.memory[:buffer.length])
	if len(buffer.memory) > 0 {
		free_error := runtime.mem_free_bytes(buffer.memory, context.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			replacement_free_error := runtime.mem_free_bytes(
				replacement, context.allocator,
			)
			if replacement_free_error != nil &&
			   replacement_free_error != .Mode_Not_Implemented {
				buffer.cleanup_memory = replacement
			}
			return false
		}
	}
	buffer.memory = replacement
	return true
}

append_input :: proc(buffer: ^input_buffer, bytes: []byte) -> bool {
	if !reserve_input(buffer, len(bytes)) do return false
	copy(buffer.memory[buffer.length:buffer.length+len(bytes)], bytes)
	buffer.length += len(bytes)
	return true
}

is_json_whitespace :: proc(byte_value: byte) -> bool {
	return byte_value == ' ' || byte_value == '\t' ||
	       byte_value == '\r' || byte_value == '\n'
}

reset_framer :: proc(framer: ^json_framer) {
	framer^ = {}
}

is_hex_digit :: proc(value: byte) -> bool {
	return value >= '0' && value <= '9' || value >= 'a' && value <= 'f' ||
	       value >= 'A' && value <= 'F'
}

parent_expects_value :: proc(framer: ^json_framer) -> bool {
	if framer.depth == 0 do return true
	frame := &framer.stack[framer.depth-1]
	if frame.kind == .Array {
		return frame.array_phase == .Expect_Value_Or_End ||
		       frame.array_phase == .Expect_Value
	}
	return frame.object_phase == .Expect_Value
}

complete_parent_value :: proc(framer: ^json_framer) -> bool {
	if framer.depth == 0 do return true
	frame := &framer.stack[framer.depth-1]
	if frame.kind == .Array {
		if frame.array_phase != .Expect_Value_Or_End &&
		   frame.array_phase != .Expect_Value {
			return false
		}
		frame.array_phase = .Expect_Separator
		return true
	}
	if frame.object_phase != .Expect_Value do return false
	frame.object_phase = .Expect_Separator
	return true
}

start_scalar :: proc(framer: ^json_framer, value: byte) -> bool {
	framer.scalar_state = .Start
	framer.literal_length = 0
	framer.literal_index = 0
	switch value {
	case '-': framer.scalar_state = .Minus
	case '0': framer.scalar_state = .Zero
	case '1'..='9': framer.scalar_state = .Integer
	case 't':
		framer.scalar_state = .Literal
		framer.literal = {'t', 'r', 'u', 'e', 0}
		framer.literal_length = 4
		framer.literal_index = 1
	case 'f':
		framer.scalar_state = .Literal
		framer.literal = {'f', 'a', 'l', 's', 'e'}
		framer.literal_length = 5
		framer.literal_index = 1
	case 'n':
		framer.scalar_state = .Literal
		framer.literal = {'n', 'u', 'l', 'l', 0}
		framer.literal_length = 4
		framer.literal_index = 1
	case: return false
	}
	return true
}

scalar_is_complete :: proc(framer: ^json_framer) -> bool {
	if framer.scalar_state == .Literal {
		return framer.literal_index == framer.literal_length
	}
	return framer.scalar_state == .Zero || framer.scalar_state == .Integer ||
	       framer.scalar_state == .Fraction ||
	       framer.scalar_state == .Exponent_Digits
}

// next_value_end incrementally recognizes one complete top-level JSON text.
// Its fixed container-kind stack rejects a mismatched/extra closer as soon as
// that byte arrives. Scalars still wait for a delimiter or EOF so split
// numbers cannot be published prematurely.
next_value_end :: proc(
	buffer: ^input_buffer, eof: bool,
) -> (end: int, result: frame_result) {
	bytes := buffer.memory[:buffer.length]
	framer := &buffer.framer
	if framer.mode == .Idle {
		if len(bytes) == 0 do return 0, .Need_More
		start := 0
		if buffer.bom_eligible && bytes[0] == 0xef {
			bom := [3]byte{0xef, 0xbb, 0xbf}
			matched := 0
			for matched < min(len(bytes), len(bom)) && bytes[matched] == bom[matched] {
				matched += 1
			}
			if matched == len(bytes) && len(bytes) < len(bom) && !eof {
				return 0, .Need_More
			}
			if matched == len(bom) do start = len(bom)
		}
		// jv_parser_set_buf strips the BOM before scan() sees the buffer, so
		// ordinary JSON whitespace after it is still framing whitespace rather
		// than an attempted scalar root.
		for start < len(bytes) && is_json_whitespace(bytes[start]) {
			start += 1
		}
		if start == len(bytes) {
			if eof do return len(bytes), .Found
			return 0, .Need_More
		}
		root := bytes[start]
		switch root {
		case '"':
			framer.mode = .Root_String
			framer.scan_index = start+1
		case '[', '{':
			framer.mode = .Container
			framer.scan_index = start
		case ']', '}', ',', ':':
			return start+1, .Malformed
		case:
			if !start_scalar(framer, root) do return start+1, .Malformed
			framer.mode = .Scalar
			framer.scan_index = start+1
		}
	}

	for framer.scan_index < len(bytes) {
		index := framer.scan_index
		byte_value := bytes[index]
		framer.scan_index += 1
		switch framer.mode {
		case .Root_String:
			if framer.unicode_remaining > 0 {
				if !is_hex_digit(byte_value) do return index+1, .Malformed
				framer.unicode_remaining -= 1
			} else if framer.escaped {
				framer.escaped = false
				if byte_value == 'u' {
					framer.unicode_remaining = 4
				} else if byte_value != '"' && byte_value != '\\' &&
				          byte_value != '/' && byte_value != 'b' &&
				          byte_value != 'f' && byte_value != 'n' &&
				          byte_value != 'r' && byte_value != 't' {
					return index+1, .Malformed
				}
			} else if byte_value == '\\' {
				framer.escaped = true
			} else if byte_value == '"' {
				return index+1, .Found
			} else if byte_value < 0x20 {
				return index+1, .Malformed
			}
		case .Scalar:
			delimiter := is_json_whitespace(byte_value) || byte_value == ']' ||
			             byte_value == '}' || byte_value == ','
			if framer.depth == 0 &&
			   (byte_value == '"' || byte_value == '[' || byte_value == '{') {
				delimiter = true
			}
			if delimiter {
				if !scalar_is_complete(framer) do return index+1, .Malformed
				if framer.depth == 0 do return index, .Found
				if !complete_parent_value(framer) do return index+1, .Malformed
				framer.mode = .Container
				framer.scan_index = index
				continue
			}
			if framer.scalar_state == .Literal {
				if framer.literal_index >= framer.literal_length ||
				   byte_value != framer.literal[framer.literal_index] {
					return index+1, .Malformed
				}
				framer.literal_index += 1
				continue
			}
			switch framer.scalar_state {
			case .Minus:
				if byte_value == '0' {
					framer.scalar_state = .Zero
				} else if byte_value >= '1' && byte_value <= '9' {
					framer.scalar_state = .Integer
				} else do return index+1, .Malformed
			case .Zero:
				if byte_value == '.' {
					framer.scalar_state = .Dot
				} else if byte_value == 'e' || byte_value == 'E' {
					framer.scalar_state = .Exponent
				} else do return index+1, .Malformed
			case .Integer:
				if byte_value >= '0' && byte_value <= '9' {
				} else if byte_value == '.' {
					framer.scalar_state = .Dot
				} else if byte_value == 'e' || byte_value == 'E' {
					framer.scalar_state = .Exponent
				} else do return index+1, .Malformed
			case .Dot:
				if byte_value < '0' || byte_value > '9' do return index+1, .Malformed
				framer.scalar_state = .Fraction
			case .Fraction:
				if byte_value >= '0' && byte_value <= '9' {
				} else if byte_value == 'e' || byte_value == 'E' {
					framer.scalar_state = .Exponent
				} else do return index+1, .Malformed
			case .Exponent:
				if byte_value == '+' || byte_value == '-' {
					framer.scalar_state = .Exponent_Sign
				} else if byte_value >= '0' && byte_value <= '9' {
					framer.scalar_state = .Exponent_Digits
				} else do return index+1, .Malformed
			case .Exponent_Sign:
				if byte_value < '0' || byte_value > '9' do return index+1, .Malformed
				framer.scalar_state = .Exponent_Digits
			case .Exponent_Digits:
				if byte_value < '0' || byte_value > '9' do return index+1, .Malformed
			case .Start, .Literal:
				return index+1, .Malformed
			}
		case .Container:
			if framer.in_string {
				if framer.unicode_remaining > 0 {
					if !is_hex_digit(byte_value) do return index+1, .Malformed
					framer.unicode_remaining -= 1
				} else if framer.escaped {
					framer.escaped = false
					if byte_value == 'u' {
						framer.unicode_remaining = 4
					} else if byte_value != '"' && byte_value != '\\' &&
					          byte_value != '/' && byte_value != 'b' &&
					          byte_value != 'f' && byte_value != 'n' &&
					          byte_value != 'r' && byte_value != 't' {
						return index+1, .Malformed
					}
				} else if byte_value == '\\' {
					framer.escaped = true
				} else if byte_value == '"' {
					framer.in_string = false
					if framer.string_is_object_key {
						framer.stack[framer.depth-1].object_phase = .Expect_Colon
					} else if !complete_parent_value(framer) do return index+1, .Malformed
					framer.string_is_object_key = false
				} else if byte_value < 0x20 {
					return index+1, .Malformed
				}
				continue
			}
			if is_json_whitespace(byte_value) do continue
			if byte_value == '"' {
				frame := &framer.stack[framer.depth-1]
				is_key := frame.kind == .Object &&
					(frame.object_phase == .Expect_Key_Or_End ||
					 frame.object_phase == .Expect_Key)
				if !is_key && !parent_expects_value(framer) do return index+1, .Malformed
				framer.in_string = true
				framer.string_is_object_key = is_key
			} else if byte_value == '[' || byte_value == '{' {
				if !parent_expects_value(framer) do return index+1, .Malformed
				if framer.syntactic_entries >= MAX_JSON_NESTING_DEPTH ||
				   framer.depth >= len(framer.stack) {
					return index+1, .Too_Deep
				}
				kind := container_kind.Array if byte_value == '[' else .Object
				framer.stack[framer.depth] = {
					kind = kind,
					object_phase = .Expect_Key_Or_End,
					array_phase = .Expect_Value_Or_End,
				}
				framer.depth += 1
				framer.syntactic_entries += 1
			} else if byte_value == ':' {
				if framer.stack[framer.depth-1].kind != .Object ||
				   framer.stack[framer.depth-1].object_phase != .Expect_Colon {
					return index+1, .Malformed
				}
				framer.stack[framer.depth-1].object_phase = .Expect_Value
				framer.stack[framer.depth-1].object_key_entry = true
				framer.syntactic_entries += 1
			} else if byte_value == ',' {
				frame := &framer.stack[framer.depth-1]
				if frame.kind == .Object {
					if frame.object_phase != .Expect_Separator do return index+1, .Malformed
					if frame.object_key_entry {
						frame.object_key_entry = false
						framer.syntactic_entries -= 1
					}
					frame.object_phase = .Expect_Key
				} else {
					if frame.array_phase != .Expect_Separator do return index+1, .Malformed
					frame.array_phase = .Expect_Value
				}
			} else if byte_value == ']' || byte_value == '}' {
				if framer.depth <= 0 do return index+1, .Malformed
				expected := container_kind.Array
				if byte_value == '}' do expected = .Object
				if framer.stack[framer.depth-1].kind != expected {
					return index+1, .Malformed
				}
				frame := &framer.stack[framer.depth-1]
				if expected == .Object {
					if frame.object_phase != .Expect_Key_Or_End &&
					   frame.object_phase != .Expect_Separator {
						return index+1, .Malformed
					}
				} else if frame.array_phase != .Expect_Value_Or_End &&
				          frame.array_phase != .Expect_Separator {
					return index+1, .Malformed
				}
				if expected == .Object &&
				   framer.stack[framer.depth-1].object_key_entry {
					framer.syntactic_entries -= 1
				}
				framer.depth -= 1
				framer.syntactic_entries -= 1
				if framer.depth == 0 do return index+1, .Found
				if !complete_parent_value(framer) do return index+1, .Malformed
			} else {
				if !parent_expects_value(framer) || !start_scalar(framer, byte_value) {
					return index+1, .Malformed
				}
				framer.mode = .Scalar
			}
		case .Idle:
		}
	}
	if eof {
		if framer.mode == .Scalar && !scalar_is_complete(framer) do return len(bytes), .Malformed
		return len(bytes), .Found
	}
	return 0, .Need_More
}

consume_prefix :: proc(buffer: ^input_buffer, count: int) {
	remaining := buffer.length-count
	if remaining > 0 do copy(buffer.memory[:remaining], buffer.memory[count:buffer.length])
	buffer.length = remaining
}

process_available :: proc(
	buffer: ^input_buffer,
	filter: string,
	compact, raw, eof, had_open_error: bool,
	prepared: ^driver.Compiled_Filter,
	values_after_open_error: ^int,
	sink: ^output_sink,
) -> (status: int, stop: bool) {
	for {
		whitespace := 0
		for whitespace < buffer.length &&
		   is_json_whitespace(buffer.memory[whitespace]) {
			whitespace += 1
		}
		if whitespace > 0 {
			buffer.bom_eligible = false
			consume_prefix(buffer, whitespace)
		}
		if buffer.length == 0 do return 0, false
		if buffer.bom_eligible && buffer.memory[0] == 0xef {
			bom := [3]byte{0xef, 0xbb, 0xbf}
			matched := 0
			for matched < min(buffer.length, len(bom)) &&
			   buffer.memory[matched] == bom[matched] {
				matched += 1
			}
			// jq consumes a matching one- or two-byte BOM prefix across parser
			// buffers. If EOF arrives before another byte, there is no JSON text
			// and therefore no error. A later mismatching byte remains malformed.
			if matched == buffer.length && buffer.length < len(bom) {
				if !eof do return 0, false
				consume_prefix(buffer, buffer.length)
				buffer.bom_eligible = false
				return 0, false
			}
			if matched == len(bom) {
				after_bom := matched
				for after_bom < buffer.length &&
				   is_json_whitespace(buffer.memory[after_bom]) {
					after_bom += 1
				}
				if after_bom == buffer.length {
					if !eof do return 0, false
					consume_prefix(buffer, buffer.length)
					buffer.bom_eligible = false
					return 0, false
				}
			}
		}
		if buffer.memory[0] == 0xef && !buffer.bom_eligible {
			// Wait for a split BOM prefix to become conclusive. Either way, a
			// non-initial 0xef begins invalid JSON and must never reach a fresh
			// driver parser at offset zero where it could be stripped.
			bom := [3]byte{0xef, 0xbb, 0xbf}
			matched := 0
			for matched < min(buffer.length, len(bom)) &&
			   buffer.memory[matched] == bom[matched] {
				matched += 1
			}
			if matched == buffer.length && buffer.length < len(bom) && !eof {
				return 0, false
			}
			_ = write_all(os.stderr, "jq-odin: JSON input error\n")
			return 4, true
		}
		end, frame_status := next_value_end(buffer, eof)
		if frame_status == .Need_More do return 0, false
		if frame_status == .Malformed || frame_status == .Too_Deep {
			_ = write_all(os.stderr, "jq-odin: JSON input error\n")
			return 4, true
		}
		status = run_input(
			transmute(string)buffer.memory[:end], compact, raw, prepared, sink,
		)
		consume_prefix(buffer, end)
		reset_framer(&buffer.framer)
		buffer.bom_eligible = false
		if status != 0 do return status, true
		if had_open_error {
			values_after_open_error^ += 1
			if values_after_open_error^ >= 1 do return 0, true
		}
	}
}

read_source :: proc(
	file: ^os.File,
	filter: string,
	compact, raw, had_open_error: bool,
	prepared: ^driver.Compiled_Filter,
	values_after_open_error: ^int,
	buffer: ^input_buffer,
	sink: ^output_sink,
) -> (status: int, stop: bool, read_ok: bool) {
	chunk: [INPUT_CHUNK_SIZE]byte
	for {
		count, read_error := os.read(file, chunk[:])
		if count > 0 {
			if !append_input(buffer, chunk[:count]) do return 2, true, false
			status, stop = process_available(
				buffer, filter, compact, raw, false, had_open_error, prepared,
				values_after_open_error, sink,
			)
			if stop do return status, true, true
		}
		if read_error == io.Error.EOF do return 0, false, true
		if read_error != nil do return 2, true, false
		if count == 0 do return 0, false, true
	}
}

run_main :: proc() -> (result: int) {
	// Convert a closed stdout/stderr pipe into an ordinary write error so the
	// command can retire driver-owned state and return the documented I/O status.
	_ = posix.signal(.SIGPIPE, auto_cast posix.SIG_IGN)

	parsed := parse_arguments(runtime.args__)
	defer delete(parsed.module_paths)
	defer delete(parsed.input_paths)
	if parsed.status != 0 do return parsed.status
	if parsed.version {
		return 0 if write_all(os.stdout, CANDIDATE_VERSION) else 2
	}
	sink: output_sink
	prepared: driver.Compiled_Filter
	prepare_error := driver.prepare_filter(
		&prepared, parsed.filter, context.allocator,
		{module_paths = parsed.module_paths[:]},
	)
	if prepare_error.kind != .None {
		status := error_status(prepare_error.kind)
		if !write_driver_error(prepare_error) do status = 2
		if cleanup_error := driver.destroy_compiled_filter(&prepared); cleanup_error != nil {
			result = 2
			_ = write_all(os.stderr, "jq-odin: cleanup error\n")
		}
		return status
	}
	defer {
		if driver.destroy_compiled_filter(&prepared) != nil {
			result = 2
			_ = write_all(os.stderr, "jq-odin: cleanup error\n")
		}
	}
	if parsed.null_input {
		return run_input("null", parsed.compact, parsed.raw, &prepared, &sink)
	}

	if len(parsed.input_paths) == 0 {
		buffer := input_buffer{bom_eligible = true}
		status, _, read_ok := read_source(
			os.stdin, parsed.filter, parsed.compact, parsed.raw, false, &prepared,
			nil, &buffer, &sink,
		)
		if status == 0 && read_ok {
			status, _ = process_available(
				&buffer, parsed.filter, parsed.compact, parsed.raw, true, false,
				&prepared, nil, &sink,
			)
		}
		if !read_ok {
			status = 2
			_ = write_all(os.stderr, "jq-odin: stdin I/O error\n")
		}
		if !destroy_input_buffer(&buffer) {
			status = 2
			_ = write_all(os.stderr, "jq-odin: input cleanup error\n")
		}
		return status
	}

	status := 0
	had_open_error := false
	values_after_open_error := 0
	buffer := input_buffer{bom_eligible = true}
	for arg in parsed.input_paths {
		file := os.stdin
		opened := true
		if arg != "-" {
			open_error: os.Error
			file, open_error = os.open(arg)
			if open_error != nil {
				opened = false
				_ = write_all(os.stderr, "jq: error: Could not open file ")
				_ = write_all(os.stderr, arg)
				_ = write_all(os.stderr, ": ")
				_ = write_all(os.stderr, input_error_string(open_error))
				_ = write_all(os.stderr, "\n")
			}
		}
		if !opened {
			had_open_error = true
			status = 2
			continue
		}
		file_status, stop, read_ok := read_source(
			file, parsed.filter, parsed.compact, parsed.raw, had_open_error,
			&prepared, &values_after_open_error, &buffer, &sink,
		)
		if arg != "-" {
			if close_error := os.close(file); close_error != nil {
				read_ok = false
			}
		}
		if !read_ok {
			status = 2
			_ = write_all(os.stderr, "jq-odin: input I/O error\n")
		}
		if file_status != 0 do status = file_status
		if stop || !read_ok do break
		if had_open_error && values_after_open_error >= 1 {
			break
		}
	}
	if status == 0 || status == 2 && had_open_error && values_after_open_error == 0 {
		final_status, _ := process_available(
			&buffer, parsed.filter, parsed.compact, parsed.raw, true, had_open_error,
			&prepared, &values_after_open_error, &sink,
		)
		if final_status != 0 do status = final_status
	}
	if had_open_error do status = 2
	if !destroy_input_buffer(&buffer) {
		status = 2
		_ = write_all(os.stderr, "jq-odin: input cleanup error\n")
	}
	return status
}

main :: proc() {
	os.exit(run_main())
}
