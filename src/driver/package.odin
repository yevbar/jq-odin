// Package driver joins one complete filter and one stream of JSON inputs.
package driver

import "base:runtime"
import compiler "jq:compiler"
import diagnostic "jq:diagnostic"
import eval "jq:eval"
import json "jq:json"
import program "jq:program"
import syntax "jq:syntax"
import value "jq:value"

Run_Error_Kind :: enum u8 {
	None,
	Filter_Parse,
	Filter_Compile,
	Module,
	JSON_Input,
	Runtime,
	Serialization,
	Output,
	Allocation,
	Cleanup,
	Misuse,
}

Output_Mode :: enum u8 {
	Pretty,
	Compact,
}

// Output_Emitter synchronously borrows one complete LF-terminated result.
// Returning true proves the bytes were consumed before the call returned; the
// driver may then reuse the same storage for the next result. Returning false
// stops evaluation with Output while retaining the current bytes for cleanup.
Output_Emitter :: proc(data: rawptr, bytes: string) -> bool

Run_Options :: struct {
	output_mode: Output_Mode,
	// module_paths borrows the ordered jq -L search paths for this execution.
	// Module loading consumes this ordered, borrowed context for this execution.
	module_paths: []string,
	// max_inputs bounds successful stream values when non-zero for embedding
	// callers that intentionally request a prefix of a borrowed input stream.
	max_inputs: int,
	emitter: Output_Emitter,
	emitter_data: rawptr,
}

// Run_Error is non-owning. runtime_key borrows Run_Result storage and remains
// valid until destroy_run_result succeeds.
Run_Error :: struct {
	kind:                 Run_Error_Kind,
	filter_parse_kind:    syntax.Parse_Error_Kind,
	filter_expected:      syntax.Parse_Expectation,
	filter_actual:        syntax.Token_Kind,
	filter_has_actual:    bool,
	filter_start:         int,
	filter_end:           int,
	compile_kind:         compiler.Lower_Error_Kind,
	module_kind:          Module_Error_Kind,
	json_kind:            json.Scalar_Parse_Error_Kind,
	json_offset:          int,
	runtime_kind:         eval.Runtime_Error_Kind,
	runtime_input_kind:   value.Kind,
	runtime_span:         program.Source_Span,
	runtime_key:          string,
	serialization_kind:  json.Compact_Error_Kind,
	resource_error:       runtime.Allocator_Error,
}

@(private)
result_state :: enum u8 {
	Invalid,
	Running,
	Ready,
	Cleanup_Only,
}

// Run_Result is an address-bound owner. The filter and JSON arguments to run
// are borrowed only for the call. Output and runtime diagnostic bytes are
// owned with allocator until destroy_run_result succeeds.
Run_Result :: struct {
	self:              ^Run_Result,
	state:             result_state,
	allocator:         runtime.Allocator,
	error:             Run_Error,
	output_memory:     []byte,
	filter_memory:     []byte,
	output_length:     int,
	cleanup_memory:    []byte,
	runtime_key_memory: []byte,
	parser:            syntax.Parser,
	compiled:          program.Program,
	input:             value.Value,
	// evaluator points into evaluator_memory. The exact typed allocation never
	// moves; it is retired only after destroy_evaluator has succeeded.
	evaluator:         ^eval.Evaluator,
	evaluator_memory:  []byte,
	serializer:        json.Compact_Serializer,
	serialized:        json.Compact_Result,
	current_output:    value.Value,
	json_error:        json.Scalar_Parse_Error,
}

// evaluator_allocation_layout reports the exact allocation contract used by
// run. It exists so allocator probes can verify both values independently of
// the allocation they observe.
evaluator_allocation_layout :: proc() -> (size, alignment: int) {
	return size_of(eval.Evaluator), align_of(eval.Evaluator)
}

run_result_bytes :: proc(result: ^Run_Result) -> (string, bool) {
	if result == nil || result.self != result ||
	   !(result.state == .Ready || result.state == .Cleanup_Only) ||
	   result.output_length < 0 || result.output_length > len(result.output_memory) {
		return "", false
	}
	if result.output_length == 0 do return "", true
	return transmute(string)result.output_memory[:result.output_length], true
}

run_result_error :: proc(result: ^Run_Result) -> (Run_Error, bool) {
	if result == nil || result.self != result ||
	   !(result.state == .Ready || result.state == .Cleanup_Only) {
		return {}, false
	}
	return result.error, true
}

