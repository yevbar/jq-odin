// Package program owns the evaluator-neutral compiled representation.
package program

import "base:runtime"

// Every serialized quantity has an intentional fixed width. Storage_Count also
// caps one Program's contiguous allocation at 2^32-1 bytes.
Instruction_Index :: distinct u32
Operand_Index :: distinct u32
Byte_Offset :: distinct u32
Count :: distinct u32
Source_Offset :: distinct u32
Storage_Count :: distinct u32

Source_Span :: struct {
	start: Source_Offset,
	end:   Source_Offset,
}

Opcode :: enum u8 {
	Identity,
	Field,
	Parenthesized,
	Sequence,
	Fork,
	Optional,
	Add,
	Subtract,
	Multiply,
	Divide,
	Modulo,
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	// Constructors are appended to preserve the serialized discriminants of
	// the existing vertical slice.
	Array,
	Object,
	Variable,
	Binding,
	Reduce,
	Length,
	Keys,
	Type,
	Abs,
	Sqrt,
	Fabs,
	Add_Builtin,
	Trim,
	Ltrim,
	Rtrim,
	Index,
	// Atan is appended to preserve existing serialized opcodes.
	Atan,
	// ASCII case filters are appended to preserve existing serialized opcodes.
	Ascii_Downcase,
	Ascii_Upcase,
	// Reverse is appended to preserve existing serialized opcodes.
	Reverse,
	// Implode is appended to preserve existing serialized opcodes.
	Implode,
	// Explode is appended to preserve existing serialized opcodes.
	Explode,
	// Keys_Unsorted is appended to preserve existing serialized opcodes.
	Keys_Unsorted,
	// Tostring is appended to preserve existing serialized opcodes.
	Tostring,
	// From_Entries is appended to preserve existing serialized opcodes.
	From_Entries,
	// To_Entries is appended to preserve existing serialized opcodes.
	To_Entries,
	// Isnan is appended to preserve existing serialized opcodes.
	Isnan,
	// Utf8bytelength is appended to preserve existing serialized opcodes.
	Utf8bytelength,
	// Not_Builtin is appended to preserve existing serialized opcodes.
	Not_Builtin,
	// Empty is appended to preserve existing serialized opcodes.
	Empty,
	// Values is appended to preserve existing serialized opcodes.
	Values,
	// Arrays is appended to preserve existing serialized opcodes.
	Arrays,
	// Objects is appended to preserve existing serialized opcodes.
	Objects,
	// Iterables is appended to preserve existing serialized opcodes.
	Iterables,
	// Scalars is appended to preserve existing serialized opcodes.
	Scalars,
	// Booleans is appended to preserve existing serialized opcodes.
	Booleans,
	// Nulls is appended to preserve existing serialized opcodes.
	Nulls,
	// Numbers is appended to preserve existing serialized opcodes.
	Numbers,
	// Strings is appended to preserve existing serialized opcodes.
	Strings,
	// Finites is appended to preserve existing serialized opcodes.
	Finites,
	// Normals is appended to preserve existing serialized opcodes.
	Normals,
	// Floor is appended to preserve existing serialized opcodes.
	Floor,
	// Round is appended to preserve existing serialized opcodes.
	Round,
	// Trunc is appended to preserve existing serialized opcodes.
	Trunc,
	// Transpose is appended to preserve existing serialized opcodes.
	Transpose,
	// Unique is appended to preserve existing serialized opcodes.
	Unique,
	// Sort is appended to preserve existing serialized opcodes.
	Sort,
	// Ceil is appended to preserve existing serialized opcodes.
	Ceil,
	// Flatten is appended to preserve existing serialized opcodes.
	Flatten,
	// Nan is appended to preserve existing serialized opcodes.
	Nan,
	// Infinite is appended to preserve existing serialized opcodes.
	Infinite,
	// Any is appended to preserve existing serialized opcodes.
	Any,
	// All is appended to preserve existing serialized opcodes.
	All,
	// Any_Not is appended to preserve existing serialized opcodes.
	Any_Not,
	// All_Not is appended to preserve existing serialized opcodes.
	All_Not,
	// Isfinite is appended to preserve existing serialized opcodes.
	Isfinite,
	// Join is appended to preserve existing serialized opcodes.
	Join,
	// Isnormal is appended to preserve existing serialized opcodes.
	Isnormal,
	// Contains is appended to preserve existing serialized opcodes.
	Contains,
	// Split is appended to preserve existing serialized opcodes.
	Split,
	// Index_Builtin is appended to preserve existing serialized opcodes.
	Index_Builtin,
	// Rindex_Builtin is appended to preserve existing serialized opcodes.
	Rindex_Builtin,
	// Indices_Builtin is appended to preserve existing serialized opcodes.
	Indices_Builtin,
	// Startswith is appended to preserve existing serialized opcodes.
	Startswith,
	// Endswith is appended to preserve existing serialized opcodes.
	Endswith,
	// Has is appended to preserve existing serialized opcodes.
	Has,
	// Bsearch is appended to preserve existing serialized opcodes.
	Bsearch,
	// Ltrimstr, Rtrimstr, and Trimstr are appended to preserve existing serialized opcodes.
	Ltrimstr,
	Rtrimstr,
	Trimstr,
	// Tonumber is appended to preserve existing serialized opcodes.
	Tonumber,
	// Min and Max are appended to preserve existing serialized opcodes.
	Min,
	Max,
	// Toboolean is appended to preserve existing serialized opcodes.
	Toboolean,
	// Base64 and Base64d are appended to preserve existing serialized opcodes.
	Base64,
	Base64d,
	// Uri and Urid are appended to preserve existing serialized opcodes.
	Uri,
	Urid,
	// Html is appended to preserve existing serialized opcodes.
	Html,
	// Text is appended to preserve existing serialized opcodes.
	Text,
	// Json is appended to preserve existing serialized opcodes.
	Json,
	// Csv is appended to preserve existing serialized opcodes.
	Csv,
	// Tsv is appended to preserve existing serialized opcodes.
	Tsv,
	// Sh is appended to preserve existing serialized opcodes.
	Sh,
	// Tojson is appended to preserve existing serialized opcodes.
	Tojson,
	// Fromjson is appended to preserve existing serialized opcodes.
	Fromjson,
	// Last is appended to preserve existing serialized opcodes.
	Last,
	// First is appended to preserve existing serialized opcodes.
	First,
	// Log10 is appended to preserve existing serialized opcodes.
	Log10,
	// Log2 is appended to preserve existing serialized opcodes.
	Log2,
	// Exp is appended to preserve existing serialized opcodes.
	Exp,
	// Exp2 is appended to preserve existing serialized opcodes.
	Exp2,
	// Exp10 is appended to preserve existing serialized opcodes.
	Exp10,
	// Asin is appended to preserve existing serialized opcodes.
	Asin,
	// Acos is appended to preserve existing serialized opcodes.
	Acos,
	// Cos is appended to preserve existing serialized opcodes.
	Cos,
	// Sin is appended to preserve existing serialized opcodes.
	Sin,
	// Tan is appended to preserve existing serialized opcodes.
	Tan,
	// Sinh is appended to preserve existing serialized opcodes.
	Sinh,
	// Isinfinite is appended to preserve existing serialized opcodes.
	Isinfinite,
	// Log is appended to preserve existing serialized opcodes.
	Log,
	// Error is appended to preserve existing serialized opcodes.
	Error,
	// Try is appended to preserve existing serialized opcodes.
	Try,
	// IsEmpty is appended to preserve existing serialized opcodes.
	IsEmpty,
	// Range is appended to preserve existing serialized opcodes.
	Range,
	// Strftime is appended to preserve existing serialized opcodes.
	Strftime,
	// Strptime is appended to preserve existing serialized opcodes.
	Strptime,
	// Mktime is appended to preserve existing serialized opcodes.
	Mktime,
	// Gmtime is appended to preserve existing serialized opcodes.
	Gmtime,
	// Fromdate is appended to preserve existing serialized opcodes.
	Fromdate,
	// Todate is appended to preserve existing serialized opcodes.
	Todate,
	// Negate is appended to preserve existing serialized opcodes.
	Negate,
	// Limit is appended to preserve existing serialized opcodes.
	Limit,
	// Skip is appended to preserve existing serialized opcodes.
	Skip,
	// Nth is appended to preserve existing serialized opcodes.
	Nth,
	// Map is appended to preserve existing serialized opcodes.
	Map,
	// Map_Values is appended to preserve existing serialized opcodes.
	Map_Values,
	// Slice is appended to preserve existing serialized opcodes.
	Slice,
}

