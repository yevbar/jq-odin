package eval

import "base:runtime"
import "core:sync"
import program "jq:program"
import value "jq:value"

Runtime_Error_Kind :: enum u8 {
	None,
	Cannot_Index_With_String,
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
	saved_operands:    [2]program.Operand,
	saved_operand_count: u8,
	has_saved_instruction: bool,
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
		seal_mix_u64(&seal, u64(instruction.operands_start))
		seal_mix_u64(&seal, u64(instruction.operands_count))
		seal_mix_u64(&seal, u64(instruction.span.start))
		seal_mix_u64(&seal, u64(instruction.span.end))
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
	runtime_key_memory: []byte,
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
capture_composite_instruction :: proc(
	storage: ^evaluator_storage,
	frame: ^eval_frame,
	instruction: program.Instruction,
) -> bool {
	if frame.mode != .Normal do return false
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
	case .Fork, .Sequence:
		if instruction.operands_count != 2 do return false
		_, left_ok := child_instruction(storage, instruction, 0)
		_, right_ok := child_instruction(storage, instruction, 1)
		if !left_ok || !right_ok do return false
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
	case .Field_Start_Child, .Field_Child_Active, .Field_Result_Active:
		if frame.mode != .Normal || instruction.opcode != .Field do return false
	case .Fork_Start_Left, .Fork_Left_Active, .Fork_Start_Right, .Fork_Right_Active:
		if frame.mode != .Normal || instruction.opcode != .Fork do return false
	case .Sequence_Start_Left, .Sequence_Left_Active, .Sequence_Right_Active:
		if frame.mode != .Normal || instruction.opcode != .Sequence do return false
	case:
		return true
	}
	expected_operand_count: u8
	if frame.phase == .Unary_Active do expected_operand_count = 1
	else do expected_operand_count = 2
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
		if found do return result, {}, true
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
resource_step :: proc(err: runtime.Allocator_Error) -> Step_Result {
	return {kind = .Resource_Error, resource_error = err}
}

@(private)
misuse_step :: proc(kind: Misuse_Kind) -> Step_Result {
	return {kind = .Misuse, misuse = kind}
}

@(private)
destroy_frames_to :: proc(storage: ^evaluator_storage, target_count: int) -> runtime.Allocator_Error {
	for storage.frame_count > target_count {
		index := storage.frame_count-1
		free_error := value.destroy_value(&storage.frames[index].input)
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
	assert(len(storage.runtime_key_memory) == 0)
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
	storage.runtime_key_memory = memory
	storage.runtime_error = err
	storage.runtime_error.key = transmute(string)storage.runtime_key_memory
	return nil
}

@(private)
release_runtime_error :: proc(storage: ^evaluator_storage) -> runtime.Allocator_Error {
	if len(storage.runtime_key_memory) > 0 {
		free_error := runtime.mem_free_bytes(storage.runtime_key_memory, storage.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
		storage.runtime_key_memory = nil
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
		if phase == .Sequence_Left_Active || phase == .Field_Child_Active do return true
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
			if !field_ok || !push_frame(storage, frame.instruction, parent, owned, .Field_Only) {
				return begin_terminal_misuse_owned(storage, .Malformed_Program, owned), true
			}
			frame.phase = .Field_Result_Active
			return {}, false
		case .Field_Result_Active:
			current = parent
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

		switch frame.phase {
		case .Enter:
			if frame.mode == .Field_Only {
				if instruction.opcode != .Field {
					return begin_terminal_misuse(storage, .Malformed_Program)
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

			switch instruction.opcode {
			case .Identity:
				if instruction.operands_count != 0 do return begin_terminal_misuse(storage, .Malformed_Program)
				capacity_error := prepare_output(storage, index)
				if capacity_error != nil do return resource_step(capacity_error)
				frame = &storage.frames[index]
				output := value.clone_value(&frame.input)
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
					if !capture_composite_instruction(storage, frame, instruction) {
						return begin_terminal_misuse(storage, .Malformed_Program)
					}
					frame.phase = .Field_Start_Child
				} else {
					return begin_terminal_misuse(storage, .Malformed_Program)
				}
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
			case:
				return begin_terminal_misuse(storage, .Malformed_Program)
			}

		case .Field_Start_Child, .Fork_Start_Left, .Fork_Start_Right, .Sequence_Start_Left:
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
			case .Fork_Start_Left:
				offset, next_phase = 0, .Fork_Left_Active
			case .Fork_Start_Right:
				offset, next_phase = 1, .Fork_Right_Active
			case .Sequence_Start_Left:
				offset, next_phase = 0, .Sequence_Left_Active
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

		case .Leaf_Yielded, .Complete:
			free_error, continuation_ok := finish_top_frame(storage)
			if free_error != nil do return resource_step(free_error)
			if !continuation_ok do return begin_terminal_misuse(storage, .Malformed_Program)

		case .Unary_Active, .Fork_Left_Active, .Fork_Right_Active,
		     .Sequence_Left_Active, .Sequence_Right_Active,
		     .Field_Child_Active, .Field_Result_Active:
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
