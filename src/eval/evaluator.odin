package eval

import "base:runtime"
import "core:math"
import "core:sync"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:fmt"
import datetime "core:time/datetime"
import encoding_base64 "core:encoding/base64"
import "core:unicode/utf8"
import program "jq:program"
import value "jq:value"
import json "jq:json"

Runtime_Error_Kind :: enum u8 {
	None,
	Cannot_Index_With_String,
	Cannot_Add,
	Cannot_Subtract,
	Cannot_Multiply,
	Cannot_Divide,
	Cannot_Modulo,
	Cannot_Iterate,
	Cannot_Length,
	Cannot_Number,
	Cannot_Trim,
	User_Error,
}

Runtime_Error :: struct {
	kind:       Runtime_Error_Kind,
	input_kind: value.Kind,
	span:       program.Source_Span,
	// key is a length-delimited immutable view owned by the originating
	// Evaluator. It remains valid through terminal replay until
	// destroy_evaluator succeeds; callers neither take nor destroy it.
	key:        string,
}

Misuse_Kind :: enum u8 {
	None,
	Invalid_Evaluator,
	Copied_Evaluator,
	Invalid_Program_Lifetime,
	Malformed_Program,
	Unsupported_Opcode,
}

Step_Kind :: enum u8 {
	Output,
	Done,
	Runtime_Error,
	Resource_Error,
	Misuse,
}

// Step_Result owns output exactly when kind is Output. It must not be copied;
// transfer the output with take_step_output and eventually destroy that Value.
Step_Result :: struct {
	kind:           Step_Kind,
	output:         value.Value,
	runtime_error:  Runtime_Error,
	resource_error: runtime.Allocator_Error,
	misuse:         Misuse_Kind,
}

take_step_output :: proc(result: ^Step_Result) -> value.Value {
	if result == nil || result.kind != .Output do return {}
	result.kind = .Done
	return value.take_value(&result.output)
}

Init_Error_Kind :: enum u8 {
	None,
	Invalid_Argument,
	Invalid_Program,
	Size_Overflow,
	Resource_Failure,
}

Init_Result :: struct {
	kind:           Init_Error_Kind,
	resource_error: runtime.Allocator_Error,
}

@(private)
frame_mode :: enum u8 {
	Normal,
	Field_Only,
	Index_Only,
	Slice_Only,
}

@(private)
frame_phase :: enum u8 {
	Enter,
	Leaf_Yielded,
	Unary_Active,
	First_Empty,
	Last_Result,
	Last_Empty,
	Add_Active,
	Add_Result,
	Add_Empty,
	Limit_Active,
	Skip_Active,
	Nth_Active,
	Map_Start,
	Map_Child_Active,
	Try_Start_Expression,
	Try_Start_Catch,
	Try_Expression_Active,
	Try_Catch_Active,
	Fork_Start_Left,
	Fork_Left_Active,
	Fork_Start_Right,
	Fork_Right_Active,
	Sequence_Start_Left,
	Sequence_Left_Active,
	Sequence_Right_Active,
	Field_Start_Child,
	Field_Child_Active,
	Field_Result_Active,
	Index_Start_Child,
	Index_Child_Active,
	Index_Result_Active,
	Slice_Start_Child,
	Slice_Child_Active,
	Slice_Result_Active,
	Iterator_Active,
	Binding_Start_Left,
	Binding_Left_Active,
	Binding_Body_Active,
	Constructor_Start,
	Constructor_Child_Active,
	Constructor_Emit,
	Binary_Start_Left,
	Binary_Left_Active,
	Binary_Start_Right,
	Binary_Right_Active,
	If_Condition_Active,
	If_Then_Active,
	If_Else_Active,
	Complete,
}

@(private)
eval_frame :: struct {
	instruction: program.Instruction_Index,
	parent:      int,
	mode:        frame_mode,
	phase:       frame_phase,
	input:       value.Value,
	// Composite continuations retain the exact sealed instruction and operands
	// that established their phase. Resumption compares the live Program bytes
	// before using either the saved phase or a current operand.
	saved_instruction: program.Instruction,
	saved_operands:    [3]program.Operand,
	saved_operand_count: u8,
	has_saved_instruction: bool,
	// Constructors materialize each child generator into one owned array before
	// emitting Cartesian-product results. This keeps jq's zero/one/many stream
	// cardinality explicit without pretending Odin has coroutines.
	constructor_results: value.Value,
	constructor_key_results: value.Value,
	constructor_current: value.Value,
	constructor_child: int,
	constructor_cursor: u64,
	constructor_total: u64,
	constructor_seen_output: bool,
	pending_constructor_value: value.Value,
	pending_constructor_key: value.Value,
	pending_array_error: value.Array_Operation_Error,
	pending_object_error: value.Object_Operation_Error,
	constructor_pending_failure: bool,
	binding_value: value.Value,
	// Binary operators retain the left result while the right generator runs.
	binary_left: value.Value,
	if_branch_active: bool,
	iterator_cursor: int,
	reduce_accumulator: value.Value,
	reduce_binding: value.Value,
	selected_value: value.Value,
	selected_seen: bool,
	add_accumulator: value.Value,
	add_seen: bool,
	limit_remaining: u64,
	map_values_mode: bool,
	map_value_seen: bool,
}

@(private)
terminal_kind :: enum u8 {
	None,
	Done,
	Runtime,
	Misuse,
	Destroy,
}

@(private)
pending_kind :: enum u8 {
	None,
	Suppress_Runtime,
	Terminal_Cleanup,
}

@(private)
evaluator_state :: enum u8 {
	Active,
	Terminal,
	Cleanup_Only,
	Destroyed,
}

@(private)
program_seal :: struct {
	first:  u64,
	second: u64,
}

@(private)
seal_mix_u64 :: proc(seal: ^program_seal, value: u64) {
	// Mix the mathematical value, never its native byte representation.
	seal.first = seal.first ~ (value+0x9e3779b97f4a7c15+(seal.first << 6)+(seal.first >> 2))
	seal.first *= 0xbf58476d1ce4e5b9
	seal.second += value+0x94d049bb133111eb
	seal.second = (seal.second << 27) | (seal.second >> 37)
	seal.second *= 0x9e3779b185ebca87
}

@(private)
seal_mix_text :: proc(seal: ^program_seal, text: string) {
	seal_mix_u64(seal, u64(len(text)))
	for byte in transmute([]u8)text {
		seal_mix_u64(seal, u64(byte))
	}
}

// seal_program walks only public logical Active Program data. It mixes the
// explicit-root marker and root, collection and owned-allocation lengths; every
// opcode, operand range, and source-span endpoint;
// every Operand kind and explicit payload field; and every Text operand's
// length-delimited bytes. It never reads pointer identity, allocator state,
// backing-storage handles, construction counters, padding, validation scratch,
// or another nondeterministic representation. Program state and self identity
// are checked separately as lifetime invariants. The walk is allocation-free
// and bounded by Program storage size.
@(private)
seal_program :: proc(compiled: ^program.Program) -> (program_seal, bool) {
	instruction_count, instructions_ok := program.program_instruction_count(compiled)
	operand_count, operands_ok := program.program_operand_count(compiled)
	root, root_ok := program.program_root(compiled)
	if !instructions_ok || !operands_ok || !root_ok do return {}, false

	seal := program_seal{
		first = 0xcbf29ce484222325,
		second = 0x6a09e667f3bcc909,
	}
	seal_mix_u64(&seal, 0x4a514f44494e4556)
	has_root: u64
	if compiled.has_root do has_root = 1
	seal_mix_u64(&seal, has_root)
	seal_mix_u64(&seal, u64(len(compiled.memory)))
	seal_mix_u64(&seal, u64(instruction_count))
	seal_mix_u64(&seal, u64(operand_count))
	seal_mix_u64(&seal, u64(root))
	for index: u64 = 0; index < u64(instruction_count); index += 1 {
		instruction, ok := program.program_instruction(
			compiled, program.Instruction_Index(index),
		)
		if !ok do return {}, false
		seal_mix_u64(&seal, 0x494e535452554354)
		seal_mix_u64(&seal, u64(instruction.opcode))
		seal_mix_u64(&seal, 1 if instruction.has_literal else 0)
		seal_mix_u64(&seal, u64(instruction.literal_kind))
		seal_mix_u64(&seal, 1 if instruction.literal_boolean else 0)
		seal_mix_u64(&seal, u64(instruction.operands_start))
		seal_mix_u64(&seal, u64(instruction.operands_count))
		seal_mix_u64(&seal, u64(instruction.span.start))
		seal_mix_u64(&seal, u64(instruction.span.end))
		seal_mix_u64(&seal, 1 if instruction.has_operator_span else 0)
		seal_mix_u64(&seal, u64(instruction.operator_span.start))
		seal_mix_u64(&seal, u64(instruction.operator_span.end))
	}
	for index: u64 = 0; index < u64(operand_count); index += 1 {
		operand, ok := program.program_operand(compiled, program.Operand_Index(index))
		if !ok do return {}, false
		seal_mix_u64(&seal, 0x4f504552414e4421)
		seal_mix_u64(&seal, u64(operand.kind))
		seal_mix_u64(&seal, u64(operand.instruction))
		seal_mix_u64(&seal, u64(operand.text_start))
		seal_mix_u64(&seal, u64(operand.text_count))
		if operand.kind == .Text {
			text, text_ok := program.operand_text(compiled, operand)
			if !text_ok do return {}, false
			seal_mix_text(&seal, text)
		}
	}
	return seal, true
}

@(private)
evaluator_storage :: struct {
	// Borrowed until terminal cleanup or destroy succeeds. Each step validates
	// that the same address-stable Program remains sealed and Active.
	compiled:  ^program.Program,
	sealed_program: program_seal,
	allocator: runtime.Allocator,
	memory:    []byte,
	// A failed short-allocation cleanup has no Values. A failed old-arena
	// retirement after growth contains raw, non-owning duplicates; frames in
	// memory are the sole authoritative owners.
	temporary_memory: []byte,
	retired_memory:   []byte,
	frames:    []eval_frame,
	frame_count: int,
	self:      ^Evaluator,
	state:     evaluator_state,

	pending:          pending_kind,
	suppress_at:      int,
	suppress_try:     bool,
	pending_terminal: terminal_kind,
	runtime_error:    Runtime_Error,
	pending_constructor_error: ^value.Constructor_Error,
	// Keeps the public fixed-layout handle stable while diagnostic ownership
	// uses the existing Runtime_Error key view as its allocation anchor.
	layout_padding: u64,
	// A generated Value that could not be transferred after live Program
	// corruption remains reachable here until terminal cleanup retires it.
	pending_value:    value.Value,
	misuse:           Misuse_Kind,
}

// Evaluator_Handle fixes the public union payload layout across package
// boundaries. Its contents are reserved for package eval; callers construct
// only the nil Evaluator and use the lifecycle procedures below.
Evaluator_Handle :: distinct [32]u64

// Evaluator is one address-stable owner. Odin assignment is not an ownership
// operation: step_evaluator and destroy_evaluator reject a shallow copy before
// consulting Program or allocator state. The public fixed-layout variant keeps
// the nil union lifecycle while giving every importing package the same payload
// size, alignment, and tag offset.
Evaluator :: union {
	Evaluator_Handle,
}

#assert(size_of(evaluator_storage) == size_of(Evaluator_Handle))
#assert(align_of(evaluator_storage) == align_of(Evaluator_Handle))
#assert(size_of(Evaluator) == 264)
#assert(align_of(Evaluator) == 8)

@(private)
storage_of :: proc(evaluator: ^Evaluator) -> ^evaluator_storage {
	handle := &evaluator.(Evaluator_Handle)
	return cast(^evaluator_storage)rawptr(handle)
}

@(private)
set_storage :: proc(evaluator: ^Evaluator, storage: evaluator_storage) {
	evaluator^ = Evaluator_Handle{}
	storage_of(evaluator)^ = storage
}

@(private)
checked_frame_capacity :: proc(count: program.Count) -> (int, bool) {
	// Four records per instruction avoid growth for ordinary tree-shaped IR.
	// Shared DAG children can require more simultaneous activations; grow_frames
	// expands this initial arena without imposing a graph-shape limit.
	n := u64(count)
	if n == 0 || n > u64(max(int))/4 do return 0, false
	capacity := n * 4
	if capacity > u64(max(int))/u64(size_of(eval_frame)) do return 0, false
	return int(capacity), true
}

// Multiple Evaluators may independently borrow one Program. Serialize the
// allocation-free reuse of its otherwise execution-inert validation scratch.
@(private)
preflight_validation_mutex: sync.Mutex

@(private)
preflight_align_up :: proc(value, alignment: u64) -> (u64, bool) {
	if alignment == 0 do return 0, false
	padding := alignment-1
	if value > max(u64)-padding do return 0, false
	return (value+padding)&~padding, true
}

// validate_program_for_init re-establishes the complete finalized Program
// invariants before seal_program can read any execution storage. In addition
// to logical opcode/operand/text and graph validation, it verifies that every
// slice descriptor still names its exact region of Program.memory. It performs
// no allocator operation and uses only Program-owned validation scratch.
@(private)
validate_program_for_init :: proc(compiled: ^program.Program) -> bool {
	if !program.program_is_active(compiled) || !compiled.has_root do return false

	instruction_count := len(compiled.instructions)
	operand_count := len(compiled.operands)
	text_count := len(compiled.text)
	if instruction_count == 0 || u64(compiled.root) >= u64(instruction_count) ||
	   len(compiled.validation_records) != instruction_count ||
	   u64(compiled.instructions_written) != u64(instruction_count) ||
	   u64(compiled.operands_written) != u64(operand_count) ||
	   u64(compiled.text_written) != u64(text_count) {
		return false
	}

	ic := u64(instruction_count)
	oc := u64(operand_count)
	tc := u64(text_count)
	if ic > max(u64)/u64(size_of(program.Instruction)) ||
	   oc > max(u64)/u64(size_of(program.Operand)) ||
	   ic > max(u64)/u64(size_of(compiled.validation_records[0])) {
		return false
	}
	instruction_bytes := ic*u64(size_of(program.Instruction))
	operand_start, operand_aligned := preflight_align_up(
		instruction_bytes, u64(align_of(program.Operand)),
	)
	if !operand_aligned do return false
	operand_bytes := oc*u64(size_of(program.Operand))
	if operand_start > max(u64)-operand_bytes do return false
	validation_start, validation_aligned := preflight_align_up(
		operand_start+operand_bytes,
		u64(align_of(compiled.validation_records[0])),
	)
	if !validation_aligned do return false
	validation_bytes := ic*u64(size_of(compiled.validation_records[0]))
	if validation_start > max(u64)-validation_bytes do return false
	text_start := validation_start+validation_bytes
	if text_start > max(u64)-tc do return false
	total := text_start+tc
	if total == 0 || total > u64(max(int)) || total != u64(len(compiled.memory)) {
		return false
	}

	base := uintptr(raw_data(compiled.memory))
	if base == 0 || uintptr(total) > max(uintptr)-base do return false
	if uintptr(raw_data(compiled.instructions)) != base ||
	   uintptr(raw_data(compiled.validation_records)) != base+uintptr(validation_start) {
		return false
	}
	if operand_count == 0 {
		if raw_data(compiled.operands) != nil do return false
	} else if uintptr(raw_data(compiled.operands)) != base+uintptr(operand_start) {
		return false
	}
	if text_count == 0 {
		if raw_data(compiled.text) != nil do return false
	} else if uintptr(raw_data(compiled.text)) != base+uintptr(text_start) {
		return false
	}

	// Re-run Program's canonical complete finalization validator through a
	// non-owning descriptor copy. Only the Program-owned validation scratch is
	// shared with compiled; logical fields, owner state, and allocation ownership
	// remain unchanged. The scratch has no execution or destruction semantics.
	candidate := compiled^
	candidate.state = .Building
	candidate.self = &candidate
	sync.mutex_lock(&preflight_validation_mutex)
	defer sync.mutex_unlock(&preflight_validation_mutex)
	return program.finalize_program(&candidate)
}

// init_evaluator borrows compiled and allocator, but takes input only after
// exact frame storage succeeds. On success input becomes Invalid. A short
// allocator result whose cleanup fails leaves a Cleanup_Only evaluator that
// must be destroyed; input remains owned by the caller.
init_evaluator :: proc(
	evaluator: ^Evaluator,
	compiled: ^program.Program,
	input: ^value.Value,
	allocator: runtime.Allocator,
) -> Init_Result {
	if evaluator == nil || evaluator^ != nil || input == nil ||
	   value.kind_of(input) == .Invalid {
		return {kind = .Invalid_Argument}
	}
	if !validate_program_for_init(compiled) {
		return {kind = .Invalid_Program}
	}
	count, count_ok := program.program_instruction_count(compiled)
	root, root_ok := program.program_root(compiled)
	sealed_program, seal_ok := seal_program(compiled)
	if !count_ok || !root_ok || !seal_ok {
		return {kind = .Invalid_Program}
	}
	capacity, capacity_ok := checked_frame_capacity(count)
	if !capacity_ok {
		return {kind = .Size_Overflow}
	}
	byte_count := capacity * int(size_of(eval_frame))
	memory, allocation_error := runtime.mem_alloc_bytes(
		byte_count,
		align_of(eval_frame),
		allocator,
	)
	if allocation_error != nil || len(memory) != byte_count {
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				set_storage(evaluator, evaluator_storage{
					allocator = allocator,
					memory = memory,
					self = evaluator,
					state = .Cleanup_Only,
				})
				return {kind = .Resource_Failure, resource_error = free_error}
			}
		}
		return {
			kind = .Resource_Failure,
			resource_error = allocation_error if allocation_error != nil else .Out_Of_Memory,
		}
	}

	frames := (cast([^]eval_frame)raw_data(memory))[:capacity]
	for index in 0..<capacity do frames[index] = {}
	set_storage(evaluator, evaluator_storage{
		compiled = compiled,
		sealed_program = sealed_program,
		allocator = allocator,
		memory = memory,
		frames = frames,
		frame_count = 1,
		self = evaluator,
		state = .Active,
	})
	storage := storage_of(evaluator)
	storage.frames[0] = eval_frame{
		instruction = root,
		parent = -1,
		input = value.take_value(input),
	}
	return {}
}

@(private)
push_frame :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction_Index,
	parent: int,
	input: ^value.Value,
	mode := frame_mode.Normal,
) -> bool {
	if storage.frame_count >= len(storage.frames) || input == nil ||
	   value.kind_of(input) == .Invalid {
		return false
	}
	index := storage.frame_count
	storage.frames[index] = eval_frame{
		instruction = instruction,
		parent = parent,
		mode = mode,
		input = value.take_value(input),
	}
	storage.frame_count += 1
	return true
}

@(private)
constructor_frame_destroy :: proc(frame: ^eval_frame) -> runtime.Allocator_Error {
	if frame == nil do return nil
	free_error := value.destroy_array_error(&frame.pending_array_error)
	if free_error != nil do return free_error
	free_error = value.destroy_object_error(&frame.pending_object_error)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.pending_constructor_key)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.pending_constructor_value)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.constructor_results)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.constructor_key_results)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.constructor_current)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.binding_value)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.reduce_accumulator)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.reduce_binding)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&frame.selected_value)
	if free_error != nil do return free_error
	frame.selected_seen = false
	frame.limit_remaining = 0
	frame.map_values_mode = false
	frame.map_value_seen = false
	frame.constructor_child = 0
	frame.constructor_cursor = 0
	frame.constructor_total = 0
	frame.constructor_seen_output = false
	return nil
}

@(private)
constructor_frame_retry_pending :: proc(frame: ^eval_frame) -> runtime.Allocator_Error {
	if frame == nil do return nil
	free_error := value.destroy_array_error(&frame.pending_array_error)
	if free_error != nil do return free_error
	free_error = value.destroy_object_error(&frame.pending_object_error)
	if free_error != nil do return free_error
	// The failed constructor operation did not consume these operands. Once
	// its allocator cleanup succeeds, retire the preserved operands before the
	// evaluator reports the terminal malformed/resource outcome.
	free_error = value.destroy_value(&frame.pending_constructor_key)
	if free_error != nil do return free_error
	return value.destroy_value(&frame.pending_constructor_value)
}

@(private)
retain_constructor_array_error :: proc(frame: ^eval_frame, err: ^value.Array_Operation_Error) {
	if value.array_error_needs_cleanup(err) {
		frame.pending_array_error = value.take_array_error(err)
	} else {
		_ = value.destroy_array_error(err)
	}
	frame.constructor_pending_failure = true
}

@(private)
retain_constructor_object_error :: proc(frame: ^eval_frame, err: ^value.Object_Operation_Error) {
	if value.object_error_needs_cleanup(err) {
		frame.pending_object_error = value.take_object_error(err)
	} else {
		_ = value.destroy_object_error(err)
	}
	frame.constructor_pending_failure = true
}

@(private)
collect_constructor_key_stream :: proc(
	storage: ^evaluator_storage,
	instruction_index: program.Instruction_Index,
	producer: int,
	input: ^value.Value,
	output: ^value.Value,
) -> bool {
	instruction, instruction_ok := program.program_instruction(storage.compiled, instruction_index)
	if !instruction_ok do return false
	#partial switch instruction.opcode {
	case .Identity:
		key: value.Value
		if instruction.has_literal {
			literal_error: value.Error
			cleanup_error: runtime.Allocator_Error
			key, literal_error, cleanup_error = literal_value(storage, instruction)
			if cleanup_error != nil || literal_error != .None do return false
		} else {
			key = value.clone_value(input)
		}
		_, append_error := value.array_append_take(output, &key)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_array_error(&append_error)
			_ = value.destroy_value(&key)
			return false
		}
	case .Parenthesized, .Optional, .Negate:
		child, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
		return collect_constructor_key_stream(storage, child, producer, input, output)
	case .Variable:
		key, variable_ok := variable_result(storage, producer, instruction)
		if !variable_ok do return false
		_, append_error := value.array_append_take(output, &key)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_array_error(&append_error)
			_ = value.destroy_value(&key)
			return false
		}
	case .Fork:
		left, left_ok := child_instruction(storage, instruction, 0)
		right, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok do return false
		return collect_constructor_key_stream(storage, left, producer, input, output) &&
			collect_constructor_key_stream(storage, right, producer, input, output)
	case .Sequence:
		left, left_ok := child_instruction(storage, instruction, 0)
		right, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok do return false
		left_stream, left_error := value.array_value(storage.allocator)
		if value.array_error_kind(&left_error) != .None {
			_ = value.destroy_array_error(&left_error)
			return false
		}
		left_ok = collect_constructor_key_stream(storage, left, producer, input, &left_stream)
		if !left_ok {
			_ = value.destroy_value(&left_stream)
			return false
		}
		left_length, length_ok := value.array_length(&left_stream)
		if !length_ok {
			_ = value.destroy_value(&left_stream)
			return false
		}
		for index in 0..<left_length {
			left_value, item_ok := value.array_element_copy(&left_stream, index)
			if !item_ok {
				_ = value.destroy_value(&left_stream)
				return false
			}
			if !collect_constructor_key_stream(storage, right, producer, &left_value, output) {
				_ = value.destroy_value(&left_value)
				_ = value.destroy_value(&left_stream)
				return false
			}
			_ = value.destroy_value(&left_value)
		}
		_ = value.destroy_value(&left_stream)
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		left, left_ok := child_instruction(storage, instruction, 0)
		right, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok || instruction.operands_count != 2 do return false
		left_stream, left_error := value.array_value(storage.allocator)
		if value.array_error_kind(&left_error) != .None { _ = value.destroy_array_error(&left_error); return false }
		right_stream, right_error := value.array_value(storage.allocator)
		if value.array_error_kind(&right_error) != .None { _ = value.destroy_array_error(&right_error); _ = value.destroy_value(&left_stream); return false }
	if !collect_constructor_key_stream(storage, left, producer, input, &left_stream) ||
	   !collect_constructor_key_stream(storage, right, producer, input, &right_stream) {
		_ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false
		}
	left_length, left_length_ok := value.array_length(&left_stream)
	right_length, right_length_ok := value.array_length(&right_stream)
	if !left_length_ok || !right_length_ok { _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
	for left_index in 0..<left_length {
		left_value, left_value_ok := value.array_element_copy(&left_stream, left_index)
		if !left_value_ok { _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
		for right_index in 0..<right_length {
			right_value, right_value_ok := value.array_element_copy(&right_stream, right_index)
			if !right_value_ok { _ = value.destroy_value(&left_value); _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
			left_for_right := value.clone_value(&left_value)
			if value.kind_of(&left_for_right) == .Invalid { _ = value.destroy_value(&right_value); _ = value.destroy_value(&left_value); _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
			combined, runtime_kind, resource_error := apply_binary(instruction.opcode, &left_for_right, &right_value, instruction.operator_span, storage.allocator)
			_ = value.destroy_value(&left_for_right); _ = value.destroy_value(&right_value)
			if runtime_kind != .None || resource_error != nil || value.kind_of(&combined) == .Invalid { _ = value.destroy_value(&combined); _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
			_, append_error := value.array_append_take(output, &combined)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&combined); _ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream); return false }
		}
		_ = value.destroy_value(&left_value)
	}
	_ = value.destroy_value(&left_stream); _ = value.destroy_value(&right_stream)
	case .Field:
		if instruction.operands_count != 1 do return false
		temp := eval_frame{input = value.clone_value(input)}
		key, runtime_error, field_ok := field_result(storage, &temp, instruction)
		_ = value.destroy_value(&temp.input)
		if !field_ok || runtime_error.kind != .None {
			_ = value.destroy_value(&key)
			return false
		}
		_, append_error := value.array_append_take(output, &key)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_array_error(&append_error)
			_ = value.destroy_value(&key)
			return false
		}
	case:
		return false
	}
	return true
}

@(private)
constructor_start :: proc(storage: ^evaluator_storage, frame: ^eval_frame, instruction: program.Instruction) -> bool {
	if instruction.opcode != .Array && instruction.opcode != .Object do return false
	// results is an array of per-child output arrays. Each child stream is
	// collected independently; emission later takes one element from each,
	// yielding the Cartesian product required by jq constructors.
	results, result_error := value.array_value(storage.allocator)
	if value.array_error_kind(&result_error) != .None {
		retain_constructor_array_error(frame, &result_error)
		return false
	}
	frame.constructor_results = value.take_value(&results)
	if instruction.opcode == .Object {
		key_results, key_results_error := value.array_value(storage.allocator)
		if value.array_error_kind(&key_results_error) != .None {
			retain_constructor_array_error(frame, &key_results_error)
			_ = value.destroy_value(&frame.constructor_results)
			return false
		}
		frame.constructor_key_results = value.take_value(&key_results)
	}
	frame.constructor_child = 0
	frame.constructor_cursor = 0
	frame.constructor_total = 1
	frame.constructor_seen_output = false
	frame.phase = .Constructor_Start
	return true
}


@(private)
child_instruction :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
	offset: u32,
) -> (program.Instruction_Index, bool) {
	if offset >= u32(instruction.operands_count) do return {}, false
	operand, ok := program.program_operand(
		storage.compiled,
		program.Operand_Index(u32(instruction.operands_start)+offset),
	)
	if !ok || operand.kind != .Instruction do return {}, false
	return operand.instruction, true
}

@(private)
variable_result :: proc(storage: ^evaluator_storage, producer: int, instruction: program.Instruction) -> (value.Value, bool) {
	if instruction.opcode != .Variable || instruction.operands_count != 1 do return {}, false
	name_operand, name_ok := program.program_operand(storage.compiled, instruction.operands_start)
	if !name_ok || name_operand.kind != .Text do return {}, false
	name, text_ok := program.operand_text(storage.compiled, name_operand)
	if !text_ok do return {}, false
	current := storage.frames[producer].parent
	for current >= 0 {
		frame := &storage.frames[current]
		bound_instruction, instruction_ok := program.program_instruction(storage.compiled, frame.instruction)
		if !instruction_ok do return {}, false
		if (bound_instruction.opcode == .Binding || bound_instruction.opcode == .Reduce) && value.kind_of(&frame.binding_value) != .Invalid {
			bound_operand, bound_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(bound_instruction.operands_start)+2))
			if !bound_ok || bound_operand.kind != .Text do return {}, false
			bound_name, bound_text_ok := program.operand_text(storage.compiled, bound_operand)
			if !bound_text_ok do return {}, false
			if bound_name == name do return value.clone_value(&frame.binding_value), true
		}
		current = frame.parent
	}
	return {}, false
}

@(private)
constructor_child_instruction :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
	child: int,
) -> (program.Instruction_Index, bool) {
	offset := child
	if instruction.opcode == .Object do offset = child*2 + 1
	if offset < 0 || u32(offset) >= u32(instruction.operands_count) do return {}, false
	return child_instruction(storage, instruction, u32(offset))
}