Operand_Kind :: enum u8 {
	Instruction,
	Text,
}

Literal_Kind :: enum u8 {
	Null,
	Boolean,
	Number,
	String,
}

// Instruction operands are stored consecutively beginning at operands_start.
// Sequence operands are ordered left then right. Fork operands are likewise
// left then right, but describe independently resumable generator branches.
// Field has an optional leading Instruction operand followed by one Text
// operand. Object operands alternate a static Text key or compiled key
// Instruction with a value Instruction. Literal has one Text operand for
// Number/String and none for Null/Boolean. Parenthesized and Optional have
// one Instruction operand.
Instruction :: struct {
	opcode:         Opcode,
	has_literal:    bool,
	literal_kind:   Literal_Kind,
	literal_boolean: bool,
	operands_start: Operand_Index,
	operands_count: Count,
	span:           Source_Span,
	operator_span:  Source_Span,
	has_operator_span: bool,
}

// Exactly one payload is meaningful according to kind. Text selects a
// half-open range in Program's owned text storage.
Operand :: struct {
	kind:        Operand_Kind,
	instruction: Instruction_Index,
	text_start:  Byte_Offset,
	text_count:  Count,
}

Program_State :: enum u8 {
	Uninitialized,
	Building,
	Active,
	Cleanup_Failed,
	Destroyed,
}