@(private)
record_cleanup_error :: proc(result: ^Run_Result, err: runtime.Allocator_Error) {
	result.error = {kind = .Cleanup, resource_error = err}
	result.state = .Cleanup_Only
}

@(private)
cleanup_execution :: proc(result: ^Run_Result) -> runtime.Allocator_Error {
	if err := cleanup_input(result); err != nil do return err
	if err := json.destroy_compact_serializer(&result.serializer); err != nil do return err
	if err := program.destroy_program(&result.compiled); err != nil do return err
	if err := syntax.destroy_parser(&result.parser); err != nil do return err
	if err := free_owned(&result.filter_memory, result.allocator); err != nil do return err
	return nil
}

@(private)
cleanup_input :: proc(result: ^Run_Result) -> runtime.Allocator_Error {
	if err := json.destroy_compact_result(&result.serialized); err != nil do return err
	if err := value.destroy_value(&result.current_output); err != nil do return err
	if result.evaluator != nil {
		if err := eval.destroy_evaluator(result.evaluator); err != nil do return err
		if len(result.evaluator_memory) == 0 do return .Invalid_Pointer
		err := runtime.mem_free_bytes(result.evaluator_memory, result.allocator)
		if err != nil && err != .Mode_Not_Implemented do return err
		result.evaluator = nil
		result.evaluator_memory = nil
	} else if len(result.evaluator_memory) != 0 {
		return .Invalid_Pointer
	}
	if err := value.destroy_value(&result.input); err != nil do return err
	if err := json.destroy_scalar_parse_error(&result.json_error); err != nil do return err
	return nil
}

@(private)
allocate_evaluator :: proc(result: ^Run_Result) -> runtime.Allocator_Error {
	size, alignment := evaluator_allocation_layout()
	memory, err := runtime.mem_alloc_bytes(size, alignment, result.allocator)
	if err != nil || len(memory) != size {
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, result.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				result.cleanup_memory = memory
				return free_error
			}
		}
		return err if err != nil else .Out_Of_Memory
	}
	if uintptr(raw_data(memory))%uintptr(alignment) != 0 {
		free_error := runtime.mem_free_bytes(memory, result.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			result.cleanup_memory = memory
			return free_error
		}
		return .Invalid_Pointer
	}
	result.evaluator_memory = memory
	result.evaluator = cast(^eval.Evaluator)raw_data(memory)
	result.evaluator^ = nil
	return nil
}

@(private)
free_owned :: proc(memory: ^[]byte, allocator: runtime.Allocator) -> runtime.Allocator_Error {
	if len(memory^) == 0 do return nil
	err := runtime.mem_free_bytes(memory^, allocator)
	if err == nil || err == .Mode_Not_Implemented {
		memory^ = nil
		return nil
	}
	return err
}

// Destruction resumes reverse-order cleanup. Success is idempotent.
destroy_run_result :: proc(result: ^Run_Result) -> runtime.Allocator_Error {
	if result == nil || result.state == .Invalid && result.self == nil do return nil
	if result.self != result do return .Invalid_Pointer
	if err := cleanup_execution(result); err != nil {
		record_cleanup_error(result, err)
		return err
	}
	if err := free_owned(&result.runtime_key_memory, result.allocator); err != nil {
		record_cleanup_error(result, err)
		return err
	}
	if err := free_owned(&result.cleanup_memory, result.allocator); err != nil {
		record_cleanup_error(result, err)
		return err
	}
	if err := free_owned(&result.output_memory, result.allocator); err != nil {
		record_cleanup_error(result, err)
		return err
	}
	result^ = {}
	return nil
}

@(private)
finish :: proc(result: ^Run_Result, err: Run_Error) -> Run_Error {
	result.error = err
	if cleanup_error := cleanup_execution(result); cleanup_error != nil {
		record_cleanup_error(result, cleanup_error)
		return result.error
	}
	result.state = .Ready
	return result.error
}

@(private)
allocation_error :: proc(result: ^Run_Result, err: runtime.Allocator_Error) -> Run_Error {
	return finish(result, {
		kind = .Allocation,
		resource_error = err if err != nil else .Out_Of_Memory,
	})
}

// A failed allocation can leave a replacement buffer retained for cleanup. In
// that case the allocator error describes cleanup ownership, not an OOM. Keep
// this decision at the driver boundary so serializer and output-buffer paths
// report the same public error kind.
allocation_or_cleanup_error :: proc(
	result: ^Run_Result,
	err: runtime.Allocator_Error,
) -> Run_Error {
	if len(result.cleanup_memory) > 0 {
		return finish(result, {kind = .Cleanup, resource_error = err})
	}
	return allocation_error(result, err)
}

