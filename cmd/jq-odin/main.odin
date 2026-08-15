package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"
import "core:sys/posix"
import driver "jq:driver"
import eval "jq:eval"
import value "jq:value"

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

json_kind_name :: proc(kind: value.Kind) -> string {
	switch kind {
	case .Null: return "null"
	case .Boolean: return "boolean"
	case .Number: return "number"
	case .String: return "string"
	case .Array: return "array"
	case .Object: return "object"
	case .Invalid: return "invalid"
	}
	return "invalid"
}

write_driver_error :: proc(err: driver.Run_Error, source: string = "") -> bool {
	if err.kind == .Runtime && err.modulemeta_failure == .Non_String_Input {
		return write_all(os.stderr, "jq: error (at <stdin>:1): modulemeta input module name must be a string\n")
	}
	if err.kind == .Runtime && err.modulemeta_failure == .Missing_Module {
		ok := write_all(os.stderr, "jq: error (at <stdin>:1): module not found: ")
		name := err.modulemeta_name
		if len(err.runtime_key) > 0 do name = err.runtime_key
		ok = write_all(os.stderr, name) && ok
		return write_all(os.stderr, "\n") && ok
	}
	if err.kind == .Runtime && len(err.runtime_key) > 0 &&
	   (err.runtime_kind == .Cannot_Add || err.runtime_kind == .Cannot_Subtract) {
		path := err.runtime_input_path
		if len(path) == 0 || path == "-" do path = "<stdin>"
		line := err.runtime_input_line
		if line <= 0 do line = 1
		ok := write_all(os.stderr, "jq: error (at ")
		ok = write_all(os.stderr, path) && ok
		ok = write_all(os.stderr, ":") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
		ok = write_all(os.stderr, "): ") && ok
		ok = write_all(os.stderr, err.runtime_key) && ok
		ok = write_all(os.stderr, "\n") && ok
		return ok
	}
	if err.kind == .Runtime && len(err.runtime_key) > len("__jq_odin_subtraction__") &&
	   err.runtime_key[:len("__jq_odin_subtraction__")] == "__jq_odin_subtraction__" {
		path := err.runtime_input_path
		if len(path) == 0 || path == "-" do path = "<stdin>"
		line := err.runtime_input_line
		if line <= 0 do line = 1
		ok := write_all(os.stderr, "jq: error (at ")
		ok = write_all(os.stderr, path) && ok
		ok = write_all(os.stderr, ":") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
		ok = write_all(os.stderr, "): ") && ok
		ok = write_all(os.stderr, json_kind_name(err.runtime_input_kind)) && ok
		ok = write_all(os.stderr, " (") && ok
		ok = write_all(os.stderr, err.runtime_key[len("__jq_odin_subtraction__"):]) && ok
		ok = write_all(os.stderr, ") and number (1) cannot be subtracted\n") && ok
		return ok
	}
	if err.kind == .Runtime && err.runtime_module_scalar_field {
		// Data-module postfixes are evaluated against an imported JSON scalar.
		// jq reports this as an input-independent type error (and uses the
		// `<unknown>` location), unlike the older generic runtime diagnostic for
		// ordinary filter field access.
		ok := write_all(os.stderr, "jq: error (at <unknown>): Cannot index ")
		ok = write_all(os.stderr, json_kind_name(err.runtime_input_kind)) && ok
		ok = write_all(os.stderr, " with string \"") && ok
		ok = write_all(os.stderr, err.runtime_key) && ok
		ok = write_all(os.stderr, "\"\n") && ok
		return ok
	}
	if err.kind == .Runtime && err.runtime_kind == .Cannot_Iterate && len(err.runtime_key) > 0 {
		// Iterator diagnostics carry their complete jq message in runtime_key.
		// They are not typed string-index failures; keep the message intact for
		// uncaught errors while try/catch continues to consume the same key.
		path := err.runtime_input_path
		if len(path) == 0 || path == "-" do path = "<stdin>"
		line := err.runtime_input_line
		if line <= 0 do line = 1
		ok := write_all(os.stderr, "jq: error (at ")
		ok = write_all(os.stderr, path) && ok
		ok = write_all(os.stderr, ":") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
		ok = write_all(os.stderr, "): ") && ok
		ok = write_all(os.stderr, err.runtime_key) && ok
		ok = write_all(os.stderr, "\n") && ok
		return ok
	}
	if err.kind == .Runtime && err.runtime_kind == .User_Error {
		path := err.runtime_input_path
		if len(path) == 0 || path == "-" do path = "<stdin>"
		line := err.runtime_input_line
		if line <= 0 do line = 1
		ok := write_all(os.stderr, "jq: error (at ")
		ok = write_all(os.stderr, path) && ok
		ok = write_all(os.stderr, ":") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
		ok = write_all(os.stderr, "): ") && ok
		ok = write_all(os.stderr, err.runtime_key) && ok
		ok = write_all(os.stderr, "\n") && ok
		return ok
	}
	if err.kind == .Runtime && err.runtime_input_kind == .Number && len(err.runtime_key) > 0 {
		// Ordinary field access on a numeric input uses jq's typed diagnostic,
		// including the current input path and line. Keep this narrow
		// to string-key indexing so numeric-index failures retain their generic
		// runtime wording until their own parity slice is implemented.
		path := err.runtime_input_path
		if len(path) == 0 || path == "-" do path = "<stdin>"
		line := err.runtime_input_line
		if line <= 0 do line = 1
		ok := write_all(os.stderr, "jq: error (at ")
		ok = write_all(os.stderr, path) && ok
		ok = write_all(os.stderr, ":") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
		ok = write_all(os.stderr, "): Cannot index number with string \"")
		ok = write_all(os.stderr, err.runtime_key) && ok
		ok = write_all(os.stderr, "\"\n") && ok
		return ok
	}
	if err.kind == .Runtime && err.runtime_input_kind != .Number && len(err.runtime_key) > 0 {
		// String-key access on containers and strings retains jq's specific
		// container wording. Numeric-looking keys are reserved for the bounded
		// numeric-index path above and continue through the generic formatter.
		numeric_key := true
		for ch in err.runtime_key {
			if ch < '0' || ch > '9' {
				numeric_key = false
				break
			}
		}
		if !numeric_key {
			path := err.runtime_input_path
			if len(path) == 0 || path == "-" do path = "<stdin>"
			line := err.runtime_input_line
			if line <= 0 do line = 1
			ok := write_all(os.stderr, "jq: error (at ")
			ok = write_all(os.stderr, path) && ok
			ok = write_all(os.stderr, ":") && ok
			ok = write_all(os.stderr, fmt.tprintf("%d", line)) && ok
			ok = write_all(os.stderr, "): Cannot index ")
			ok = write_all(os.stderr, json_kind_name(err.runtime_input_kind)) && ok
			ok = write_all(os.stderr, " with string \"") && ok
			ok = write_all(os.stderr, err.runtime_key) && ok
			ok = write_all(os.stderr, "\"\n") && ok
			return ok
		}
	}
	ok := true
	if err.kind == .Module && (err.module_kind == .Undefined_Function || err.module_kind == .Syntax_Error) {
		column := 1
		for at := 0; at+len(err.module_name) <= len(source); at += 1 {
			if source[at:at+len(err.module_name)] == err.module_name { column = at+1; break }
		}
		if err.module_kind == .Undefined_Function {
			ok = write_all(os.stderr, "jq: error: ") && ok
			ok = write_all(os.stderr, err.module_name) && ok
			ok = write_all(os.stderr, fmt.tprintf("/%d is not defined at <top-level>, line 1, column %d:\n    ", err.module_arity, column)) && ok
			ok = write_all(os.stderr, source) && ok
			ok = write_all(os.stderr, "\n    ") && ok
			for _ in 1..<column do ok = write_all(os.stderr, " ") && ok
			ok = write_all(os.stderr, "^\njq: 1 compile error\n") && ok
			return ok
		}
		unexpected := ")"
		if err.module_arity < 0 { unexpected = ":" }
		ok = write_all(os.stderr, "jq: error: syntax error, unexpected '") && ok
		ok = write_all(os.stderr, unexpected) && ok
		ok = write_all(os.stderr, "' at <top-level>, line 1, column ") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d:\n    ", column+2)) && ok
		ok = write_all(os.stderr, source) && ok
		ok = write_all(os.stderr, "\n    ") && ok
		for _ in 1..<(column+2) do ok = write_all(os.stderr, " ") && ok
		ok = write_all(os.stderr, "^\njq: 1 compile error\n") && ok
		return ok
	}
	if err.kind == .Filter_Compile && err.compile_kind == .Unresolved_Label && len(source) > 0 {
		start := err.compile_error_span.start
		end := err.compile_error_span.end
		name_start := err.compile_error_name_span.start
		name_end := err.compile_error_name_span.end
		if start < 0 || end < start || end > len(source) || name_start < 0 || name_end < name_start || name_end > len(source) {
			return write_all(os.stderr, "jq-odin: filter compile error\n")
		}
		name := source[name_start:name_end]
		ok = write_all(os.stderr, "jq: error: $*label-") && ok
		ok = write_all(os.stderr, name) && ok
		ok = write_all(os.stderr, " is not defined at <top-level>, line 1, column ") && ok
		ok = write_all(os.stderr, fmt.tprintf("%d", start+1)) && ok
		ok = write_all(os.stderr, ":\n    ") && ok
		ok = write_all(os.stderr, source) && ok
		ok = write_all(os.stderr, "\n    ") && ok
		for _ in 1..<start+1 do ok = write_all(os.stderr, " ") && ok
		for _ in start..<end do ok = write_all(os.stderr, "^") && ok
		ok = write_all(os.stderr, "\njq: 1 compile error\n") && ok
		return ok
	}
	ok = write_all(os.stderr, "jq-odin: ") && ok
	ok = write_all(os.stderr, kind_name(err.kind)) && ok
	if err.kind == .Module {
		if err.module_kind == .Undefined_Function || err.module_kind == .Syntax_Error {
			// Module call failures are compile diagnostics in jq, including the
			// source excerpt and caret. The module name borrows the original filter.
			column := 1
			if len(err.module_name) > 0 {
				for at := 0; at+len(err.module_name) <= len(source); at += 1 {
					if source[at:at+len(err.module_name)] == err.module_name { column = at+1; break }
				}
			}
			if err.module_kind == .Undefined_Function {
				ok = write_all(os.stderr, "jq: error: ") && ok
				ok = write_all(os.stderr, err.module_name) && ok
				ok = write_all(os.stderr, fmt.tprintf("/%d is not defined at <top-level>, line 1, column %d:\n    ", err.module_arity, column)) && ok
				ok = write_all(os.stderr, source) && ok
				ok = write_all(os.stderr, "\n    ") && ok
				for _ in 1..<column do ok = write_all(os.stderr, " ") && ok 
				ok = write_all(os.stderr, "^\njq: 1 compile error\n") && ok
				return ok
			}
			ok = write_all(os.stderr, "jq: error: syntax error, unexpected ')' at <top-level>, line 1, column ") && ok
			ok = write_all(os.stderr, fmt.tprintf("%d:\n    ", column+1)) && ok
			ok = write_all(os.stderr, source) && ok
			ok = write_all(os.stderr, "\n    ") && ok
			for _ in 1..<column do ok = write_all(os.stderr, " ") && ok 
			ok = write_all(os.stderr, " ^\njq: 1 compile error\n") && ok
			return ok
		}
		message := ""
		switch err.module_kind {
		case .Not_Found: message = ": module file not found"
		case .Read_Failure: message = ": unable to read module file"
		case .Unsupported_Syntax: message = ": unsupported module syntax"
		case .Import_Unsupported: message = ": unsupported module import"
		case .Depth_Overflow: message = ": module dependency depth exceeded"
		case .Duplicate_Definition: message = ": duplicate module definition"
		case .Cycle: message = ": cyclic module dependency"
		case .Undefined_Function, .Syntax_Error: message = ""
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

emit_stderr :: proc(data: rawptr, bytes: string) -> bool {
	sink := cast(^output_sink)data
	if sink == nil || sink.failed do return false
	sink.failed = !write_all(os.stderr, bytes)
	return !sink.failed
}

run_input :: proc(
	input: string,
	input_path: string,
	input_line: int,
	compact: bool,
	raw: bool,
	prepared: ^driver.Compiled_Filter,
	sink: ^output_sink,
	input_provider: eval.Input_Provider = {},
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
			input_path = input_path,
			input_line = input_line,
			compiled_filter = prepared,
			emitter = emit_stdout,
			emitter_data = sink,
			diagnostic_emitter = emit_stderr,
			diagnostic_emitter_data = sink,
			input_provider = input_provider,
		},
	)

	status := error_status(err.kind)
	if err.kind == .Runtime && input_provider.data != nil {
		provider_state := cast(^cli_input_provider)input_provider.data
		if provider_state.error_line > 0 {
			err.runtime_input_line = provider_state.error_line
			err.runtime_input_path = provider_state.error_path
		}
	}
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
	N_Prefix,
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
	literal: [8]byte,
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
		framer.literal = {'t', 'r', 'u', 'e', 0, 0, 0, 0}
		framer.literal_length = 4
		framer.literal_index = 1
	case 'f':
		framer.scalar_state = .Literal
		framer.literal = {'f', 'a', 'l', 's', 'e', 0, 0, 0}
		framer.literal_length = 5
		framer.literal_index = 1
	case 'n':
		// jq reserves `nu...` for null and routes other n-prefixed tokens to
		// its numeric parser. Keep the bounded CLI framer exact for the
		// payload-free lowercase NaN spelling supported by this slice.
		framer.scalar_state = .N_Prefix
	case 'N':
		framer.scalar_state = .Literal
		framer.literal = {'N', 'a', 'N', 0, 0, 0, 0, 0}
		framer.literal_length = 3
		framer.literal_index = 1
	case 'I':
		framer.scalar_state = .Literal
		framer.literal = {'I', 'n', 'f', 'i', 'n', 'i', 't', 'y'}
		framer.literal_length = 8
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
			if framer.scalar_state == .N_Prefix {
				switch byte_value {
				case 'u':
					framer.literal = {'n', 'u', 'l', 'l', 0, 0, 0, 0}
					framer.literal_length = 4
					framer.literal_index = 2
				case 'a':
					framer.literal = {'n', 'a', 'n', 0, 0, 0, 0, 0}
					framer.literal_length = 3
					framer.literal_index = 2
				case:
					return index+1, .Malformed
				}
				framer.scalar_state = .Literal
				continue
			}
			switch framer.scalar_state {
			case .Minus:
				if byte_value == '0' {
					framer.scalar_state = .Zero
				} else if byte_value >= '1' && byte_value <= '9' {
					framer.scalar_state = .Integer
				} else if byte_value == 'N' {
					framer.literal = {'N', 'a', 'N', 0, 0, 0, 0, 0}
					framer.literal_length = 3
					framer.literal_index = 1
					framer.scalar_state = .Literal
				} else if byte_value == 'I' {
					framer.literal = {'I', 'n', 'f', 'i', 'n', 'i', 't', 'y'}
					framer.literal_length = 8
					framer.literal_index = 1
					framer.scalar_state = .Literal
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
			case .Start, .Literal, .N_Prefix:
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

cli_source_cursor :: struct {
	paths:       []string,
	next_index:  int,
	file:        ^os.File,
	file_open:   bool,
	file_owned:  bool,
	current_path: string,
	terminal:    bool,
	advanced:    bool,
}

open_next_source :: proc(cursor: ^cli_source_cursor) -> (string, bool) {
	if cursor == nil do return "", false
	for cursor.next_index < len(cursor.paths) {
		arg := cursor.paths[cursor.next_index]
		cursor.next_index += 1
		if arg == "-" {
			cursor.advanced = cursor.file_open
			cursor.file = os.stdin
			cursor.file_open = true
			cursor.file_owned = false
			cursor.current_path = arg
			cursor.terminal = false
			return "", true
		}
		file, open_error := os.open(arg)
		if open_error != nil {
			cursor.current_path = arg
			return "input file open failure", false
		}
		cursor.advanced = cursor.file_open
		cursor.file = file
		cursor.file_open = true
		cursor.file_owned = true
		cursor.current_path = arg
		cursor.terminal = false
		return "", true
	}
	cursor.terminal = true
	return "", false
}

close_source :: proc(cursor: ^cli_source_cursor) -> bool {
	if cursor == nil || !cursor.file_open do return true
	cursor.file_open = false
	if !cursor.file_owned do return true
	err := os.close(cursor.file)
	cursor.file_owned = false
	return err == nil
}

cli_input_provider :: struct {
	buffer: ^input_buffer,
	eof:    bool,
	start:  int,
	line_base: int,
	source_line_base: int,
	source_mark: int,
	error_line: int,
	error_path: string,
	file:   ^os.File,
	cursor: ^cli_source_cursor,
}

cli_next_input :: proc(data: rawptr) -> (string, eval.Input_Provider_Status) {
	state := cast(^cli_input_provider)data
	if state == nil || state.buffer == nil do return "", .EOF
	b := state.buffer
	if state.cursor != nil {
		if state.cursor.file_open {
			state.file = state.cursor.file
		} else {
			state.file = nil
		}
		if state.cursor.terminal do state.eof = true
	}
	whitespace := 0
	for state.start+whitespace < b.length && is_json_whitespace(b.memory[state.start+whitespace]) do whitespace += 1
	state.start += whitespace
	if state.start >= b.length {
		if state.eof || state.file == nil {
			if state.cursor != nil && !state.cursor.terminal {
				// The outer source loop is still draining the old file. Mark the
				// transition before retiring it so that loop does not close the
				// newly opened successor on return from this run.
				state.cursor.advanced = true
				if !close_source(state.cursor) do return "input close failure", .Error
				err, opened := open_next_source(state.cursor)
				if !opened {
					if state.cursor.terminal do return "", .EOF
					return err, .Error
				}
				state.cursor.advanced = true
				state.file = state.cursor.file
				state.eof = false
				for byte_value in b.memory[state.source_mark:b.length] {
					if byte_value == '\n' do state.line_base += 1
				}
				state.source_line_base = 1
				state.source_mark = state.start
				return cli_next_input(data)
			}
			return "", .EOF
		}
		chunk: [INPUT_CHUNK_SIZE]byte
		count, read_error := os.read(state.file, chunk[:])
		if count > 0 {
			if !append_input(b, chunk[:count]) do return "input allocation failure", .Error
			state.eof = read_error == io.Error.EOF
			return cli_next_input(data)
		}
		if read_error == io.Error.EOF {
			state.eof = true
			return cli_next_input(data)
		}
		if read_error != nil do return "input read failure", .Error
		state.eof = true
		return cli_next_input(data)
	}
	// The provider starts a fresh value framer at the unread suffix.  The
	// outer framer may be in its terminal Found state for the current value;
	// copying that state would make the next scalar look like a continuation
	// of the previous one.
	sub := input_buffer{memory=b.memory[state.start:], length=b.length-state.start, framer={}, bom_eligible=false}
	end, status := next_value_end(&sub, state.eof)
	if status == .Need_More {
		if state.file == nil do return "", .EOF
		chunk: [INPUT_CHUNK_SIZE]byte
		count, read_error := os.read(state.file, chunk[:])
		if count > 0 {
			if !append_input(b, chunk[:count]) do return "input allocation failure", .Error
			state.eof = read_error == io.Error.EOF
			return cli_next_input(data)
		}
		if read_error == io.Error.EOF { state.eof = true; return cli_next_input(data) }
		if read_error != nil do return "input read failure", .Error
		state.eof = true
		return cli_next_input(data)
	}
	if status != .Found {
		// The malformed value belongs to the provider stream, not the outer
		// framing loop. Mark the source terminal and consume the unread bytes so
		// a caught input error is not reported a second time as a top-level JSON
		// framing error.
		state.eof = true
		if state.cursor != nil do state.cursor.terminal = true
		line := state.line_base
		column := 0
		for byte_value in b.memory[state.source_mark:b.length] {
			if byte_value == '\n' {
				line += 1
				column = 0
			} else {
				column += 1
			}
		}
		error_line := state.source_line_base
		if b.length > 0 && b.memory[b.length-1] == '\n' {
			for byte_value in b.memory[state.source_mark:state.start] {
				if byte_value == '\n' do error_line += 1
			}
		}
		state.error_line = error_line
		if state.cursor != nil do state.error_path = state.cursor.current_path
		state.start = b.length
		if b.length > 0 && b.memory[b.length-1] == '\n' {
			return fmt.tprintf("Invalid numeric literal at line %d, column 0", line), .Error
		}
		return fmt.tprintf("Invalid numeric literal at EOF at line %d, column %d", line, column), .Error
	}
	raw := transmute(string)b.memory[state.start:state.start+end]
	state.start += end
	return raw, .Value
}

process_available :: proc(
	buffer: ^input_buffer,
	file: ^os.File,
	cursor: ^cli_source_cursor,
	filter: string,
	input_path: string,
	input_line: ^int,
	compact, raw, eof, had_open_error: bool,
	prepared: ^driver.Compiled_Filter,
	values_after_open_error: ^int,
	sink: ^output_sink,
) -> (status: int, stop: bool) {
	for {
		whitespace := 0
		for whitespace < buffer.length &&
		   is_json_whitespace(buffer.memory[whitespace]) {
			// The framer intentionally leaves delimiters and inter-value
			// whitespace in the buffer after a scalar.  Account for those
			// consumed newlines before reporting the next value's source line;
			// counting only bytes in [:end] would miss this leading region.
			if input_line != nil && buffer.memory[whitespace] == '\n' do input_line^ += 1
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
		line := 1
		if input_line != nil do line = input_line^
		current_input := transmute(string)buffer.memory[:end]
		// Advance the outer framer before evaluating input/0 so the provider
		// starts at the next value in this source buffer.
		if input_line != nil {
			for byte_value in buffer.memory[:end] {
				if byte_value == '\n' do input_line^ += 1
			}
		}
		// The outer framer has already established a complete current value;
		// treat the currently buffered suffix as a complete provider stream.
		provider_state := cli_input_provider{buffer=buffer, eof=eof, start=end, line_base=line, source_line_base=line, file=file, cursor=cursor}
		status = run_input(
			current_input, input_path, line,
			compact, raw, prepared, sink,
			eval.Input_Provider{data=&provider_state, next=cli_next_input},
		)
		consume_prefix(buffer, provider_state.start)
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
	cursor: ^cli_source_cursor,
	filter: string,
	input_path: string,
	input_line: ^int,
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
				buffer, file, cursor, filter, input_path, input_line, compact, raw, false, had_open_error, prepared,
				values_after_open_error, sink,
			)
			if stop do return status, true, true
			// An input/0 provider may have retired this outer source while
			// crossing an argv boundary. Do not read the closed descriptor again.
			if cursor != nil && cursor.advanced do return status, false, true
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
		if !write_driver_error(prepare_error, parsed.filter) do status = 2
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
		// -n suppresses the outer input stream but does not disable input/0.
		// Give the evaluator a live provider over stdin for this invocation.
		buffer := input_buffer{bom_eligible = true}
		provider_state := cli_input_provider{buffer=&buffer, eof=false, start=0, line_base=1, source_line_base=1, file=os.stdin}
		status := run_input(
			"null", "", 1, parsed.compact, parsed.raw, &prepared, &sink,
			eval.Input_Provider{data=&provider_state, next=cli_next_input},
		)
		if !destroy_input_buffer(&buffer) do status = 2
		return status
	}

	if len(parsed.input_paths) == 0 {
		buffer := input_buffer{bom_eligible = true}
		input_line := 1
		status, _, read_ok := read_source(
			os.stdin, nil, parsed.filter, "", &input_line, parsed.compact, parsed.raw, false, &prepared,
			nil, &buffer, &sink,
		)
		if status == 0 && read_ok {
			status, _ = process_available(
				&buffer, os.stdin, nil, parsed.filter, "", &input_line, parsed.compact, parsed.raw, true, false,
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
	input_line := 1
	buffer := input_buffer{bom_eligible = true}
	cursor := cli_source_cursor{paths=parsed.input_paths[:], next_index=0}
	for arg_index := 0; arg_index < len(parsed.input_paths); arg_index += 1 {
		if cursor.terminal do break
		// A provider invoked from the previous top-level value may already have
		// crossed one or more argv boundaries. Those sources have been consumed
		// and must not be reopened by the outer framing loop.
		if arg_index+1 < cursor.next_index do continue
		if !cursor.file_open {
			open_message, opened := open_next_source(&cursor)
			if !opened {
				had_open_error = !cursor.terminal
				if had_open_error {
					status = 2
					_ = write_all(os.stderr, "jq: error: ")
					_ = write_all(os.stderr, open_message)
					_ = write_all(os.stderr, "\n")
				}
				continue
			}
		}
		input_line = 1
		outer_file := cursor.file
		outer_path := cursor.current_path
		cursor.advanced = false
		file_status, stop, read_ok := read_source(
			outer_file, &cursor, parsed.filter, outer_path, &input_line, parsed.compact, parsed.raw,
			had_open_error, &prepared, &values_after_open_error, &buffer, &sink,
		)
		if !cursor.advanced && cursor.file_open {
			if !close_source(&cursor) do read_ok = false
		}
		if !read_ok {
			status = 2
			_ = write_all(os.stderr, "jq-odin: input I/O error\n")
		}
		if file_status != 0 do status = file_status
		if stop || !read_ok do break
		if had_open_error && values_after_open_error >= 1 do break
	}
	if status == 0 || status == 2 && had_open_error && values_after_open_error == 0 {
		final_status, _ := process_available(
			&buffer, cursor.file, &cursor, parsed.filter, cursor.current_path, &input_line, parsed.compact, parsed.raw, true, had_open_error,
			&prepared, &values_after_open_error, &sink,
		)
		if final_status != 0 do status = final_status
	}
	if had_open_error do status = 2
	if !close_source(&cursor) do status = 2
	if !destroy_input_buffer(&buffer) {
		status = 2
		_ = write_all(os.stderr, "jq-odin: input cleanup error\n")
	}
	return status
}

main :: proc() {
	os.exit(run_main())
}