Init_Error_Kind :: enum u8 {
	None,
	Size_Overflow,
	Resource_Failure,
}

Init_Error :: struct {
	kind:           Init_Error_Kind,
	resource_error: runtime.Allocator_Error,
}

@(private="package")
Validation_State :: enum u8 {
	Unseen,
	Visiting,
	Done,
}

@(private="package")
Validation_Record :: struct {
	state:      Validation_State,
	next_child: Count,
	parent:     Instruction_Index,
	has_parent: bool,
}

// Program owns one allocation containing its instruction, operand, private
// graph-validation, and text storage. It borrows no source or syntax storage.
// allocator and its backing state must remain valid until destroy_program
// succeeds. A live Program is
// address-stable and must not be copied with Odin `=`. Odin cannot hide fields
// of a public struct; direct field rewriting is outside the valid API.
Program :: struct {
	instructions: []Instruction,
	operands:     []Operand,
	text:         []u8,
	root:         Instruction_Index,
	has_root:     bool,
	instructions_written: Count,
	operands_written:     Count,
	text_written:         Count,
	validation_records: []Validation_Record,
	memory:       []byte,
	allocator:    runtime.Allocator,
	state:        Program_State,
	self:         ^Program,
}

@(private="package")
align_up :: proc(value, alignment: u64) -> (u64, bool) {
	assert(alignment > 0)
	padding := alignment - 1
	if value > max(u64) - padding {
		return 0, false
	}
	return (value + padding) & ~padding, true
}

