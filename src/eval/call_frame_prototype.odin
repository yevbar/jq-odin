package eval

import program "jq:program"

// CALL_FRAME_PROTOTYPE_LIMIT is intentionally small.  This file is an
// executable contract for the first callable evaluator frame; it is not yet
// wired into Evaluator.  Keeping the state explicit lets the eventual VM
// replace the fixed storage with an allocator-owned stack without changing
// the transition rules.
CALL_FRAME_PROTOTYPE_LIMIT :: 64

Call_Frame_Prototype :: struct {
	// Return location in the caller.  The callee always starts at entry.
	return_instruction: program.Instruction_Index,
	entry_instruction:  program.Instruction_Index,
	// Definition snapshot selected at call activation.  A later redefinition
	// must not mutate this frame's selected body.
	definition_id:      u32,
}

Call_Frame_Stack_Prototype :: struct {
	frames: [CALL_FRAME_PROTOTYPE_LIMIT]Call_Frame_Prototype,
	count:  int,
}

call_frame_push_prototype :: proc(
	stack: ^Call_Frame_Stack_Prototype,
	frame: Call_Frame_Prototype,
) -> bool {
	if stack == nil || stack.count < 0 || stack.count >= CALL_FRAME_PROTOTYPE_LIMIT do return false
	stack.frames[stack.count] = frame
	stack.count += 1
	return true
}

call_frame_return_prototype :: proc(
	stack: ^Call_Frame_Stack_Prototype,
) -> (Call_Frame_Prototype, bool) {
	if stack == nil || stack.count <= 0 do return {}, false
	stack.count -= 1
	return stack.frames[stack.count], true
}

call_frame_peek_prototype :: proc(
	stack: ^Call_Frame_Stack_Prototype,
) -> (Call_Frame_Prototype, bool) {
	if stack == nil || stack.count <= 0 do return {}, false
	return stack.frames[stack.count-1], true
}