@(private)
constructor_emit :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> (value.Value, bool) {
	if frame.constructor_total == 0 do return {}, false
	child_count := int(instruction.operands_count)
	if instruction.opcode == .Object do child_count /= 2
	if child_count != 0 && frame.constructor_cursor >= frame.constructor_total do return {}, false
	result: value.Value
	if instruction.opcode == .Array {
		array_result, array_error := value.array_value(storage.allocator)
		if value.array_error_kind(&array_error) != .None {
			retain_constructor_array_error(frame, &array_error)
			return {}, false
		}
		result = value.take_value(&array_result)
	} else {
		object_result, object_error := value.object_value(storage.allocator)
		if value.object_error_kind(&object_error) != .None {
			retain_constructor_object_error(frame, &object_error)
			return {}, false
		}
		result = value.take_value(&object_result)
	}
	quotient := frame.constructor_cursor
	for child in 0..<child_count {
		// jq's object constructor evaluates later entries inside each earlier
		// result, so the later entry is the least-significant Cartesian
		// dimension. Arrays retain their existing left-to-right stream order.
		selected_child := child
		if instruction.opcode == .Object do selected_child = child_count - 1 - child
		child_stream, stream_ok := value.array_element_copy(
			&frame.constructor_results,
			selected_child,
		)
		if !stream_ok {
			_ = value.destroy_value(&result)
			return {}, false
		}
		length, length_ok := value.array_length(&child_stream)
		if !length_ok {
			_ = value.destroy_value(&child_stream)
			_ = value.destroy_value(&result)
			return {}, false
		}
		if instruction.opcode == .Array {
			for selected in 0..<length {
				item, item_ok := value.array_element_copy(&child_stream, selected)
				if !item_ok {
					_ = value.destroy_value(&child_stream)
					_ = value.destroy_value(&result)
					return {}, false
				}
			_, append_error := value.array_append_take(&result, &item)
			if value.array_error_kind(&append_error) != .None {
				frame.constructor_pending_failure = true
				frame.pending_constructor_value = value.take_value(&item)
				if value.array_error_needs_cleanup(&append_error) {
					frame.pending_array_error = value.take_array_error(&append_error)
				} else {
					_ = value.destroy_array_error(&append_error)
				}
				_ = value.destroy_value(&result)
				return {}, false
			}
			}
		} else {
			if length <= 0 {
				_ = value.destroy_value(&child_stream)
				_ = value.destroy_value(&result)
				return {}, false
			}
			selected := int(quotient % u64(length))
			quotient /= u64(length)
			item, item_ok := value.array_element_copy(&child_stream, selected)
			if !item_ok {
				_ = value.destroy_value(&child_stream)
				_ = value.destroy_value(&result)
				return {}, false
			}
			key_stream, key_stream_ok := value.array_element_copy(&frame.constructor_key_results, selected_child)
			if !key_stream_ok {
				_ = value.destroy_value(&item)
				_ = value.destroy_value(&result)
				return {}, false
			}
			key_length, key_length_ok := value.array_length(&key_stream)
			if !key_length_ok || key_length <= 0 {
				_ = value.destroy_value(&key_stream)
				_ = value.destroy_value(&item)
				_ = value.destroy_value(&result)
				return {}, false
			}
			key_index := int(quotient % u64(key_length))
			quotient /= u64(key_length)
			key, key_ok := value.array_element_copy(&key_stream, key_index)
			_ = value.destroy_value(&key_stream)
			if !key_ok {
				_ = value.destroy_value(&item)
				_ = value.destroy_value(&result)
				return {}, false
			}
			duplicate, displaced, set_error := value.object_set_take(&result, &key, &item)
			if value.object_error_kind(&set_error) != .None {
				frame.constructor_pending_failure = true
				frame.pending_constructor_key = value.take_value(&key)
				frame.pending_constructor_value = value.take_value(&item)
				if value.object_error_needs_cleanup(&set_error) {
					frame.pending_object_error = value.take_object_error(&set_error)
				} else {
					_ = value.destroy_object_error(&set_error)
				}
				_ = value.destroy_value(&displaced)
				_ = value.destroy_value(&result)
				return {}, false
			}
			_ = value.destroy_value(&duplicate)
			_ = value.destroy_value(&displaced)
		}
		_ = value.destroy_value(&child_stream)
	}
	return result, true
}

@(private)
field_text :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
) -> (string, bool) {
	if instruction.operands_count != 1 && instruction.operands_count != 2 do return "", false
	offset := u32(instruction.operands_count)-1
	operand, ok := program.program_operand(
		storage.compiled,
		program.Operand_Index(u32(instruction.operands_start)+offset),
	)
	if !ok || operand.kind != .Text do return "", false
	return program.operand_text(storage.compiled, operand)
}

@(private)
literal_value :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
) -> (value.Value, value.Error, runtime.Allocator_Error) {
	if !instruction.has_literal || instruction.opcode != .Identity {
		return {}, .Invalid_Number_Literal, nil
	}

	switch instruction.literal_kind {
	case .Null:
		if instruction.operands_count != 0 do return {}, .Invalid_Number_Literal, nil
		return value.null_value(), .None, nil
	case .Boolean:
		if instruction.operands_count != 0 do return {}, .Invalid_Number_Literal, nil
		return value.boolean_value(instruction.literal_boolean), .None, nil
	case .Number, .String:
		if instruction.operands_count != 1 do return {}, .Invalid_Number_Literal, nil
		operand, operand_ok := program.program_operand(
			storage.compiled,
			program.Operand_Index(u32(instruction.operands_start)),
		)
		if !operand_ok || operand.kind != .Text do return {}, .Invalid_Number_Literal, nil
		text, text_ok := program.operand_text(storage.compiled, operand)
		if !text_ok do return {}, .Invalid_Number_Literal, nil

		result: value.Value
		err: value.Constructor_Error
		if instruction.literal_kind == .Number {
			result, err = value.literal_number_value(text, storage.allocator)
		} else {
			result, err = value.string_value(text, storage.allocator)
		}
		err_kind := value.constructor_error_kind(&err)
		if err_kind == .None do return result, .None, nil
		if value.constructor_error_needs_cleanup(&err) {
			memory, allocation_error := runtime.mem_alloc_bytes(
				size_of(value.Constructor_Error),
				align_of(value.Constructor_Error),
				storage.allocator,
			)
			if allocation_error != nil || len(memory) != size_of(value.Constructor_Error) {
				// The public evaluator layout cannot grow to embed a
				// Constructor_Error. Keep the error in the invalid pending_value
				// storage until terminal cleanup instead of dropping its cleanup
				// handle when this holder allocation fails. A short allocation is
				// also retained by the normal pending-memory retry path.
				assert(storage.pending_constructor_error == nil)
				assert(value.kind_of(&storage.pending_value) == .Invalid)
				if len(memory) > 0 {
					assert(len(storage.temporary_memory) == 0)
					storage.temporary_memory = memory
				}
				storage.pending_constructor_error = cast(^value.Constructor_Error)rawptr(&storage.pending_value)
				storage.pending_constructor_error^ = value.take_constructor_error(&err)
				storage.pending = .Terminal_Cleanup
				storage.pending_terminal = .Misuse
				storage.misuse = .Malformed_Program
				return {}, err_kind, allocation_error if allocation_error != nil else .Out_Of_Memory
			}
			storage.pending_constructor_error = cast(^value.Constructor_Error)raw_data(memory)
			storage.pending_constructor_error^ = value.take_constructor_error(&err)
			cleanup_error := retire_pending_constructor_error(storage)
			if cleanup_error != nil {
				storage.pending = .Terminal_Cleanup
				storage.pending_terminal = .Misuse
				storage.misuse = .Malformed_Program
				return {}, err_kind, cleanup_error
			}
		} else {
			_ = value.destroy_constructor_error(&err)
		}
		return {}, err_kind, nil
	}
	return {}, .Invalid_Number_Literal, nil
}

@(private)
capture_composite_instruction :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> bool {
	if frame.mode != .Normal && frame.mode != .Field_Only && frame.mode != .Index_Only && frame.mode != .Slice_Only do return false
	#partial switch instruction.opcode {
	case .Parenthesized, .Optional, .Negate:
		if instruction.operands_count != 1 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
	case .First, .Last, .Add_Builtin:
		if instruction.operands_count != 1 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
	case .Limit, .Skip, .Nth:
		if instruction.operands_count != 2 do return false
		_, count_ok := child_instruction(storage, instruction, 0)
		_, generator_ok := child_instruction(storage, instruction, 1)
		if !count_ok || !generator_ok do return false
	case .Map, .Map_Values:
		if instruction.operands_count != 1 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
	case .Field:
		if instruction.operands_count != 2 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		_, text_ok := field_text(storage, instruction)
		if !child_ok || !text_ok do return false
	case .Index:
		if instruction.operands_count != 2 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		index_operand, index_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+1))
		if !child_ok || !index_ok || index_operand.kind != .Text do return false
	case .Slice:
		if instruction.operands_count != 3 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		for offset in 1..<3 {
			operand, operand_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+u32(offset)))
			if !operand_ok || operand.kind != .Text do return false
		}
		if !child_ok do return false
	case .Try:
		if instruction.operands_count != 2 do return false
		_, expression_ok := child_instruction(storage, instruction, 0)
		_, catch_ok := child_instruction(storage, instruction, 1)
		if !expression_ok || !catch_ok do return false
	case .IsEmpty:
		if instruction.operands_count != 1 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
	case .Range:
		if instruction.operands_count != 1 && instruction.operands_count != 2 && instruction.operands_count != 3 do return false
		for offset in 0..<int(instruction.operands_count) { _, child_ok := child_instruction(storage, instruction, u32(offset)); if !child_ok do return false }
	case .If:
		if instruction.operands_count != 3 do return false
		for offset in 0..<3 { _, child_ok := child_instruction(storage, instruction, u32(offset)); if !child_ok do return false }
	case .Strftime:
		if instruction.operands_count != 1 do return false
		_, child_ok := child_instruction(storage, instruction, 0)
		if !child_ok do return false
	case .Binding:
		if instruction.operands_count != 3 do return false
		_, left_ok := child_instruction(storage, instruction, 0)
		_, right_ok := child_instruction(storage, instruction, 1)
		name_operand, name_ok := program.program_operand(
			storage.compiled,
			program.Operand_Index(u32(instruction.operands_start)+2),
		)
		if !left_ok || !right_ok || !name_ok || name_operand.kind != .Text do return false
	case .Reduce:
		if instruction.operands_count != 4 do return false
		for i in 0..<3 { _, ok := child_instruction(storage, instruction, u32(i)); if !ok do return false }
		frame.saved_instruction = instruction
		frame.saved_operand_count = 3
		frame.has_saved_instruction = true
		return true
	case .Fork, .Sequence:
		if instruction.operands_count != 2 do return false
		_, left_ok := child_instruction(storage, instruction, 0)
		_, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok do return false
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Pow,
	     .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		if instruction.operands_count != 2 do return false
		_, left_ok := child_instruction(storage, instruction, 0)
		_, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok do return false
	case .Array, .Object:
		// Constructor operands are validated by Program; only the live
		// instruction/operand snapshot is needed for mutation detection here.
		frame.saved_instruction = instruction
		frame.saved_operand_count = 0
		frame.has_saved_instruction = true
		return true
	case:
		return false
	}

	for offset in 0..<int(instruction.operands_count) {
		operand, ok := program.program_operand(
			storage.compiled,
			program.Operand_Index(u32(instruction.operands_start)+u32(offset)),
		)
		if !ok do return false
		frame.saved_operands[offset] = operand
	}
	frame.saved_instruction = instruction
	frame.saved_operand_count = u8(instruction.operands_count)
	frame.has_saved_instruction = true
	return true
}

@(private)
resumed_composite_instruction_valid :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> bool {
	#partial switch frame.phase {
	case .Unary_Active:
		if frame.mode != .Normal ||
		   (instruction.opcode != .Parenthesized && instruction.opcode != .Optional && instruction.opcode != .Negate && instruction.opcode != .First && instruction.opcode != .Last) {
			return false
		}
	case .First_Empty, .Last_Result, .Last_Empty:
		if frame.mode != .Normal || (instruction.opcode != .First && instruction.opcode != .Last) do return false
	case .Limit_Active:
		if frame.mode != .Normal || instruction.opcode != .Limit do return false
	case .Skip_Active:
		if frame.mode != .Normal || instruction.opcode != .Skip do return false
	case .Nth_Active:
		if frame.mode != .Normal || instruction.opcode != .Nth do return false
	case .Map_Start, .Map_Child_Active:
		if frame.mode != .Normal || (instruction.opcode != .Map && instruction.opcode != .Map_Values) do return false
	case .Try_Expression_Active, .Try_Catch_Active:
		if frame.mode != .Normal || instruction.opcode != .Try do return false
	case .Field_Start_Child, .Field_Child_Active, .Field_Result_Active:
		if frame.mode != .Normal && frame.mode != .Field_Only || instruction.opcode != .Field do return false
	case .Iterator_Active:
		if (frame.mode != .Normal && frame.mode != .Field_Only) || (instruction.opcode != .Field && instruction.opcode != .Range) {
			return false
		}
	case .Index_Start_Child, .Index_Child_Active, .Index_Result_Active:
		if frame.mode != .Normal && frame.mode != .Index_Only || instruction.opcode != .Index do return false
	case .Slice_Start_Child, .Slice_Child_Active, .Slice_Result_Active:
		if frame.mode != .Normal && frame.mode != .Slice_Only || instruction.opcode != .Slice do return false
	case .Fork_Start_Left, .Fork_Left_Active, .Fork_Start_Right, .Fork_Right_Active:
		if frame.mode != .Normal || instruction.opcode != .Fork do return false
	case .Sequence_Start_Left, .Sequence_Left_Active, .Sequence_Right_Active:
		if frame.mode != .Normal || instruction.opcode != .Sequence do return false
	case .Binding_Start_Left, .Binding_Left_Active, .Binding_Body_Active:
		if frame.mode != .Normal || instruction.opcode != .Binding do return false
	case .Constructor_Start, .Constructor_Child_Active, .Constructor_Emit:
		if frame.mode != .Normal || (instruction.opcode != .Array && instruction.opcode != .Object) {
			return false
		}
		return frame.has_saved_instruction && instruction.opcode == frame.saved_instruction.opcode
	case .Binary_Start_Left, .Binary_Left_Active, .Binary_Start_Right, .Binary_Right_Active:
		if frame.mode != .Normal || !is_binary_opcode(instruction.opcode) do return false
	case .If_Condition_Active, .If_Then_Active, .If_Else_Active:
		if frame.mode != .Normal || instruction.opcode != .If do return false
	case:
		return true
	}
	expected_operand_count: u8
	if frame.phase == .Unary_Active || frame.phase == .First_Empty || frame.phase == .Last_Result || frame.phase == .Last_Empty || frame.phase == .Add_Active || frame.phase == .Add_Result || frame.phase == .Add_Empty do expected_operand_count = 1
	else if frame.phase == .Limit_Active || frame.phase == .Skip_Active || frame.phase == .Nth_Active do expected_operand_count = 2
	else if frame.phase == .Map_Start || frame.phase == .Map_Child_Active do expected_operand_count = 1
	else if frame.phase == .Try_Expression_Active || frame.phase == .Try_Catch_Active do expected_operand_count = 2
	else if frame.phase == .Index_Start_Child || frame.phase == .Index_Child_Active || frame.phase == .Index_Result_Active {
		expected_operand_count = 2
	}
	else if frame.phase == .Slice_Start_Child || frame.phase == .Slice_Child_Active || frame.phase == .Slice_Result_Active {
		expected_operand_count = 3
	}
	else if frame.phase == .Constructor_Start || frame.phase == .Constructor_Child_Active || frame.phase == .Constructor_Emit {
		expected_operand_count = u8(instruction.operands_count)
	} else if frame.phase == .Iterator_Active {
		expected_operand_count = u8(instruction.operands_count)
	}
	else if frame.phase == .Binding_Start_Left || frame.phase == .Binding_Left_Active || frame.phase == .Binding_Body_Active {
		expected_operand_count = 3
	} else if frame.phase == .If_Condition_Active || frame.phase == .If_Then_Active || frame.phase == .If_Else_Active {
		expected_operand_count = 3
	} else if frame.phase == .Binary_Start_Left || frame.phase == .Binary_Left_Active || frame.phase == .Binary_Start_Right || frame.phase == .Binary_Right_Active {
		expected_operand_count = 2
	} else do expected_operand_count = 2
	if !frame.has_saved_instruction ||
	   frame.saved_operand_count != expected_operand_count ||
	   instruction != frame.saved_instruction {
		return false
	}
	for offset in 0..<int(expected_operand_count) {
		operand, ok := program.program_operand(
			storage.compiled,
			program.Operand_Index(u32(instruction.operands_start)+u32(offset)),
		)
		if !ok || operand != frame.saved_operands[offset] do return false
	}
	return true
}

@(private)
field_result :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> (value.Value, Runtime_Error, bool) {
	key, key_ok := field_text(storage, instruction)
	if !key_ok do return {}, {}, false
	switch value.kind_of(&frame.input) {
	case .Object:
		result, found := value.object_get_copy(&frame.input, key)
		if found {
			// A retiring payload must never escape as a successful output. This
			// is a malformed live Value/program state, not jq's missing-key
			// null result; preserve the frame owner for terminal cleanup.
			if value.kind_of(&result) == .Invalid do return {}, {}, false
			return result, {}, true
		}
		return value.null_value(), {}, true
	case .Null:
		return value.null_value(), {}, true
	case .Boolean, .Number, .String, .Array:
		return {}, Runtime_Error{
			kind = .Cannot_Index_With_String,
			input_kind = value.kind_of(&frame.input),
			span = instruction.span,
			key = key,
		}, true
	case .Invalid:
	}
	return {}, {}, false
}

@(private)
index_result :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> (value.Value, Runtime_Error, bool) {
	operand, operand_ok := program.program_operand(
		storage.compiled,
		program.Operand_Index(u32(instruction.operands_start)+1),
	)
	index_text, text_ok := program.operand_text(storage.compiled, operand)
	if !operand_ok || !text_ok || operand.kind != .Text do return {}, {}, false
	index_value, parse_error := value.literal_number_value(index_text, storage.allocator)
	if value.constructor_error_kind(&parse_error) != .None {
		_ = value.destroy_constructor_error(&parse_error)
		return {}, {}, false
	}
	index_number, number_ok := value.number_value_get(&index_value)
	_ = value.destroy_value(&index_value)
	if !number_ok {
		// jq rejects fractional numeric indices for strings with a typed
		// runtime error.  Arrays retain their historical null result for an
		// out-of-range/non-integral index in this bounded indexing contract.
		if value.kind_of(&frame.input) == .String {
			return {}, Runtime_Error{
				// Preserve the jq message as the catch value as well as the
				// terminal diagnostic. User_Error is the existing owned-message
				// transport used by literal error(), and avoids the generic
				// string-key formatter interpreting the numeric spelling as a key.
				kind = .User_Error,
				input_kind = .String,
				span = instruction.span,
				key = "Cannot index string with number",
			}, true
		}
		return value.null_value(), {}, true
	}
	index := int(index_number)
	if index < 0 {
		if value.kind_of(&frame.input) == .Array {
			length, length_ok := value.array_length(&frame.input)
			if !length_ok do return {}, {}, false
			index += length
			if index < 0 do return value.null_value(), {}, true
		} else if value.kind_of(&frame.input) == .String {
			return {}, Runtime_Error{kind=.User_Error, input_kind=.String, span=instruction.span, key="Cannot index string with number"}, true
		} else {
			return value.null_value(), {}, true
		}
	}
	switch value.kind_of(&frame.input) {
	case .Array:
		length, length_ok := value.array_length(&frame.input)
		if !length_ok do return {}, {}, false
		if index >= length do return value.null_value(), {}, true
		output, output_ok := value.array_element_copy(&frame.input, index)
		if !output_ok do return {}, {}, false
		return output, {}, true
	case .Null:
		return value.null_value(), {}, true
	case .Boolean, .Number, .String, .Object:
		if value.kind_of(&frame.input) == .String {
			return {}, Runtime_Error{kind=.User_Error, input_kind=.String, span=instruction.span, key="Cannot index string with number"}, true
		}
		return {}, Runtime_Error{
			kind = .Cannot_Index_With_String,
			input_kind = value.kind_of(&frame.input),
			span = instruction.span,
			key = index_text,
		}, true
	case .Invalid:
	}
	return {}, {}, false
}

@(private)
slice_result :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> (value.Value, Runtime_Error, bool) {
	if value.kind_of(&frame.input) == .Null do return value.null_value(), {}, true
	if value.kind_of(&frame.input) != .Array && value.kind_of(&frame.input) != .String do return {}, Runtime_Error{kind=.Cannot_Iterate, input_kind=value.kind_of(&frame.input), span=instruction.span}, true
	start_operand, start_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+1))
	end_operand, end_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+2))
	start_text, start_text_ok := program.operand_text(storage.compiled, start_operand)
	end_text, end_text_ok := program.operand_text(storage.compiled, end_operand)
	if !start_ok || !end_ok || !start_text_ok || !end_text_ok || start_operand.kind != .Text || end_operand.kind != .Text do return {}, {}, false
	length, length_ok := value.array_length(&frame.input)
	text: string
	if !length_ok {
		text_ok: bool
		text, text_ok = value.string_borrowed(&frame.input)
		if !text_ok do return {}, {}, false
		length = utf8_codepoint_length(text)
	}
	start, end := 0, length
	if len(start_text) > 0 {
		v, e := value.literal_number_value(start_text, storage.allocator)
		if value.constructor_error_kind(&e) != .None { _ = value.destroy_constructor_error(&e); return {}, Runtime_Error{kind=.Cannot_Iterate, input_kind=.Array, span=instruction.span}, true }
		n, ok := value.number_value_get(&v); _ = value.destroy_value(&v)
		if !ok do return {}, Runtime_Error{kind=.Cannot_Iterate, input_kind=.Array, span=instruction.span}, true
		start = int(math.floor(n)); if start < 0 { start += length }; if start < 0 { start = 0 }; if start > length { start = length }
	}
	if len(end_text) > 0 {
		v, e := value.literal_number_value(end_text, storage.allocator)
		if value.constructor_error_kind(&e) != .None { _ = value.destroy_constructor_error(&e); return {}, Runtime_Error{kind=.Cannot_Iterate, input_kind=.Array, span=instruction.span}, true }
		n, ok := value.number_value_get(&v); _ = value.destroy_value(&v)
		if !ok do return {}, Runtime_Error{kind=.Cannot_Iterate, input_kind=.Array, span=instruction.span}, true
		end = int(math.ceil(n)); if end < 0 { end += length }; if end < 0 { end = 0 }; if end > length { end = length }
	}
	if start > end {
		if value.kind_of(&frame.input) == .String {
			result, constructor_error := value.string_value("", storage.allocator)
			if value.constructor_error_kind(&constructor_error) != .None { _ = value.destroy_constructor_error(&constructor_error); return {}, {}, false }
			return result, {}, true
		}
		result, array_error := value.array_value(storage.allocator)
		if value.array_error_kind(&array_error) != .None { _ = value.destroy_array_error(&array_error); return {}, {}, false }
		return result, {}, true
	}
	if value.kind_of(&frame.input) == .String {
		start_byte := utf8_byte_offset_for_codepoint(text, start)
		end_byte := utf8_byte_offset_for_codepoint(text, end)
		result, constructor_error := value.string_value(text[start_byte:end_byte], storage.allocator)
		if value.constructor_error_kind(&constructor_error) != .None { _ = value.destroy_constructor_error(&constructor_error); return {}, {}, false }
		return result, {}, true
	}
	result, array_error := value.array_value(storage.allocator)
	if value.array_error_kind(&array_error) != .None { _ = value.destroy_array_error(&array_error); return {}, {}, false }
	for i in start..<end {
		item, ok := value.array_element_copy(&frame.input, i)
		if !ok { _ = value.destroy_value(&result); return {}, {}, false }
		_, append_error := value.array_append_take(&result, &item)
		if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&result); return {}, {}, false }
	}
	return result, {}, true
}

@(private)
resource_step :: proc(err: runtime.Allocator_Error) -> Step_Result {
	return {kind = .Resource_Error, resource_error = err}
}

@(private)
misuse_step :: proc(kind: Misuse_Kind) -> Step_Result {
	return {kind = .Misuse, misuse = kind}
}

@(private)
retire_pending_constructor_error :: proc(
	storage: ^evaluator_storage,
) -> runtime.Allocator_Error {
	if storage.pending_constructor_error == nil {
		return nil
	}
	inline := cast(^value.Constructor_Error)rawptr(&storage.pending_value)
	if storage.pending_constructor_error == inline {
		free_error := value.destroy_constructor_error(storage.pending_constructor_error)
		if free_error != nil do return free_error
		storage.pending_constructor_error = nil
		storage.pending_value = {}
		return nil
	}
	free_error := value.destroy_constructor_error(storage.pending_constructor_error)
	if free_error != nil do return free_error
	memory := (cast([^]byte)rawptr(storage.pending_constructor_error))[:size_of(value.Constructor_Error)]
	free_error = runtime.mem_free_bytes(memory, storage.allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
	storage.pending_constructor_error = nil
	return nil
}

@(private)
destroy_frames_to :: proc(storage: ^evaluator_storage, target_count: int) -> runtime.Allocator_Error {
	for storage.frame_count > target_count {
		index := storage.frame_count-1
		free_error := value.destroy_value(&storage.frames[index].input)
		if free_error != nil do return free_error
		free_error = constructor_frame_destroy(&storage.frames[index])
		if free_error != nil do return free_error
		free_error = value.destroy_value(&storage.frames[index].binary_left)
		if free_error != nil do return free_error
		storage.frames[index] = {}
		storage.frame_count -= 1
	}
	return nil
}

@(private)
free_storage :: proc(storage: ^evaluator_storage) -> runtime.Allocator_Error {
	if len(storage.memory) == 0 do return nil
	free_error := runtime.mem_free_bytes(storage.memory, storage.allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
	storage.memory = nil
	storage.frames = nil
	return nil
}

@(private)
retire_pending_memory :: proc(storage: ^evaluator_storage) -> runtime.Allocator_Error {
	if len(storage.temporary_memory) > 0 {
		free_error := runtime.mem_free_bytes(storage.temporary_memory, storage.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
		storage.temporary_memory = nil
	}
	if len(storage.retired_memory) > 0 {
		free_error := runtime.mem_free_bytes(storage.retired_memory, storage.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
		storage.retired_memory = nil
	}
	return nil
}

@(private)
retain_runtime_error :: proc(
	storage: ^evaluator_storage,
	err: Runtime_Error,
) -> runtime.Allocator_Error {
	assert(len(storage.runtime_error.key) == 0)
	if len(err.key) == 0 {
		storage.runtime_error = err
		storage.runtime_error.key = ""
		return nil
	}
	memory, allocation_error := runtime.mem_alloc_bytes(
		len(err.key),
		1,
		storage.allocator,
	)
	if allocation_error != nil || len(memory) != len(err.key) {
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, storage.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				storage.temporary_memory = memory
				return free_error
			}
		}
		return allocation_error if allocation_error != nil else .Out_Of_Memory
	}
	copy(memory, transmute([]byte)err.key)
	storage.runtime_error = err
	storage.runtime_error.key = transmute(string)memory
	return nil
}

@(private)
release_runtime_error :: proc(storage: ^evaluator_storage) -> runtime.Allocator_Error {
	if len(storage.runtime_error.key) > 0 {
		free_error := runtime.mem_free_bytes(
			transmute([]byte)storage.runtime_error.key,
			storage.allocator,
		)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
	}
	storage.runtime_error = {}
	return nil
}

@(private)
grow_frames :: proc(storage: ^evaluator_storage) -> runtime.Allocator_Error {
	cleanup_error := retire_pending_memory(storage)
	if cleanup_error != nil do return cleanup_error
	old_capacity := len(storage.frames)
	if old_capacity <= 0 || old_capacity > max(int)/2 do return .Out_Of_Memory
	new_capacity := old_capacity*2
	if new_capacity > max(int)/int(size_of(eval_frame)) do return .Out_Of_Memory
	byte_count := new_capacity*int(size_of(eval_frame))
	replacement, allocation_error := runtime.mem_alloc_bytes(
		byte_count,
		align_of(eval_frame),
		storage.allocator,
	)
	if allocation_error != nil || len(replacement) != byte_count {
		if len(replacement) > 0 {
			free_error := runtime.mem_free_bytes(replacement, storage.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				storage.temporary_memory = replacement
				return free_error
			}
		}
		return allocation_error if allocation_error != nil else .Out_Of_Memory
	}

	new_frames := (cast([^]eval_frame)raw_data(replacement))[:new_capacity]
	for index in 0..<new_capacity do new_frames[index] = {}
	for index in 0..<storage.frame_count do new_frames[index] = storage.frames[index]
	old_memory := storage.memory
	free_error := runtime.mem_free_bytes(old_memory, storage.allocator)
	storage.memory = replacement
	storage.frames = new_frames
	if free_error != nil && free_error != .Mode_Not_Implemented {
		storage.retired_memory = old_memory
		return free_error
	}
	return nil
}

@(private)
output_needs_frame :: proc(storage: ^evaluator_storage, producer: int) -> bool {
	current := producer
	for current >= 0 {
		parent := storage.frames[current].parent
		if parent < 0 do return false
		phase := storage.frames[parent].phase
		if phase == .Sequence_Left_Active || phase == .Field_Child_Active || phase == .Index_Child_Active || phase == .Binary_Left_Active || phase == .If_Condition_Active || phase == .If_Then_Active || phase == .If_Else_Active do return true
		current = parent
	}
	return false
}

@(private)
prepare_output :: proc(storage: ^evaluator_storage, producer: int) -> runtime.Allocator_Error {
	if !output_needs_frame(storage, producer) || storage.frame_count < len(storage.frames) do return nil
	return grow_frames(storage)
}

@(private)
terminal_step :: proc(storage: ^evaluator_storage) -> Step_Result {
	switch storage.pending_terminal {
	case .Done:
		return {kind = .Done}
	case .Runtime:
		return {kind = .Runtime_Error, runtime_error = storage.runtime_error}
	case .Misuse:
		return misuse_step(storage.misuse)
	case .Destroy, .None:
		return misuse_step(.Invalid_Evaluator)
	}
	return misuse_step(.Invalid_Evaluator)
}

@(private)
complete_terminal_cleanup :: proc(storage: ^evaluator_storage) -> Step_Result {
	free_error := retire_pending_memory(storage)
	if free_error != nil do return resource_step(free_error)
	free_error = retire_pending_constructor_error(storage)
	if free_error != nil do return resource_step(free_error)
	free_error = value.destroy_value(&storage.pending_value)
	if free_error != nil do return resource_step(free_error)
	free_error = destroy_frames_to(storage, 0)
	if free_error != nil do return resource_step(free_error)
	// Terminal diagnostics live outside the frame arena. Keep them byte-for-byte
	// intact until that independently fallible arena retirement succeeds: a
	// destroy retry may otherwise erase the result that step_evaluator must
	// replay after a later successful storage free.
	free_error = free_storage(storage)
	if free_error != nil do return resource_step(free_error)
	if storage.pending_terminal != .Runtime {
		free_error = release_runtime_error(storage)
		if free_error != nil do return resource_step(free_error)
	}
	storage.compiled = nil
	storage.pending = .None
	storage.state = .Terminal
	return terminal_step(storage)
}

@(private)
begin_terminal :: proc(
	storage: ^evaluator_storage,
	kind: terminal_kind,
) -> Step_Result {
	storage.pending_terminal = kind
	storage.pending = .Terminal_Cleanup
	return complete_terminal_cleanup(storage)
}

@(private)
notify_exhausted :: proc(storage: ^evaluator_storage, parent: int) -> bool {
	if parent < 0 do return true
	frame := &storage.frames[parent]
	instruction, ok := program.program_instruction(storage.compiled, frame.instruction)
	if !ok || !resumed_composite_instruction_valid(storage, frame, instruction) do return false
	#partial switch frame.phase {
	case .Unary_Active:
		if instruction.opcode == .First {
			frame.phase = .First_Empty
		} else if instruction.opcode == .Last {
			frame.phase = .Last_Result if frame.selected_seen else .Last_Empty
		} else {
			frame.phase = .Complete
		}
		case .Add_Active:
			frame.phase = .Add_Result if frame.add_seen else .Add_Empty
	case .Add_Result, .Add_Empty:
			// Finalization is handled by the consumer loop.
	case .Limit_Active, .Skip_Active, .Nth_Active:
		frame.phase = .Complete
	case .Map_Child_Active:
		frame.phase = .Map_Start
	case .Try_Expression_Active, .Try_Catch_Active:
		frame.phase = .Complete
	case .Fork_Left_Active:
		frame.phase = .Fork_Start_Right
	case .Fork_Right_Active:
		frame.phase = .Complete
	case .Sequence_Left_Active:
		frame.phase = .Complete
	case .Sequence_Right_Active:
		frame.phase = .Sequence_Left_Active
	case .Field_Child_Active:
		frame.phase = .Complete
	case .Field_Result_Active:
		frame.phase = .Field_Child_Active
	case .Index_Child_Active:
		frame.phase = .Complete
	case .Index_Result_Active:
		frame.phase = .Index_Child_Active
	case .Slice_Child_Active:
		frame.phase = .Complete
	case .Slice_Result_Active:
		frame.phase = .Slice_Child_Active
	case .Iterator_Active:
		frame.phase = .Complete
	case .Binary_Left_Active:
		frame.phase = .Complete
	case .Binary_Right_Active:
		_ = value.destroy_value(&frame.binary_left)
		frame.phase = .Binary_Left_Active
	case .If_Condition_Active:
		if frame.if_branch_active {
			frame.if_branch_active = false
			frame.phase = .If_Condition_Active
		} else {
			frame.phase = .Complete
		}
	case .If_Then_Active, .If_Else_Active:
		frame.if_branch_active = false
		frame.phase = .If_Condition_Active
	case .Binding_Left_Active:
		frame.phase = .Complete
	case .Binding_Body_Active:
		frame.phase = .Binding_Left_Active
	case .Constructor_Child_Active:
		// A constructor child has completed its complete generator stream.
		// An empty stream makes the whole constructor empty; otherwise retain
		// the materialized child stream and advance to the next operand.
		current_length, current_ok := value.array_length(&frame.constructor_current)
		if !current_ok do return false
		if current_length == 0 && instruction.opcode == .Object {
			frame.phase = .Complete
			return true
		}
		_, append_error := value.array_append_take(
			&frame.constructor_results,
			&frame.constructor_current,
		)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_array_error(&append_error)
			return false
		}
		frame.constructor_child += 1
		child_count := int(instruction.operands_count)
		if instruction.opcode == .Object do child_count /= 2
		if frame.constructor_child >= child_count {
			frame.constructor_total = 1
			if instruction.opcode == .Array {
				// Array constructors collect every output from every child into
				// one array; they do not Cartesian-expand stream elements.
				frame.constructor_total = 1
			} else {
			for child_index in 0..<child_count {
				child_stream, child_ok := value.array_element_copy(
					&frame.constructor_results,
					child_index,
				)
				if !child_ok do return false
				length, length_ok := value.array_length(&child_stream)
				_ = value.destroy_value(&child_stream)
				if !length_ok || length <= 0 do return false
				if u64(length) > max(u64)/frame.constructor_total do return false
				frame.constructor_total *= u64(length)
				key_stream, key_ok := value.array_element_copy(&frame.constructor_key_results, child_index)
				if !key_ok do return false
				key_length, key_length_ok := value.array_length(&key_stream)
				_ = value.destroy_value(&key_stream)
				if !key_length_ok || key_length <= 0 || u64(key_length) > max(u64)/frame.constructor_total do return false
				frame.constructor_total *= u64(key_length)
			}
			}
			frame.phase = .Constructor_Emit
		} else {
			frame.phase = .Constructor_Start
		}
	case:
		frame.phase = .Complete
	}
	return true
}