// init_program allocates exact storage and initializes an address-stable owner.
// Counts or layout arithmetic exceeding u32 are rejected before allocation.
// Zero counts form a valid allocation-free Program. program must be inert.
init_program :: proc(
	program: ^Program,
	instruction_count, operand_count, text_count: Count,
	allocator: runtime.Allocator,
) -> Init_Error {
	if program == nil || program.state == .Building || program.state == .Active ||
	   program.state == .Cleanup_Failed {
		return Init_Error{kind = .Resource_Failure, resource_error = .Invalid_Argument}
	}

	ic := u64(instruction_count)
	oc := u64(operand_count)
	tc := u64(text_count)
	instruction_bytes := ic * u64(size_of(Instruction))
	operand_start, aligned := align_up(instruction_bytes, u64(align_of(Operand)))
	if !aligned {
		return Init_Error{kind = .Size_Overflow}
	}
	operand_bytes := oc * u64(size_of(Operand))
	if operand_start > max(u64) - operand_bytes {
		return Init_Error{kind = .Size_Overflow}
	}
	validation_unaligned := operand_start + operand_bytes
	validation_start, validation_aligned := align_up(
		validation_unaligned,
		u64(align_of(Validation_Record)),
	)
	if !validation_aligned {
		return Init_Error{kind = .Size_Overflow}
	}
	validation_bytes := ic * u64(size_of(Validation_Record))
	if validation_start > max(u64) - validation_bytes {
		return Init_Error{kind = .Size_Overflow}
	}
	text_start := validation_start + validation_bytes
	if text_start > max(u64) - tc {
		return Init_Error{kind = .Size_Overflow}
	}
	total := text_start + tc
	if total > u64(max(Storage_Count)) || total > u64(max(int)) {
		return Init_Error{kind = .Size_Overflow}
	}

	program^ = {}
	program.allocator = allocator
	program.state = .Building
	program.self = program
	if total == 0 {
		return {}
	}

	memory, allocation_error := runtime.mem_alloc_bytes(
		int(total),
		max(align_of(Instruction), align_of(Operand), align_of(Validation_Record)),
		allocator,
	)
	if allocation_error != nil || len(memory) != int(total) {
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				program.memory = memory
				program.state = .Cleanup_Failed
				return Init_Error{kind = .Resource_Failure, resource_error = free_error}
			}
		}
		program^ = {}
		return Init_Error{
			kind = .Resource_Failure,
			resource_error = allocation_error if allocation_error != nil else .Out_Of_Memory,
		}
	}

	program.memory = memory
	base := uintptr(raw_data(memory))
	if ic > 0 {
		program.instructions = (cast([^]Instruction)rawptr(base))[:int(ic)]
	}
	if oc > 0 {
		program.operands = (cast([^]Operand)rawptr(base + uintptr(operand_start)))[:int(oc)]
	}
	if ic > 0 {
		program.validation_records = (
			cast([^]Validation_Record)rawptr(base + uintptr(validation_start))
		)[:int(ic)]
		for index in 0..<len(program.validation_records) {
			program.validation_records[index] = {}
		}
	}
	if tc > 0 {
		program.text = (cast([^]u8)rawptr(base + uintptr(text_start)))[:int(tc)]
	}
	return {}
}

// Construction setters form an intentionally narrow ordered builder surface.
// They reject writes outside Building, repeated/skipped slots, and ranges that
// exceed the exact allocation. They do not allocate.
set_instruction :: proc(program: ^Program, index: Instruction_Index, value: Instruction) -> bool {
	if !program_is_building(program) || u64(index) != u64(program.instructions_written) ||
	   u64(index) >= u64(len(program.instructions)) {
		return false
	}
	program.instructions[int(index)] = value
	program.instructions_written += 1
	return true
}

set_operand :: proc(program: ^Program, index: Operand_Index, value: Operand) -> bool {
	if !program_is_building(program) || u64(index) != u64(program.operands_written) ||
	   u64(index) >= u64(len(program.operands)) {
		return false
	}
	program.operands[int(index)] = value
	program.operands_written += 1
	return true
}

