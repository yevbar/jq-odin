package eval

import "base:runtime"
import "core:math"
import "core:sync"
import "core:strings"
import "core:strconv"
import program "jq:program"
import value "jq:value"

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
}

@(private)
frame_phase :: enum u8 {
	Enter,
	Leaf_Yielded,
	Unary_Active,
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
	iterator_cursor: int,
	reduce_accumulator: value.Value,
	reduce_binding: value.Value,
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
	case .Parenthesized, .Optional:
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
	if frame.mode != .Normal && frame.mode != .Field_Only && frame.mode != .Index_Only do return false
	#partial switch instruction.opcode {
	case .Parenthesized, .Optional:
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
	case .Add, .Subtract, .Multiply, .Divide, .Modulo,
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
		   (instruction.opcode != .Parenthesized && instruction.opcode != .Optional) {
			return false
		}
	case .Field_Start_Child, .Field_Child_Active, .Field_Result_Active, .Iterator_Active:
		if frame.mode != .Normal && frame.mode != .Field_Only || instruction.opcode != .Field do return false
	case .Index_Start_Child, .Index_Child_Active, .Index_Result_Active:
		if frame.mode != .Normal && frame.mode != .Index_Only || instruction.opcode != .Index do return false
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
	case:
		return true
	}
	expected_operand_count: u8
	if frame.phase == .Unary_Active do expected_operand_count = 1
	else if frame.phase == .Index_Start_Child || frame.phase == .Index_Child_Active || frame.phase == .Index_Result_Active {
		expected_operand_count = 2
	}
	else if frame.phase == .Constructor_Start || frame.phase == .Constructor_Child_Active || frame.phase == .Constructor_Emit {
		expected_operand_count = u8(instruction.operands_count)
	}
	else if frame.phase == .Binding_Start_Left || frame.phase == .Binding_Left_Active || frame.phase == .Binding_Body_Active {
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
	if !number_ok || index_number < 0 || index_number != f64(int(index_number)) {
		return value.null_value(), {}, true
	}
	index := int(index_number)
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
		if phase == .Sequence_Left_Active || phase == .Field_Child_Active || phase == .Index_Child_Active || phase == .Binary_Left_Active do return true
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
	case .Iterator_Active:
		frame.phase = .Complete
	case .Binary_Left_Active:
		frame.phase = .Complete
	case .Binary_Right_Active:
		_ = value.destroy_value(&frame.binary_left)
		frame.phase = .Binary_Left_Active
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
		case .Unary_Active, .Fork_Left_Active, .Fork_Right_Active:
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
				_ = value.destroy_value(owned)
				result_step, ready := raise_runtime(storage, parent, {kind = runtime_kind, input_kind = value.kind_of(&frame.binary_left), span = instruction.operator_span})
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
	case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
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
		text, text_ok := value.string_borrowed(&item)
		if !text_ok {
			_ = value.destroy_value(&item); strings.builder_destroy(&builder); return {}, .Cannot_Iterate, nil
		}
		if strings.write_string(&builder, text) != len(text) {
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
contains_result :: proc(input: ^value.Value, needle: string) -> (value.Value, Runtime_Error_Kind) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate
	haystack, ok := value.string_borrowed(input)
	if !ok do return {}, .Cannot_Iterate
	return value.boolean_value(strings.contains(haystack, needle)), .None
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
split_result :: proc(input: ^value.Value, separator: string, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	if value.kind_of(input) != .String do return {}, .Cannot_Iterate, nil
	text, text_ok := value.string_borrowed(input)
	if !text_ok || len(separator) == 0 do return {}, .Cannot_Iterate, nil
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	// jq emits no segments when a non-empty separator is applied to an empty
	// string. Empty-separator code-point splitting remains intentionally deferred.
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
search_result :: proc(input: ^value.Value, needle: string, opcode: program.Opcode, allocator: runtime.Allocator) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	kind := value.kind_of(input)
	// jq's search builtins preserve null as null.  Arrays search exact string
	// elements (rather than serializing the array); non-string elements simply
	// cannot match a literal string needle.
	if kind == .Null do return value.null_value(), .None, nil
	if kind == .Array {
		length, length_ok := value.array_length(input)
		if !length_ok do return {}, .Cannot_Iterate, nil
		if opcode == .Indices_Builtin {
			result, array_error := value.array_value(allocator)
			if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
			for index in 0..<length {
				item, item_ok := value.array_element_copy(input, index)
				if !item_ok {
					_ = value.destroy_value(&result)
					return {}, .Cannot_Iterate, nil
				}
				item_kind := value.kind_of(&item)
				matches := false
				if item_kind == .String {
					item_text, text_ok := value.string_borrowed(&item)
					matches = text_ok && item_text == needle
				}
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
			item_kind := value.kind_of(&item)
			matches := false
			if item_kind == .String {
				item_text, text_ok := value.string_borrowed(&item)
				matches = text_ok && item_text == needle
			}
			_ = value.destroy_value(&item)
			if matches {
				if opcode == .Index_Builtin do return value.number_value(f64(index)), .None, nil
				last_index = index
			}
		}
		if last_index < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(last_index)), .None, nil
	}
	if kind != .String || len(needle) == 0 do return {}, .Cannot_Iterate, nil
	text, text_ok := value.string_borrowed(input)
	if !text_ok do return {}, .Cannot_Iterate, nil
	if opcode == .Index_Builtin {
		position := strings.index(text, needle)
		if position < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(utf8_codepoint_offset(text, position))), .None, nil
	}
	if opcode == .Rindex_Builtin {
		position := strings.last_index(text, needle)
		if position < 0 do return value.null_value(), .None, nil
		return value.number_value(f64(utf8_codepoint_offset(text, position))), .None, nil
	}
	result, array_error := value.array_value(allocator)
	if value.array_error_kind(&array_error) != .None do return {}, .None, .Out_Of_Memory
	start := 0
	for start <= len(text) {
		relative := strings.index(text[start:], needle)
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
builtin_result :: proc(opcode: program.Opcode, input: ^value.Value, allocator: runtime.Allocator, flatten_depth: int = -1) -> (value.Value, Runtime_Error_Kind, runtime.Allocator_Error) {
	kind := value.kind_of(input)
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
	if opcode == .Abs || opcode == .Sqrt || opcode == .Fabs {
		if kind == .String && opcode == .Abs {
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
	if opcode == .Length {
		if kind == .Null do return value.number_value(0), .None, nil
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
			if !number_ok || number < 0 || number > 127 || math.trunc(number) != number { strings.builder_destroy(&builder); return {}, .Cannot_Number, nil }
			if strings.write_byte(&builder, u8(number)) != 1 { strings.builder_destroy(&builder); return {}, .None, .Out_Of_Memory }
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
		for byte in text {
			item := value.number_value(f64(byte))
			_, append_error := value.array_append_take(&result, &item)
			if value.array_error_kind(&append_error) != .None { _ = value.destroy_value(&item); _ = value.destroy_array_error(&append_error); _ = value.destroy_value(&result); return {}, .None, .Out_Of_Memory }
		}
		return result, .None, nil
	}
	if opcode == .Tostring {
		if kind != .String do return {}, .Cannot_Trim, nil
		result := value.clone_value(input)
		if value.kind_of(&result) == .Invalid do return {}, .None, .Out_Of_Memory
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
			key, key_ok := value.object_get_copy(&entry, "key")
			item, item_ok := value.object_get_copy(&entry, "value")
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
		if kind != .Number do return {}, .Cannot_Number, nil
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
	if opcode == .Add_Builtin {
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
		result, kind := value.number_multiply(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Multiply, nil
	case .Divide:
		result, kind := value.number_divide(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Divide, nil
	case .Modulo:
		result, kind := value.number_modulo(left, right)
		if kind == .Success do return result, .None, nil
		return {}, .Cannot_Modulo, nil
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
						result, ready := raise_runtime(storage, index, Runtime_Error{kind=.Cannot_Iterate, input_kind=kind, span=instruction.span})
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
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
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
				needle_operand, operand_ok := program.program_operand(storage.compiled, needle_instruction.operands_start)
				needle, needle_text_ok := program.operand_text(storage.compiled, needle_operand)
				if !child_ok || !needle_ok || needle_operand.kind != .Text || !needle_instruction.has_literal || needle_instruction.literal_kind != .String || !operand_ok || !needle_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind := contains_result(&frame.input, needle)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
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
				needle_operand, operand_ok := program.program_operand(storage.compiled, needle_instruction.operands_start)
				needle, needle_text_ok := program.operand_text(storage.compiled, needle_operand)
				if !child_ok || !needle_ok || needle_operand.kind != .Text || !needle_instruction.has_literal || needle_instruction.literal_kind != .String || !operand_ok || !needle_text_ok {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				output, runtime_kind, resource_error := search_result(&frame.input, needle, instruction.opcode, storage.allocator)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
					if ready do return result
					continue
				}
				frame.phase = .Leaf_Yielded
				result, ready := propagate_output(storage, index, &output)
				if ready do return result
			case .Length, .Keys, .Keys_Unsorted, .Tostring, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Floor, .Round, .Transpose, .Unique, .Sort, .Ceil, .Flatten, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode:
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				flatten_depth := -1
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
					if flatten_depth < 0 do flatten_depth = -2
				}
				output, runtime_kind, resource_error := builtin_result(instruction.opcode, &frame.input, storage.allocator, flatten_depth)
				if resource_error != nil do return resource_step(resource_error)
				if runtime_kind != .None {
					result, ready := raise_runtime(storage, index, Runtime_Error{kind=runtime_kind, input_kind=value.kind_of(&frame.input), span=instruction.span})
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
				seed_frame := eval_frame{input = value.clone_value(&frame.input)}
				seed, seed_error, seed_cleanup := literal_value(storage, init_instruction)
				_ = value.destroy_value(&seed_frame.input)
				if seed_cleanup != nil || seed_error != .None do return begin_terminal_misuse(storage, .Malformed_Program)
				if update_instruction.opcode == .Identity {
					frame.phase = .Leaf_Yielded
					result, ready := propagate_output(storage, index, &seed)
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
			case .Parenthesized, .Optional:
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
			case .Fork:
				if !capture_composite_instruction(storage, frame, instruction) {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
				frame.phase = .Fork_Start_Left
			case .Add, .Subtract, .Multiply, .Divide, .Modulo,
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

		case .Field_Start_Child, .Index_Start_Child, .Fork_Start_Left, .Fork_Start_Right, .Sequence_Start_Left, .Binding_Start_Left, .Binary_Start_Left, .Binary_Start_Right:
			if storage.frame_count == len(storage.frames) {
				capacity_error := grow_frames(storage)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
			}
			offset: u32
			next_phase: frame_phase
			#partial switch frame.phase {
			case .Field_Start_Child:
				offset, next_phase = 0, .Field_Child_Active
			case .Index_Start_Child:
				offset, next_phase = 0, .Index_Child_Active
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

		case .Leaf_Yielded, .Complete:
			free_error, continuation_ok := finish_top_frame(storage)
			if free_error != nil do return resource_step(free_error)
			if !continuation_ok do return begin_terminal_misuse(storage, .Malformed_Program)

		case .Unary_Active, .Fork_Left_Active, .Fork_Right_Active,
		     .Sequence_Left_Active, .Sequence_Right_Active,
		     .Field_Child_Active, .Field_Result_Active,
		     .Index_Child_Active, .Index_Result_Active,
		     .Binary_Left_Active, .Binary_Right_Active,
		     .Binding_Left_Active, .Binding_Body_Active, .Constructor_Child_Active:
			// An active consumer is never the top frame: its producer is above it.
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