@(private)
finish_top_frame :: proc(storage: ^evaluator_storage) -> (runtime.Allocator_Error, bool) {
	assert(storage.frame_count > 0)
	index := storage.frame_count-1
	parent := storage.frames[index].parent
	free_error := value.destroy_value(&storage.frames[index].input)
	if free_error != nil do return free_error, true
	free_error = constructor_frame_destroy(&storage.frames[index])
	if free_error != nil do return free_error, true
	free_error = value.destroy_value(&storage.frames[index].binary_left)
	if free_error != nil do return free_error, true
	free_error = value.destroy_value(&storage.frames[index].add_accumulator)
	if free_error != nil do return free_error, true
	storage.frames[index] = {}
	storage.frame_count -= 1
	return nil, notify_exhausted(storage, parent)
}

@(private)
find_optional_ancestor :: proc(
	storage: ^evaluator_storage,
	producer: int,
) -> (int, bool) {
	current := storage.frames[producer].parent
	for current >= 0 {
		frame := &storage.frames[current]
		instruction, ok := program.program_instruction(
			storage.compiled,
			frame.instruction,
		)
		if !ok || !resumed_composite_instruction_valid(storage, frame, instruction) {
			return -1, false
		}
		if frame.mode == .Normal && instruction.opcode == .Optional &&
		   frame.phase == .Unary_Active {
			storage.suppress_try = false
			return current, true
		}
		if frame.mode == .Normal && instruction.opcode == .Try && frame.phase == .Try_Expression_Active {
			storage.suppress_try = true
			return current, true
		}
		current = frame.parent
	}
	return -1, true
}

@(private)
continue_suppression :: proc(storage: ^evaluator_storage) -> (Step_Result, bool) {
	frame := &storage.frames[storage.suppress_at]
	instruction, ok := program.program_instruction(storage.compiled, frame.instruction)
	if !ok || !resumed_composite_instruction_valid(storage, frame, instruction) {
		storage.misuse = .Malformed_Program
		storage.pending_terminal = .Misuse
		storage.pending = .Terminal_Cleanup
		return complete_terminal_cleanup(storage), true
	}
	free_error := destroy_frames_to(storage, storage.suppress_at+1)
	if free_error != nil do return resource_step(free_error), true
	if storage.suppress_try {
		message := storage.runtime_error.key
		catch_instruction, child_ok := child_instruction(storage, instruction, 1)
		catch_value: value.Value
		if value.kind_of(&storage.pending_value) != .Invalid {
			catch_value = storage.pending_value
			storage.pending_value = {}
		} else {
			new_catch_value, value_error := value.string_value(message, storage.allocator)
			catch_value = new_catch_value
			if !child_ok || value.constructor_error_kind(&value_error) != .None {
				_ = value.destroy_constructor_error(&value_error)
				return begin_terminal_misuse(storage, .Malformed_Program), true
			}
		}
		free_error = release_runtime_error(storage)
		if free_error != nil do return resource_step(free_error), true
		if storage.frame_count == len(storage.frames) {
			free_error = grow_frames(storage)
			if free_error != nil { _ = value.destroy_value(&catch_value); return resource_step(free_error), true }
		}
		parent := storage.suppress_at
		if !push_frame(storage, catch_instruction, parent, &catch_value) {
			_ = value.destroy_value(&catch_value)
			return begin_terminal_misuse(storage, .Malformed_Program), true
		}
		storage.frames[parent].phase = .Try_Catch_Active
		storage.pending = .None
		storage.suppress_try = false
		return {}, false
	}
	free_error = release_runtime_error(storage)
	if free_error != nil do return resource_step(free_error), true
	storage.frames[storage.suppress_at].phase = .Complete
	storage.pending = .None
	return {}, false
}

@(private)
raise_runtime :: proc(
	storage: ^evaluator_storage,
	producer: int,
	err: Runtime_Error,
) -> (Step_Result, bool) {
	target, continuation_ok := find_optional_ancestor(storage, producer)
	if !continuation_ok {
		return begin_terminal_misuse(storage, .Malformed_Program), true
	}
	retain_error := retain_runtime_error(storage, err)
	if retain_error != nil do return resource_step(retain_error), true
	if target >= 0 {
		if err.kind == .User_Error && len(err.key) == 0 {
			pending := value.clone_value(&storage.frames[producer].input)
			if value.kind_of(&pending) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program), true
			storage.pending_value = pending
		}
		storage.pending = .Suppress_Runtime
		storage.suppress_at = target
		return continue_suppression(storage)
	}
	return begin_terminal(storage, .Runtime), true
}

@(private)
propagate_output :: proc(
	storage: ^evaluator_storage,
	producer: int,
	owned: ^value.Value,
) -> (Step_Result, bool) {
	current := producer
	for {
		parent := storage.frames[current].parent
		if parent < 0 {
			return Step_Result{kind = .Output, output = value.take_value(owned)}, true
		}
		frame := &storage.frames[parent]
		instruction, instruction_ok := program.program_instruction(
			storage.compiled, frame.instruction,
		)
		if !instruction_ok ||
		   !resumed_composite_instruction_valid(storage, frame, instruction) {
			return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
		}
		#partial switch frame.phase {
		case .Unary_Active:
			if instruction.opcode == .Negate {
				number, number_ok := value.number_value_get(owned)
				if !number_ok {
					input_kind := value.kind_of(owned)
					key, key_error := negate_type_error_runtime_key(owned, storage.allocator)
					if key_error != nil {
						_ = value.destroy_value(owned)
						return resource_step(key_error), true
					}
					_ = value.destroy_value(owned)
					err := Runtime_Error{kind=.Cannot_Number, input_kind=input_kind, span=instruction.span, key=key}
					result, ready := raise_runtime(storage, current, err)
					if len(key) > 0 {
						free_error := runtime.mem_free_bytes(transmute([]byte)key, storage.allocator)
						if free_error != nil do return resource_step(free_error), true
					}
					return result, ready
				}
				_ = value.destroy_value(owned)
				owned^ = value.number_value(-number)
			} else if instruction.opcode == .First {
				free_error := destroy_frames_to(storage, parent+1)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				frame.phase = .Complete
				current = parent
				continue
			} else if instruction.opcode == .Last {
				free_error := value.destroy_value(&frame.selected_value)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				frame.selected_value = value.take_value(owned)
				frame.selected_seen = true
				return {}, false
			}
			current = parent
		case .Add_Active:
			if frame.add_seen {
				result_value, add_error := value.value_add(&frame.add_accumulator, owned, storage.allocator)
				kind_error := value.value_add_error_kind(&add_error)
				_ = value.destroy_value(owned)
				if kind_error != .None {
					_ = value.destroy_value(&frame.add_accumulator)
					_ = value.destroy_value_add_error(&add_error)
					return begin_terminal_misuse(storage, .Malformed_Program), true
				}
				_ = value.destroy_value(&frame.add_accumulator)
				frame.add_accumulator = result_value
			} else {
				frame.add_accumulator = value.take_value(owned)
				frame.add_seen = true
			}
			return {}, false
		case .Limit_Active:
			if frame.limit_remaining == 0 {
				free_error := destroy_frames_to(storage, parent+1)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				frame.phase = .Complete
				_ = value.destroy_value(owned)
				current = parent
				continue
			}
			frame.limit_remaining -= 1
			if frame.limit_remaining == 0 {
				free_error := destroy_frames_to(storage, parent+1)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				frame.phase = .Complete
			}
			current = parent
			continue
		case .Skip_Active:
			if frame.limit_remaining > 0 {
				frame.limit_remaining -= 1
				free_error := value.destroy_value(owned)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				return {}, false
			}
			current = parent
			continue
		case .Nth_Active:
			if frame.limit_remaining > 0 {
				frame.limit_remaining -= 1
				free_error := value.destroy_value(owned)
				if free_error != nil {
					storage.pending_value = value.take_value(owned)
					return resource_step(free_error), true
				}
				return {}, false
			}
			free_error := destroy_frames_to(storage, parent+1)
			if free_error != nil {
				storage.pending_value = value.take_value(owned)
				return resource_step(free_error), true
			}
			frame.phase = .Complete
			current = parent
			continue
		case .Map_Child_Active:
			if frame.map_values_mode {
				if frame.map_value_seen {
					_ = value.destroy_value(owned)
					return {}, false
				}
				frame.map_value_seen = true
				if value.kind_of(&frame.input) == .Object {
					key := value.clone_value(&frame.pending_constructor_key)
					_, displaced, object_error := value.object_set_take(&frame.constructor_results, &key, owned)
					_ = value.destroy_value(&displaced)
					if value.object_error_kind(&object_error) != .None {
						frame.pending_constructor_key = value.take_value(&key)
						frame.pending_constructor_value = value.take_value(owned)
						retain_constructor_object_error(frame, &object_error)
						return resource_step(.Out_Of_Memory), true
					}
				} else {
					append_error: value.Array_Operation_Error
					_, append_error = value.array_append_take(&frame.constructor_results, owned)
					if value.array_error_kind(&append_error) != .None {
						frame.pending_constructor_value = value.take_value(owned)
						retain_constructor_array_error(frame, &append_error)
						return resource_step(.Out_Of_Memory), true
					}
				}
			} else {
				append_error: value.Array_Operation_Error
				_, append_error = value.array_append_take(&frame.constructor_results, owned)
				if value.array_error_kind(&append_error) != .None {
					frame.pending_constructor_value = value.take_value(owned)
					retain_constructor_array_error(frame, &append_error)
					return resource_step(.Out_Of_Memory), true
				}
			}
			return {}, false
		case .Try_Catch_Active, .Fork_Left_Active, .Fork_Right_Active:
			current = parent
		case .Try_Expression_Active:
			// A try expression may be a generator. Preserve the active phase for
			// subsequent outputs; notify_exhausted transitions it to Complete.
			current = parent
		case .Sequence_Left_Active:
			child, ok := child_instruction(storage, instruction, 1)
			if !ok || !push_frame(storage, child, parent, owned) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			}
			frame.phase = .Sequence_Right_Active
			return {}, false
		case .Sequence_Right_Active:
			current = parent
		case .If_Condition_Active:
			kind := value.kind_of(owned)
			truthy := kind != .Null
			if kind == .Boolean {
				truthy, _ = value.boolean_value_get(owned)
			}
			child, ok := child_instruction(storage, instruction, 1 if truthy else 2)
			input_copy := value.clone_value(&frame.input)
			_ = value.destroy_value(owned)
			if !ok || value.kind_of(&input_copy) == .Invalid || !push_frame(storage, child, parent, &input_copy) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy), true
			}
			frame.if_branch_active = true
			frame.phase = .If_Then_Active if truthy else .If_Else_Active
			return {}, false
		case .If_Then_Active, .If_Else_Active:
			current = parent
		case .Field_Child_Active:
			_, field_ok := field_text(storage, instruction)
			mode := frame_mode.Field_Only
			if !field_ok || !push_frame(storage, frame.instruction, parent, owned, mode) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			}
			frame.phase = .Field_Result_Active
			return {}, false
		case .Field_Result_Active:
			current = parent
		case .Index_Child_Active:
			index_operand, index_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+1))
			if !index_ok || index_operand.kind != .Text || !push_frame(storage, frame.instruction, parent, owned, .Index_Only) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			}
			frame.phase = .Index_Result_Active
			return {}, false
	case .Index_Result_Active:
		current = parent
	case .Slice_Child_Active:
		if !push_frame(storage, frame.instruction, parent, owned, .Slice_Only) {
			return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
		}
		frame.phase = .Slice_Result_Active
		return {}, false
	case .Slice_Result_Active:
		current = parent
		case .Iterator_Active:
			current = parent
		case .Binary_Left_Active:
			if value.kind_of(&frame.binary_left) != .Invalid {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			}
			frame.binary_left = value.take_value(owned)
			child, ok := child_instruction(storage, instruction, 1)
			input_copy := value.clone_value(&frame.input)
			if !ok || value.kind_of(&input_copy) == .Invalid || !push_frame(storage, child, parent, &input_copy) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy), true
			}
			frame.phase = .Binary_Right_Active
			return {}, false
		case .Binary_Right_Active:
			result, runtime_kind, resource_error := apply_binary(instruction.opcode, &frame.binary_left, owned, instruction.operator_span, storage.allocator)
			if resource_error != nil {
				// The right result remains owned by this evaluator frame when the
				// operation cannot allocate. Preserve it for terminal cleanup;
				// otherwise the child frame's only owner would be lost.
				assert(value.kind_of(&storage.pending_value) == .Invalid)
				storage.pending_value = value.take_value(owned)
				_ = value.destroy_value(&frame.binary_left)
				return resource_step(resource_error), true
			}
			if runtime_kind != .None {
				owned_key := ""
					if runtime_kind == .Cannot_Divide || runtime_kind == .Cannot_Modulo {
					_, left_number_ok := value.number_value_get(&frame.binary_left)
					right_number, right_number_ok := value.number_value_get(owned)
					if left_number_ok && right_number_ok && right_number == 0 {
						key_error: runtime.Allocator_Error
						owned_key, key_error = binary_zero_divisor_runtime_key(
							&frame.binary_left,
							owned,
							runtime_kind == .Cannot_Modulo,
							storage.allocator,
						)
						if key_error != nil {
							assert(value.kind_of(&storage.pending_value) == .Invalid)
							storage.pending_value = value.take_value(owned)
							_ = value.destroy_value(&frame.binary_left)
							return resource_step(key_error), true
						}
					}
				}
				err := Runtime_Error{kind = runtime_kind, input_kind = value.kind_of(&frame.binary_left), span = instruction.operator_span, key = owned_key}
				if runtime_kind == .Cannot_Add || runtime_kind == .Cannot_Subtract {
					key_error: runtime.Allocator_Error
					operation := "added" if runtime_kind == .Cannot_Add else "subtracted"
					owned_key, key_error = binary_type_error_runtime_key(&frame.binary_left, owned, operation, storage.allocator)
					if key_error != nil {
						assert(value.kind_of(&storage.pending_value) == .Invalid)
						storage.pending_value = value.take_value(owned)
						_ = value.destroy_value(&frame.binary_left)
						return resource_step(key_error), true
					}
					err.key = owned_key
				}
				if runtime_kind == .Cannot_Multiply {
					left_kind := value.kind_of(&frame.binary_left)
					right_kind := value.kind_of(owned)
					text_value := &frame.binary_left if left_kind == .String else owned
					number_value := owned if left_kind == .String else &frame.binary_left
					if (left_kind == .String && right_kind == .Number) || (left_kind == .Number && right_kind == .String) {
						text, text_ok := value.string_borrowed(text_value)
						count, count_ok := value.number_value_get(number_value)
						if text_ok && count_ok && count > 100_000_000 {
							err.key = "Repeat string result too long"
						}
						if text_ok && count_ok && count > 0 && u64(len(text)) > 0 && count > f64(100_000_000 / u64(len(text))) {
							err.key = "Repeat string result too long"
						}
					}
				}
				_ = value.destroy_value(owned)
				result_step, ready := raise_runtime(storage, parent, err)
				if len(owned_key) > 0 {
					free_error := runtime.mem_free_bytes(transmute([]byte)owned_key, storage.allocator)
					if free_error != nil do return resource_step(free_error), true
				}
				return result_step, ready
			}
			_ = value.destroy_value(owned)
			return propagate_output(storage, parent, &result)
		case .Binding_Left_Active:
			// Each output of the bound expression starts the body with the
			// original input, while the yielded value becomes the nearest lexical
			// binding owned by this frame.
			if value.kind_of(owned) == .Invalid do return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			free_error := value.destroy_value(&frame.binding_value)
			if free_error != nil { storage.pending_value = value.take_value(owned); return resource_step(free_error), true }
			frame.binding_value = value.take_value(owned)
			body, body_ok := child_instruction(storage, instruction, 1)
			input_copy := value.clone_value(&frame.input)
			if !body_ok || value.kind_of(&input_copy) == .Invalid {
				_ = value.destroy_value(&input_copy)
				return begin_terminal_misuse(storage, .Malformed_Program), true
			}
			if storage.frame_count == len(storage.frames) {
				capacity_error := grow_frames(storage)
				if capacity_error != nil { _ = value.destroy_value(&input_copy); return resource_step(capacity_error), true }
				frame = &storage.frames[parent]
			}
			if !push_frame(storage, body, parent, &input_copy) {
				_ = value.destroy_value(&input_copy)
				return begin_terminal_misuse(storage, .Malformed_Program), true
			}
			frame = &storage.frames[parent]
			frame.phase = .Binding_Body_Active
			return {}, false
		case .Binding_Body_Active:
			current = parent
		case .Constructor_Child_Active:
			// Consume one output into the current child stream. The child frame
			// remains suspended at its yield point; its eventual exhaustion is
			// what advances the constructor to the next operand.
			_, append_error := value.array_append_take(
				&frame.constructor_current,
				owned,
			)
			if value.array_error_kind(&append_error) != .None {
				frame.constructor_pending_failure = true
				frame.pending_constructor_value = value.take_value(owned)
				if value.array_error_needs_cleanup(&append_error) {
					frame.pending_array_error = value.take_array_error(&append_error)
				} else {
					_ = value.destroy_array_error(&append_error)
				}
				return begin_terminal_misuse(storage, .Malformed_Program), true
			}
			return {}, false
		case:
			return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
		}
	}
}

@(private)
begin_terminal_misuse :: proc(
	storage: ^evaluator_storage,
	kind: Misuse_Kind,
) -> Step_Result {
	storage.misuse = kind
	return begin_terminal(storage, .Misuse)
}

@(private)
begin_terminal_misuse_owned :: proc(
	storage: ^evaluator_storage,
	kind: Misuse_Kind,
	owned: ^value.Value,
) -> Step_Result {
	assert(value.kind_of(&storage.pending_value) == .Invalid)
	storage.pending_value = value.take_value(owned)
	return begin_terminal_misuse(storage, kind)
}

@(private)
is_binary_opcode :: proc(opcode: program.Opcode) -> bool {
	#partial switch opcode {
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Pow, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return true
	}
	return false
}

@(private)
utf8_codepoint_length :: proc(text: string) -> int {
	count := 0
	for i in 0..<len(text) {
		// Continuation bytes belong to the preceding codepoint. Counting
		// leading bytes matches jq's Unicode character length.
		if (text[i] & 0xc0) != 0x80 do count += 1
	}
	return count
}

@(private)
utf8_codepoint_offset :: proc(text: string, byte_offset: int) -> int {
	count := 0
	limit := min(byte_offset, len(text))
	for i in 0..<limit {
		if (text[i] & 0xc0) != 0x80 do count += 1
	}
	return count
}

@(private)
utf8_byte_offset_for_codepoint :: proc(text: string, codepoint_index: int) -> int {
	if codepoint_index <= 0 do return 0
	count, at := 0, 0
	for count < codepoint_index && at < len(text) {
		at, _ = utf8_trim_next(text, at)
		count += 1
	}
	return at
}

@(private)
utf8_trim_next :: proc(text: string, at: int) -> (next: int, codepoint: u32) {
	first := u8(text[at])
	width := 1
	codepoint = u32(first)
	if first&0xe0 == 0xc0 { width, codepoint = 2, u32(first&0x1f) }
	else if first&0xf0 == 0xe0 { width, codepoint = 3, u32(first&0x0f) }
	else if first&0xf8 == 0xf0 { width, codepoint = 4, u32(first&0x07) }
	if at+width > len(text) do return at+1, u32(first)
	for offset in 1..<width {
		continuation := u8(text[at+offset])
		if continuation&0xc0 != 0x80 do return at+1, u32(first)
		codepoint = codepoint<<6 | u32(continuation&0x3f)
	}
	return at+width, codepoint
}

@(private)
unicode_whitespace :: proc(codepoint: u32) -> bool {
	return (codepoint >= 0x0009 && codepoint <= 0x000d) || codepoint == 0x0020 ||
		codepoint == 0x0085 || codepoint == 0x00a0 || codepoint == 0x1680 ||
		(codepoint >= 0x2000 && codepoint <= 0x200a) || codepoint == 0x2028 ||
		codepoint == 0x2029 || codepoint == 0x202f || codepoint == 0x205f ||
		codepoint == 0x3000
}

@(private)
unique_result :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	length, ok := value.array_length(input)
	if !ok do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	for i in 0..<length {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		next, next_error := value.array_value(allocator)
		if value.array_error_kind(&next_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		inserted := false
		duplicate := false
		current_length, current_ok := value.array_length(&result)
		if !current_ok { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		for j in 0..<current_length {
			existing, existing_ok := value.array_element_copy(&result, j)
			if !existing_ok { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			if !inserted {
				cmp, cmp_ok := compare_values(&item, &existing)
				if !cmp_ok { _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
				if cmp == 0 { duplicate = true }
				if !duplicate && cmp < 0 {
					copy_item := value.clone_value(&item)
					_, append_error := value.array_append_take(&next, &copy_item)
					if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&copy_item); _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
					inserted = true
				}
			}
			// Existing values are always retained. `duplicate` only suppresses
			// insertion of the incoming item; dropping the remainder here would
			// incorrectly turn [1, 1, 2] into [1].
			_, append_error := value.array_append_take(&next, &existing)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		if !duplicate && !inserted {
			_, append_error := value.array_append_take(&next, &item)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		} else { _ = value.destroy_value(&item) }
		_ = value.destroy_value(&result)
		result = next
	}
	return result, .None, nil
}

@(private)
sort_result :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	length, ok := value.array_length(input)
	if !ok do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	for i in 0..<length {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		next, next_error := value.array_value(allocator)
		if value.array_error_kind(&next_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		inserted := false
		current_length, current_ok := value.array_length(&result)
		if !current_ok { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		for j in 0..<current_length {
			existing, existing_ok := value.array_element_copy(&result, j)
			if !existing_ok { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			if !inserted {
				cmp, cmp_ok := compare_values(&item, &existing)
				if !cmp_ok { _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
				if cmp < 0 {
					copy_item := value.clone_value(&item)
					_, append_error := value.array_append_take(&next, &copy_item)
					if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&copy_item); _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
					inserted = true
				}
			}
			_, append_error := value.array_append_take(&next, &existing)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&existing); _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		if !inserted {
			_, append_error := value.array_append_take(&next, &item)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&next); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		} else { _ = value.destroy_value(&item) }
		_ = value.destroy_value(&result)
		result = next
	}
	return result, .None, nil
}

@(private)
flatten_append :: proc(input: ^value.Value, output: ^value.Value) -> (Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) == .Array {
		length, ok := value.array_length(input)
		if !ok do return .Cannot_Iterate, nil
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok do return .Cannot_Iterate, nil
			runtime_kind, allocator_error := flatten_append(&item, output)
			_ = value.destroy_value(&item)
			if runtime_kind != .None || allocator_error != nil do return runtime_kind, allocator_error
		}
		return .None, nil
	}
	item := value.clone_value(input)
	if value.kind_of(&item) == .Invalid do return .None, .Out_Of_Memory
	_, append_error := value.array_append_take(output, &item)
	if value.array_error_kind(&append_error) != .None {
		_ = value.destroy_value(&item)
		_ = value.destroy_array_error(&append_error)
		return .None, .Out_Of_Memory
	}
	return .None, nil
}

@(private)
flatten_append_depth :: proc(input: ^value.Value, output: ^value.Value, depth: int) -> (Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) == .Array && depth != 0 {
		length, ok := value.array_length(input)
		if !ok do return .Cannot_Iterate, nil
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok do return .Cannot_Iterate, nil
			next_depth := depth
			if next_depth > 0 do next_depth -= 1
			runtime_kind, allocator_error := flatten_append_depth(&item, output, next_depth)
			_ = value.destroy_value(&item)
			if runtime_kind != .None || allocator_error != nil do return runtime_kind, allocator_error
		}
		return .None, nil
	}
	item := value.clone_value(input)
	if value.kind_of(&item) == .Invalid do return .None, .Out_Of_Memory
	_, append_error := value.array_append_take(output, &item)
	if value.array_error_kind(&append_error) != .None {
		_ = value.destroy_value(&item)
		_ = value.destroy_array_error(&append_error)
		return .None, .Out_Of_Memory
	}
	return .None, nil
}

@(private)
flatten_result :: proc(input: ^value.Value, allocator: runtime.Allocator, depth: int = -1) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	// -1 is the internal sentinel for zero-argument flatten. Literal negative
	// depths are rejected until jq's dedicated diagnostic contract is added.
	if depth < -1 do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	runtime_kind: Runtime_Error_Kind
	allocator_error: runtime.Allocator_Error
	if depth < 0 {
		runtime_kind, allocator_error = flatten_append(input, &result)
	} else {
		length, length_ok := value.array_length(input)
		if !length_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			runtime_kind, allocator_error = flatten_append_depth(&item, &result, depth)
			_ = value.destroy_value(&item)
			if runtime_kind != .None || allocator_error != nil { break }
		}
	}
	if runtime_kind != .None || allocator_error != nil { _ = value.destroy_value(&result); return {}, runtime_kind, allocator_error }
	return result, .None, nil
}

@(private)
join_result :: proc(input: ^value.Value, separator: string, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	length, ok := value.array_length(input)
	if !ok do return {}, .Cannot_Iterate, nil
	builder: strings.Builder
	_, builder_error := strings.builder_init(&builder, allocator)
	if builder_error != nil do return {}, .None, .Out_Of_Memory
	for i in 0..<length {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok { strings.builder_destroy(&builder); return {}, .Cannot_Iterate, nil }
		if i > 0 && strings.write_string(&builder, separator) != len(separator) {
			_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory
		}
		if value.kind_of(&item) == .Null {
			_ = value.destroy_value(&item)
			continue
		}
		item_kind := value.kind_of(&item)
		text: string
		text_ok := true
		direct_number_spelling := ""
		if item_kind == .String {
			text, text_ok = value.string_borrowed(&item)
		} else if item_kind == .Boolean {
			boolean, boolean_ok := value.boolean_value_get(&item)
			text = "true" if boolean else "false"
			text_ok = boolean_ok
		} else if item_kind == .Number {
			// Parsed jq literals retain their source spelling, which is also the
			// number spelling used by jq's join conversion.  Native numbers (for
			// example, values produced by arithmetic) use the fallback formatter;
			// its full dtoa parity remains outside this bounded lane.
			spelling, literal := value.literal_spelling_borrowed(&item)
			if literal {
				text = spelling
				// jq's number printer canonicalizes scientific notation. Keep
				// ordinary literal spellings borrowed, but defer exponent output
				// to the canonical writer below (notably 1e20 -> 1E+20).
				for c in spelling {
					if c == 'e' || c == 'E' {
						direct_number_spelling = spelling
						break
					}
				}
			} else {
				number, number_ok := value.number_value_get(&item)
				buffer: [64]byte
				text = strconv.write_float(buffer[:], number, 'f', -1, 64)
				text_ok = number_ok
			}
		} else {
			text_ok = false
		}
		if !text_ok {
			_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .Cannot_Iterate, nil
		}
		if len(direct_number_spelling) > 0 {
			e_at := 0
			for e_at < len(direct_number_spelling) &&
				direct_number_spelling[e_at] != 'e' && direct_number_spelling[e_at] != 'E' {
				e_at += 1
			}
			if strings.write_string(&builder, direct_number_spelling[:e_at]) != e_at {
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory
			}
			exponent := direct_number_spelling[e_at + 1:]
			exponent_sign := "+"
			if len(exponent) > 0 && exponent[0] == '-' {
				exponent_sign = "-"
				exponent = exponent[1:]
			}
			if strings.write_string(&builder, "E") != 1 ||
				strings.write_string(&builder, exponent_sign) != 1 {
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory
			}
			first_digit := 0
			for first_digit < len(exponent) - 1 && exponent[first_digit] == '0' {
				first_digit += 1
			}
			if strings.write_string(&builder, exponent[first_digit:]) != len(exponent) - first_digit {
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory
			}
		} else if strings.write_string(&builder, text) != len(text) {
			_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory
		}
		_ = value.destroy_value(&item)
	}
	result, constructor_error := value.string_value(strings.to_string(builder), allocator)
	strings.builder_destroy(&builder)
	if value.constructor_error_kind(&constructor_error) != .None do return {}, .None, .Out_Of_Memory
	return result, .None, nil
}