set_text :: proc(program: ^Program, start: Byte_Offset, value: string) -> bool {
	start_u64 := u64(start)
	text_len := u64(len(program.text))
	if !program_is_building(program) || start_u64 != u64(program.text_written) ||
	   start_u64 > text_len || u64(len(value)) > text_len-start_u64 {
		return false
	}
	copy(program.text[int(start):int(start)+len(value)], transmute([]u8)value)
	program.text_written += Count(len(value))
	return true
}

set_root :: proc(program: ^Program, root: Instruction_Index) -> bool {
	if !program_is_building(program) || program.has_root {
		return false
	}
	program.root = root
	program.has_root = true
	return true
}

@(private="package")
opcode_is_binary :: proc(opcode: Opcode) -> bool {
	switch opcode {
	case .Add, .Subtract, .Multiply, .Divide, .Modulo,
	     .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return true
	case .Identity, .Last, .First, .Log10, .Log2, .Exp, .Exp2, .Exp10, .Asin, .Acos, .Cos, .Sin, .Tan, .Sinh, .Isinfinite, .Any_Not, .All_Not, .Error, .Try, .IsEmpty, .Range, .Limit, .Skip, .Nth, .Map, .Map_Values, .Slice, .Strftime, .Strptime, .Mktime, .Gmtime, .Fromdate, .Todate, .Negate, .Field, .Index, .Parenthesized, .Sequence, .Fork, .Optional,
	     .Array, .Object, .Variable, .Binding, .Reduce, .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Trunc, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Flatten, .Nan, .Infinite, .Any, .All, .Isfinite, .Join, .Isnormal, .Contains, .Split, .Index_Builtin, .Rindex_Builtin, .Indices_Builtin, .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr:
		return false
	}
	return false
}