@(private)
reserve_output :: proc(result: ^Run_Result, additional: int) -> runtime.Allocator_Error {
	if additional < 0 || result.output_length > max(int)-additional do return .Out_Of_Memory
	required := result.output_length+additional
	if required <= len(result.output_memory) do return nil
	capacity := max(len(result.output_memory), 256)
	for capacity < required {
		if capacity > max(int)-capacity/2 {
			capacity = required
			break
		}
		capacity += capacity/2
	}
	memory, alloc_error := runtime.mem_alloc_bytes(capacity, align_of(uintptr), result.allocator)
	if alloc_error != nil || len(memory) != capacity {
		if len(memory) > 0 {
			if free_error := runtime.mem_free_bytes(memory, result.allocator);
			   free_error != nil && free_error != .Mode_Not_Implemented {
				result.cleanup_memory = memory
				return free_error
			}
		}
		return alloc_error if alloc_error != nil else .Out_Of_Memory
	}
	if result.output_length > 0 {
		copy(memory[:result.output_length], result.output_memory[:result.output_length])
	}
	if len(result.output_memory) > 0 {
		free_error := runtime.mem_free_bytes(result.output_memory, result.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			result.cleanup_memory = memory
			return free_error
		}
	}
	result.output_memory = memory
	return nil
}

@(private)
pretty_size :: proc(compact: string) -> (size: int, ok: bool) {
	depth := 0
	i := 0
	for i < len(compact) {
		c := compact[i]
		if c == '"' {
			quote_at := i
			escaped := false
			for {
				if size == max(int) do return 0, false
				size += 1
				i += 1
				if escaped {
					escaped = false
					continue
				}
				if compact[i-1] == '\\' {
					escaped = true
					continue
				}
				if compact[i-1] == '"' && i-1 != quote_at do break
				if i >= len(compact) do return 0, false
			}
			continue
		}
		switch c {
		case '[', '{':
			matching := byte(']') if c == '[' else byte('}')
			if i+1 < len(compact) && compact[i+1] == matching {
				if size > max(int)-2 do return 0, false
				size += 2
				i += 2
				continue
			}
			depth += 1
			if depth > (max(int)-size-2)/2 do return 0, false
			size += 2+2*depth
		case ']', '}':
			if depth <= 0 do return 0, false
			depth -= 1
			if depth > (max(int)-size-2)/2 do return 0, false
			size += 2+2*depth
		case ',':
			if depth > (max(int)-size-2)/2 do return 0, false
			size += 2+2*depth
		case ':':
			if size > max(int)-2 do return 0, false
			size += 2
		case:
			if size == max(int) do return 0, false
			size += 1
		}
		i += 1
	}
	return size, depth == 0
}

@(private)
write_indent :: proc(destination: []byte, at: ^int, depth: int) {
	for _ in 0..<2*depth {
		destination[at^] = ' '
		at^ += 1
	}
}

@(private)
write_pretty :: proc(destination: []byte, compact: string) -> bool {
	at := 0
	depth := 0
	i := 0
	for i < len(compact) {
		c := compact[i]
		if c == '"' {
			quote_at := i
			escaped := false
			for {
				destination[at] = compact[i]
				at += 1
				i += 1
				if escaped {
					escaped = false
					continue
				}
				if compact[i-1] == '\\' {
					escaped = true
					continue
				}
				if compact[i-1] == '"' && i-1 != quote_at do break
			}
			continue
		}
		switch c {
		case '[', '{':
			matching := byte(']') if c == '[' else byte('}')
			destination[at] = c
			at += 1
			if i+1 < len(compact) && compact[i+1] == matching {
				destination[at] = matching
				at += 1
				i += 2
				continue
			}
			depth += 1
			destination[at] = '\n'
			at += 1
			write_indent(destination, &at, depth)
		case ']', '}':
			depth -= 1
			destination[at] = '\n'
			at += 1
			write_indent(destination, &at, depth)
			destination[at] = c
			at += 1
		case ',':
			destination[at] = ','
			destination[at+1] = '\n'
			at += 2
			write_indent(destination, &at, depth)
		case ':':
			destination[at] = ':'
			destination[at+1] = ' '
			at += 2
		case:
			destination[at] = c
			at += 1
		}
		i += 1
	}
	return at == len(destination)
}