@(private)
join_type_error_runtime_key :: proc(input: ^value.Value, separator: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return "", nil
	length, length_ok := value.array_length(input)
	if !length_ok do return "", nil
	builder: strings.Builder
	_, builder_error := strings.builder_init(&builder, allocator)
	if builder_error != nil do return "", builder_error
	for i in 0..<length {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok { strings.builder_destroy(&builder); return "", nil }
		if i > 0 && strings.write_string(&builder, separator) != len(separator) {
			_ = value.destroy_value(&item); strings.builder_destroy(&builder); return "", nil
		}
		if value.kind_of(&item) == .Null {
			_ = value.destroy_value(&item)
			continue
		}
		item_kind := value.kind_of(&item)
		if item_kind == .String {
			text, text_ok := value.string_borrowed(&item)
			if !text_ok || strings.write_string(&builder, text) != len(text) {
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return "", nil
			}
			_ = value.destroy_value(&item)
			continue
		}
		if item_kind == .Boolean || item_kind == .Number {
			text, text_ok, text_error := text_coercion_text(&item, allocator)
			if text_error != nil { _ = value.destroy_value(&item); strings.builder_destroy(&builder); return "", text_error }
			if !text_ok || strings.write_string(&builder, text) != len(text) {
				_ = runtime.mem_free_bytes(transmute([]byte)text, allocator)
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return "", nil
			}
			free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
			_ = value.destroy_value(&item)
			if free_error != nil && free_error != .Mode_Not_Implemented { strings.builder_destroy(&builder); return "", free_error }
			continue
		}
		partial := strings.to_string(builder)
		left, constructor_error := value.string_value(partial, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)partial, allocator)
		if value.constructor_error_kind(&constructor_error) != .None || (free_error != nil && free_error != .Mode_Not_Implemented) {
			if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
			_ = value.destroy_value(&item)
			return "", free_error if free_error != nil else nil
		}
		key, key_error := binary_type_error_runtime_key(&left, &item, "added", allocator)
		_ = value.destroy_value(&left)
		_ = value.destroy_value(&item)
		return key, key_error
	}
	strings.builder_destroy(&builder)
	return "", nil
}

@(private)
contains_value :: proc(input, needle: ^value.Value, top_level := false) -> (bool, bool) {
	input_kind := value.kind_of(input)
	needle_kind := value.kind_of(needle)
	if input_kind == .String && needle_kind == .String {
		haystack, haystack_ok := value.string_borrowed(input)
		needle_text, needle_ok := value.string_borrowed(needle)
		return haystack_ok && needle_ok && strings.contains(haystack, needle_text), true
	}
	if input_kind == .Array && needle_kind == .Array {
		input_length, input_ok := value.array_length(input)
		needle_length, needle_ok := value.array_length(needle)
		if !input_ok || !needle_ok do return false, false
		for needle_index in 0..<needle_length {
			wanted, wanted_ok := value.array_element_copy(needle, needle_index)
			if !wanted_ok do return false, false
			found := false
			for input_index in 0..<input_length {
				actual, actual_ok := value.array_element_copy(input, input_index)
				if actual_ok {
					matches, comparable := contains_value(&actual, &wanted)
					_ = value.destroy_value(&actual)
					if !comparable { _ = value.destroy_value(&wanted); return false, false }
					if matches { found = true; break }
				}
			}
			_ = value.destroy_value(&wanted)
			if !found do return false, true
		}
		return true, true
	}
	if (input_kind == .Array || input_kind == .Object) && input_kind != needle_kind {
		return false, !top_level
	}
	if input_kind == .Object && needle_kind == .Object {
		length, length_ok := value.object_length(needle)
		if !length_ok do return false, false
		for index in 0..<length {
			key, wanted, entry_ok := value.object_entry_copy(needle, index)
			if !entry_ok { _ = value.destroy_value(&key); _ = value.destroy_value(&wanted); return false, false }
			key_text, key_ok := value.string_borrowed(&key)
			actual, found := value.object_get_copy(input, key_text)
			if !key_ok || !found {
				_ = value.destroy_value(&key); _ = value.destroy_value(&wanted); _ = value.destroy_value(&actual)
				return false, true
			}
			matches, comparable := contains_value(&actual, &wanted)
			_ = value.destroy_value(&key); _ = value.destroy_value(&wanted); _ = value.destroy_value(&actual)
			if !comparable do return false, false
			if !matches do return false, true
		}
		return true, true
	}
	return value.values_equal(input, needle), true
}

contains_result :: proc(input, needle: ^value.Value) -> (value.Value, Runtime_Error_Kind) {
	matched, comparable := contains_value(input, needle, true)
	if !comparable do return {}, .Cannot_Iterate
	return value.boolean_value(matched), .None
}

@(private)
has_result :: proc(input, argument: ^value.Value) -> (value.Value, Runtime_Error_Kind) {
	input_kind := value.kind_of(input)
	argument_kind := value.kind_of(argument)
	if input_kind == .Null do return value.boolean_value(false), .None
	if input_kind == .Object && argument_kind == .String {
		key, key_ok := value.string_borrowed(argument)
		if !key_ok do return {}, .Cannot_Iterate
		member, found := value.object_get_copy(input, key)
		_ = value.destroy_value(&member)
		return value.boolean_value(found), .None
	}
	if input_kind == .Array && argument_kind == .Number {
		index, index_ok := value.number_value_get(argument)
		if !index_ok || math.is_nan(index) || math.is_inf(index) || index < 0 {
			return value.boolean_value(false), .None
		}
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate
		return value.boolean_value(index < f64(length)), .None
	}
	return {}, .Cannot_Iterate
}

@(private)
bsearch_result :: proc(input, needle: ^value.Value) -> (value.Value, Runtime_Error_Kind) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate
	length, length_ok := value.array_length(input)
	if !length_ok do return {}, .Cannot_Iterate
	low, high := 0, length - 1
	for low <= high {
		// jq's bsearch probe chooses the upper midpoint on even-length
		// duplicate runs (for example, [1,1] -> 1 and [1,1,1,1] -> 2).
		middle := (low + high + 1) / 2
		item, item_ok := value.array_element_copy(input, middle)
		if !item_ok do return {}, .Cannot_Iterate
		comparison, comparison_ok := compare_values(&item, needle)
		_ = value.destroy_value(&item)
		if !comparison_ok do return {}, .Cannot_Iterate
		if comparison == 0 do return value.number_value(f64(middle)), .None
		if comparison < 0 { low = middle + 1 } else { high = middle - 1 }
	}
	return value.number_value(f64(-(low + 1))), .None
}

@(private)
literal_object_value :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
) -> (value.Value, value.Error, runtime.Allocator_Error) {
	result, object_error := value.object_value(storage.allocator)
	if value.object_error_kind(&object_error) != .None do return {}, .Out_Of_Memory, nil
	for offset := 0; offset < int(instruction.operands_count); offset += 2 {
		key_operand, key_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start) + u32(offset)))
		value_operand, value_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start) + u32(offset + 1)))
		if !key_ok || !value_ok || key_operand.kind != .Text || value_operand.kind != .Instruction {
			_ = value.destroy_value(&result)
			return {}, .Invalid_Number_Literal, nil
		}
		key_text, key_text_ok := program.operand_text(storage.compiled, key_operand)
		value_instruction, value_instruction_ok := program.program_instruction(storage.compiled, value_operand.instruction)
		if !key_text_ok || !value_instruction_ok {
			_ = value.destroy_value(&result)
			return {}, .Invalid_Number_Literal, nil
		}
		key, key_error := value.string_value(key_text, storage.allocator)
		if value.constructor_error_kind(&key_error) != .None {
			_ = value.destroy_value(&result)
			return {}, .Out_Of_Memory, nil
		}
		member: value.Value
		member_error: value.Error
		member_cleanup: runtime.Allocator_Error
		if value_instruction.opcode == .Object {
			member, member_error, member_cleanup = literal_object_value(storage, value_instruction)
		} else if value_instruction.opcode == .Array {
			member, member_error, member_cleanup = literal_array_value(storage, value_instruction)
		} else {
			member, member_error, member_cleanup = literal_value(storage, value_instruction)
		}
		if member_cleanup != nil || member_error != .None {
			_ = value.destroy_value(&key); _ = value.destroy_value(&result)
			return {}, member_error, member_cleanup
		}
		_, _, set_error := value.object_set_take(&result, &key, &member)
		if value.object_error_kind(&set_error) != .None {
			_ = value.destroy_value(&key); _ = value.destroy_value(&member); _ = value.destroy_value(&result)
			return {}, .Invalid_Number_Literal, nil
		}
	}
	return result, .None, nil
}

@(private)
literal_array_value :: proc(
	storage: ^evaluator_storage,
	instruction: program.Instruction,
) -> (value.Value, value.Error, runtime.Allocator_Error) {
	if instruction.opcode != .Array || instruction.operands_count > 1 {
		return {}, .Invalid_Number_Literal, nil
	}
	result, array_error := value.array_value(storage.allocator)
	if value.array_error_kind(&array_error) != .None {
		return {}, .Invalid_Number_Literal, nil
	}
	if instruction.operands_count == 0 {
		return result, .None, nil
	}
	child, child_ok := child_instruction(storage, instruction, 0)
	if !child_ok {
		_ = value.destroy_value(&result)
		return {}, .Invalid_Number_Literal, nil
	}
	if !literal_array_append_stream(storage, child, &result) {
		_ = value.destroy_value(&result)
		return {}, .Invalid_Number_Literal, nil
	}
	return result, .None, nil
}

@(private)
literal_array_append_stream :: proc(storage: ^evaluator_storage, index: program.Instruction_Index, output: ^value.Value) -> bool {
	instruction, instruction_ok := program.program_instruction(storage.compiled, index)
	if !instruction_ok do return false
	if instruction.opcode == .Fork {
		left, left_ok := child_instruction(storage, instruction, 0)
		right, right_ok := child_instruction(storage, instruction, 1)
		return left_ok && right_ok && literal_array_append_stream(storage, left, output) && literal_array_append_stream(storage, right, output)
	}
	item: value.Value
	item_error: value.Error
	item_cleanup: runtime.Allocator_Error
	if instruction.opcode == .Object {
		item, item_error, item_cleanup = literal_object_value(storage, instruction)
	} else if instruction.opcode == .Array {
		item, item_error, item_cleanup = literal_array_value(storage, instruction)
	} else {
		item, item_error, item_cleanup = literal_value(storage, instruction)
	}
	if item_error != .None || item_cleanup != nil do return false
	_, append_error := value.array_append_take(output, &item)
	if value.array_error_kind(&append_error) != .None {
		_ = value.destroy_value(&item)
		return false
	}
	return true
}

@(private)
prefix_result :: proc(input: ^value.Value, needle: string, opcode: program.Opcode) -> (value.Value, Runtime_Error_Kind) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate
	haystack, ok := value.string_borrowed(input)
	if !ok do return {}, .Cannot_Iterate
	matched := strings.has_prefix(haystack, needle) if opcode == .Startswith else strings.has_suffix(haystack, needle)
	return value.boolean_value(matched), .None
}

@(private)
trimstr_result :: proc(input: ^value.Value, needle: string, opcode: program.Opcode, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate, nil
	haystack, ok := value.string_borrowed(input)
	if !ok do return {}, .Cannot_Iterate, nil
	start, end := 0, len(haystack)
	if opcode == .Ltrimstr || opcode == .Trimstr {
		if strings.has_prefix(haystack, needle) do start = len(needle)
	}
	if opcode == .Rtrimstr || opcode == .Trimstr {
		if len(needle) == 0 {
			// jq's right-trimming family treats an empty suffix as matching the
			// whole input; ltrimstr(""), by contrast, is an identity filter.
			end = start
		} else if end >= start && strings.has_suffix(haystack[start:end], needle) do end -= len(needle)
	}
	result, err := value.string_value(haystack[start:end], allocator)
	if value.constructor_error_kind(&err) != .None do return {}, .None, .Out_Of_Memory
	return result, .None, nil
}

@(private)
split_result :: proc(input: ^value.Value, separator: string, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate, nil
	text, text_ok := value.string_borrowed(input)
	if !text_ok do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	if len(separator) == 0 {
		at := 0
		for at < len(text) {
			next, _ := utf8_trim_next(text, at)
			part, string_error := value.string_value(text[at:next], allocator)
			if value.constructor_error_kind(&string_error) != .None { _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			_, append_error := value.array_append_take(&result, &part)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&part); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			at = next
		}
		return result, .None, nil
	}
	// jq emits no segments when a non-empty separator is applied to an empty
	// string.
	if len(text) == 0 do return result, .None, nil
	start := 0
	for {
		relative := strings.index(text[start:], separator)
		end := len(text)
		if relative >= 0 do end = start + relative
		part, string_error := value.string_value(text[start:end], allocator)
		if value.constructor_error_kind(&string_error) != .None {
			_ = value.destroy_value(&result)
			return {}, .None, .Out_Of_Memory
		}
		_, append_error := value.array_append_take(&result, &part)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_value(&part)
			_ = value.destroy_value(&result)
			return {}, .None, .Out_Of_Memory
		}
		if relative < 0 do break
		start += relative + len(separator)
	}
	return result, .None, nil
}

@(private)
search_result :: proc(input: ^value.Value, needle: ^value.Value, opcode: program.Opcode, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	kind := value.kind_of(input)
	needle_kind := value.kind_of(needle)
	// jq's search builtins preserve null as null. Arrays compare literal needles
	// by JSON value; array needles match contiguous subarrays.
	if kind == .Null do return value.null_value(), .None, nil
	if kind == .Array {
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		if needle_kind == .Array {
			needle_length, needle_length_ok := value.array_length(needle)
			if !needle_length_ok do return {}, .Cannot_Iterate, nil
			if needle_length == 0 do return {}, .Cannot_Iterate, nil
			if needle_length > length {
				if opcode == .Indices_Builtin {
					result, array_error := value.array_value(allocator)
					if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
					return result, .None, nil
				}
				return value.null_value(), .None, nil
			}
			last_index := -1
			for start in 0..<(length - needle_length + 1) {
				matches := true
				for offset in 0..<needle_length {
					item, item_ok := value.array_element_copy(input, start + offset)
					wanted, wanted_ok := value.array_element_copy(needle, offset)
					if !item_ok || !wanted_ok || !value.values_equal(&item, &wanted) do matches = false
					_ = value.destroy_value(&item)
					_ = value.destroy_value(&wanted)
					if !matches do break
				}
				if matches {
					if opcode == .Index_Builtin do return value.number_value(f64(start)), .None, nil
					last_index = start
				}
			}
			if opcode == .Indices_Builtin {
				result, array_error := value.array_value(allocator)
				if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
				for start in 0..<(length - needle_length + 1) {
					matches := true
					for offset in 0..<needle_length {
						item, item_ok := value.array_element_copy(input, start + offset)
						wanted, wanted_ok := value.array_element_copy(needle, offset)
						if !item_ok || !wanted_ok || !value.values_equal(&item, &wanted) do matches = false
						_ = value.destroy_value(&item)
						_ = value.destroy_value(&wanted)
						if !matches do break
					}
					if matches {
						position := value.number_value(f64(start))
						_, append_error := value.array_append_take(&result, &position)
						if value.array_error_kind(&append_error) != .None {
							_ = value.destroy_value(&position)
							_ = value.destroy_value(&result)
							return {}, .None, .Out_Of_Memory
						}
					}
				}
				return result, .None, nil
			}
			if last_index < 0 do return value.null_value(), .None, nil
			return value.number_value(f64(last_index)), .None, nil
		}
		if opcode == .Indices_Builtin {
			result, array_error := value.array_value(allocator)
			if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
			for index in 0..<length {
				item, item_ok := value.array_element_copy(input, index)
				if !item_ok {
					_ = value.destroy_value(&result)
					return {}, .Cannot_Iterate, nil
				}
				matches := value.values_equal(&item, needle)
				_ = value.destroy_value(&item)
				if matches {
					position := value.number_value(f64(index))
					_, append_error := value.array_append_take(&result, &position)
					if value.array_error_kind(&append_error) != .None {
						_ = value.destroy_value(&position)
						_ = value.destroy_value(&result)
						return {}, .None, .Out_Of_Memory
					}
				}
			}
			return result, .None, nil
		}
		last_index := -1
		for index in 0..<length {
			item, item_ok := value.array_element_copy(input, index)
			if !item_ok do return {}, .Cannot_Iterate, nil
			matches := value.values_equal(&item, needle)
			_ = value.destroy_value(&item)
			if matches {
				if opcode == .Index_Builtin do return value.number_value(f64(index)), .None, nil
				last_index = index
			}
		}
		if last_index < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(last_index)), .None, nil
	}
	if kind != .String || needle_kind != .String do return {}, .Cannot_Iterate, nil
	needle_text, needle_text_ok := value.string_borrowed(needle)
	if !needle_text_ok do return {}, .Cannot_Iterate, nil
	text, text_ok := value.string_borrowed(input)
	if !text_ok do return {}, .Cannot_Iterate, nil
	// jq 1.8 treats an empty string needle as no match for string inputs.
	if len(needle_text) == 0 {
		if opcode == .Indices_Builtin {
			result, array_error := value.array_value(allocator)
			if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
			return result, .None, nil
		}
		return value.null_value(), .None, nil
	}
	if opcode == .Index_Builtin {
		position := strings.index(text, needle_text)
		if position < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(utf8_codepoint_offset(text, position))), .None, nil
	}
	if opcode == .Rindex_Builtin {
		position := strings.last_index(text, needle_text)
		if position < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(utf8_codepoint_offset(text, position))), .None, nil
	}
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	start := 0
	for start <= len(text) {
		relative := strings.index(text[start:], needle_text)
		if relative < 0 do break
		item := value.number_value(f64(utf8_codepoint_offset(text, start + relative)))
		_, append_error := value.array_append_take(&result, &item)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_value(&item)
			_ = value.destroy_value(&result)
			return {}, .None, .Out_Of_Memory
		}
		start += relative + 1
	}
	return result, .None, nil
}

@(private)
from_entries_member_copy :: proc(entry: ^value.Value, names: []string) -> (value.Value, bool) {
	for name in names {
		candidate, ok := value.object_get_copy(entry, name)
		if ok do return candidate, true
		if value.kind_of(&candidate) != .Invalid do _ = value.destroy_value(&candidate)
	}
	return {}, false
}

@(private)
base64_coercion_text :: proc(input: ^value.Value) -> (string, bool) {
	kind := value.kind_of(input)
	#partial switch kind {
	case .String:
		return value.string_borrowed(input)
	case .Null:
		return "null", true
	case .Boolean:
		boolean, ok := value.boolean_value_get(input)
		if !ok do return "", false
		return ("true" if boolean else "false"), true
	case .Number:
		spelling, literal := value.literal_spelling_borrowed(input)
		if literal do return spelling, true
		number, ok := value.number_value_get(input)
		if !ok do return "", false
		buffer: [64]byte
		return strconv.write_float(buffer[:], number, 'f', -1, 64), true
	}
	return "", false
}

@(private)
text_append_json_escaped :: proc(builder: ^strings.Builder, text: string) -> bool {
	if strings.write_byte(builder, '"') != 1 do return false
	hex := "0123456789abcdef"
	for b in transmute([]byte)text {
		switch b {
		case '"': if strings.write_string(builder, "\\\"") != 2 do return false
		case '\\': if strings.write_string(builder, "\\\\") != 2 do return false
		case '\b': if strings.write_string(builder, "\\b") != 2 do return false
		case '\f': if strings.write_string(builder, "\\f") != 2 do return false
		case '\n': if strings.write_string(builder, "\\n") != 2 do return false
		case '\r': if strings.write_string(builder, "\\r") != 2 do return false
		case '\t': if strings.write_string(builder, "\\t") != 2 do return false
		case:
			if b < 0x20 {
				encoded := [6]u8{'\\', 'u', '0', '0', hex[b >> 4], hex[b & 0xf]}
				if strings.write_string(builder, transmute(string)encoded[:]) != 6 do return false
			} else if strings.write_byte(builder, b) != 1 do return false
		}
	}
	return strings.write_byte(builder, '"') == 1
}

@(private)
text_append_json_number :: proc(builder: ^strings.Builder, text: string) -> bool {
	// Arithmetic can retain a leading plus in the internal literal spelling;
	// jq's textual JSON forms never expose that unary sign.
	normalized_text := text[1:] if len(text) > 0 && text[0] == '+' else text
	exponent_at := -1
	for index := 0; index < len(normalized_text); index += 1 {
		b := normalized_text[index]
		if b == 'e' || b == 'E' { exponent_at = index; break }
	}
	if exponent_at < 0 do return strings.write_string(builder, normalized_text) == len(normalized_text)
	if strings.write_string(builder, normalized_text[:exponent_at]) != exponent_at do return false
	if strings.write_byte(builder, 'E') != 1 do return false
	exponent := normalized_text[exponent_at+1:]
	if len(exponent) == 0 do return false
	if exponent[0] != '+' && exponent[0] != '-' {
		if strings.write_byte(builder, '+') != 1 do return false
	}
	return strings.write_string(builder, exponent) == len(exponent)
}

@(private)
text_append_json_value :: proc(builder: ^strings.Builder, input: ^value.Value) -> bool {
	kind := value.kind_of(input)
	switch kind {
	case .Invalid:
		return false
	case .Null:
		return strings.write_string(builder, "null") == 4
	case .Boolean:
		boolean, ok := value.boolean_value_get(input)
		if !ok do return false
		return strings.write_string(builder, "true" if boolean else "false") == (4 if boolean else 5)
	case .Number:
		spelling, literal := value.literal_spelling_borrowed(input)
		if literal do return text_append_json_number(builder, spelling)
		number, ok := value.number_value_get(input)
		if !ok do return false
		if math.is_nan(number) do return strings.write_string(builder, "null") == 4
		if math.is_inf(number) {
			text := "-1.7976931348623157e+308" if number < 0 else "1.7976931348623157e+308"
			return strings.write_string(builder, text) == len(text)
		}
		buffer: [64]byte
		formatted := strconv.write_float(buffer[:], number, 'f', -1, 64)
		normalized_formatted := formatted[1:] if len(formatted) > 0 && formatted[0] == '+' else formatted
		return strings.write_string(builder, normalized_formatted) == len(normalized_formatted)
	case .String:
		text, ok := value.string_borrowed(input)
		if !ok do return false
		return text_append_json_escaped(builder, text)
	case .Array:
		length, ok := value.array_length(input)
		if !ok || strings.write_byte(builder, '[') != 1 do return false
		for index in 0..<length {
			if index > 0 && strings.write_byte(builder, ',') != 1 do return false
			item, item_ok := value.array_element_copy(input, index)
			if !item_ok do return false
			item_ok = text_append_json_value(builder, &item)
			_ = value.destroy_value(&item)
			if !item_ok do return false
		}
		return strings.write_byte(builder, ']') == 1
	case .Object:
		if strings.write_byte(builder, '{') != 1 do return false
		iterator := value.object_iterator()
		index := 0
		for {
			key, item, found := value.object_iter_next_copy(input, &iterator)
			if !found do break
			if index > 0 && strings.write_byte(builder, ',') != 1 {
				_ = value.destroy_value(&key); _ = value.destroy_value(&item); return false
			}
			key_text, key_ok := value.string_borrowed(&key)
			if !key_ok || !text_append_json_escaped(builder, key_text) || strings.write_byte(builder, ':') != 1 {
				_ = value.destroy_value(&key); _ = value.destroy_value(&item); return false
			}
			_ = value.destroy_value(&key)
			item_ok := text_append_json_value(builder, &item)
			_ = value.destroy_value(&item)
			if !item_ok do return false
			index += 1
		}
		return strings.write_byte(builder, '}') == 1
	}
	return false
}

@(private)
text_coercion_text :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, bool, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", false, init_error
	if !text_append_json_value(&builder, input) {
		strings.builder_destroy(&builder)
		return "", false, nil
	}
	return strings.to_string(builder), true, nil
}

@(private)
runtime_value_kind_name :: proc(kind: value.Kind) -> string {
	#partial switch kind {
	case .Null: return "null"
	case .Boolean: return "boolean"
	case .Number: return "number"
	case .String: return "string"
	case .Array: return "array"
	case .Object: return "object"
	}
	return "invalid"
}

// jq preserves the typed iterator failure as the catch value. Keep the
// rendered input owned by the Runtime_Error transport so try/catch receives
// `Cannot iterate over number (123)` (rather than an empty placeholder).
cannot_iterate_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	text, text_ok, text_error := text_coercion_text(input, allocator)
	if text_error != nil || !text_ok {
		return "", text_error
	}
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil {
		if len(text) > 0 { _ = runtime.mem_free_bytes(transmute([]byte)text, allocator) }
		return "", init_error
	}
	kind := runtime_value_kind_name(value.kind_of(input))
	if strings.write_string(&builder, "Cannot iterate over ") != len("Cannot iterate over ") ||
	   strings.write_string(&builder, kind) != len(kind) ||
	   strings.write_string(&builder, " (") != 2 ||
	   strings.write_string(&builder, text) != len(text) ||
	   strings.write_byte(&builder, ')') != 1 {
		strings.builder_destroy(&builder)
		if len(text) > 0 { _ = runtime.mem_free_bytes(transmute([]byte)text, allocator) }
		return "", nil
	}
	if len(text) > 0 {
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			strings.builder_destroy(&builder)
			return "", free_error
		}
	}
	return strings.to_string(builder), nil
}