@(private="package")
instruction_structure_valid :: proc(program: ^Program, instruction: Instruction, next_text: ^u64) -> bool {
	if instruction.span.start > instruction.span.end {
		return false
	}
	start := u64(instruction.operands_start)
	count := u64(instruction.operands_count)
	if start > u64(len(program.operands)) || count > u64(len(program.operands))-start {
		return false
	}
	// Literal metadata belongs to the Identity literal carrier. Other
	// opcodes must not reinterpret one of their operands as literal text.
	if instruction.has_literal && instruction.opcode != .Identity {
		return false
	}

	expected_count: u64
	switch instruction.opcode {
	case .Identity:
		if instruction.has_literal {
			if instruction.literal_kind == .Number || instruction.literal_kind == .String {
				expected_count = 1
			} else if instruction.literal_kind == .Null || instruction.literal_kind == .Boolean {
				expected_count = 0
			} else {
				return false
			}
		} else {
			expected_count = 0
		}
	case .Field:
		if count != 1 && count != 2 {
			return false
		}
		expected_count = count
	case .Index:
		if count != 2 do return false
		expected_count = 2
	case .Parenthesized, .Optional, .Negate:
		expected_count = 1
	case .Array:
		expected_count = count
	case .Object:
		// Object operands alternate a text key and a value instruction.
		if count % 2 != 0 do return false
		expected_count = count
	case .Variable:
		expected_count = 1
	case .Binding:
		 expected_count = 3
	case .Reduce:
		if count != 4 { return false }; expected_count = 4
	case .Join, .Contains:
		if count != 1 { return false }; expected_count = 1
	case .Split:
		if count != 1 { return false }; expected_count = 1
	case .Index_Builtin, .Rindex_Builtin, .Indices_Builtin, .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr, .Error:
		if count != 1 { return false }; expected_count = 1
	case .Try:
		if count != 2 { return false }; expected_count = 2
	case .IsEmpty, .Map, .Map_Values:
		if count != 1 { return false }; expected_count = 1
	case .Slice:
		if count != 3 { return false }; expected_count = 3
	case .Range:
		if count != 1 && count != 2 && count != 3 { return false }; expected_count = count
	case .Limit:
		if count != 2 { return false }; expected_count = 2
	case .Skip:
		if count != 2 { return false }; expected_count = 2
	case .Nth:
		if count != 2 { return false }; expected_count = 2
	case .Strftime, .Strptime:
		if count != 1 { return false }; expected_count = 1
	case .Flatten:
		if count != 0 && count != 1 do return false
		expected_count = count
	case .Last, .First:
		if count > 1 { return false }
		expected_count = count
	case .Log10, .Log2, .Exp, .Exp2, .Exp10, .Asin, .Acos, .Cos, .Sin, .Tan, .Sinh, .Isinfinite, .Mktime, .Gmtime, .Fromdate, .Todate:
		expected_count = 0
	case .Any_Not, .All_Not:
		expected_count = 0
	case .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Trunc, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal:
		expected_count = 0
	case .Sequence, .Fork,
	     .Add, .Subtract, .Multiply, .Divide, .Modulo,
	     .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		expected_count = 2
	case:
		return false
	}
	if count != expected_count {
		return false
	}
	binary := opcode_is_binary(instruction.opcode)
	if binary != instruction.has_operator_span {
		return false
	}
	if !binary && instruction.operator_span != (Source_Span{}) {
		return false
	}
	if binary && (instruction.operator_span.start >= instruction.operator_span.end ||
	              instruction.operator_span.start < instruction.span.start ||
	              instruction.operator_span.end > instruction.span.end) {
		return false
	}
	if !instruction.has_literal &&
	   (instruction.literal_kind != .Null || instruction.literal_boolean) {
		return false
	}
	if instruction.has_literal && instruction.literal_kind != .Boolean &&
	   instruction.literal_boolean {
		return false
	}

	for offset in 0..<count {
		operand := program.operands[int(start+offset)]
		expected_kind := Operand_Kind.Instruction
		if ((instruction.opcode == .Field || instruction.opcode == .Index) && offset == count-1) ||
		   (instruction.opcode == .Slice && offset > 0) ||
		   (instruction.has_literal && offset == 0) {
			expected_kind = .Text
		}
	if instruction.opcode == .Object && offset % 2 == 0 {
			// Object keys are either static Text operands or compiled key
			// expressions. Values remain Instruction operands at odd offsets.
			if operand.kind != .Text && operand.kind != .Instruction do return false
			expected_kind = operand.kind
		}
		if instruction.opcode == .Variable && offset == 0 {
			expected_kind = .Text
		}
		if instruction.opcode == .Binding && offset == 2 {
			expected_kind = .Text
		}
		if instruction.opcode == .Reduce && offset == 3 {
			expected_kind = .Text
		}
		if operand.kind != expected_kind {
			return false
		}
		if operand.kind == .Instruction {
			if u64(operand.instruction) >= u64(len(program.instructions)) {
				return false
			}
		} else {
			text_start := u64(operand.text_start)
			text_count := u64(operand.text_count)
			if text_start != next_text^ || text_start > u64(len(program.text)) ||
			   text_count > u64(len(program.text))-text_start {
				return false
			}
			next_text^ += text_count
		}
	}
	return true
}

