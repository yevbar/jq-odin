package eval

import "core:testing"
import program "jq:program"

call_frame_prototype_push_and_return_restores_caller :: proc(t: ^testing.T) {
	stack: Call_Frame_Stack_Prototype
	caller := Call_Frame_Prototype{
		return_instruction = program.Instruction_Index(7),
		entry_instruction = program.Instruction_Index(0),
		definition_id = 11,
	}
	callee := Call_Frame_Prototype{
		return_instruction = program.Instruction_Index(19),
		entry_instruction = program.Instruction_Index(42),
		definition_id = 12,
	}
	testing.expect(t, call_frame_push_prototype(&stack, caller))
	testing.expect(t, call_frame_push_prototype(&stack, callee))
	peeked, peek_ok := call_frame_peek_prototype(&stack)
	testing.expect(t, peek_ok)
	testing.expect_value(t, peeked.entry_instruction, callee.entry_instruction)
	testing.expect_value(t, peeked.definition_id, callee.definition_id)
	returned, return_ok := call_frame_return_prototype(&stack)
	testing.expect(t, return_ok)
	testing.expect_value(t, returned.return_instruction, callee.return_instruction)
	testing.expect_value(t, stack.count, 1)
	caller_again, caller_ok := call_frame_peek_prototype(&stack)
	testing.expect(t, caller_ok)
	testing.expect_value(t, caller_again.return_instruction, caller.return_instruction)
}

call_frame_prototype_snapshots_definition_across_redefinition :: proc(t: ^testing.T) {
	stack: Call_Frame_Stack_Prototype
	first := Call_Frame_Prototype{
		return_instruction = program.Instruction_Index(3),
		entry_instruction = program.Instruction_Index(10),
		definition_id = 100,
	}
	second := Call_Frame_Prototype{
		return_instruction = program.Instruction_Index(4),
		entry_instruction = program.Instruction_Index(20),
		definition_id = 101,
	}
	testing.expect(t, call_frame_push_prototype(&stack, first))
	// A new definition gets a new frame; it cannot rewrite the first frame.
	testing.expect(t, call_frame_push_prototype(&stack, second))
	_, _ = call_frame_return_prototype(&stack)
	original, ok := call_frame_return_prototype(&stack)
	testing.expect(t, ok)
	testing.expect_value(t, original.entry_instruction, first.entry_instruction)
	testing.expect_value(t, original.definition_id, first.definition_id)
}

call_frame_prototype_rejects_stack_overflow_and_underflow :: proc(t: ^testing.T) {
	stack: Call_Frame_Stack_Prototype
	for index in 0..<CALL_FRAME_PROTOTYPE_LIMIT {
		testing.expect(t, call_frame_push_prototype(&stack, Call_Frame_Prototype{definition_id=u32(index)}))
	}
	testing.expect(t, !call_frame_push_prototype(&stack, {}))
	for _ in 0..<CALL_FRAME_PROTOTYPE_LIMIT {
		_, ok := call_frame_return_prototype(&stack)
		testing.expect(t, ok)
	}
	_, underflow_ok := call_frame_return_prototype(&stack)
	testing.expect(t, !underflow_ok)
}