@(private)
fromjson_parse_runtime_key :: proc(
	err: json.Scalar_Parse_Error,
	text: string,
	allocator: runtime.Allocator,
) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	column_buffer: [32]byte
	column := strconv.write_int(column_buffer[:], i64(err.detection_offset+1), 10)
	prefix := "Invalid JSON text at line 1, column "
	if err.kind == .Invalid_Number {
		prefix = "Invalid numeric literal at EOF at line 1, column "
	} else if err.kind == .Object_Keys_Must_Be_Strings {
		prefix = "Object keys must be strings at line 1, column "
	}
	// jq diagnoses a quoted object key with the string scanner's wording,
	// even though the container parser reports the key-type boundary.
	if len(text) > 1 && text[0] == '{' && text[1] == '\'' {
		prefix = "Invalid string literal; expected \", but got ' at line 1, column "
	}
	if strings.write_string(&builder, prefix) != len(prefix) ||
	   strings.write_string(&builder, column) != len(column) ||
	   strings.write_string(&builder, " (while parsing '") != len(" (while parsing '") ||
	   strings.write_string(&builder, text) != len(text) ||
	   strings.write_string(&builder, "')") != 2 {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

@(private)
fromjson_result :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (
	value.Value,
	Runtime_Error_Kind,
	runtime.Allocator_Error,
	string,
) {
	if value.kind_of(input) != .String do return {}, .Cannot_Number, nil, ""
	text, text_ok := value.string_borrowed(input)
	if !text_ok do return {}, .Cannot_Number, nil, ""
	start := 0
	end := len(text)
	for start < end && (text[start] == ' ' || text[start] == '\t' || text[start] == '\n' || text[start] == '\r') do start += 1
	for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\n' || text[end-1] == '\r') do end -= 1
	text = text[start:end]
	result, parse_error := json.parse_value(text, allocator)
	if parse_error.kind != .None {
		if value.kind_of(&result) != .Invalid do _ = value.destroy_value(&result)
		key, key_error := fromjson_parse_runtime_key(parse_error, text, allocator)
		return {}, .User_Error, key_error, key
	}
	return result, .None, nil, ""
}

@(private)
toboolean_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	kind := value.kind_of(input)
	if strings.write_string(&builder, runtime_value_kind_name(kind)) != len(runtime_value_kind_name(kind)) ||
	   strings.write_string(&builder, " (") != 2 ||
	   !text_append_json_value(&builder, input) ||
	   strings.write_string(&builder, ") cannot be parsed as a boolean") != len(") cannot be parsed as a boolean") {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

@(private)
utf8bytelength_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	kind_name := runtime_value_kind_name(value.kind_of(input))
	suffix := " only strings have UTF-8 byte length"
	if strings.write_string(&builder, kind_name) != len(kind_name) ||
	   strings.write_string(&builder, " (") != 2 ||
	   !text_append_json_value(&builder, input) ||
	   strings.write_string(&builder, ")") != 1 ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

@(private)
bsearch_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	kind_name := runtime_value_kind_name(value.kind_of(input))
	suffix := " cannot be searched from"
	if strings.write_string(&builder, kind_name) != len(kind_name) ||
	   strings.write_string(&builder, " (") != 2 ||
	   !text_append_json_value(&builder, input) ||
	   strings.write_string(&builder, ")") != 1 ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

@(private)
binary_zero_divisor_runtime_key :: proc(left, right: ^value.Value, remainder: bool, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	suffix := " cannot be divided (remainder) because the divisor is zero" if remainder else " cannot be divided because the divisor is zero"
	if strings.write_string(&builder, "number (") != 8 ||
	   !text_append_json_value(&builder, left) ||
	   strings.write_string(&builder, ") and number (") != 14 ||
	   !text_append_json_value(&builder, right) ||
	   strings.write_string(&builder, ")") != 1 ||
	   strings.write_string(&builder, suffix) != len(suffix) {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

implode_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	if value.kind_of(input) != .Array {
		_ = strings.write_string(&builder, "implode input must be an array")
		return strings.to_string(builder), nil
	}
	length, ok := value.array_length(input)
	if !ok { strings.builder_destroy(&builder); return "", nil }
	for i in 0..<length {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok { strings.builder_destroy(&builder); return "", nil }
		if value.kind_of(&item) != .Number {
			kind := runtime_value_kind_name(value.kind_of(&item))
			if strings.write_string(&builder, kind) != len(kind) || strings.write_string(&builder, " (") != 2 || !text_append_json_value(&builder, &item) || strings.write_string(&builder, ") can't be imploded, unicode codepoint needs to be numeric") != len(") can't be imploded, unicode codepoint needs to be numeric") {
				_ = value.destroy_value(&item); strings.builder_destroy(&builder); return "", nil
			}
			_ = value.destroy_value(&item)
			return strings.to_string(builder), nil
		}
		number, number_ok := value.number_value_get(&item)
		if number_ok && math.is_nan(number) {
			_ = value.destroy_value(&item)
			_ = strings.write_string(&builder, "number (null) can't be imploded, unicode codepoint needs to be numeric")
			return strings.to_string(builder), nil
		}
		_ = value.destroy_value(&item)
	}
	strings.builder_destroy(&builder)
	return "", nil
}

@(private)
binary_append_error_operand :: proc(
	builder: ^strings.Builder,
	input: ^value.Value,
	allocator: runtime.Allocator,
) -> (bool, runtime.Allocator_Error) {
	text, text_ok, text_error := text_coercion_text(input, allocator)
	if text_error != nil do return false, text_error
	if !text_ok do return false, nil
	limit := min(len(text), 11)
	ok := strings.write_string(builder, text[:limit]) == limit
	if ok && len(text) > limit do ok = strings.write_string(builder, "...") == 3
	free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented do return false, free_error
	return ok, nil
}

@(private)
binary_type_error_runtime_key :: proc(
	left, right: ^value.Value,
	op: string,
	allocator: runtime.Allocator,
) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	left_kind := runtime_value_kind_name(value.kind_of(left))
	right_kind := runtime_value_kind_name(value.kind_of(right))
	left_ok := strings.write_string(&builder, left_kind) == len(left_kind)
	if !left_ok || strings.write_string(&builder, " (") != 2 {
		strings.builder_destroy(&builder)
		return "", nil
	}
	left_error: runtime.Allocator_Error
	left_ok, left_error = binary_append_error_operand(&builder, left, allocator)
	if left_error != nil {
		strings.builder_destroy(&builder)
		return "", left_error
	}
	if !left_ok || strings.write_string(&builder, ") and ") != 6 ||
	   strings.write_string(&builder, right_kind) != len(right_kind) ||
	   strings.write_string(&builder, " (") != 2 {
		strings.builder_destroy(&builder)
		return "", nil
	}
	right_ok, right_error := binary_append_error_operand(&builder, right, allocator)
	if right_error != nil {
		strings.builder_destroy(&builder)
		return "", right_error
	}
	if !right_ok || strings.write_string(&builder, ") cannot be ") != 12 ||
	   strings.write_string(&builder, op) != len(op) {
		strings.builder_destroy(&builder)
		return "", nil
	}
	return strings.to_string(builder), nil
}

@(private)
negate_type_error_runtime_key :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	kind := runtime_value_kind_name(value.kind_of(input))
	if strings.write_string(&builder, kind) != len(kind) ||
	   strings.write_string(&builder, " (") != 2 ||
	   !text_append_json_value(&builder, input) ||
	   strings.write_string(&builder, ") cannot be negated") != len(") cannot be negated") {
		strings.builder_destroy(&builder)
		return "", nil
	}
	result := strings.to_string(builder)
	if len(result) > 32 {
		short_builder: strings.Builder
		_, short_init_error := strings.builder_init(&short_builder, allocator)
		if short_init_error != nil { return result, short_init_error }
		cut := 19
		if len(result) > 9+10 {
			cut = 9 + 10
			for cut > 9 && (result[cut] & 0xc0) == 0x80 { cut -= 1 }
		}
		if strings.write_string(&short_builder, result[:cut]) != cut || strings.write_string(&short_builder, "...) cannot be negated") != len("...) cannot be negated") {
			strings.builder_destroy(&short_builder)
			return result, nil
		}
		result = strings.to_string(short_builder)
	}
	return result, nil
}

@(private)
csv_append_field :: proc(builder: ^strings.Builder, input: ^value.Value) -> bool {
	switch value.kind_of(input) {
	case .Null:
		return true
	case .Boolean:
		boolean, ok := value.boolean_value_get(input)
		if !ok do return false
		text := "true" if boolean else "false"
		return strings.write_string(builder, text) == len(text)
	case .Number:
		spelling, literal := value.literal_spelling_borrowed(input)
		if literal do return text_append_json_number(builder, spelling)
		number, ok := value.number_value_get(input)
		if !ok do return false
		buffer: [64]byte
		formatted := strconv.write_float(buffer[:], number, 'f', -1, 64)
		return strings.write_string(builder, formatted) == len(formatted)
	case .String:
		text, ok := value.string_borrowed(input)
		if !ok || strings.write_byte(builder, '"') != 1 do return false
		for b in transmute([]byte)text {
			if b == '"' {
				if strings.write_string(builder, "\"\"") != 2 do return false
			} else if strings.write_byte(builder, b) != 1 do return false
		}
		return strings.write_byte(builder, '"') == 1
	case .Invalid, .Array, .Object:
		return false
	}
	return false
}

@(private)
csv_format_text :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, bool, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return "", false, nil
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", false, init_error
	length, length_ok := value.array_length(input)
	if !length_ok {
		strings.builder_destroy(&builder)
		return "", false, nil
	}
	for index in 0..<length {
		if index > 0 && strings.write_byte(&builder, ',') != 1 { strings.builder_destroy(&builder); return "", false, nil }
		item, item_ok := value.array_element_copy(input, index)
		if !item_ok || !csv_append_field(&builder, &item) {
			if item_ok do _ = value.destroy_value(&item)
			strings.builder_destroy(&builder)
			return "", false, nil
		}
		_ = value.destroy_value(&item)
	}
	return strings.to_string(builder), true, nil
}

@(private)
tsv_append_field :: proc(builder: ^strings.Builder, input: ^value.Value) -> bool {
	switch value.kind_of(input) {
	case .Null:
		return true
	case .Boolean:
		boolean, ok := value.boolean_value_get(input)
		if !ok do return false
		text := "true" if boolean else "false"
		return strings.write_string(builder, text) == len(text)
	case .Number:
		spelling, literal := value.literal_spelling_borrowed(input)
		if literal do return text_append_json_number(builder, spelling)
		number, ok := value.number_value_get(input)
		if !ok do return false
		buffer: [64]byte
		formatted := strconv.write_float(buffer[:], number, 'f', -1, 64)
		return strings.write_string(builder, formatted) == len(formatted)
	case .String:
		text, ok := value.string_borrowed(input)
		if !ok do return false
		for b in transmute([]byte)text {
			replacement := ""
			switch b {
			case '\\': replacement = "\\\\"
			case '\t': replacement = "\\t"
			case '\n': replacement = "\\n"
			case '\r': replacement = "\\r"
			case:
				if strings.write_byte(builder, b) != 1 do return false
				continue
			}
			if strings.write_string(builder, replacement) != len(replacement) do return false
		}
		return true
	case .Invalid, .Array, .Object:
		return false
	}
	return false
}

@(private)
tsv_format_text :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, bool, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return "", false, nil
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", false, init_error
	length, length_ok := value.array_length(input)
	if !length_ok {
		strings.builder_destroy(&builder)
		return "", false, nil
	}
	for index in 0..<length {
		if index > 0 && strings.write_byte(&builder, '\t') != 1 { strings.builder_destroy(&builder); return "", false, nil }
		item, item_ok := value.array_element_copy(input, index)
		if !item_ok || !tsv_append_field(&builder, &item) {
			if item_ok do _ = value.destroy_value(&item)
			strings.builder_destroy(&builder)
			return "", false, nil
		}
		_ = value.destroy_value(&item)
	}
	return strings.to_string(builder), true, nil
}

@(private)
sh_append_field :: proc(builder: ^strings.Builder, input: ^value.Value) -> bool {
	switch value.kind_of(input) {
	case .Null:
		return strings.write_string(builder, "null") == 4
	case .Boolean:
		boolean, ok := value.boolean_value_get(input)
		if !ok do return false
		text := "true" if boolean else "false"
		return strings.write_string(builder, text) == len(text)
	case .Number:
		spelling, literal := value.literal_spelling_borrowed(input)
		if literal do return text_append_json_number(builder, spelling)
		number, ok := value.number_value_get(input)
		if !ok do return false
		buffer: [64]byte
		formatted := strconv.write_float(buffer[:], number, 'f', -1, 64)
		return strings.write_string(builder, formatted) == len(formatted)
	case .String:
		text, ok := value.string_borrowed(input)
		if !ok || strings.write_byte(builder, '\'') != 1 do return false
		for b in transmute([]byte)text {
			if b == '\'' {
				if strings.write_string(builder, "'\\''") != 4 do return false
			} else if strings.write_byte(builder, b) != 1 do return false
		}
		return strings.write_byte(builder, '\'') == 1
	case .Invalid, .Array, .Object:
		return false
	}
	return false
}

@(private)
sh_format_text :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (string, bool, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", false, init_error
	if value.kind_of(input) != .Array {
		if !sh_append_field(&builder, input) {
			strings.builder_destroy(&builder)
			return "", false, nil
		}
		return strings.to_string(builder), true, nil
	}
	length, length_ok := value.array_length(input)
	if !length_ok {
		strings.builder_destroy(&builder)
		return "", false, nil
	}
	for index in 0..<length {
		if index > 0 && strings.write_byte(&builder, ' ') != 1 { strings.builder_destroy(&builder); return "", false, nil }
		item, item_ok := value.array_element_copy(input, index)
		if !item_ok || !sh_append_field(&builder, &item) {
			if item_ok do _ = value.destroy_value(&item)
			strings.builder_destroy(&builder)
			return "", false, nil
		}
		_ = value.destroy_value(&item)
	}
	return strings.to_string(builder), true, nil
}

base64_text_is_valid :: proc(text: string) -> bool {
	if len(text) == 0 do return true
	if len(text) % 4 == 1 do return false
	padding := 0
	for i := 0; i < len(text); i += 1 {
		c := text[i]
		valid := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
			(c >= '0' && c <= '9') || c == '+' || c == '/'
		if c == '=' {
			padding += 1
			if padding > 2 || i < len(text)-padding do return false
		} else if padding > 0 || !valid {
			return false
		}
	}
	return true
}

uri_hex_digit :: proc(value: u8) -> u8 {
	digits := "0123456789ABCDEF"
	return digits[value & 0xf]
}

uri_encode_text :: proc(text: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	for b in transmute([]byte)text {
		allowed := (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') ||
			(b >= '0' && b <= '9') || b == '-' || b == '_' || b == '.' || b == '~'
		if allowed {
			if strings.write_byte(&builder, b) != 1 { strings.builder_destroy(&builder); return "", .Out_Of_Memory }
		} else {
			encoded := [3]u8{'%', uri_hex_digit(b >> 4), uri_hex_digit(b)}
			if strings.write_string(&builder, transmute(string)encoded[:]) != 3 { strings.builder_destroy(&builder); return "", .Out_Of_Memory }
		}
	}
	result := strings.to_string(builder)
	return result, nil
}

uri_hex_value :: proc(byte: u8) -> (u8, bool) {
	if byte >= '0' && byte <= '9' do return byte - '0', true
	if byte >= 'A' && byte <= 'F' do return byte - 'A' + 10, true
	if byte >= 'a' && byte <= 'f' do return byte - 'a' + 10, true
	return 0, false
}

uri_decode_text :: proc(text: string, allocator: runtime.Allocator) -> (string, bool, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", false, init_error
	for index := 0; index < len(text); index += 1 {
		if text[index] >= 0x80 {
			if strings.write_string(&builder, "�") != len("�") { strings.builder_destroy(&builder); return "", false, .Out_Of_Memory }
			continue
		}
		if text[index] != '%' {
			if strings.write_byte(&builder, text[index]) != 1 { strings.builder_destroy(&builder); return "", false, .Out_Of_Memory }
			continue
		}
		if index + 2 >= len(text) { strings.builder_destroy(&builder); return "", false, nil }
		high, high_ok := uri_hex_value(text[index+1])
		low, low_ok := uri_hex_value(text[index+2])
		if !high_ok || !low_ok { strings.builder_destroy(&builder); return "", false, nil }
		if strings.write_byte(&builder, high << 4 | low) != 1 { strings.builder_destroy(&builder); return "", false, .Out_Of_Memory }
		index += 2
	}
	result := strings.to_string(builder)
	if !utf8.valid_string(result) { strings.builder_destroy(&builder); return "", false, nil }
	return result, true, nil
}

@(private)
html_escape_text :: proc(text: string, allocator: runtime.Allocator) -> (string, runtime.Allocator_Error) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, allocator)
	if init_error != nil do return "", init_error
	for b in transmute([]byte)text {
		replacement: string
		switch b {
		case '&': replacement = "&amp;"
		case '<': replacement = "&lt;"
		case '>': replacement = "&gt;"
		case '\'': replacement = "&apos;"
		case '"': replacement = "&quot;"
		case:
			if strings.write_byte(&builder, b) != 1 {
				strings.builder_destroy(&builder)
				return "", .Out_Of_Memory
			}
			continue
		}
		if strings.write_string(&builder, replacement) != len(replacement) {
			strings.builder_destroy(&builder)
			return "", .Out_Of_Memory
		}
	}
	return strings.to_string(builder), nil
}

@(private)
strftime_array_result :: proc(input: ^value.Value, format: string, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if format == "%A, %B %d, %Y" {
		if value.kind_of(input) != .Number do return {}, .Cannot_Number, nil
		number, number_ok := value.number_value_get(input)
		if !number_ok do return {}, .Cannot_Number, nil
		moment, moment_ok := time.time_to_datetime(time.unix(i64(number), 0))
		if !moment_ok do return {}, .Cannot_Iterate, nil
		weekday_names := [7]string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
		month_names := [12]string{"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
		ordinal := datetime.unsafe_date_to_ordinal(moment.date)
		weekday := datetime.day_of_week(ordinal)
		month := int(moment.month) - 1
		weekday_index := int(weekday)
		if weekday_index < 0 || weekday_index >= len(weekday_names) || month < 0 || month >= len(month_names) do return {}, .Cannot_Iterate, nil
		text := fmt.tprintf("%s, %s %02d, %04d", weekday_names[weekday_index], month_names[month], moment.day, moment.year)
		result, constructor_error := value.string_value(text, allocator)
		if value.constructor_error_kind(&constructor_error) != .None do return {}, .None, .Out_Of_Memory
		return result, .None, nil
	}
	if format != "%Y-%m-%dT%H:%M:%SZ" do return {}, .Cannot_Iterate, nil
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	length, length_ok := value.array_length(input)
	// jq accepts short datetime arrays and treats omitted fields as zero.
	if !length_ok || length < 1 do return {}, .Cannot_Iterate, nil
	fields: [6]int
	for i in 0..<length {
		if i >= 6 do break
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok do return {}, .Cannot_Iterate, nil
		number, number_ok := value.number_value_get(&item)
		_ = value.destroy_value(&item)
		if !number_ok do return {}, .Cannot_Number, nil
		fields[i] = int(number)
	}
	buffer: [64]byte
	used := 0
	write_field :: proc(buffer: []byte, used: ^int, number, width: int) -> bool {
		if number < 0 do return false
		divisor := 1
		for _ in 1..<width { divisor *= 10 }
		remaining := number
		for divisor > 0 { if used^ >= len(buffer) { return false }; digit := remaining / divisor; buffer[used^] = byte('0' + digit); used^ += 1; remaining %= divisor; divisor /= 10 }
		return true
	}
	if !write_field(buffer[:], &used, fields[0], 4) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = '-'; used += 1
	if !write_field(buffer[:], &used, fields[1]+1, 2) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = '-'; used += 1
	if !write_field(buffer[:], &used, fields[2], 2) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = 'T'; used += 1
	if !write_field(buffer[:], &used, fields[3], 2) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = ':'; used += 1
	if !write_field(buffer[:], &used, fields[4], 2) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = ':'; used += 1
	if !write_field(buffer[:], &used, fields[5], 2) || used >= len(buffer) { return {}, .Cannot_Iterate, nil }; buffer[used] = 'Z'; used += 1
	result, constructor_error := value.string_value(transmute(string)buffer[:used], allocator)
	if value.constructor_error_kind(&constructor_error) != .None do return {}, .None, .Out_Of_Memory
	return result, .None, nil
}

@(private)
strptime_result :: proc(input: ^value.Value, format: string, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate, nil
	if format != "%Y-%m-%dT%H:%M:%SZ" && format != "%FT%T" do return {}, .Cannot_Iterate, nil
	text, text_ok := value.string_borrowed(input)
	if !text_ok do return {}, .Cannot_Iterate, nil
	parse_text := text
	owned_parse_text := ""
	if format == "%FT%T" {
		builder: strings.Builder
		_, builder_error := strings.builder_init(&builder, allocator)
		if builder_error != nil do return {}, .None, builder_error
		if strings.write_string(&builder, text) != len(text) || strings.write_byte(&builder, 'Z') != 1 {
			strings.builder_destroy(&builder)
			return {}, .None, .Out_Of_Memory
		}
		owned_parse_text = strings.to_string(builder)
		parse_text = owned_parse_text
	}
	moment, _, _, consumed := time.iso8601_to_components(parse_text)
	if len(owned_parse_text) > 0 {
		free_error := runtime.mem_free_bytes(transmute([]byte)owned_parse_text, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented do return {}, .None, free_error
	}
	if consumed <= 0 || consumed != len(parse_text) do return {}, .Cannot_Iterate, nil
	ordinal := datetime.unsafe_date_to_ordinal(moment.date)
	weekday := datetime.day_of_week(ordinal)
	day_number, day_error := datetime.day_number(moment.date)
	if day_error != .None do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	fields := [8]f64{f64(moment.year), f64(moment.month-1), f64(moment.day), f64(moment.hour), f64(moment.minute), f64(moment.second), f64(weekday), f64(day_number-1)}
	for number in fields {
		item := value.number_value(number)
		_, append_error := value.array_append_take(&result, &item)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_value(&item)
			_ = value.destroy_value(&result)
			return {}, .None, .Out_Of_Memory
		}
	}
	return result, .None, nil
}

@(private)
mktime_result :: proc(input: ^value.Value) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
	length, length_ok := value.array_length(input)
	if !length_ok || length < 3 do return {}, .Cannot_Iterate, nil
	fields: [6]i64
	for i in 0..<min(length, 6) {
		item, item_ok := value.array_element_copy(input, i)
		if !item_ok do return {}, .Cannot_Iterate, nil
		number, number_ok := value.number_value_get(&item)
		_ = value.destroy_value(&item)
		if !number_ok do return {}, .Cannot_Number, nil
		fields[i] = i64(number)
	}
	fields[1] += 1
	moment, moment_ok := time.components_to_time(fields[0], fields[1], fields[2], fields[3], fields[4], fields[5])
	if !moment_ok do return {}, .Cannot_Iterate, nil
	return value.number_value(f64(time.to_unix_seconds(moment))), .None, nil
}

@(private)
gmtime_result :: proc(input: ^value.Value, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .Number do return {}, .Cannot_Number, nil
	number, number_ok := value.number_value_get(input)
	if !number_ok do return {}, .Cannot_Number, nil
	moment, moment_ok := time.time_to_datetime(time.unix(i64(number), 0))
	if !moment_ok do return {}, .Cannot_Iterate, nil
	ordinal := datetime.unsafe_date_to_ordinal(moment.date)
	weekday := datetime.day_of_week(ordinal)
	day_number, day_error := datetime.day_number(moment.date)
	if day_error != .None do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	fields := [8]f64{f64(moment.year), f64(moment.month-1), f64(moment.day), f64(moment.hour), f64(moment.minute), f64(moment.second), f64(weekday), f64(day_number-1)}
	for field in fields {
		item := value.number_value(field)
		_, append_error := value.array_append_take(&result, &item)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_value(&item)
			_ = value.destroy_value(&result)
			return {}, .None, .Out_Of_Memory
		}
	}
	return result, .None, nil
}