@(private="package")
instruction_child_count :: proc(program: ^Program, instruction: Instruction) -> Count {
	switch instruction.opcode {
	case .Identity, .Log10, .Log2, .Exp, .Exp2, .Exp10, .Asin, .Acos, .Cos, .Sin, .Tan, .Sinh, .Isinfinite, .Mktime, .Gmtime, .Fromdate, .Todate, .Any_Not, .All_Not, .Length, .Keys, .Keys_Unsorted, .Tostring, .Tonumber, .Min, .Max, .Toboolean, .Base64, .Base64d, .Uri, .Urid, .Html, .Text, .Json, .Csv, .Tsv, .Sh, .Tojson, .Fromjson, .Log, .From_Entries, .To_Entries, .Isnan, .Utf8bytelength, .Not_Builtin, .Empty, .Values, .Arrays, .Objects, .Iterables, .Scalars, .Booleans, .Nulls, .Numbers, .Strings, .Finites, .Normals, .Floor, .Round, .Trunc, .Transpose, .Unique, .Sort, .Type, .Abs, .Sqrt, .Fabs, .Add_Builtin, .Trim, .Ltrim, .Rtrim, .Atan, .Ascii_Downcase, .Ascii_Upcase, .Reverse, .Implode, .Explode, .Ceil, .Nan, .Infinite, .Any, .All, .Isfinite, .Isnormal:
		return 0
	case .Last, .First:
		return instruction.operands_count
	case .Flatten:
		return instruction.operands_count
	case .Join, .Contains, .Split, .Index_Builtin, .Rindex_Builtin, .Indices_Builtin, .Startswith, .Endswith, .Has, .Bsearch, .Ltrimstr, .Rtrimstr, .Trimstr, .Error, .IsEmpty, .Map, .Map_Values, .Strftime, .Strptime:
		return 1
	case .Slice:
		return 1
	case .Try:
		return 2
	case .Range:
		return instruction.operands_count
	case .Limit:
		return 2
	case .Skip:
		return 2
	case .Nth:
		return 2
	case .Field:
		return 1 if instruction.operands_count == 2 else 0
	case .Index:
		return 1
	case .Parenthesized, .Optional:
		return 1
	case .Negate:
		return 1
	case .Array:
		return instruction.operands_count
	case .Object:
		// Object operands alternate key/value.  Text keys have no graph edge,
		// while computed key instructions do.  Count both key and value edges so
		// cycle validation covers the complete instruction graph.
		count: Count
		for offset in 0..<instruction.operands_count {
			operand := program.operands[int(u64(instruction.operands_start)+u64(offset))]
			if operand.kind == .Instruction do count += 1
		}
		return count
	case .Binding:
		return 2
	case .Reduce:
		return 3
	case .Variable:
		return 0
	case .Sequence, .Fork,
	     .Add, .Subtract, .Multiply, .Divide, .Modulo,
	     .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return 2
	}
	return 0
}

@(private="package")
instruction_child_at :: proc(program: ^Program, instruction: Instruction, offset: Count) -> Instruction_Index {
	assert(offset < instruction_child_count(program, instruction))
	operand_offset: Count
	if instruction.opcode != .Object {
		operand_offset = offset
	} else {
		edge: Count
		for candidate in 0..<instruction.operands_count {
			operand := program.operands[int(u64(instruction.operands_start)+u64(candidate))]
			if operand.kind != .Instruction do continue
			if edge == offset {
				operand_offset = candidate
				break
			}
			edge += 1
		}
	}
	return program.operands[int(u64(instruction.operands_start)+u64(operand_offset))].instruction
}

@(private="package")
validate_instruction_graph :: proc(program: ^Program) -> bool {
	records := program.validation_records
	for index in 0..<len(records) {
		records[index] = {}
	}
	acyclic := true
	for _, start in program.instructions {
		if records[start].state != .Unseen {
			continue
		}
		records[start].state = .Visiting
		current := Instruction_Index(start)
		for {
			record := &records[int(current)]
			instruction := program.instructions[int(current)]
			child_count := instruction_child_count(program, instruction)
			if record.next_child < child_count {
				child := instruction_child_at(program, instruction, record.next_child)
				record.next_child += 1
				switch records[int(child)].state {
				case .Unseen:
					records[int(child)].state = .Visiting
					records[int(child)].parent = current
					records[int(child)].has_parent = true
					current = child
				case .Visiting:
					acyclic = false
				case .Done:
				}
				if !acyclic {
					break
				}
				continue
			}
			record.state = .Done
			if !record.has_parent {
				break
			}
			current = record.parent
		}
		if !acyclic {
			break
		}
	}

	return acyclic
}