@(private)
append_serialized_line :: proc(
	result: ^Run_Result,
	bytes: string,
	mode: Output_Mode,
) -> runtime.Allocator_Error {
	formatted_length := len(bytes)
	if mode == .Pretty {
		formatted_ok := false
		formatted_length, formatted_ok = pretty_size(bytes)
		if !formatted_ok do return .Invalid_Argument
	}
	if formatted_length == max(int) do return .Out_Of_Memory
	if err := reserve_output(result, formatted_length+1); err != nil do return err
	destination := result.output_memory[result.output_length:result.output_length+formatted_length]
	if mode == .Pretty {
		if !write_pretty(destination, bytes) do return .Invalid_Argument
	} else {
		copy(destination, transmute([]byte)bytes)
	}
	result.output_length += formatted_length
	result.output_memory[result.output_length] = '\n'
	result.output_length += 1
	return nil
}

@(private)
emit_output :: proc(result: ^Run_Result, options: Run_Options) -> bool {
	if options.emitter == nil || result.output_length == 0 do return true
	bytes := transmute(string)result.output_memory[:result.output_length]
	if !options.emitter(options.emitter_data, bytes) do return false
	// A successful synchronous return ends the borrow. Retain the allocation,
	// but reuse its logical contents for the next serialized result.
	result.output_length = 0
	return true
}

@(private)
copy_runtime_key :: proc(result: ^Run_Result, text: string) -> runtime.Allocator_Error {
	if len(text) == 0 do return nil
	memory, err := runtime.mem_alloc_bytes(len(text), 1, result.allocator)
	if err != nil || len(memory) != len(text) {
		if len(memory) > 0 {
			if free_error := runtime.mem_free_bytes(memory, result.allocator);
			   free_error != nil && free_error != .Mode_Not_Implemented {
				result.cleanup_memory = memory
				return free_error
			}
		}
		return err if err != nil else .Out_Of_Memory
	}
	copy(memory, transmute([]byte)text)
	result.runtime_key_memory = memory
	return nil
}