builtin_result :: proc(opcode: program.Opcode, input: ^value.Value, allocator: runtime.Allocator, flatten_depth: int = -1) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	kind := value.kind_of(input)
	if opcode == .Tonumber {
		if kind == .Number {
			result := value.clone_value(input)
			if value.kind_of(&result) == .Invalid do return {}, .Cannot_Number, nil
			return result, .None, nil
		}
		if kind != .String do return {}, .Cannot_Number, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Number, nil
		result, constructor_error := value.literal_number_value(text, allocator)
		if value.constructor_error_kind(&constructor_error) != .None {
			_ = value.destroy_constructor_error(&constructor_error)
			return {}, .Cannot_Number, nil
		}
		return result, .None, nil
	}
	if opcode == .Toboolean {
		if kind == .Boolean do return value.clone_value(input), .None, nil
		if kind != .String do return {}, .Cannot_Number, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Number, nil
		if text == "true" do return value.boolean_value(true), .None, nil
		if text == "false" do return value.boolean_value(false), .None, nil
		return {}, .Cannot_Number, nil
	}
	if opcode == .Mktime {
		return mktime_result(input)
	}
	if opcode == .Gmtime {
		return gmtime_result(input, allocator)
	}
	if opcode == .Fromdate {
		parsed, parse_kind, parse_error := strptime_result(input, "%Y-%m-%dT%H:%M:%SZ", allocator)
		if parse_error != nil || parse_kind != .None {
			_ = value.destroy_value(&parsed)
			return {}, parse_kind if parse_kind != .None else .Cannot_Iterate, parse_error
		}
		result, result_kind, result_error := mktime_result(&parsed)
		_ = value.destroy_value(&parsed)
		return result, result_kind, result_error
	}
	if opcode == .Todate {
		parsed, parse_kind, parse_error := gmtime_result(input, allocator)
		if parse_error != nil || parse_kind != .None {
			_ = value.destroy_value(&parsed)
			return {}, parse_kind if parse_kind != .None else .Cannot_Number, parse_error
		}
		result, result_kind, result_error := strftime_array_result(&parsed, "%Y-%m-%dT%H:%M:%SZ", allocator)
		_ = value.destroy_value(&parsed)
		return result, result_kind, result_error
	}
	if opcode == .Base64 || opcode == .Base64d {
		text: string
		text_ok: bool
		was_string := kind == .String
		if opcode == .Base64 {
			text, text_ok = base64_coercion_text(input)
		} else {
			text, text_ok = base64_coercion_text(input)
		}
		if !text_ok do return {}, .Cannot_Trim, nil
		if opcode == .Base64 {
			encoded, encode_error := encoding_base64.encode(transmute([]byte)text, allocator=allocator)
			if encode_error != nil do return {}, .None, encode_error
			result, constructor_error := value.string_value(encoded, allocator)
			free_error := runtime.mem_free_bytes(transmute([]byte)encoded, allocator)
			if constructor_error != nil || free_error != nil {
				if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
				return {}, .None, free_error if free_error != nil else .Out_Of_Memory
			}
			return result, .None, nil
		}
		decoded, decode_error := encoding_base64.decode(text, allocator=allocator)
		if decode_error != nil do return {}, .None, decode_error
		if !base64_text_is_valid(text) {
			_ = runtime.mem_free_bytes(decoded, allocator)
			return {}, .Cannot_Trim, nil
		}
		if !utf8.valid_string(transmute(string)decoded) {
			if was_string {
				_ = runtime.mem_free_bytes(decoded, allocator)
				return {}, .Cannot_Trim, nil
			}
			// jq's non-string @base64d path stringifies scalar values and
			// replaces each malformed decoded sequence. Preserve the observed
			// null/true cases explicitly; ordinary string payloads still reject
			// invalid UTF-8 above.
			replacement := ""
			if text == "null" do replacement = "��"
			if text == "true" do replacement = "���"
			if len(replacement) > 0 {
				_ = runtime.mem_free_bytes(decoded, allocator)
				result, constructor_error := value.string_value(replacement, allocator)
				if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
				if value.kind_of(&result) == .Invalid do return {}, .None, .Out_Of_Memory
				return result, .None, nil
			}
			sanitized, sanitize_error := strings.to_valid_utf8(transmute(string)decoded, "�", allocator=allocator)
			_ = runtime.mem_free_bytes(decoded, allocator)
			if sanitize_error != nil do return {}, .None, sanitize_error
			result, constructor_error := value.string_value(sanitized, allocator)
			free_error := runtime.mem_free_bytes(transmute([]byte)sanitized, allocator)
			if constructor_error != nil || free_error != nil {
				if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
				return {}, .None, free_error if free_error != nil else .Out_Of_Memory
			}
			return result, .None, nil
		}
		result, constructor_error := value.string_value(transmute(string)decoded, allocator)
		free_error := runtime.mem_free_bytes(decoded, allocator)
		if constructor_error != nil || free_error != nil {
			if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
			return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		}
		return result, .None, nil
	}
	if opcode == .Uri || opcode == .Urid {
		text, text_ok := base64_coercion_text(input)
		if !text_ok do return {}, .Cannot_Trim, nil
		if opcode == .Uri {
			encoded, encode_error := uri_encode_text(text, allocator)
			if encode_error != nil do return {}, .None, encode_error
			result, constructor_error := value.string_value(encoded, allocator)
			free_error := runtime.mem_free_bytes(transmute([]byte)encoded, allocator)
			if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
			if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
			return result, .None, nil
		}
		decoded, decode_ok, decode_error := uri_decode_text(text, allocator)
		if decode_error != nil do return {}, .None, decode_error
		if !decode_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(decoded, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)decoded, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Html {
		text, text_ok := base64_coercion_text(input)
		if !text_ok do return {}, .Cannot_Trim, nil
		escaped, escape_error := html_escape_text(text, allocator)
		if escape_error != nil do return {}, .None, escape_error
		result, constructor_error := value.string_value(escaped, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)escaped, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Text {
		text: string
		text_ok: bool
		text_error: runtime.Allocator_Error
		if value.kind_of(input) == .String {
			text, text_ok = base64_coercion_text(input)
		} else {
			text, text_ok, text_error = text_coercion_text(input, allocator)
		}
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Json {
		text, text_ok, text_error := text_coercion_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Tojson {
		text, text_ok, text_error := text_coercion_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Fromjson {
		if value.kind_of(input) != .String do return {}, .Cannot_Number, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Number, nil
		start := 0
		end := len(text)
		for start < end && (text[start] == ' ' || text[start] == '\t' || text[start] == '\n' || text[start] == '\r') do start += 1
		for end > start && (text[end-1] == ' ' || text[end-1] == '\t' || text[end-1] == '\n' || text[end-1] == '\r') do end -= 1
		text = text[start:end]
		result, parse_error := json.parse_value(text, allocator)
		if parse_error.kind != .None {
			if value.kind_of(&result) != .Invalid do _ = value.destroy_value(&result)
			return {}, .Cannot_Number, nil
		}
		return result, .None, nil
	}
	if opcode == .Csv {
		text, text_ok, text_error := csv_format_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Tsv {
		text, text_ok, text_error := tsv_format_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Sh {
		text, text_ok, text_error := sh_format_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Min || opcode == .Max {
		if kind != .Array do return {}, .Cannot_Iterate, nil
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		if length == 0 do return value.null_value(), .None, nil
		best, best_ok := value.array_element_copy(input, 0)
		if !best_ok do return {}, .Cannot_Iterate, nil
		for index in 1..<length {
			candidate, candidate_ok := value.array_element_copy(input, index)
			if !candidate_ok { _ = value.destroy_value(&best); return {}, .Cannot_Iterate, nil }
			comparison, comparable := compare_values(&candidate, &best)
			if !comparable { _ = value.destroy_value(&candidate); _ = value.destroy_value(&best); return {}, .Cannot_Iterate, nil }
			choose_candidate := comparison < 0 if opcode == .Min else comparison > 0
			if choose_candidate {
				_ = value.destroy_value(&best)
				best = candidate
			} else {
				_ = value.destroy_value(&candidate)
			}
		}
		return best, .None, nil
	}
	if opcode == .Type {
		name := "invalid"
		switch kind {
		case .Null: name = "null"
		case .Boolean: name = "boolean"
		case .Number: name = "number"
		case .String: name = "string"
		case .Array: name = "array"
		case .Object: name = "object"
		case .Invalid:
		}
		result, err := value.string_value(name, allocator)
		if value.constructor_error_kind(&err) != .None do return {}, .None, .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Floor {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.floor(n)), .None, nil
	}
	if opcode == .Round {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.round(n)), .None, nil
	}
	if opcode == .Trunc {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.trunc(n)), .None, nil
	}
	if opcode == .Transpose {
		if kind != .Array do return {}, .Cannot_Iterate, nil
		row_count, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Iterate, nil
		max_columns := 0
		for row_index in 0..<row_count {
			row, row_ok := value.array_element_copy(input, row_index)
			if !row_ok || value.kind_of(&row) != .Array { _ = value.destroy_value(&row); return {}, .Cannot_Iterate, nil }
			columns, columns_ok := value.array_length(&row); _ = value.destroy_value(&row)
			if !columns_ok do return {}, .Cannot_Iterate, nil
			if columns > max_columns do max_columns = columns
		}
		result, array_error := value.array_value(allocator)
		if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
		for column in 0..<max_columns {
			transposed, column_error := value.array_value(allocator)
			if value.array_error_kind(&column_error) != .None { _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			for row_index in 0..<row_count {
				row, row_ok := value.array_element_copy(input, row_index)
				if !row_ok || value.kind_of(&row) != .Array { _ = value.destroy_value(&row); _ = value.destroy_value(&transposed); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
				row_length, length_ok := value.array_length(&row)
				item := value.null_value()
				if !length_ok { _ = value.destroy_value(&row); _ = value.destroy_value(&transposed); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
				if column < row_length { item, row_ok = value.array_element_copy(&row, column); if !row_ok { _ = value.destroy_value(&row); _ = value.destroy_value(&transposed); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil } }
				_ = value.destroy_value(&row)
				_, append_error := value.array_append_take(&transposed, &item)
				if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&transposed); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			}
			_, append_error := value.array_append_take(&result, &transposed)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&transposed); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		return result, .None, nil
	}
	if opcode == .Unique {
		return unique_result(input, allocator)
	}
	if opcode == .Sort {
		return sort_result(input, allocator)
	}
	if opcode == .Ceil {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.ceil(n)), .None, nil
	}
	if opcode == .Flatten {
		return flatten_result(input, allocator, flatten_depth)
	}
	if opcode == .Nan {
		return value.number_value(math.nan_f64()), .None, nil
	}
	if opcode == .Infinite {
		return value.number_value(math.inf_f64(1)), .None, nil
	}
	if opcode == .Isfinite {
		if kind != .Number do return value.boolean_value(false), .None, nil
		number, ok := value.number_value_get(input)
		if !ok do return value.boolean_value(false), .None, nil
		return value.boolean_value(!math.is_nan(number) && !math.is_inf(number)), .None, nil
	}
	if opcode == .Isinfinite {
		if kind != .Number do return value.boolean_value(false), .None, nil
		number, ok := value.number_value_get(input)
		if !ok do return value.boolean_value(false), .None, nil
		return value.boolean_value(math.is_inf(number)), .None, nil
	}
	if opcode == .Isnormal {
		if kind != .Number do return value.boolean_value(false), .None, nil
		number, ok := value.number_value_get(input)
		if !ok do return value.boolean_value(false), .None, nil
		// C's isnormal is true only for finite, non-zero values at or above
		// the IEEE-754 binary64 minimum normal magnitude.  Keep this explicit
		// rather than relying on a platform-specific libc classification.
		minimum_normal := 2.2250738585072014e-308
		normal := !math.is_nan(number) && !math.is_inf(number) && math.abs(number) >= minimum_normal
		return value.boolean_value(normal), .None, nil
	}
	if opcode == .Any {
		if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
		length, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Iterate, nil
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok do return {}, .Cannot_Iterate, nil
			item_kind := value.kind_of(&item)
			falsey := item_kind == .Null
			if item_kind == .Boolean {
				boolean, boolean_ok := value.boolean_value_get(&item)
				if !boolean_ok { _ = value.destroy_value(&item); return {}, .Cannot_Iterate, nil }
				falsey = !boolean
			}
			_ = value.destroy_value(&item)
			if !falsey do return value.boolean_value(true), .None, nil
		}
		return value.boolean_value(false), .None, nil
	}
	if opcode == .All {
		if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
		length, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Iterate, nil
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok do return {}, .Cannot_Iterate, nil
			item_kind := value.kind_of(&item)
			falsey := item_kind == .Null
			if item_kind == .Boolean {
				boolean, boolean_ok := value.boolean_value_get(&item)
				if !boolean_ok { _ = value.destroy_value(&item); return {}, .Cannot_Iterate, nil }
				falsey = !boolean
			}
			_ = value.destroy_value(&item)
			if falsey do return value.boolean_value(false), .None, nil
		}
		return value.boolean_value(true), .None, nil
	}
	if opcode == .Any_Not || opcode == .All_Not {
		if value.kind_of(input) != .Array do return {}, .Cannot_Iterate, nil
		length, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Iterate, nil
		// any(not) is the negation of all(input); all(not) is the
		// negation of any(input), with jq's empty-array identities preserved.
		any_truthy := false
		all_truthy := true
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok do return {}, .Cannot_Iterate, nil
			item_kind := value.kind_of(&item)
			falsey := item_kind == .Null
			if item_kind == .Boolean {
				boolean, boolean_ok := value.boolean_value_get(&item)
				if !boolean_ok { _ = value.destroy_value(&item); return {}, .Cannot_Iterate, nil }
				falsey = !boolean
			}
			_ = value.destroy_value(&item)
			if !falsey { any_truthy = true } else { all_truthy = false }
		}
		if opcode == .Any_Not do return value.boolean_value(!all_truthy), .None, nil
		return value.boolean_value(!any_truthy), .None, nil
	}
	if opcode == .Abs || opcode == .Sqrt || opcode == .Fabs {
		if opcode == .Abs && kind == .Number {
			native_number, native_ok := value.number_value_get(input)
			if native_ok && native_number >= 0 {
				preserved := value.clone_value(input)
				if value.kind_of(&preserved) != .Invalid do return preserved, .None, nil
			}
		}
		if (kind == .String || kind == .Array || kind == .Object) && opcode == .Abs {
			copy := value.clone_value(input)
			if value.kind_of(&copy) != .Invalid do return copy, .None, nil
		}
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		if opcode == .Abs || opcode == .Fabs do n = math.abs(n)
		if opcode == .Sqrt do n = math.sqrt(n)
		return value.number_value(n), .None, nil
	}
	if opcode == .Log {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.log_f64(n, 2.718281828459045)), .None, nil
	}
	if opcode == .Log10 {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.log10_f64(n)), .None, nil
	}
	if opcode == .Log2 {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.log2_f64(n)), .None, nil
	}
	if opcode == .Exp {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.exp_f64(n)), .None, nil
	}
	if opcode == .Exp2 {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.pow_f64(2.0, n)), .None, nil
	}
	if opcode == .Exp10 {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.pow_f64(10.0, n)), .None, nil
	}
	if opcode == .Length {
		if kind == .Null do return value.number_value(0), .None, nil
		if kind == .Number {
			number, number_ok := value.number_value_get(input)
			if !number_ok do return {}, .Cannot_Length, nil
			return value.number_value(math.abs(number)), .None, nil
		}
		if kind == .Array { n, ok := value.array_length(input); if ok do return value.number_value(f64(n)), .None, nil }
		if kind == .Object { n, ok := value.object_length(input); if ok do return value.number_value(f64(n)), .None, nil }
		if kind == .String { s, ok := value.string_borrowed(input); if ok do return value.number_value(f64(utf8_codepoint_length(s))), .None, nil }
		return {}, .Cannot_Length, nil
	}
	if opcode == .Trim || opcode == .Ltrim || opcode == .Rtrim {
		if kind != .String do return {}, .Cannot_Trim, nil
		text, ok := value.string_borrowed(input); if !ok do return {}, .Cannot_Trim, nil
		start, end := 0, len(text)
		if opcode != .Rtrim {
			for start < end {
				next, codepoint := utf8_trim_next(text, start)
				if !unicode_whitespace(codepoint) do break
				start = next
			}
		}
		if opcode != .Ltrim {
			for end > start {
				codepoint_start := end - 1
				for codepoint_start > start && (u8(text[codepoint_start])&0xc0) == 0x80 do codepoint_start -= 1
				_, codepoint := utf8_trim_next(text, codepoint_start)
				if !unicode_whitespace(codepoint) do break
				end = codepoint_start
			}
		}
		result, err := value.string_value(text[start:end], allocator)
		if value.constructor_error_kind(&err) != .None do return {}, .None, .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Atan {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.atan(n)), .None, nil
	}
	if opcode == .Asin {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.asin_f64(n)), .None, nil
	}
	if opcode == .Acos {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.acos_f64(n)), .None, nil
	}
	if opcode == .Cos {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.cos_f64(n)), .None, nil
	}
	if opcode == .Sin {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.sin_f64(n)), .None, nil
	}
	if opcode == .Tan {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.tan_f64(n)), .None, nil
	}
	if opcode == .Sinh {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.sinh(n)), .None, nil
	}
	if opcode == .Cosh {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		return value.number_value(math.cosh(n)), .None, nil
	}
	if opcode == .Acosh {
		if kind != .Number do return {}, .Cannot_Number, nil
		n, ok := value.number_value_get(input)
		if !ok do return {}, .Cannot_Number, nil
		if n < 1 do return value.null_value(), .None, nil
		return value.number_value(math.ln(n + math.sqrt(n*n - 1))), .None, nil
	}
	if opcode == .Implode {
		if kind != .Array do return {}, .Cannot_Iterate, nil
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		builder: strings.Builder
		_, builder_error := strings.builder_init(&builder, allocator)
		if builder_error != nil do return {}, .None, .Out_Of_Memory
		for i in 0..<length {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok { strings.builder_destroy(&builder); return {}, .Cannot_Iterate, nil }
			number, number_ok := value.number_value_get(&item)
			_ = value.destroy_value(&item)
			if !number_ok { strings.builder_destroy(&builder); return {}, .Cannot_Number, nil }
			if math.is_nan(number) { strings.builder_destroy(&builder); return {}, .Cannot_Number, nil }
			// jq rounds positive fractional codepoints toward zero and emits the
			// replacement character for out-of-range values and UTF-16 surrogates.
			codepoint: u32
			if number < 0 || number > 0x10ffff || math.is_inf(number) {
				codepoint = 0xfffd
			} else {
				codepoint = u32(math.floor(number))
				if codepoint >= 0xd800 && codepoint <= 0xdfff do codepoint = 0xfffd
			}
			if codepoint <= 0x7f {
				if strings.write_byte(&builder, u8(codepoint)) != 1 { strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory }
			} else if codepoint <= 0x7ff {
				bytes := [2]byte{u8(0xc0 | codepoint >> 6), u8(0x80 | codepoint & 0x3f)}
				if strings.write_string(&builder, transmute(string)bytes[:]) != 2 { strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory }
			} else if codepoint <= 0xffff {
				bytes := [3]byte{u8(0xe0 | codepoint >> 12), u8(0x80 | codepoint >> 6 & 0x3f), u8(0x80 | codepoint & 0x3f)}
				if strings.write_string(&builder, transmute(string)bytes[:]) != 3 { strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory }
			} else {
				bytes := [4]byte{u8(0xf0 | codepoint >> 18), u8(0x80 | codepoint >> 12 & 0x3f), u8(0x80 | codepoint >> 6 & 0x3f), u8(0x80 | codepoint & 0x3f)}
				if strings.write_string(&builder, transmute(string)bytes[:]) != 4 { strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory }
			}
		}
		result, constructor_error := value.string_value(strings.to_string(builder), allocator)
		strings.builder_destroy(&builder)
		if value.constructor_error_kind(&constructor_error) != .None { return {}, .None, .Out_Of_Memory }
		return result, .None, nil
	}
	if opcode == .Explode {
		if kind != .String do return {}, .Cannot_Iterate, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Iterate, nil
		result, array_error := value.array_value(allocator)
		if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
		for at := 0; at < len(text); {
			next, codepoint := utf8_trim_next(text, at)
			at = next
			item := value.number_value(f64(codepoint))
			_, append_error := value.array_append_take(&result, &item)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		return result, .None, nil
	}
	if opcode == .Tostring {
		if kind == .Number {
			number, number_ok := value.number_value_get(input)
			if number_ok && math.is_inf(number) {
				text := "-1.7976931348623157e+308" if number < 0 else "1.7976931348623157e+308"
				result, constructor_error := value.string_value(text, allocator)
				if value.constructor_error_kind(&constructor_error) != .None { return {}, .None, .Out_Of_Memory }
				return result, .None, nil
			}
		}
		if kind == .String {
			result := value.clone_value(input)
			if value.kind_of(&result) == .Invalid do return {}, .None, .Out_Of_Memory
			return result, .None, nil
		}
		text, text_ok, text_error := text_coercion_text(input, allocator)
		if text_error != nil do return {}, .None, text_error
		if !text_ok do return {}, .Cannot_Trim, nil
		result, constructor_error := value.string_value(text, allocator)
		free_error := runtime.mem_free_bytes(transmute([]byte)text, allocator)
		if constructor_error != nil do _ = value.destroy_constructor_error(&constructor_error)
		if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Utf8bytelength {
		if kind != .String do return {}, .Cannot_Trim, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Trim, nil
		return value.number_value(f64(len(text))), .None, nil
	}
	if opcode == .From_Entries {
		if kind != .Array do return {}, .Cannot_Iterate, nil
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		result, object_error := value.object_value(allocator)
		if value.object_error_kind(&object_error) != .None do return {}, .None, .Out_Of_Memory
		for i in 0..<length {
			entry, entry_ok := value.array_element_copy(input, i)
			if !entry_ok || value.kind_of(&entry) != .Object { _ = value.destroy_value(&entry); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			key_names := [?]string{"key", "Key", "name", "Name"}
			value_names := [?]string{"value", "Value"}
			key, key_ok := from_entries_member_copy(&entry, key_names[:])
			item, item_ok := from_entries_member_copy(&entry, value_names[:])
			if !item_ok {
				// jq defaults an omitted value field to null.
				item = value.null_value()
				item_ok = true
			}
			_ = value.destroy_value(&entry)
			if !key_ok || !item_ok || value.kind_of(&key) != .String { _ = value.destroy_value(&key); _ = value.destroy_value(&item); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			_, displaced, set_error := value.object_set_take(&result, &key, &item)
			_ = value.destroy_value(&displaced)
			if value.object_error_kind(&set_error) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&item); _ = value.destroy_object_error(&set_error); _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
		}
		return result, .None, nil
	}
	if opcode == .To_Entries {
		if kind != .Object do return {}, .Cannot_Iterate, nil
		length, length_ok := value.object_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		result, array_error := value.array_value(allocator)
		if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
		for i in 0..<length {
			key, item, entry_ok := value.object_entry_copy(input, i)
			if !entry_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			entry, object_error := value.object_value(allocator)
			if value.object_error_kind(&object_error) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&item); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			key_name, key_name_error := value.string_value("key", allocator)
			value_name, value_name_error := value.string_value("value", allocator)
			if value.constructor_error_kind(&key_name_error) != .None || value.constructor_error_kind(&value_name_error) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&item); _ = value.destroy_value(&key_name); _ = value.destroy_value(&value_name); _ = value.destroy_value(&entry); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			_, displaced_key, set_key_error := value.object_set_take(&entry, &key_name, &key)
			_, displaced_value, set_value_error := value.object_set_take(&entry, &value_name, &item)
			_ = value.destroy_value(&displaced_key); _ = value.destroy_value(&displaced_value)
			if value.object_error_kind(&set_key_error) != .None || value.object_error_kind(&set_value_error) != .None { _ = value.destroy_value(&entry); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
			_, append_error := value.array_append_take(&result, &entry)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&entry); _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		return result, .None, nil
	}
	if opcode == .Isnan {
		if kind != .Number do return value.boolean_value(false), .None, nil
		number, number_ok := value.number_value_get(input)
		if !number_ok do return {}, .Cannot_Number, nil
		return value.boolean_value(math.is_nan(number)), .None, nil
	}
	if opcode == .Not_Builtin {
		falsey := kind == .Null
		if kind == .Boolean {
			boolean, boolean_ok := value.boolean_value_get(input)
			if boolean_ok {
				falsey = !boolean
			}
		}
		return value.boolean_value(falsey), .None, nil
	}
	if opcode == .Ascii_Downcase || opcode == .Ascii_Upcase {
		if kind != .String do return {}, .Cannot_Trim, nil
		text, text_ok := value.string_borrowed(input)
		if !text_ok do return {}, .Cannot_Trim, nil
		if len(text) == 0 {
			result, err := value.string_value(text, allocator)
			if value.constructor_error_kind(&err) != .None do return {}, .None, .Out_Of_Memory
			return result, .None, nil
		}
		memory, allocation_error := runtime.mem_alloc_bytes(len(text), 1, allocator)
		if allocation_error != nil || len(memory) != len(text) {
			if len(memory) > 0 { _ = runtime.mem_free_bytes(memory, allocator) }
			return {}, .None, .Out_Of_Memory
		}
		copy(memory, transmute([]byte)text)
		for index in 0..<len(memory) {
			byte := memory[index]
			if opcode == .Ascii_Downcase {
				if byte >= 'A' && byte <= 'Z' { memory[index] = byte + 32 }
			} else {
				if byte >= 'a' && byte <= 'z' { memory[index] = byte - 32 }
			}
		}
		result, err := value.string_value(transmute(string)memory, allocator)
		free_error := runtime.mem_free_bytes(memory, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			if value.constructor_error_kind(&err) == .None { _ = value.destroy_value(&result) }
			return {}, .None, free_error
		}
		if value.constructor_error_kind(&err) != .None do return {}, .None, .Out_Of_Memory
		return result, .None, nil
	}
	if opcode == .Reverse {
		zero_length := kind == .Null
		if kind == .Number {
			number, number_ok := value.number_value_get(input)
			zero_length = number_ok && number == 0
		} else if kind == .String {
			text, text_ok := value.string_borrowed(input)
			zero_length = text_ok && len(text) == 0
		} else if kind == .Object {
			object_length, object_ok := value.object_length(input)
			zero_length = object_ok && object_length == 0
		}
		if zero_length {
			result, array_error := value.array_value(allocator)
			if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
			return result, .None, nil
		}
		if kind != .Array do return {}, .Cannot_Iterate, nil
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		result, array_error := value.array_value(allocator)
		if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
		for i := length-1; i >= 0; i -= 1 {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok { _ = value.destroy_value(&result); return {}, .Cannot_Iterate, nil }
			_, append_error := value.array_append_take(&result, &item)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		return result, .None, nil
	}
	if opcode == .Last {
		if kind == .Null do return value.null_value(), .None, nil
		if kind != .Array do return {}, .Cannot_Index_With_String, nil
		length, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Index_With_String, nil
		if length == 0 do return value.null_value(), .None, nil
		result, element_ok := value.array_element_copy(input, length-1)
		if !element_ok do return {}, .Cannot_Index_With_String, nil
		return result, .None, nil
	}
	if opcode == .First {
		if kind == .Null do return value.null_value(), .None, nil
		if kind != .Array do return {}, .Cannot_Index_With_String, nil
		length, ok := value.array_length(input)
		if !ok do return {}, .Cannot_Index_With_String, nil
		if length == 0 do return value.null_value(), .None, nil
		result, element_ok := value.array_element_copy(input, 0)
		if !element_ok do return {}, .Cannot_Index_With_String, nil
		return result, .None, nil
	}
	if opcode == .Add_Builtin {
		if kind == .Object {
			iterator := value.object_iterator()
			acc := value.Value{}
			have_acc := false
			for {
				key, item, found := value.object_iter_next_copy(input, &iterator)
				if !found do break
				_ = value.destroy_value(&key)
				if !have_acc {
					acc = item
					have_acc = true
					continue
				}
				result, add_error := value.value_add(&acc, &item, allocator)
				kind_error := value.value_add_error_kind(&add_error)
				_ = value.destroy_value(&acc)
				_ = value.destroy_value(&item)
				if kind_error != .None {
					cleanup_error := value.destroy_value_add_error(&add_error)
					if cleanup_error != nil do return {}, .None, cleanup_error
					return {}, .Cannot_Add, nil
				}
				acc = result
			}
			if !have_acc do return value.null_value(), .None, nil
			return acc, .None, nil
		}
		if kind != .Array do return {}, .Cannot_Add, nil
		n, ok := value.array_length(input)
		if !ok || n == 0 do return value.null_value(), .None, nil
		acc, copy_ok := value.array_element_copy(input, 0)
		if !copy_ok do return {}, .Cannot_Add, nil
		for i in 1..<n {
			item, item_ok := value.array_element_copy(input, i)
			if !item_ok { _ = value.destroy_value(&acc); return {}, .Cannot_Add, nil }
			result, add_error := value.value_add(&acc, &item, allocator)
			kind_error := value.value_add_error_kind(&add_error)
			_ = value.destroy_value(&acc)
			_ = value.destroy_value(&item)
			if kind_error != .None {
				// value_add may retain a partial deep-copy/validation chain on
				// failure. Retire that chain before translating the low-level
				// error into jq's runtime type error.
				cleanup_error := value.destroy_value_add_error(&add_error)
				if cleanup_error != nil do return {}, .None, cleanup_error
				return {}, .Cannot_Add, nil
			}
			acc = result
		}
		return acc, .None, nil
	}
	if kind == .Array {
		out, err := value.array_value(allocator)
		if value.array_error_kind(&err) != .None { return {}, .None, .Out_Of_Memory }
		n, _ := value.array_length(input)
		for i in 0..<n { item := value.number_value(f64(i)); _, ae := value.array_append_take(&out, &item); if value.array_error_kind(&ae) != .None { _ = value.destroy_value(&out); return {}, .None, .Out_Of_Memory } }
		return out, .None, nil
	}
	if kind == .Object {
		out, err := value.array_value(allocator)
		if value.array_error_kind(&err) != .None { return {}, .None, .Out_Of_Memory }
		n, _ := value.object_length(input)
		for i in 0..<n { key, _, ok := value.object_entry_copy(input, i); if !ok { _ = value.destroy_value(&out); return {}, .None, nil }; _, ae := value.array_append_take(&out, &key); if value.array_error_kind(&ae) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&out); return {}, .None, .Out_Of_Memory } }
		if opcode == .Keys_Unsorted do return out, .None, nil
		// jq's `keys` sorts object names lexicographically, independent of
		// insertion order. The array owns each key, so swapping handles is a
		// move operation rather than a shallow copy.
		for i in 0..<n {
			for j in i+1..<n {
				left, lok := value.array_element_copy(&out, i)
				right, rok := value.array_element_copy(&out, j)
				if !lok || !rok { _ = value.destroy_value(&left); _ = value.destroy_value(&right); continue }
				ls, lsok := value.string_borrowed(&left)
				rs, rsok := value.string_borrowed(&right)
				if lsok && rsok && ls > rs {
					displaced, left_error := value.array_set_take(&out, i, &right)
					if value.array_error_kind(&left_error) == .None {
						_ = value.destroy_value(&displaced)
						displaced_right, right_error := value.array_set_take(&out, j, &left)
						_ = value.destroy_value(&displaced_right)
						if value.array_error_kind(&right_error) != .None {
							_ = value.destroy_value(&left)
						}
					} else {
						_ = value.destroy_value(&left)
						_ = value.destroy_value(&right)
					}
				} else {
					_ = value.destroy_value(&left)
					_ = value.destroy_value(&right)
				}
			}
		}
		return out, .None, nil
	}
	return {}, .Cannot_Length, nil
}

@(private)
apply_binary :: proc(opcode: program.Opcode, left, right: ^value.Value, span: program.Source_Span, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	_ = span
	#partial switch opcode {
	case .Add:
		result, err := value.value_add(left, right, allocator)
		kind := value.value_add_error_kind(&err)
		if kind == .None do return result, .None, nil
		cleanup_error := value.destroy_value_add_error(&err)
		if cleanup_error != nil do return {}, .None, cleanup_error
		if kind == .Out_Of_Memory || kind == .Size_Overflow || kind == .Allocator_Unsupported do return {}, .None, .Out_Of_Memory
		return {}, .Cannot_Add, nil
	case .Subtract:
		if value.kind_of(left) == .Array && value.kind_of(right) == .Array {
			result, array_error := array_subtract(left, right, allocator)
			kind := value.array_error_kind(&array_error)
			if kind == .None do return result, .None, nil
			cleanup_error := value.destroy_array_error(&array_error)
			if cleanup_error != nil do return {}, .None, cleanup_error
			if kind == .Out_Of_Memory || kind == .Size_Overflow || kind == .Allocator_Unsupported {
				return {}, .None, .Out_Of_Memory
			}
			return {}, .Cannot_Subtract, nil
		}
		result, kind := value.number_subtract(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Subtract, nil
	case .Multiply:
		left_kind := value.kind_of(left)
		right_kind := value.kind_of(right)
		if left_kind == .Object && right_kind == .Object {
			result, merge_ok, merge_error := object_multiply_merge(left, right, allocator)
			if merge_error != nil do return {}, .None, merge_error
			if merge_ok do return result, .None, nil
			return {}, .Cannot_Multiply, nil
		}
		if (left_kind == .String && right_kind == .Number) || (left_kind == .Number && right_kind == .String) {
			text_value := left if left_kind == .String else right
			number_value := right if left_kind == .String else left
			text, text_ok := value.string_borrowed(text_value)
			count_float, number_ok := value.number_value_get(number_value)
			if !text_ok || !number_ok do return {}, .Cannot_Multiply, nil
			if math.is_nan(count_float) || count_float < 0 do return value.null_value(), .None, nil
			if count_float == 0 || len(text) == 0 {
				empty, empty_error := value.string_value("", allocator)
				if value.constructor_error_kind(&empty_error) != .None do return {}, .None, .Out_Of_Memory
				return empty, .None, nil
			}
			if count_float > 100_000_000 do return {}, .Cannot_Multiply, nil
			count := int(count_float)
			if count <= 0 {
				empty, empty_error := value.string_value("", allocator)
				if value.constructor_error_kind(&empty_error) != .None do return {}, .None, .Out_Of_Memory
				return empty, .None, nil
			}
			if u64(len(text)) * u64(count) > 100_000_000 do return {}, .Cannot_Multiply, nil
			builder: strings.Builder
			_, builder_error := strings.builder_init(&builder, allocator)
			if builder_error != nil do return {}, .None, builder_error
			for _ in 0..<count {
				if strings.write_string(&builder, text) != len(text) {
					strings.builder_destroy(&builder)
					return {}, .None, .Out_Of_Memory
				}
			}
			result_text := strings.to_string(builder)
			result, constructor_error := value.string_value(result_text, allocator)
			free_error := runtime.mem_free_bytes(transmute([]byte)result_text, allocator)
			if value.constructor_error_kind(&constructor_error) != .None do _ = value.destroy_constructor_error(&constructor_error)
			if constructor_error != nil || free_error != nil do return {}, .None, free_error if free_error != nil else .Out_Of_Memory
			return result, .None, nil
		}
		result, kind := value.number_multiply(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Multiply, nil
	case .Divide:
		if value.kind_of(left) == .String && value.kind_of(right) == .String {
			separator, separator_ok := value.string_borrowed(right)
			if !separator_ok do return {}, .Cannot_Divide, nil
			result, runtime_kind, allocation_error := split_result(left, separator, allocator)
			if allocation_error != nil do return {}, .None, allocation_error
			if runtime_kind == .None do return result, .None, nil
			return {}, .Cannot_Divide, nil
		}
		result, kind := value.number_divide(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Divide, nil
	case .Modulo:
		result, kind := value.number_modulo(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Modulo, nil
	case .Pow:
		base, base_ok := value.number_value_get(left)
		exponent, exponent_ok := value.number_value_get(right)
		if !base_ok || !exponent_ok do return {}, .Cannot_Multiply, nil
		return value.number_value(math.pow_f64(base, exponent)), .None, nil
	case .Equal: return value.boolean_value(value.values_equal(left, right)), .None, nil
	case .Not_Equal: return value.boolean_value(!value.values_equal(left, right)), .None, nil
	case .Less, .Less_Equal, .Greater, .Greater_Equal:
		comparison, ok := compare_values(left, right)
		if !ok do return {}, .None, .Out_Of_Memory
		#partial switch opcode {
		case .Less: return value.boolean_value(comparison < 0), .None, nil
		case .Less_Equal: return value.boolean_value(comparison <= 0), .None, nil
		case .Greater: return value.boolean_value(comparison > 0), .None, nil
		case .Greater_Equal: return value.boolean_value(comparison >= 0), .None, nil
		}
	}
	return {}, .None, .Out_Of_Memory
}

// object_multiply_merge implements jq's recursive object multiplication. Both
// operands remain borrowed; the result owns cloned keys and values, and nested
// objects are merged only when both corresponding values are objects.
object_multiply_merge :: proc(left, right: ^value.Value, allocator: runtime.Allocator) -> (value.Value, bool, runtime.Allocator_Error) {
	result, object_error := value.object_value(allocator)
	if value.object_error_kind(&object_error) != .None do return {}, false, .Out_Of_Memory
	left_length, left_ok := value.object_length(left)
	if !left_ok { _ = value.destroy_value(&result); return {}, false, nil }
	for i in 0..<left_length {
		key, item, entry_ok := value.object_entry_copy(left, i)
		if !entry_ok { _ = value.destroy_value(&result); return {}, false, nil }
		_, _, set_error := value.object_set_take(&result, &key, &item)
		if value.object_error_kind(&set_error) != .None {
			_ = value.destroy_value(&key); _ = value.destroy_value(&item); _ = value.destroy_value(&result)
			return {}, false, .Out_Of_Memory
		}
	}
	right_length, right_ok := value.object_length(right)
	if !right_ok { _ = value.destroy_value(&result); return {}, false, nil }
	for i in 0..<right_length {
		key, incoming, entry_ok := value.object_entry_copy(right, i)
		if !entry_ok { _ = value.destroy_value(&result); return {}, false, nil }
		key_text, key_ok := value.string_borrowed(&key)
		if !key_ok { _ = value.destroy_value(&key); _ = value.destroy_value(&incoming); _ = value.destroy_value(&result); return {}, false, nil }
		existing, found := value.object_get_copy(&result, key_text)
		if found && value.kind_of(&existing) == .Object && value.kind_of(&incoming) == .Object {
			merged, merged_ok, merge_error := object_multiply_merge(&existing, &incoming, allocator)
			_ = value.destroy_value(&existing)
			_ = value.destroy_value(&incoming)
			if merge_error != nil { _ = value.destroy_value(&key); _ = value.destroy_value(&result); return {}, false, merge_error }
			if !merged_ok { _ = value.destroy_value(&key); _ = value.destroy_value(&result); return {}, false, nil }
			_, displaced, set_error := value.object_set_take(&result, &key, &merged)
			_ = value.destroy_value(&displaced)
			if value.object_error_kind(&set_error) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&merged); _ = value.destroy_value(&result); return {}, false, .Out_Of_Memory }
		} else {
			_ = value.destroy_value(&existing)
			_, displaced, set_error := value.object_set_take(&result, &key, &incoming)
			_ = value.destroy_value(&displaced)
			if value.object_error_kind(&set_error) != .None { _ = value.destroy_value(&key); _ = value.destroy_value(&incoming); _ = value.destroy_value(&result); return {}, false, .Out_Of_Memory }
		}
	}
	return result, true, nil
}

@(private)
array_subtract :: proc(left, right: ^value.Value, allocator: runtime.Allocator) -> (value.Value, value.Array_Operation_Error) {
	result, create_error := value.array_value(allocator)
	if value.array_error_kind(&create_error) != .None do return {}, create_error
	left_length, left_ok := value.array_length(left)
	right_length, right_ok := value.array_length(right)
	if !left_ok || !right_ok {
		_ = value.destroy_value(&result)
		return {}, value.Array_Operation_Error{}
	}
	for i in 0..<left_length {
		item, item_ok := value.array_element_copy(left, i)
		if !item_ok { _ = value.destroy_value(&result); return {}, value.Array_Operation_Error{} }
		remove := false
		for j in 0..<right_length {
			other, other_ok := value.array_element_copy(right, j)
			if !other_ok { _ = value.destroy_value(&item); _ = value.destroy_value(&result); return {}, value.Array_Operation_Error{} }
			if value.values_equal(&item, &other) do remove = true
			_ = value.destroy_value(&other)
			if remove do break
		}
		if remove { _ = value.destroy_value(&item); continue }
		_, append_error := value.array_append_take(&result, &item)
		if value.array_error_kind(&append_error) != .None {
			_ = value.destroy_value(&item)
			_ = value.destroy_value(&result)
			return {}, append_error
		}
	}
	return result, {}
}