// finalize_program validates complete owned storage, the complete acyclic
// instruction graph, and its explicit entry instruction. Success seals Building
// exactly once and makes it Active. Failure leaves it unreadable in Building
// for destruction. Iterative graph scratch is private storage inside Program's
// one allocation, so finalization performs no allocation or native recursion.
finalize_program :: proc(program: ^Program) -> bool {
	if !program_is_building(program) || !program.has_root ||
	   u64(program.root) >= u64(len(program.instructions)) ||
	   u64(program.instructions_written) != u64(len(program.instructions)) ||
	   u64(program.operands_written) != u64(len(program.operands)) ||
	   u64(program.text_written) != u64(len(program.text)) {
		return false
	}

	next_operand: u64
	next_text: u64
	for instruction in program.instructions {
		if u64(instruction.operands_start) != next_operand ||
		   !instruction_structure_valid(program, instruction, &next_text) {
			return false
		}
		next_operand += u64(instruction.operands_count)
	}
	if next_operand != u64(len(program.operands)) || next_text != u64(len(program.text)) {
		return false
	}
	if !validate_instruction_graph(program) {
		return false
	}
	program.state = .Active
	return true
}

program_root :: proc(program: ^Program) -> (Instruction_Index, bool) {
	if !program_is_active(program) {
		return {}, false
	}
	return program.root, true
}

// Runtime storage access is read-only by value and unavailable while Building.
program_instruction_count :: proc(program: ^Program) -> (Count, bool) {
	if !program_is_active(program) {
		return {}, false
	}
	return Count(len(program.instructions)), true
}

program_operand_count :: proc(program: ^Program) -> (Count, bool) {
	if !program_is_active(program) {
		return {}, false
	}
	return Count(len(program.operands)), true
}

program_instruction :: proc(program: ^Program, index: Instruction_Index) -> (Instruction, bool) {
	if !program_is_active(program) || u64(index) >= u64(len(program.instructions)) {
		return {}, false
	}
	return program.instructions[int(index)], true
}

program_operand :: proc(program: ^Program, index: Operand_Index) -> (Operand, bool) {
	if !program_is_active(program) || u64(index) >= u64(len(program.operands)) {
		return {}, false
	}
	return program.operands[int(index)], true
}

// The returned immutable string borrows Program-owned text backing. It remains
// valid only while this Program is live and expires when destruction begins.
operand_text :: proc(program: ^Program, operand: Operand) -> (string, bool) {
	if !program_is_active(program) || operand.kind != .Text {
		return "", false
	}
	start := u64(operand.text_start)
	end := start + u64(operand.text_count)
	if end > u64(len(program.text)) {
		return "", false
	}
	return string(program.text[int(start):int(end)]), true
}

program_is_active :: proc(program: ^Program) -> bool {
	return program != nil && program.state == .Active && program.self == program
}

program_is_building :: proc(program: ^Program) -> bool {
	return program != nil && program.state == .Building && program.self == program
}

// destroy_program releases the single owned allocation. Genuine allocator
// errors preserve ownership for retry; Mode_Not_Implemented retires storage
// under a bulk allocator. A shallow copy of a live owner is rejected before
// any backing or allocator access. Successful destruction is idempotent.
destroy_program :: proc(program: ^Program) -> runtime.Allocator_Error {
	if program == nil || program.state == .Uninitialized || program.state == .Destroyed {
		return nil
	}
	if program.self != program {
		return .Invalid_Pointer
	}
	if len(program.memory) > 0 {
		free_error := runtime.mem_free_bytes(program.memory, program.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			program.state = .Cleanup_Failed
			return free_error
		}
	}
	program^ = Program{state = .Destroyed}
	return nil
}