// run_with_options parses one complete filter and a stream of JSON input
// values, drains every evaluator output for each input in order, and produces
// owned LF-delimited bytes in the requested formatting mode.
run_with_options :: proc(
	result: ^Run_Result,
	filter, json_input: string,
	allocator: runtime.Allocator,
	options: Run_Options,
) -> Run_Error {
	if result == nil || result.self != nil || result.state != .Invalid {
		return {kind = .Misuse}
	}
	result.self = result
	result.state = .Running
	result.allocator = allocator
	filter_source := filter
	filter_memory, module_outcome := load_filter_modules(filter, options.module_paths, allocator)
	if module_outcome.kind != .None {
		if module_outcome.resource_error != nil {
			return allocation_error(result, module_outcome.resource_error)
		}
		return finish(result, {kind = .Module, module_kind = module_outcome.kind,
			resource_error = module_outcome.resource_error})
	}
	if len(filter_memory) > 0 {
		result.filter_memory = filter_memory
		filter_source = transmute(string)filter_memory
	}

	source := diagnostic.borrow_source("<filter>", filter_source)
	if !syntax.init_parser(&result.parser, source, allocator) {
		return finish(result, {kind = .Misuse})
	}
	parsed := syntax.parse_filter(&result.parser)
	switch parsed.kind {
	case .Input_Error:
		start, end, _ := diagnostic.span_offsets(source, parsed.error.span)
		return finish(result, {
			kind = .Filter_Parse,
			filter_parse_kind = parsed.error.kind,
			filter_expected = parsed.error.expected,
			filter_actual = parsed.error.actual,
			filter_has_actual = parsed.error.has_actual,
			filter_start = start,
			filter_end = end,
		})
	case .Resource_Failure:
		return allocation_error(result, parsed.resource_error)
	case .Misuse:
		return finish(result, {kind = .Misuse})
	case .Success:
	}

	lowered := compiler.lower_filter(
		&result.compiled,
		syntax.parser_nodes(&result.parser),
		parsed.root,
		source,
		allocator,
	)
	if lowered.kind != .None {
		if lowered.kind == .Resource_Failure do return allocation_error(result, lowered.resource_error)
		return finish(result, {kind = .Filter_Compile, compile_kind = lowered.kind})
	}

	if !json.init_compact_serializer(&result.serializer, allocator) {
		return finish(result, {kind = .Misuse})
	}

	cursor := 0
	input_count := 0
	for {
		if options.max_inputs > 0 && input_count >= options.max_inputs {
			return finish(result, {})
		}
		next := cursor
		done := false
		result.input, next, done, result.json_error = json.parse_next_value(
			json_input, cursor, allocator,
		)
		if result.json_error.kind != .None {
			if result.json_error.kind == .Scratch_Cleanup_Failure {
				// json_error remains the sole owner of the retained parser state;
				// cleanup_input replays its destruction without copying it.
				return finish(result, {
					kind = .Cleanup,
					resource_error = .Invalid_Pointer,
				})
			}
			if result.json_error.kind == .Allocation_Failure ||
			   result.json_error.kind == .Size_Overflow {
				resource := runtime.Allocator_Error(.Out_Of_Memory)
				return allocation_error(result, resource)
			}
			return finish(result, {
				kind = .JSON_Input,
				json_kind = result.json_error.kind,
				json_offset = result.json_error.detection_offset,
			})
		}
		if done do return finish(result, {})

		if evaluator_error := allocate_evaluator(result); evaluator_error != nil {
			return allocation_or_cleanup_error(result, evaluator_error)
		}
		initialized := eval.init_evaluator(result.evaluator, &result.compiled, &result.input, allocator)
		if initialized.kind != .None {
			if initialized.kind == .Resource_Failure {
				// A non-nil evaluator after rejected initialization is a cleanup-only
				// owner. Keep its exact inner allocation reachable through the stable
				// evaluator address and expose cleanup, not allocation, to callers.
				if result.evaluator^ != nil {
					return finish(result, {
						kind = .Cleanup,
						resource_error = initialized.resource_error,
					})
				}
				return allocation_error(result, initialized.resource_error)
			}
			return finish(result, {kind = .Misuse})
		}

		evaluation_loop: for {
			step := eval.step_evaluator(result.evaluator)
			switch step.kind {
			case .Output:
				result.current_output = eval.take_step_output(&step)
				serialized_error := json.serialize_compact(
					&result.serializer, &result.current_output, &result.serialized,
				)
				if serialized_error.kind != .None {
					if serialized_error.kind == .Cleanup_Failed {
						return finish(result, {kind = .Cleanup, resource_error = .Invalid_Pointer})
					}
					if serialized_error.kind == .Out_Of_Memory || serialized_error.kind == .Size_Overflow {
						return allocation_error(result, .Out_Of_Memory)
					}
					return finish(result, {
						kind = .Serialization,
						serialization_kind = serialized_error.kind,
					})
				}
				bytes, bytes_ok := json.compact_result_bytes(&result.serialized)
				if !bytes_ok do return finish(result, {kind = .Misuse})
				if append_error := append_serialized_line(result, bytes, options.output_mode);
				   append_error != nil {
					return allocation_or_cleanup_error(result, append_error)
				}
				if !emit_output(result, options) {
					return finish(result, {kind = .Output})
				}
				if cleanup_error := json.destroy_compact_result(&result.serialized); cleanup_error != nil {
					return finish(result, {kind = .Cleanup, resource_error = cleanup_error})
				}
				if cleanup_error := value.destroy_value(&result.current_output); cleanup_error != nil {
					return finish(result, {kind = .Cleanup, resource_error = cleanup_error})
				}
			case .Done:
				if cleanup_error := cleanup_input(result); cleanup_error != nil {
					return finish(result, {kind = .Cleanup, resource_error = cleanup_error})
				}
				cursor = next
				input_count += 1
				break evaluation_loop
			case .Runtime_Error:
				if key_error := copy_runtime_key(result, step.runtime_error.key); key_error != nil {
					return allocation_or_cleanup_error(result, key_error)
				}
				key := ""
				if len(result.runtime_key_memory) > 0 do key = transmute(string)result.runtime_key_memory
				return finish(result, {
					kind = .Runtime,
					runtime_kind = step.runtime_error.kind,
					runtime_input_kind = step.runtime_error.input_kind,
					runtime_span = step.runtime_error.span,
					runtime_key = key,
				})
			case .Resource_Error:
				return allocation_error(result, step.resource_error)
			case .Misuse:
				return finish(result, {kind = .Misuse})
			}
		}
	}
}

// run uses jq's ordinary pretty JSON output. Formatting is a borrowed option;
// it does not alter Run_Result ownership or cleanup.
run :: proc(
	result: ^Run_Result,
	filter, json_input: string,
	allocator: runtime.Allocator,
) -> Run_Error {
	return run_with_options(result, filter, json_input, allocator, {})
}