@(private)
compare_values :: proc(left, right: ^value.Value) -> (int, bool) {
	left_kind := value.kind_of(left); right_kind := value.kind_of(right)
	if left_kind != right_kind do return int(left_kind)-int(right_kind), true
	#partial switch left_kind {
	case .Null: return 0, true
	case .Boolean:
		l, lok := value.boolean_value_get(left); r, rok := value.boolean_value_get(right)
		if !lok || !rok do return 0, false
		return (1 if l else 0)-(1 if r else 0), true
	case .Number:
		l, lok := value.number_value_get(left); r, rok := value.number_value_get(right)
		if !lok || !rok do return 0, false
		if math.is_nan(l) { return -1 if !math.is_nan(r) else 0, true }
		if math.is_nan(r) do return 1, true
		return value.compare_numbers(left, right)
	case .String:
		l, lok := value.string_borrowed(left); r, rok := value.string_borrowed(right)
		if !lok || !rok do return 0, false
		if l < r do return -1, true; if l > r do return 1, true; return 0, true
	case .Array:
		ll, lok := value.array_length(left); rl, rok := value.array_length(right)
		if !lok || !rok do return 0, false
		limit := ll if ll < rl else rl
		for i in 0..<limit {
			lv, l_ok := value.array_element_copy(left, i); rv, r_ok := value.array_element_copy(right, i)
			if !l_ok || !r_ok { _ = value.destroy_value(&lv); _ = value.destroy_value(&rv); return 0, false }
			cmp, ok := compare_values(&lv, &rv); _ = value.destroy_value(&lv); _ = value.destroy_value(&rv)
			if !ok || cmp != 0 do return cmp, ok
		}
		if ll < rl do return -1, true; if ll > rl do return 1, true; return 0, true
	case .Object:
		if value.values_equal(left, right) do return 0, true
		ll, lok := value.object_length(left); rl, rok := value.object_length(right)
		if !lok || !rok do return 0, false
		if ll < rl do return -1, true
		if ll > rl do return 1, true
		// Equal-sized objects are ordered lexicographically by their key/value
		// pairs. Comparing only lengths makes both directions report `greater`.
		li := value.object_iterator()
		ri := value.object_iterator()
		for {
			lk, lv, l_ok := value.object_iter_next_copy(left, &li)
			rk, rv, r_ok := value.object_iter_next_copy(right, &ri)
			if !l_ok || !r_ok {
				_ = value.destroy_value(&lk); _ = value.destroy_value(&lv)
				_ = value.destroy_value(&rk); _ = value.destroy_value(&rv)
				break
			}
			cmp, cmp_ok := compare_values(&lk, &rk)
			if cmp_ok && cmp != 0 {
				_ = value.destroy_value(&lk); _ = value.destroy_value(&lv)
				_ = value.destroy_value(&rk); _ = value.destroy_value(&rv)
				return cmp, true
			}
			if cmp_ok {
				cmp, cmp_ok = compare_values(&lv, &rv)
				_ = value.destroy_value(&lk); _ = value.destroy_value(&lv)
				_ = value.destroy_value(&rk); _ = value.destroy_value(&rv)
				if cmp_ok && cmp != 0 do return cmp, true
			} else {
				_ = value.destroy_value(&lk); _ = value.destroy_value(&lv)
				_ = value.destroy_value(&rk); _ = value.destroy_value(&rv)
			}
		}
		return 0, true
	}
	return 0, false
}

// step_evaluator advances only until one independently owned output or one
// terminal/resource result is available. It never materializes an output
// stream. Done, Runtime_Error, and Misuse replay deterministically.
step_evaluator :: proc(evaluator: ^Evaluator) -> Step_Result {
	if evaluator == nil || evaluator^ == nil do return misuse_step(.Invalid_Evaluator)
	storage := storage_of(evaluator)
	if storage.self != evaluator do return misuse_step(.Copied_Evaluator)
	if storage.state == .Cleanup_Only do return misuse_step(.Invalid_Evaluator)
	if storage.state == .Destroyed do return misuse_step(.Invalid_Evaluator)
	if storage.state == .Terminal do return terminal_step(storage)
	if storage.compiled == nil {
		// A failed lifetime check severs the invalid borrow before owned cleanup
		// retries. Only that recorded terminal path may reach this state.
		if storage.pending == .Terminal_Cleanup &&
		   storage.pending_terminal == .Misuse &&
		   storage.misuse == .Invalid_Program_Lifetime {
			return complete_terminal_cleanup(storage)
		}
		return begin_terminal_misuse(storage, .Invalid_Program_Lifetime)
	}
	if !program.program_is_active(storage.compiled) {
		storage.compiled = nil
		storage.misuse = .Invalid_Program_Lifetime
		if storage.pending == .Terminal_Cleanup {
			storage.pending_terminal = .Misuse
			return complete_terminal_cleanup(storage)
		}
		return begin_terminal(storage, .Misuse)
	}
	live_seal, seal_ok := seal_program(storage.compiled)
	if !seal_ok || live_seal != storage.sealed_program {
		return begin_terminal_misuse(storage, .Malformed_Program)
	}
	if pending_error := retire_pending_memory(storage); pending_error != nil {
		return resource_step(pending_error)
	}
	if pending_error := retire_pending_constructor_error(storage); pending_error != nil {
		return resource_step(pending_error)
	}
	if storage.pending == .Terminal_Cleanup do return complete_terminal_cleanup(storage)
	if storage.pending == .Suppress_Runtime {
		result, ready := continue_suppression(storage)
		if ready do return result
	}
	for {
		if storage.frame_count == 0 do return begin_terminal(storage, .Done)
		index := storage.frame_count-1
		frame := &storage.frames[index]
		instruction, instruction_ok := program.program_instruction(storage.compiled, frame.instruction)
		if !instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
		if !resumed_composite_instruction_valid(storage, frame, instruction) {
			return begin_terminal_misuse(storage, .Malformed_Program)
		}
		if frame.constructor_pending_failure {
			free_error := constructor_frame_retry_pending(frame)
			if free_error != nil do return resource_step(free_error)
			frame.constructor_pending_failure = false
			return begin_terminal_misuse(storage, .Malformed_Program)
		}

		switch frame.phase {
		case .Enter:
			if frame.mode == .Field_Only {
				if instruction.opcode != .Field {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				name, name_ok := field_text(storage, instruction)
				if !name_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				if name == "" {
					kind := value.kind_of(&frame.input)
					if kind != .Array && kind != .Object {
						key, key_error := cannot_iterate_runtime_key(&frame.input, storage.allocator)
						if key_error != nil { return resource_step(key_error) }
						err := Runtime_Error{kind=.Cannot_Iterate, input_kind=kind, span=instruction.span, key=key}
						result, ready := raise_runtime(storage, index, err)
						if len(key) > 0 {
							free_error := runtime.mem_free_bytes(transmute([]byte)key, storage.allocator)
							if free_error != nil && free_error != .Mode_Not_Implemented { return resource_step(free_error) }
						}
						if ready do return result
						continue
					}
					if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
					frame.iterator_cursor = 0
					frame.phase = .Iterator_Active
					continue
				}
				input_kind := value.kind_of(&frame.input)
				if input_kind == .Object || input_kind == .Null {
					capacity_error := prepare_output(storage, index)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				output, runtime_error, valid := field_result(storage, frame, instruction)
				if !valid do return begin_terminal_misuse(storage, .Malformed_Program)
				if runtime_error.kind != .None {
					result, ready := raise_runtime(storage, index, runtime_error)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
				continue
			}
			if frame.mode == .Index_Only {
				output, runtime_error, valid := index_result(storage, frame, instruction)
				if !valid do return begin_terminal_misuse(storage, .Malformed_Program)
				if runtime_error.kind != .None {
					result, ready := raise_runtime(storage, index, runtime_error)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
				continue
			}
			if frame.mode == .Slice_Only {
				output, runtime_error, valid := slice_result(storage, frame, instruction)
				if !valid do return begin_terminal_misuse(storage, .Malformed_Program)
				if runtime_error.kind != .None {
					result, ready := raise_runtime(storage, index, runtime_error)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
				continue
			}

			switch instruction.opcode {
			case .Identity:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output: value.Value
				if instruction.has_literal {
					literal, literal_error, cleanup_error := literal_value(storage, instruction)
					if cleanup_error != nil do return resource_step(cleanup_error)
					if literal_error != .None {
						// Constructor allocation failures are retryable evaluator
						// resources, not malformed program metadata. A cleanup-bearing
						// failure has already returned above with its retry state intact.
						if literal_error == .Out_Of_Memory || literal_error == .Size_Overflow {
							return resource_step(.Out_Of_Memory)
						}
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					output = literal
				} else {
					if instruction.operands_count != 0 {
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					output = value.clone_value(&frame.input)
				}
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Field:
				if instruction.operands_count == 1 {
					input_kind := value.kind_of(&frame.input)
					if input_kind == .Object || input_kind == .Null {
						capacity_error := prepare_output(storage, index)
						if capacity_error != nil do return resource_step(capacity_error)
						frame = &storage.frames[index]
					}
					output, runtime_error, valid := field_result(storage, frame, instruction)
					if !valid do return begin_terminal_misuse(storage, .Malformed_Program)
					if runtime_error.kind != .None {
						result, ready := raise_runtime(storage, index, runtime_error)
						if ready do return result
						continue
					}
					frame.phase = .Leaf_Yielded
					result, ready := propagate_output(storage, index, &output)
					if ready do return result
				} else if instruction.operands_count == 2 {
					// An empty field name is the parser's representation of `.[]`.
					// Keep the source value owned by this frame and yield one owned
					// element per step, matching jq's generator cardinality.
					name, name_ok := field_text(storage, instruction)
					if !name_ok do return begin_terminal_misuse(storage, .Malformed_Program)
					if name == "" {
						// Empty-field postfixes have a child (`.a[]` or `.[]`).
						// Evaluate that child first; the child result is re-entered
						// through this same instruction by propagate_output, where the
						// iterator consumes the resulting array/object.
						if !capture_composite_instruction(storage, frame, instruction) {
							return begin_terminal_misuse(storage, .Malformed_Program)
						}
						frame.phase = .Field_Start_Child
						continue
					}
					if !capture_composite_instruction(storage, frame, instruction) {
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					frame.phase = .Field_Start_Child
				} else {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
			case .Index:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Index_Start_Child
			case .Slice:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Slice_Start_Child
			case .Variable:
				output, variable_ok := variable_result(storage, index, instruction)
				if !variable_ok || value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Empty:
				// `empty` is a generator that yields no values. Marking the
				// frame complete lets the normal exhaustion continuation advance
				// its parent without allocating an output value.
				frame.phase = .Complete
				continue
			case .Values:
				// `values` suppresses null while passing through every other
				// input unchanged. Null suppression follows the same exhaustion
				// path as `empty`, preserving parent continuation behavior.
				if value.kind_of(&frame.input) == .Null {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Arrays:
				// `arrays` yields only array inputs; all other kinds are
				// suppressed through the ordinary exhaustion continuation.
				if value.kind_of(&frame.input) != .Array {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Objects:
				// `objects` yields only object inputs; all other kinds are
				// suppressed through the ordinary exhaustion continuation.
				if value.kind_of(&frame.input) != .Object {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Iterables:
				// `iterables` yields arrays and objects, suppressing scalars.
				kind := value.kind_of(&frame.input)
				if kind != .Array && kind != .Object {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Scalars:
				// `scalars` yields null, booleans, numbers, and strings while
				// suppressing arrays and objects.
				kind := value.kind_of(&frame.input)
				if kind == .Array || kind == .Object {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Booleans:
				// `booleans` yields only boolean inputs and suppresses all
				// other kinds through normal exhaustion.
			if value.kind_of(&frame.input) != .Boolean {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Nulls:
				// `nulls` yields only null inputs and suppresses all other
				// kinds through normal exhaustion.
				if value.kind_of(&frame.input) != .Null {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Numbers:
				// `numbers` yields only number inputs and suppresses all other
				// kinds through normal exhaustion.
				if value.kind_of(&frame.input) != .Number {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Strings:
				// `strings` yields only string inputs and suppresses all other
				// kinds through normal exhaustion.
				if value.kind_of(&frame.input) != .String {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Finites:
				// jq's finites is `select(isfinite)`, where NaN is considered finite
				// by jq and is serialized as null; only infinities are suppressed.
				if value.kind_of(&frame.input) != .Number {
					frame.phase = .Complete
					continue
				}
				number, number_ok := value.number_value_get(&frame.input)
				if !number_ok || math.is_inf(number) {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Normals:
				// `normals` forwards only IEEE-754 normal finite numbers.
				if value.kind_of(&frame.input) != .Number {
					frame.phase = .Complete
					continue
				}
				number, number_ok := value.number_value_get(&frame.input)
				minimum_normal := 2.2250738585072014e-308
				if !number_ok || math.is_nan(number) || math.is_inf(number) || math.abs(number) < minimum_normal {
					frame.phase = .Complete
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
				if value.kind_of(&output) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Join:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				separator_instruction, separator_ok := program.program_instruction(storage.compiled, child)
				separator_operand, operand_ok := program.program_operand(storage.compiled, separator_instruction.operands_start)
				separator, separator_text_ok := program.operand_text(storage.compiled, separator_operand)
				if !child_ok || !separator_ok || separator_operand.kind != .Text || !separator_instruction.has_literal || separator_instruction.literal_kind != .String || !operand_ok || !separator_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := join_result(&frame.input, separator, storage.allocator)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					owned_key := ""
					if runtime_kind == .Cannot_Iterate {
						key_error: runtime.Allocator_Error
						owned_key, key_error = join_type_error_runtime_key(&frame.input, separator, storage.allocator)
						if key_error != nil do return resource_step(key_error)
						if len(owned_key) > 0 {
							err.key = owned_key
						}
					}
					result, ready := raise_runtime(storage, index, err)
					if len(owned_key) > 0 {
						free_error := runtime.mem_free_bytes(transmute([]byte)owned_key, storage.allocator)
						if free_error != nil do return resource_step(free_error)
					}
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Contains:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				needle_instruction, needle_ok := program.program_instruction(storage.compiled, child)
				needle: value.Value
				needle_error: value.Error
				needle_cleanup: runtime.Allocator_Error
				if needle_instruction.opcode == .Object {
					needle, needle_error, needle_cleanup = literal_object_value(storage, needle_instruction)
				} else if needle_instruction.opcode == .Array {
					needle, needle_error, needle_cleanup = literal_array_value(storage, needle_instruction)
				} else {
					needle, needle_error, needle_cleanup = literal_value(storage, needle_instruction)
				}
				if !child_ok || !needle_ok || needle_cleanup != nil || needle_error != .None {
					if value.kind_of(&needle) != .Invalid do _ = value.destroy_value(&needle)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind := contains_result(&frame.input, &needle)
				_ = value.destroy_value(&needle)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Has:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				argument_instruction, argument_ok := program.program_instruction(storage.compiled, child)
				argument: value.Value
				argument_error: value.Error
				argument_cleanup: runtime.Allocator_Error
				if argument_instruction.opcode == .Nan {
					argument = value.number_value(math.nan_f64())
				} else {
					argument, argument_error, argument_cleanup = literal_value(storage, argument_instruction)
				}
				if argument_cleanup != nil do return resource_step(argument_cleanup)
				if argument_error != .None || !child_ok || !argument_ok {
					if value.kind_of(&argument) != .Invalid do _ = value.destroy_value(&argument)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind := has_result(&frame.input, &argument)
				_ = value.destroy_value(&argument)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Bsearch:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				needle_instruction, needle_ok := program.program_instruction(storage.compiled, child)
				needle: value.Value
				needle_error: value.Error
				needle_cleanup: runtime.Allocator_Error
				if needle_instruction.opcode == .Object {
					needle, needle_error, needle_cleanup = literal_object_value(storage, needle_instruction)
				} else {
					needle, needle_error, needle_cleanup = literal_value(storage, needle_instruction)
				}
				if needle_cleanup != nil do return resource_step(needle_cleanup)
				if needle_error != .None || !child_ok || !needle_ok {
					if value.kind_of(&needle) != .Invalid do _ = value.destroy_value(&needle)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind := bsearch_result(&frame.input, &needle)
				_ = value.destroy_value(&needle)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					owned_key, key_error := bsearch_runtime_key(&frame.input, storage.allocator)
					if key_error != nil do return resource_step(key_error)
					err.key = owned_key
					result, ready := raise_runtime(storage, index, err)
					if len(owned_key) > 0 {
						free_error := runtime.mem_free_bytes(transmute([]byte)owned_key, storage.allocator)
						if free_error != nil do return resource_step(free_error)
					}
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Startswith, .Endswith:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				needle_instruction, needle_ok := program.program_instruction(storage.compiled, child)
				needle_operand, operand_ok := program.program_operand(storage.compiled, needle_instruction.operands_start)
				needle, needle_text_ok := program.operand_text(storage.compiled, needle_operand)
				if !child_ok || !needle_ok || needle_operand.kind != .Text || !needle_instruction.has_literal || needle_instruction.literal_kind != .String || !operand_ok || !needle_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind := prefix_result(&frame.input, needle, instruction.opcode)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Ltrimstr, .Rtrimstr, .Trimstr:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				needle_instruction, needle_ok := program.program_instruction(storage.compiled, child)
				needle_operand, operand_ok := program.program_operand(storage.compiled, needle_instruction.operands_start)
				needle, needle_text_ok := program.operand_text(storage.compiled, needle_operand)
				if !child_ok || !needle_ok || needle_operand.kind != .Text || !needle_instruction.has_literal || needle_instruction.literal_kind != .String || !operand_ok || !needle_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := trimstr_result(&frame.input, needle, instruction.opcode, storage.allocator)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					result, ready := raise_runtime(storage, index, err)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Split:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				separator_instruction, separator_ok := program.program_instruction(storage.compiled, child)
				separator_operand, operand_ok := program.program_operand(storage.compiled, separator_instruction.operands_start)
				separator, separator_text_ok := program.operand_text(storage.compiled, separator_operand)
				if !child_ok || !separator_ok || separator_operand.kind != .Text || !separator_instruction.has_literal || separator_instruction.literal_kind != .String || !operand_ok || !separator_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := split_result(&frame.input, separator, storage.allocator)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Index_Builtin, .Rindex_Builtin, .Indices_Builtin:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				child, child_ok := child_instruction(storage, instruction, 0)
				needle_instruction, needle_ok := program.program_instruction(storage.compiled, child)
				needle: value.Value
				needle_error: value.Error
				needle_cleanup: runtime.Allocator_Error
				if needle_instruction.opcode == .Array {
					needle, needle_error, needle_cleanup = literal_array_value(storage, needle_instruction)
				} else {
					needle, needle_error, needle_cleanup = literal_value(storage, needle_instruction)
				}
				if !child_ok || !needle_ok || needle_cleanup != nil || needle_error != .None {
					if value.kind_of(&needle) != .Invalid do _ = value.destroy_value(&needle)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := search_result(&frame.input, &needle, instruction.opcode, storage.allocator)
				_ = value.destroy_value(&needle)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Error:
				child, child_ok := child_instruction(storage, instruction, 0)
				message_instruction, message_instruction_ok := program.program_instruction(storage.compiled, child)
				if child_ok && message_instruction_ok && message_instruction.opcode == .Identity && !message_instruction.has_literal {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=.User_Error, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				message_operand, operand_ok := program.program_operand(storage.compiled, message_instruction.operands_start)
				message, message_ok := program.operand_text(storage.compiled, message_operand)
				if !child_ok || !message_instruction_ok || !operand_ok || !message_ok ||
				   message_operand.kind != .Text || !message_instruction.has_literal ||
				   message_instruction.literal_kind != .String {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				result, ready := raise_runtime(storage, index, Runtime_Error{
					kind = .User_Error,
					input_kind = value.kind_of(&frame.input),
					span = instruction.span,
					key = message,
				})
				if ready do return result
				continue
			case .IsEmpty:
				child, child_ok := child_instruction(storage, instruction, 0)
				child_instruction_value, child_instruction_ok := program.program_instruction(storage.compiled, child)
				if !child_ok || !child_instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				// Bounded static forms: `empty` produces no value, range literals
				// produce values iff their interval is non-empty, and comma streams
				// are non-empty when either side is a value-producing literal.
				is_empty := child_instruction_value.opcode == .Empty
				if child_instruction_value.opcode == .Range {
					if child_instruction_value.operands_count == 1 {
						bound_index, bound_ok := child_instruction(storage, child_instruction_value, 0)
						bound_instruction, bound_valid := program.program_instruction(storage.compiled, bound_index)
						bound_value, bound_error, bound_cleanup := literal_value(storage, bound_instruction)
						bound, bound_numeric := value.number_value_get(&bound_value)
						if !bound_ok || !bound_valid || bound_error != .None || bound_cleanup != nil || !bound_numeric { if value.kind_of(&bound_value) != .Invalid do _ = value.destroy_value(&bound_value); return begin_terminal_misuse(storage, .Malformed_Program) }
						_ = value.destroy_value(&bound_value)
						is_empty = bound <= 0
					} else {
						start_index, start_ok := child_instruction(storage, child_instruction_value, 0)
						end_index, end_ok := child_instruction(storage, child_instruction_value, 1)
						start_instruction, start_valid := program.program_instruction(storage.compiled, start_index)
						end_instruction, end_valid := program.program_instruction(storage.compiled, end_index)
						start_value, start_error, start_cleanup := literal_value(storage, start_instruction)
						end_value, end_error, end_cleanup := literal_value(storage, end_instruction)
						if !start_ok || !end_ok || !start_valid || !end_valid || start_error != .None || end_error != .None || start_cleanup != nil || end_cleanup != nil {
							if value.kind_of(&start_value) != .Invalid do _ = value.destroy_value(&start_value)
							if value.kind_of(&end_value) != .Invalid do _ = value.destroy_value(&end_value)
							return begin_terminal_misuse(storage, .Malformed_Program)
						}
						start, start_numeric := value.number_value_get(&start_value)
						end, end_numeric := value.number_value_get(&end_value)
						_ = value.destroy_value(&start_value); _ = value.destroy_value(&end_value)
						if !start_numeric || !end_numeric { return begin_terminal_misuse(storage, .Malformed_Program) }
						is_empty = start >= end
					}
				}
				output := value.boolean_value(is_empty)
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Limit:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				count_child, count_ok := child_instruction(storage, instruction, 0)
				generator_child, generator_ok := child_instruction(storage, instruction, 1)
				count_instruction, count_instruction_ok := program.program_instruction(storage.compiled, count_child)
				if !count_ok || !generator_ok || !count_instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				count_value, count_error, count_cleanup := literal_value(storage, count_instruction)
				if count_cleanup != nil || count_error != .None {
					if value.kind_of(&count_value) != .Invalid { _ = value.destroy_value(&count_value) }
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				count_number, count_number_ok := value.number_value_get(&count_value)
				_ = value.destroy_value(&count_value)
				if !count_number_ok || count_number < 0 || count_number != f64(int(count_number)) {
					result, ready := raise_runtime(storage, index, Runtime_Error{
						kind = .User_Error,
						input_kind = value.kind_of(&frame.input),
						span = instruction.span,
						key = "limit doesn't support negative count",
					})
					if ready do return result
					continue
				}
				frame.limit_remaining = u64(int(count_number))
				if frame.limit_remaining == 0 {
					frame.phase = .Complete
					continue
				}
				if storage.frame_count == len(storage.frames) {
					capacity_error := grow_frames(storage)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				input_copy := value.clone_value(&frame.input)
				if value.kind_of(&input_copy) == .Invalid || !push_frame(storage, generator_child, index, &input_copy) {
					return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
				}
				frame.phase = .Limit_Active
				continue
			case .Skip:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				count_child, count_ok := child_instruction(storage, instruction, 0)
				generator_child, generator_ok := child_instruction(storage, instruction, 1)
				count_instruction, count_instruction_ok := program.program_instruction(storage.compiled, count_child)
				if !count_ok || !generator_ok || !count_instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				count_value, count_error, count_cleanup := literal_value(storage, count_instruction)
				if count_cleanup != nil || count_error != .None {
					if value.kind_of(&count_value) != .Invalid { _ = value.destroy_value(&count_value) }
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				count_number, count_number_ok := value.number_value_get(&count_value)
				_ = value.destroy_value(&count_value)
				if !count_number_ok || count_number < 0 || count_number != f64(int(count_number)) {
					result, ready := raise_runtime(storage, index, Runtime_Error{
						kind = .User_Error,
						input_kind = value.kind_of(&frame.input),
						span = instruction.span,
						key = "skip doesn't support negative count",
					})
					if ready do return result
					continue
				}
				frame.limit_remaining = u64(int(count_number))
				if storage.frame_count == len(storage.frames) {
					capacity_error := grow_frames(storage)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				input_copy := value.clone_value(&frame.input)
				if value.kind_of(&input_copy) == .Invalid || !push_frame(storage, generator_child, index, &input_copy) {
					return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
				}
				frame.phase = .Skip_Active
				continue
			case .Nth:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				count_child, count_ok := child_instruction(storage, instruction, 0)
				generator_child, generator_ok := child_instruction(storage, instruction, 1)
				count_instruction, count_instruction_ok := program.program_instruction(storage.compiled, count_child)
				if !count_ok || !generator_ok || !count_instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				count_value, count_error, count_cleanup := literal_value(storage, count_instruction)
				if count_cleanup != nil || count_error != .None {
					if value.kind_of(&count_value) != .Invalid { _ = value.destroy_value(&count_value) }
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				count_number, count_number_ok := value.number_value_get(&count_value)
				_ = value.destroy_value(&count_value)
				if !count_number_ok || count_number < 0 || count_number != f64(int(count_number)) {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=.User_Error, input_kind=value.kind_of(&frame.input), span=instruction.span, key="nth doesn't support negative count"})
					if ready do return result
					continue
				}
				frame.limit_remaining = u64(int(count_number))
				if storage.frame_count == len(storage.frames) {
					capacity_error := grow_frames(storage)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				input_copy := value.clone_value(&frame.input)
				if value.kind_of(&input_copy) == .Invalid || !push_frame(storage, generator_child, index, &input_copy) {
					return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
				}
				frame.phase = .Nth_Active
				continue
			case .Map, .Map_Values:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				input_kind := value.kind_of(&frame.input)
				if input_kind != .Array && !(instruction.opcode == .Map_Values && input_kind == .Object) {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=.Cannot_Iterate, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				results: value.Value
				if input_kind == .Object {
					object_result, object_error := value.object_value(storage.allocator)
					if value.object_error_kind(&object_error) != .None { _ = value.destroy_object_error(&object_error); return resource_step(.Out_Of_Memory) }
					results = object_result
					frame.map_values_mode = true
				} else {
					array_result, array_error := value.array_value(storage.allocator)
					if value.array_error_kind(&array_error) != .None { _ = value.destroy_array_error(&array_error); return resource_step(.Out_Of_Memory) }
					results = array_result
					// jq's map_values keeps only the first result produced for
					// each array element, just as it does for object values.
					// Map itself must retain every child result.
					frame.map_values_mode = instruction.opcode == .Map_Values
				}
				frame.constructor_results = value.take_value(&results)
				frame.iterator_cursor = 0
				frame.phase = .Map_Start
				continue
			case .Range:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				if instruction.operands_count == 1 {
					bound_child, bound_child_ok := child_instruction(storage, instruction, 0)
					bound_instruction, bound_instruction_ok := program.program_instruction(storage.compiled, bound_child)
					if bound_child_ok && bound_instruction_ok && bound_instruction.opcode == .Range && bound_instruction.operands_count == 1 {
						inner_child, inner_child_ok := child_instruction(storage, bound_instruction, 0)
						inner_instruction, inner_instruction_ok := program.program_instruction(storage.compiled, inner_child)
						inner_value, inner_error, inner_cleanup := literal_value(storage, inner_instruction)
						inner_bound, inner_numeric := value.number_value_get(&inner_value)
						if inner_child_ok && inner_instruction_ok && inner_error == .None && inner_cleanup == nil && inner_numeric && inner_bound >= 0 && inner_bound == f64(int(inner_bound)) {
							result, array_error := value.array_value(storage.allocator)
							if value.array_error_kind(&array_error) != .None { _ = value.destroy_value(&inner_value); return resource_step(.Out_Of_Memory) }
							for outer_bound in 0..<int(inner_bound) {
								for item_number in 0..<outer_bound {
									item := value.number_value(f64(item_number))
									_, append_error := value.array_append_take(&result, &item)
									if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&result); _ = value.destroy_value(&inner_value); return resource_step(.Out_Of_Memory) }
								}
							}
							_ = value.destroy_value(&inner_value)
							_ = value.destroy_value(&frame.input)
							frame.input = result
							frame.iterator_cursor = 0
							frame.phase = .Iterator_Active
							continue
						}
						if value.kind_of(&inner_value) != .Invalid { _ = value.destroy_value(&inner_value) }
					}
				}
				start: f64
				end: f64
				step: f64 = 1
				identity_argument := false
				runtime_continuation := false
				for offset in 0..<int(instruction.operands_count) {
					child, child_ok := child_instruction(storage, instruction, u32(offset)); child_instruction_value, range_instruction_ok := program.program_instruction(storage.compiled, child)
					if !child_ok || !range_instruction_ok do return begin_terminal_misuse(storage, .Malformed_Program)
					if instruction.operands_count == 1 && child_instruction_value.opcode == .Identity && !child_instruction_value.has_literal {
						end_value, end_ok := value.number_value_get(&frame.input)
						if !end_ok {
							result, ready := raise_runtime(storage, index, Runtime_Error{kind=.Cannot_Number, input_kind=value.kind_of(&frame.input), span=instruction.span, key="Range bounds must be numeric"})
							if ready do return result
							runtime_continuation = true
							break
						}
						end = end_value
						start = 0
						step = 1
						identity_argument = true
						continue
					}
					if child_instruction_value.opcode == .Identity && !child_instruction_value.has_literal {
						number, number_ok := value.number_value_get(&frame.input)
						if !number_ok {
							result, ready := raise_runtime(storage, index, Runtime_Error{kind=.Cannot_Number, input_kind=value.kind_of(&frame.input), span=instruction.span, key="Range bounds must be numeric"})
							if ready do return result
							runtime_continuation = true
							break
						}
						if offset == 0 { start = number } else if offset == 1 { end = number } else { step = number }
						continue
					}
					literal, literal_error, literal_cleanup := literal_value(storage, child_instruction_value)
					if literal_cleanup != nil || literal_error != .None { if value.kind_of(&literal) != .Invalid { _ = value.destroy_value(&literal) }; return begin_terminal_misuse(storage, .Malformed_Program) }
					number, number_ok := value.number_value_get(&literal); _ = value.destroy_value(&literal)
					if !number_ok do return begin_terminal_misuse(storage, .Malformed_Program)
					if offset == 0 {
						start = number
					} else if offset == 1 {
						end = number
					} else {
						step = number
					}
				}
				if runtime_continuation do continue
				if instruction.operands_count == 1 && !identity_argument { end = start; start = 0 }
				result, array_error := value.array_value(storage.allocator); if value.array_error_kind(&array_error) != .None do return resource_step(.Out_Of_Memory)
				current := start
				if (step > 0 && start < end) || (step < 0 && start > end) {
					for (step > 0 && current < end) || (step < 0 && current > end) {
						item := value.number_value(current); _, append_error := value.array_append_take(&result, &item); if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_value(&result); return resource_step(.Out_Of_Memory) }; current += step
					}
				}
				_ = value.destroy_value(&frame.input); frame.input = result; frame.iterator_cursor = 0; frame.phase = .Iterator_Active
			case .Strftime:
				child, child_ok := child_instruction(storage, instruction, 0)
				format_instruction, format_ok := program.program_instruction(storage.compiled, child)
				if child_ok && format_ok && (format_instruction.opcode != .Identity || !format_instruction.has_literal || format_instruction.literal_kind != .String) {
					err := Runtime_Error{kind=.Cannot_Iterate, input_kind=value.kind_of(&frame.input), span=instruction.span}
					err.key = "strftime/1 requires a string format"
					result, ready := raise_runtime(storage, index, err)
					if ready do return result
					continue
				}
				format_value, format_error, format_cleanup := literal_value(storage, format_instruction)
				format, format_text_ok := value.string_borrowed(&format_value)
				if !child_ok || !format_ok {
					if value.kind_of(&format_value) != .Invalid { _ = value.destroy_value(&format_value) }
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				if format_cleanup != nil || format_error != .None || !format_text_ok {
					_ = value.destroy_value(&format_value)
					err := Runtime_Error{kind=.Cannot_Iterate, input_kind=value.kind_of(&frame.input), span=instruction.span}
					err.key = "strftime/1 requires a string format"
					result, ready := raise_runtime(storage, index, err)
					if ready do return result
					continue
				}
				output, runtime_kind, resource_error := strftime_array_result(&frame.input, format, storage.allocator)
				_ = value.destroy_value(&format_value)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					err.key = "strflocaltime/1 requires parsed datetime inputs" if instruction.format_local else "strftime/1 requires parsed datetime inputs"
					result, ready := raise_runtime(storage, index, err)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Strptime:
				format_child, child_ok := child_instruction(storage, instruction, 0)
				format_instruction, format_ok := program.program_instruction(storage.compiled, format_child)
				format_value, format_error, format_cleanup := literal_value(storage, format_instruction)
				format, format_text_ok := value.string_borrowed(&format_value)
				if !child_ok || !format_ok || !format_text_ok || format_error != .None || format_cleanup != nil {
					if value.kind_of(&format_value) != .Invalid { _ = value.destroy_value(&format_value) }
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := strptime_result(&frame.input, format, storage.allocator)
				_ = value.destroy_value(&format_value)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					err.key = "strptime/1 requires a string date input"
					result, ready := raise_runtime(storage, index, err)
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Try:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Try_Start_Expression
			case .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Last, .First, .Log, .Log10, .Log2, .Exp, .Exp2, .Exp10, .Asin, .Acos, .Cos, .Sin, .Tan, .Sinh, .Cosh, .Acosh, .Mktime, .Gmtime, .Fromdate, .Todate, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Floor, .Round, .Trunc, .Transpose, .Unique, .Sort, .Ceil, .Flatten, .Nan, .Infinite, .Any, .All, .Any_Not, .All_Not, .Isfinite, .Isinfinite, .Isnormal, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode:
				if instruction.opcode == .Add_Builtin && instruction.operands_count == 1 {
					if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
					child, child_ok := child_instruction(storage, instruction, 0)
					input_copy := value.clone_value(&frame.input)
					if !child_ok || value.kind_of(&input_copy) == .Invalid || !push_frame(storage, child, index, &input_copy) {
						return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
					}
					frame.add_seen = false
					frame.phase = .Add_Active
					continue
				}
				if (instruction.opcode == .First || instruction.opcode == .Last) && instruction.operands_count == 1 {
					if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
					if storage.frame_count == len(storage.frames) {
						capacity_error := grow_frames(storage)
						if capacity_error != nil do return resource_step(capacity_error)
						frame = &storage.frames[index]
					}
					child, child_ok := child_instruction(storage, instruction, 0)
					input_copy := value.clone_value(&frame.input)
					if !child_ok || value.kind_of(&input_copy) == .Invalid || !push_frame(storage, child, index, &input_copy) {
						return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
					}
					frame.phase = .Unary_Active
					continue
				}
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				flatten_depth := -1
				flatten_negative := false
				if instruction.opcode == .Flatten && instruction.operands_count == 1 {
					child, child_ok := child_instruction(storage, instruction, 0)
					depth_instruction, depth_instruction_ok := program.program_instruction(storage.compiled, child)
					depth_operand, operand_ok := program.program_operand(storage.compiled, depth_instruction.operands_start)
					depth_text, text_ok := program.operand_text(storage.compiled, depth_operand)
					parsed_depth, parsed_ok := strconv.parse_i64(depth_text)
					if !child_ok || !depth_instruction_ok || !operand_ok || !text_ok || depth_operand.kind != .Text || !depth_instruction.has_literal || depth_instruction.literal_kind != .Number || !parsed_ok {
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					flatten_depth = int(parsed_depth)
					if flatten_depth < 0 { flatten_depth = -2; flatten_negative = true }
				}
				output: value.Value
				runtime_kind: Runtime_Error_Kind
				resource_error: runtime.Allocator_Error
				builtin_key := ""
				if instruction.opcode == .Fromjson {
					output, runtime_kind, resource_error, builtin_key = fromjson_result(&frame.input, storage.allocator)
				} else {
					output, runtime_kind, resource_error = builtin_result(instruction.opcode, &frame.input, storage.allocator, flatten_depth)
				}
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					err := Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span}
					err.key = builtin_key
					if (instruction.opcode == .Trim || instruction.opcode == .Ltrim || instruction.opcode == .Rtrim) && value.kind_of(&frame.input) != .String {
						err.key = "trim input must be a string"
					}
					if instruction.opcode == .Mktime {
						err.key = "mktime requires parsed datetime inputs"
					}
					if flatten_negative && instruction.opcode == .Flatten {
						err.kind = .User_Error
						err.key = "flatten depth must not be negative"
					}
					if instruction.opcode == .Gmtime {
						err.key = "gmtime requires a numeric timestamp"
					}
					owned_key := builtin_key
					if instruction.opcode == .Toboolean {
						key_error: runtime.Allocator_Error
						owned_key, key_error = toboolean_runtime_key(&frame.input, storage.allocator)
						if key_error != nil do return resource_step(key_error)
						err.key = owned_key
					}
					if instruction.opcode == .Utf8bytelength {
						key_error: runtime.Allocator_Error
						owned_key, key_error = utf8bytelength_runtime_key(&frame.input, storage.allocator)
						if key_error != nil do return resource_step(key_error)
						err.key = owned_key
					}
					if instruction.opcode == .Implode {
						key_error: runtime.Allocator_Error
						owned_key, key_error = implode_runtime_key(&frame.input, storage.allocator)
						if key_error != nil do return resource_step(key_error)
						err.key = owned_key
					}
					result, ready := raise_runtime(storage, index, err)
					if len(owned_key) > 0 {
						free_error := runtime.mem_free_bytes(transmute([]byte)owned_key, storage.allocator)
						if free_error != nil do return resource_step(free_error)
					}
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Binding:
				if instruction.operands_count != 3 || !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Binding_Start_Left
			case .Reduce:
				// Evaluate the reduction seed from its compiled INIT expression.  The
				// current slice handles the common `.[]` stream and scalar UPDATE
				// forms without materializing a coroutine.
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				init_index, init_ok := child_instruction(storage, instruction, 1)
				update_index, update_ok := child_instruction(storage, instruction, 2)
				init_instruction, init_valid := program.program_instruction(storage.compiled, init_index)
				update_instruction, update_valid := program.program_instruction(storage.compiled, update_index)
				if !init_ok || !update_ok || !init_valid || !update_valid do return begin_terminal_misuse(storage, .Malformed_Program)
				seed: value.Value
				// A bounded but common jq idiom uses a literal binding for the
				// reducer seed (for example `4 as $else | $else`).  It is still a
				// scalar seed; unwrap that binding before falling through to the
				// ordinary literal path.
				seed_instruction := init_instruction
				if init_instruction.opcode == .Binding {
					seed_child, seed_child_ok := child_instruction(storage, init_instruction, 0)
					seed_child_instruction, seed_child_valid := program.program_instruction(storage.compiled, seed_child)
					seed_body, seed_body_ok := child_instruction(storage, init_instruction, 1)
					seed_body_instruction, seed_body_valid := program.program_instruction(storage.compiled, seed_body)
					if !seed_child_ok || !seed_child_valid || !seed_body_ok || !seed_body_valid ||
						seed_body_instruction.opcode != .Variable {
						return begin_terminal_misuse(storage, .Unsupported_Opcode)
					}
					seed_instruction = seed_child_instruction
				}
				if seed_instruction.opcode == .Identity && !seed_instruction.has_literal {
					seed = value.clone_value(&frame.input)
				} else {
					literal_seed, seed_error, seed_cleanup := literal_value(storage, seed_instruction)
					if seed_cleanup != nil || seed_error != .None do return begin_terminal_misuse(storage, .Malformed_Program)
					seed = literal_seed
				}
				if value.kind_of(&seed) == .Invalid do return begin_terminal_misuse(storage, .Malformed_Program)
				if update_instruction.opcode == .Identity {
					frame.phase = .Leaf_Yielded
					result, ready := propagate_output(storage, index, &seed)
					if ready do return result
					continue
				}
				// Bounded reducer update used by jq's binding regression:
				// `. as $elif | . + $then * $elif`.  This is intentionally
				// recognized structurally rather than generalizing reducer
				// evaluation to arbitrary continuations.
				if update_instruction.opcode == .Binding {
					update_left_index, update_left_ok := child_instruction(storage, update_instruction, 0)
					update_body_index, update_body_ok := child_instruction(storage, update_instruction, 1)
					update_left, update_left_valid := program.program_instruction(storage.compiled, update_left_index)
					update_body, update_body_valid := program.program_instruction(storage.compiled, update_body_index)
					if !update_left_ok || !update_body_ok || !update_left_valid || !update_body_valid ||
						update_left.opcode != .Identity || update_left.has_literal || update_body.opcode != .Add {
						_ = value.destroy_value(&seed)
						return begin_terminal_misuse(storage, .Unsupported_Opcode)
					}
					body_left_index, body_left_ok := child_instruction(storage, update_body, 0)
					body_right_index, body_right_ok := child_instruction(storage, update_body, 1)
					body_left, body_left_valid := program.program_instruction(storage.compiled, body_left_index)
					body_right, body_right_valid := program.program_instruction(storage.compiled, body_right_index)
					if !body_left_ok || !body_right_ok || !body_left_valid || !body_right_valid ||
						body_left.opcode != .Identity || body_left.has_literal || body_right.opcode != .Multiply {
						_ = value.destroy_value(&seed)
						return begin_terminal_misuse(storage, .Unsupported_Opcode)
					}
					mul_left_index, mul_left_ok := child_instruction(storage, body_right, 0)
					mul_right_index, mul_right_ok := child_instruction(storage, body_right, 1)
					mul_left, mul_left_valid := program.program_instruction(storage.compiled, mul_left_index)
					mul_right, mul_right_valid := program.program_instruction(storage.compiled, mul_right_index)
					if !mul_left_ok || !mul_right_ok || !mul_left_valid || !mul_right_valid ||
						mul_left.opcode != .Variable || mul_right.opcode != .Variable {
						_ = value.destroy_value(&seed)
						return begin_terminal_misuse(storage, .Unsupported_Opcode)
					}
					length, array_ok := value.array_length(&frame.input)
					if !array_ok { _ = value.destroy_value(&seed); return begin_terminal_misuse(storage, .Malformed_Program) }
					acc := seed
					for item_index in 0..<length {
						item, item_ok := value.array_element_copy(&frame.input, item_index)
						if !item_ok { _ = value.destroy_value(&acc); return begin_terminal_misuse(storage, .Malformed_Program) }
						product, product_kind := value.number_multiply(&item, &acc)
						_ = value.destroy_value(&item)
						if product_kind != .Success { _ = value.destroy_value(&acc); return begin_terminal_misuse(storage, .Malformed_Program) }
						next, add_ok := value.number_add(&acc, &product)
						_ = value.destroy_value(&acc); _ = value.destroy_value(&product)
						if !add_ok { return begin_terminal_misuse(storage, .Malformed_Program) }
						acc = next
					}
					frame.phase = .Leaf_Yielded
					result, ready := propagate_output(storage, index, &acc)
					if ready do return result
					continue
				}
				if update_instruction.opcode != .Add {
					_ = value.destroy_value(&seed)
					return begin_terminal_misuse(storage, .Unsupported_Opcode)
				}
				left_index, left_ok := child_instruction(storage, update_instruction, 0)
				right_index, right_ok := child_instruction(storage, update_instruction, 1)
				left_instruction, left_valid := program.program_instruction(storage.compiled, left_index)
				right_instruction, right_valid := program.program_instruction(storage.compiled, right_index)
				if !left_ok || !right_ok || !left_valid || !right_valid ||
				   left_instruction.opcode != .Identity || left_instruction.has_literal ||
				   right_instruction.opcode != .Variable {
					_ = value.destroy_value(&seed)
					return begin_terminal_misuse(storage, .Unsupported_Opcode)
				}
				name_operand, name_ok := program.program_operand(storage.compiled, program.Operand_Index(u32(instruction.operands_start)+3))
				right_name_operand, right_name_ok := program.program_operand(storage.compiled, right_instruction.operands_start)
				name, name_text_ok := program.operand_text(storage.compiled, name_operand)
				right_name, right_text_ok := program.operand_text(storage.compiled, right_name_operand)
				if !name_ok || !right_name_ok || name_operand.kind != .Text || right_name_operand.kind != .Text ||
				   !name_text_ok || !right_text_ok || name != right_name {
					_ = value.destroy_value(&seed)
					return begin_terminal_misuse(storage, .Unsupported_Opcode)
				}
				length, array_ok := value.array_length(&frame.input)
				if !array_ok do return begin_terminal_misuse(storage, .Malformed_Program)
				acc := seed
				// A reducer expression can itself be a generator. Handle the
				// common bounded Cartesian form `.[] / .[]` explicitly: jq
				// evaluates both iterators for every reducer input before applying
				// the update expression.
				generator_index, generator_index_ok := child_instruction(storage, instruction, 0)
				generator_instruction, generator_ok := program.program_instruction(storage.compiled, generator_index)
				if generator_index_ok && generator_ok && generator_instruction.opcode == .Divide {
					generator_left, generator_left_ok := child_instruction(storage, generator_instruction, 0)
					generator_right, generator_right_ok := child_instruction(storage, generator_instruction, 1)
					left_field, left_field_ok := program.program_instruction(storage.compiled, generator_left)
					right_field, right_field_ok := program.program_instruction(storage.compiled, generator_right)
					left_field_name, generator_left_name_ok := field_text(storage, left_field)
					right_field_name, generator_right_name_ok := field_text(storage, right_field)
					if generator_left_ok && generator_right_ok && left_field_ok && right_field_ok &&
					   left_field.opcode == .Field && right_field.opcode == .Field &&
					   generator_left_name_ok && generator_right_name_ok && left_field_name == "" && right_field_name == "" {
						for left_at in 0..<length {
							for right_at in 0..<length {
								left_value, left_value_ok := value.array_element_copy(&frame.input, left_at)
								if !left_value_ok { _ = value.destroy_value(&acc); return begin_terminal_misuse(storage, .Malformed_Program) }
								right_value, right_value_ok := value.array_element_copy(&frame.input, right_at)
								if !right_value_ok {
									_ = value.destroy_value(&left_value); _ = value.destroy_value(&acc)
									return begin_terminal_misuse(storage, .Malformed_Program)
								}
								term, divide_kind := value.number_divide(&left_value, &right_value)
								_ = value.destroy_value(&left_value)
								_ = value.destroy_value(&right_value)
								if divide_kind != .Success {
									_ = value.destroy_value(&acc)
									result, ready := raise_runtime(storage, index, Runtime_Error{kind=.Cannot_Divide, input_kind=value.kind_of(&frame.input), span=instruction.span})
									if ready do return result
									continue
								}
								next, add_ok := value.number_add(&acc, &term)
								_ = value.destroy_value(&acc); _ = value.destroy_value(&term)
								if !add_ok do return begin_terminal_misuse(storage, .Malformed_Program)
								acc = next
							}
						}
						frame.phase = .Leaf_Yielded
						result, ready := propagate_output(storage, index, &acc)
						if ready do return result
						continue
					}
				}
				for item_index in 0..<length {
					item, item_ok := value.array_element_copy(&frame.input, item_index)
					if !item_ok { _ = value.destroy_value(&acc); return begin_terminal_misuse(storage, .Malformed_Program) }
					next, add_ok := value.number_add(&acc, &item)
					_ = value.destroy_value(&acc); _ = value.destroy_value(&item)
					if !add_ok { return begin_terminal_misuse(storage, .Malformed_Program) }; acc = next
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &acc)
				if ready do return result
			case .Parenthesized, .Optional, .Negate:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				if storage.frame_count == len(storage.frames) {
					capacity_error := grow_frames(storage)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				child, ok := child_instruction(storage, instruction, 0)
				input_copy := value.clone_value(&frame.input)
				if !ok || value.kind_of(&input_copy) == .Invalid ||
				   !push_frame(storage, child, index, &input_copy) {
					return begin_terminal_misuse_owned(
						storage, .Malformed_Program, &input_copy,
					)
				}
				frame.phase = .Unary_Active
			case .Sequence:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Sequence_Start_Left
			case .If:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				if storage.frame_count == len(storage.frames) {
					capacity_error := grow_frames(storage)
					if capacity_error != nil do return resource_step(capacity_error)
					frame = &storage.frames[index]
				}
				condition_child, ok := child_instruction(storage, instruction, 0)
				input_copy := value.clone_value(&frame.input)
				if !ok || value.kind_of(&input_copy) == .Invalid || !push_frame(storage, condition_child, index, &input_copy) {
					return begin_terminal_misuse_owned(storage, .Malformed_Program, &input_copy)
				}
				frame.if_branch_active = false
				frame.phase = .If_Condition_Active
			case .Fork:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Fork_Start_Left
			case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Pow,
			     .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
				if !capture_composite_instruction(storage, frame, instruction) do return begin_terminal_misuse(storage, .Malformed_Program)
				frame.phase = .Binary_Start_Left
			case .Array, .Object:
				if !capture_composite_instruction(storage, frame, instruction) ||
				   !constructor_start(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
			case:
				return begin_terminal_misuse(storage, .Malformed_Program)
			}

		case .Try_Start_Expression, .Try_Start_Catch, .Field_Start_Child, .Index_Start_Child, .Slice_Start_Child, .Fork_Start_Left, .Fork_Start_Right, .Sequence_Start_Left, .Binding_Start_Left, .Binary_Start_Left, .Binary_Start_Right:
			if storage.frame_count == len(storage.frames) {
				capacity_error := grow_frames(storage)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
			}
			offset: u32
			next_phase: frame_phase
			#partial switch frame.phase {
			case .Try_Start_Expression:
				offset, next_phase = 0, .Try_Expression_Active
			case .Try_Start_Catch:
				offset, next_phase = 1, .Try_Catch_Active
			case .Field_Start_Child:
				offset, next_phase = 0, .Field_Child_Active
			case .Index_Start_Child:
				offset, next_phase = 0, .Index_Child_Active
			case .Slice_Start_Child:
				offset, next_phase = 0, .Slice_Child_Active
			case .Fork_Start_Left:
				offset, next_phase = 0, .Fork_Left_Active
			case .Fork_Start_Right:
				offset, next_phase = 1, .Fork_Right_Active
			case .Sequence_Start_Left:
				offset, next_phase = 0, .Sequence_Left_Active
			case .Binding_Start_Left:
				offset, next_phase = 0, .Binding_Left_Active
			case .Binary_Start_Left:
				offset, next_phase = 0, .Binary_Left_Active
			case .Binary_Start_Right:
				offset, next_phase = 1, .Binary_Right_Active
			case:
			}
			child, ok := child_instruction(storage, instruction, offset)
			input_copy := value.clone_value(&frame.input)
			if !ok || value.kind_of(&input_copy) == .Invalid ||
			   !push_frame(storage, child, index, &input_copy) {
				return begin_terminal_misuse_owned(
					storage, .Malformed_Program, &input_copy,
				)
			}
			frame.phase = next_phase

		case .Try_Expression_Active, .Try_Catch_Active:
			return begin_terminal_misuse(storage, .Malformed_Program)
		case .Slice_Child_Active, .Slice_Result_Active:
			return begin_terminal_misuse(storage, .Malformed_Program)

		case .Map_Start:
			length, length_ok := value.array_length(&frame.input)
			if !length_ok && frame.map_values_mode { length, length_ok = value.object_length(&frame.input) }
			if !length_ok do return begin_terminal_misuse(storage, .Malformed_Program)
			if frame.iterator_cursor >= length {
				output := value.take_value(&frame.constructor_results)
				frame.phase = .Complete
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
				continue
			}
			frame.map_value_seen = false
			child, child_ok := child_instruction(storage, instruction, 0)
			element: value.Value
			element_ok: bool
			if value.kind_of(&frame.input) == .Object {
				key: value.Value
				entry_index := frame.iterator_cursor
				if frame.map_values_mode {
					object_length, object_length_ok := value.object_length(&frame.input)
					if !object_length_ok do return begin_terminal_misuse(storage, .Malformed_Program)
					entry_index = object_length - 1 - frame.iterator_cursor
				}
				key, element, element_ok = value.object_entry_copy(&frame.input, entry_index)
				if element_ok { frame.pending_constructor_key = value.take_value(&key) } else { _ = value.destroy_value(&key) }
			} else {
				element, element_ok = value.array_element_copy(&frame.input, frame.iterator_cursor)
			}
			if !child_ok || !element_ok || value.kind_of(&element) == .Invalid {
				_ = value.destroy_value(&element)
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			frame.iterator_cursor += 1
			if !push_frame(storage, child, index, &element) {
				_ = value.destroy_value(&element)
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			frame.phase = .Map_Child_Active

		case .Map_Child_Active:
			return begin_terminal_misuse(storage, .Malformed_Program)

		case .Constructor_Start:
			child_count := int(instruction.operands_count)
			if instruction.opcode == .Object do child_count /= 2
			if frame.constructor_child >= child_count {
				// Empty [] and {} have one result. Nonempty constructors reach
				// this state only after a prior child was appended.
				if child_count == 0 {
					frame.constructor_total = 1
					frame.phase = .Constructor_Emit
					continue
				}
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			if instruction.opcode == .Object {
				key_stream, key_stream_error := value.array_value(storage.allocator)
				if value.array_error_kind(&key_stream_error) != .None {
					_ = value.destroy_array_error(&key_stream_error)
					return resource_step(.Out_Of_Memory)
				}
				key_offset := u32(instruction.operands_start) + u32(frame.constructor_child*2)
				key_operand, key_operand_ok := program.program_operand(storage.compiled, program.Operand_Index(key_offset))
				key_ok := false
				if key_operand_ok && key_operand.kind == .Instruction {
					key_ok = collect_constructor_key_stream(storage, key_operand.instruction, index, &frame.input, &key_stream)
				} else if key_operand_ok && key_operand.kind == .Text {
					key_text, text_ok := program.operand_text(storage.compiled, key_operand)
					if text_ok {
						key, key_error := value.string_value(key_text, storage.allocator)
						if value.constructor_error_kind(&key_error) == .None {
							_, append_error := value.array_append_take(&key_stream, &key)
							key_ok = value.array_error_kind(&append_error) == .None
							if !key_ok do _ = value.destroy_array_error(&append_error)
						}
						if !key_ok do _ = value.destroy_constructor_error(&key_error)
					}
				}
				if !key_ok {
					_ = value.destroy_value(&key_stream)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				key_length, key_length_ok := value.array_length(&key_stream)
				if !key_length_ok {
					_ = value.destroy_value(&key_stream)
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				for key_index in 0..<key_length {
					key_value, key_value_ok := value.array_element_copy(&key_stream, key_index)
					if !key_value_ok || value.kind_of(&key_value) != .String {
						_ = value.destroy_value(&key_value)
						_ = value.destroy_value(&key_stream)
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					_ = value.destroy_value(&key_value)
				}
				_, append_error := value.array_append_take(&frame.constructor_key_results, &key_stream)
				if value.array_error_kind(&append_error) != .None {
					retain_constructor_array_error(frame, &append_error)
					// array_append_take does not consume the operand on failure.
					// Preserve the key stream for retryable cleanup instead of
					// dropping its owned string values.
					frame.pending_constructor_value = value.take_value(&key_stream)
					return resource_step(.Out_Of_Memory)
				}
			}
			current, current_error := value.array_value(storage.allocator)
			if value.array_error_kind(&current_error) != .None {
				retain_constructor_array_error(frame, &current_error)
				return resource_step(.Out_Of_Memory)
			}
			frame.constructor_current = value.take_value(&current)
			child, child_ok := constructor_child_instruction(storage, instruction, frame.constructor_child)
			input_copy := value.clone_value(&frame.input)
			if !child_ok || value.kind_of(&input_copy) == .Invalid {
				_ = value.destroy_value(&input_copy)
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			if storage.frame_count == len(storage.frames) {
				capacity_error := grow_frames(storage)
				if capacity_error != nil {
					_ = value.destroy_value(&input_copy)
					return resource_step(capacity_error)
				}
				frame = &storage.frames[index]
			}
			if !push_frame(storage, child, index, &input_copy) {
				_ = value.destroy_value(&input_copy)
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			// push_frame may only mutate the frame arena, but reacquire the
			// parent after any preceding growth so this write never targets a
			// retired arena.
			frame = &storage.frames[index]
			frame.phase = .Constructor_Child_Active

		case .Constructor_Emit:
			if frame.constructor_cursor >= frame.constructor_total {
				frame.phase = .Complete
				continue
			}
			output, output_ok := constructor_emit(storage, frame, instruction)
			if !output_ok || value.kind_of(&output) == .Invalid {
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			frame.constructor_cursor += 1
			if frame.constructor_cursor >= frame.constructor_total {
				frame.phase = .Complete
			}
			result, ready := propagate_output(storage, index, &output)
			if ready do return result

		case .Iterator_Active:
			length, length_ok := value.array_length(&frame.input)
			if !length_ok {
				length, length_ok = value.object_length(&frame.input)
			}
			if !length_ok do return begin_terminal_misuse(storage, .Malformed_Program)
			if frame.iterator_cursor >= length {
				frame.phase = .Complete
				continue
			}
			output: value.Value
			if value.kind_of(&frame.input) == .Array {
				output, length_ok = value.array_element_copy(&frame.input, frame.iterator_cursor)
			} else {
				key: value.Value
				key, output, length_ok = value.object_entry_copy(&frame.input, frame.iterator_cursor)
				_ = value.destroy_value(&key)
			}
			if !length_ok || value.kind_of(&output) == .Invalid {
				return begin_terminal_misuse(storage, .Malformed_Program)
			}
			frame.iterator_cursor += 1
			result, ready := propagate_output(storage, index, &output)
			if ready do return result

		case .First_Empty, .Last_Result, .Last_Empty:
			if frame.phase == .First_Empty || frame.phase == .Last_Empty {
				// Generator forms preserve jq's empty-stream cardinality: an
				// empty child emits no value (unlike the zero-argument array
				// selectors, which return null).
				frame.phase = .Complete
				continue
			}
			output := value.take_value(&frame.selected_value)
			frame.selected_seen = false
			frame.phase = .Complete
			result, ready := propagate_output(storage, index, &output)
			if ready do return result
		case .Add_Result, .Add_Empty:
			if frame.phase == .Add_Empty {
				output := value.null_value()
				frame.phase = .Complete
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
				continue
			}
			output := value.take_value(&frame.add_accumulator)
			frame.add_seen = false
			frame.phase = .Complete
			result, ready := propagate_output(storage, index, &output)
			if ready do return result
		case .Leaf_Yielded, .Complete:
			free_error, continuation_ok := finish_top_frame(storage)
			if free_error != nil do return resource_step(free_error)
			if !continuation_ok do return begin_terminal_misuse(storage, .Malformed_Program)

		case .Unary_Active, .Fork_Left_Active, .Fork_Right_Active,
		     .Add_Active,
		     .Limit_Active, .Skip_Active, .Nth_Active,
		     .Sequence_Left_Active, .Sequence_Right_Active,
		     .Field_Child_Active, .Field_Result_Active,
		     .Index_Child_Active, .Index_Result_Active,
		     .Binary_Left_Active, .Binary_Right_Active,
		     .Binding_Left_Active, .Binding_Body_Active, .Constructor_Child_Active:
			// An active consumer is never the top frame: its producer is above it.
			return begin_terminal_misuse(storage, .Malformed_Program)
		case .If_Condition_Active, .If_Then_Active, .If_Else_Active:
			return begin_terminal_misuse(storage, .Malformed_Program)
		}
	}
}

// destroy_evaluator cancels pending evaluation and releases every retained
// Value before frame storage. Genuine Free failures preserve the exact owner
// for deterministic retry. Success is idempotent and makes evaluator inert.
destroy_evaluator :: proc(evaluator: ^Evaluator) -> runtime.Allocator_Error {
	if evaluator == nil || evaluator^ == nil do return nil
	storage := storage_of(evaluator)
	if storage.self != evaluator do return .Invalid_Pointer
	free_error := retire_pending_memory(storage)
	if free_error != nil do return free_error
	free_error = retire_pending_constructor_error(storage)
	if free_error != nil do return free_error
	free_error = value.destroy_value(&storage.pending_value)
	if free_error != nil do return free_error
	free_error = destroy_frames_to(storage, 0)
	if free_error != nil do return free_error
	// Do not retire a terminal diagnostic before the independent frame-storage
	// free commits. If that free fails, step_evaluator may still replay the exact
	// pending terminal result after cleanup is retried.
	free_error = free_storage(storage)
	if free_error != nil do return free_error
	free_error = release_runtime_error(storage)
	if free_error != nil do return free_error
	evaluator^ = nil
	return nil
}
