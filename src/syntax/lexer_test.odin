package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(private="package")
expect_span :: proc(
	t: ^testing.T,
	source: diagnostic.Source,
	span: diagnostic.Span,
	expected_start, expected_end: int,
) {
	start, end, ok := diagnostic.span_offsets(source, span)
	testing.expect(t, ok)
	testing.expect_value(t, start, expected_start)
	testing.expect_value(t, end, expected_end)
}

@(private="package")
expect_token :: proc(
	t: ^testing.T,
	scanner: ^Scanner,
	source: diagnostic.Source,
	kind: Token_Kind,
	start, end: int,
) -> Token {
	outcome := next_token(scanner)
	testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Token)
	testing.expect_value(t, outcome.token.kind, kind)
	expect_span(t, source, outcome.token.span, start, end)
	testing.expect(t, !outcome.has_error_span)
	equal_but_distinct := diagnostic.borrow_source(
		diagnostic.source_name(source),
		diagnostic.source_bytes(source),
	)
	_, _, mismatched_ok := diagnostic.span_offsets(
		equal_but_distinct,
		outcome.token.span,
	)
	testing.expect(t, !mismatched_ok)
	return outcome.token
}

@(private="package")
init_test_scanner :: proc(
	t: ^testing.T,
	scanner: ^Scanner,
	source: diagnostic.Source,
	allocator := context.allocator,
) {
	testing.expect(t, init_scanner(scanner, source, allocator))
}

@(test)
test_every_accepted_fixed_token_and_operator :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: Token_Kind,
	}
	cases := [?]Case{
		{".", .Dot},
		{"?", .Question},
		{"=", .Assign},
		{";", .Semicolon},
		{",", .Comma},
		{":", .Colon},
		{"|", .Pipe},
		{"+", .Plus},
		{"-", .Minus},
		{"*", .Multiply},
		{"/", .Divide},
		{"%", .Modulo},
		{"$", .Dollar},
		{"<", .Less},
		{">", .Greater},
		{"[", .Open_Bracket},
		{"{", .Open_Brace},
		{"(", .Open_Paren},
		{"!=", .Not_Equal},
		{"==", .Equal},
		{"as", .As},
		{"import", .Import},
		{"include", .Include},
		{"module", .Module},
		{"def", .Def},
		{"if", .If},
		{"then", .Then},
		{"else", .Else},
		{"elif", .Else_If},
		{"and", .And},
		{"or", .Or},
		{"end", .End},
		{"reduce", .Reduce},
		{"foreach", .Foreach},
		{"//", .Defined_Or},
		{"try", .Try},
		{"catch", .Catch},
		{"label", .Label},
		{"break", .Break},
		{"$__loc__", .Location},
		{"|=", .Assign_Pipe},
		{"+=", .Assign_Plus},
		{"-=", .Assign_Minus},
		{"*=", .Assign_Multiply},
		{"/=", .Assign_Divide},
		{"%=", .Assign_Modulo},
		{"//=", .Assign_Defined_Or},
		{"<=", .Less_Equal},
		{">=", .Greater_Equal},
		{"..", .Recurse},
		{"?//", .Alternation},
	}

	for test_case in cases {
		source := diagnostic.borrow_source(test_case.text, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		expect_token(t, &scanner, source, test_case.kind, 0, len(test_case.text))
		testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
		destroy_scanner(&scanner)
	}
}

@(test)
test_jq_assignment_tokens_stay_distinct :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source(
		"<assignments>",
		"= |= += -= *= /= %= //=",
	)
	kinds := [?]Token_Kind{
		.Assign,
		.Assign_Pipe,
		.Assign_Plus,
		.Assign_Minus,
		.Assign_Multiply,
		.Assign_Divide,
		.Assign_Modulo,
		.Assign_Defined_Or,
	}
	starts := [?]int{0, 2, 5, 8, 11, 14, 17, 20}
	ends := [?]int{1, 4, 7, 10, 13, 16, 19, 23}

	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	for kind, index in kinds {
		expect_token(t, &scanner, source, kind, starts[index], ends[index])
	}
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_identifiers_bindings_formats_fields_and_longest_match :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source(
		"<names>",
		"word ns::leaf $binding $ns::leaf @fmt_2 .field as asx $__loc__ $__loc__x foo::",
	)
	Case :: struct {
		kind:        Token_Kind,
		start:       int,
		end:         int,
		value_start: int,
		value_end:   int,
		has_value:   bool,
	}
	cases := [?]Case{
		{.Identifier, 0, 4, 0, 0, false},
		{.Identifier, 5, 13, 0, 0, false},
		{.Binding, 14, 22, 15, 22, true},
		{.Binding, 23, 32, 24, 32, true},
		{.Format, 33, 39, 34, 39, true},
		{.Field, 40, 46, 41, 46, true},
		{.As, 47, 49, 0, 0, false},
		{.Identifier, 50, 53, 0, 0, false},
		{.Location, 54, 62, 0, 0, false},
		{.Binding, 63, 72, 64, 72, true},
		{.Identifier, 73, 76, 0, 0, false},
		{.Colon, 76, 77, 0, 0, false},
		{.Colon, 77, 78, 0, 0, false},
	}

	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	for test_case in cases {
		token := expect_token(
			t,
			&scanner,
			source,
			test_case.kind,
			test_case.start,
			test_case.end,
		)
		testing.expect_value(t, token.has_value_span, test_case.has_value)
		if test_case.has_value {
			expect_span(
				t,
				source,
				token.value_span,
				test_case.value_start,
				test_case.value_end,
			)
		}
	}
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_comment_odd_even_backslashes_lf :: proc(t: ^testing.T) {
	Case :: struct {
		name: string,
		text: string,
		dot_start: int,
	}
	cases := [?]Case{
		{"zero", "# zero\n.", 7},
		{"one", "# one \\\ncontinued\n.", 18},
		{"two", "# two \\\\\n.", 9},
		{"three", "# three \\\\\\\ncontinued\n.", 22},
	}
	for test_case in cases {
		source := diagnostic.borrow_source(test_case.name, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		expect_token(t, &scanner, source, .Dot, test_case.dot_start, test_case.dot_start+1)
		testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
		destroy_scanner(&scanner)
	}
}

@(test)
test_comment_odd_even_backslashes_crlf :: proc(t: ^testing.T) {
	// jq's comment rule consumes either a backslash pair or one
	// backslash-CRLF continuation before considering CRLF a terminator:
	// upstream/jq/src/lexer.l:41-46. These cases pin the resulting spans
	// under docs/decisions/0004-syntax-token-contract.md:27-43,67-78.
	Case :: struct {
		name:       string,
		text:       string,
		next_kind:  Token_Kind,
		next_start: int,
		next_end:   int,
	}
	cases := [?]Case{
		{"zero", "# zero\r\n.", .Dot, 8, 9},
		{"one", "# one \\\r\ncontinued\r\n.", .Dot, 20, 21},
		{"two", "# two \\\\\r\ncontinued\r\n.", .Identifier, 10, 19},
		{"three", "# three \\\\\\\r\ncontinued\r\n.", .Dot, 24, 25},
	}
	for test_case in cases {
		source := diagnostic.borrow_source(test_case.name, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		expect_token(
			t,
			&scanner,
			source,
			test_case.next_kind,
			test_case.next_start,
			test_case.next_end,
		)
		if test_case.name == "two" {
			expect_token(t, &scanner, source, .Dot, 21, 22)
		}
		testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
		destroy_scanner(&scanner)
	}
}

@(test)
test_comment_lf_crlf_cr_and_eof_boundaries :: proc(t: ^testing.T) {
	Case :: struct {
		name:      string,
		text:      string,
		first_kind: Scan_Outcome_Kind,
		dot_start: int,
	}
	cases := [?]Case{
		{"LF terminates", "# x\n.", .Token, 4},
		{"CRLF terminates", "# x\r\n.", .Token, 5},
		{"bare CR continues", "# x\r.", .End_Of_Input, 0},
		{"continued CRLF", "# x\\\r\ncontinued\r\n.", .Token, 17},
		{"comment EOF", "# x", .End_Of_Input, 0},
		{"continued newline EOF", "# x\\\n", .End_Of_Input, 0},
	}
	for test_case in cases {
		source := diagnostic.borrow_source(test_case.name, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		if test_case.first_kind == .Token {
			expect_token(t, &scanner, source, .Dot, test_case.dot_start, test_case.dot_start+1)
			testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
		} else {
			testing.expect_value(t, next_token(&scanner).kind, test_case.first_kind)
			testing.expect_value(t, next_token(&scanner).kind, test_case.first_kind)
		}
		destroy_scanner(&scanner)
	}
}

@(test)
test_whitespace_exactly_matches_accepted_ascii_set :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<ws>", " \r\n\t.")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .Dot, 4, 5)
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_balanced_nesting_and_mismatched_closers :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<nested>", "([{()}])")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	kinds := [?]Token_Kind{
		.Open_Paren,
		.Open_Bracket,
		.Open_Brace,
		.Open_Paren,
		.Close_Paren,
		.Close_Brace,
		.Close_Bracket,
		.Close_Paren,
	}
	for kind, index in kinds {
		expect_token(t, &scanner, source, kind, index, index+1)
	}
	testing.expect_value(t, len(scanner.delimiters), 0)
	destroy_scanner(&scanner)

	unopened_closers := [?]string{")", "]", "}"}
	for text in unopened_closers {
		mismatch_source := diagnostic.borrow_source(text, text)
		mismatch_scanner: Scanner
		init_test_scanner(t, &mismatch_scanner, mismatch_source)
		outcome := next_token(&mismatch_scanner)
		testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Lexical_Error)
		testing.expect(t, outcome.has_error_span)
		expect_span(t, mismatch_source, outcome.error_span, 0, 1)
		testing.expect_value(
			t,
			next_token(&mismatch_scanner).kind,
			Scan_Outcome_Kind.End_Of_Input,
		)
		destroy_scanner(&mismatch_scanner)
	}

	// try_exit returns an error without popping an opener on mismatch, while
	// enter records each delimiter kind: upstream/jq/src/lexer.l:83-89,144-181.
	// docs/decisions/0004-syntax-token-contract.md:67-78 requires
	// delimiter-specific retained state and exact closer spans.
	Case :: struct {
		name:         string,
		text:         string,
		opener_kind:  Token_Kind,
		closer_kind:  Token_Kind,
	}
	cases := [?]Case{
		{"paren-bracket", "(])", .Open_Paren, .Close_Paren},
		{"paren-brace", "(})", .Open_Paren, .Close_Paren},
		{"bracket-paren", "[)]", .Open_Bracket, .Close_Bracket},
		{"bracket-brace", "[}]", .Open_Bracket, .Close_Bracket},
		{"brace-paren", "{)}", .Open_Brace, .Close_Brace},
		{"brace-bracket", "{]}", .Open_Brace, .Close_Brace},
	}
	for test_case in cases {
		mismatch_source := diagnostic.borrow_source(test_case.name, test_case.text)
		mismatch_scanner: Scanner
		init_test_scanner(t, &mismatch_scanner, mismatch_source)
		expect_token(t, &mismatch_scanner, mismatch_source, test_case.opener_kind, 0, 1)

		outcome := next_token(&mismatch_scanner)
		testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Lexical_Error)
		testing.expect(t, outcome.has_error_span)
		expect_span(t, mismatch_source, outcome.error_span, 1, 2)
		testing.expect_value(t, len(mismatch_scanner.delimiters), 1)

		expect_token(t, &mismatch_scanner, mismatch_source, test_case.closer_kind, 2, 3)
		testing.expect_value(t, len(mismatch_scanner.delimiters), 0)
		testing.expect_value(
			t,
			next_token(&mismatch_scanner).kind,
			Scan_Outcome_Kind.End_Of_Input,
		)
		destroy_scanner(&mismatch_scanner)
	}
}

@(private="package")
delimiter_open_kind :: proc(byte: u8) -> Token_Kind {
	switch byte {
	case '(': return .Open_Paren
	case '[': return .Open_Bracket
	case '{': return .Open_Brace
	}
	unreachable()
}

@(test)
test_embedded_nul_unmatched_bytes_and_exact_byte_spans :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<bytes>", "\x00\xffé .x")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	for index in 0 ..< 4 {
		outcome := next_token(&scanner)
		testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Lexical_Error)
		expect_span(t, source, outcome.error_span, index, index+1)
	}
	expect_token(t, &scanner, source, .Field, 5, 7)
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_token_source_identity_and_value_containment :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<one>", "$ns::value")
	other := diagnostic.borrow_source("<two>", "$ns::value")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	token := expect_token(t, &scanner, source, .Binding, 0, 10)
	expect_span(t, source, token.value_span, 1, 10)

	_, _, token_other_ok := diagnostic.span_offsets(other, token.span)
	_, _, value_other_ok := diagnostic.span_offsets(other, token.value_span)
	testing.expect(t, !token_other_ok)
	testing.expect(t, !value_other_ok)

	full_start, full_end, _ := diagnostic.span_offsets(source, token.span)
	value_start, value_end, _ := diagnostic.span_offsets(source, token.value_span)
	testing.expect(t, value_start >= full_start && value_end <= full_end)
	destroy_scanner(&scanner)
}

@(test)
test_retained_source_outlives_scanner :: proc(t: ^testing.T) {
	owned, clone_error := strings.clone("$kept", context.allocator)
	testing.expect(t, clone_error == nil)
	defer delete(owned)

	source := diagnostic.borrow_source("<owned>", owned)
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	token := expect_token(t, &scanner, source, .Binding, 0, 5)
	destroy_scanner(&scanner)

	start, end, ok := diagnostic.span_offsets(source, token.value_span)
	testing.expect(t, ok)
	testing.expect_value(t, diagnostic.source_bytes(source)[start:end], "kept")
}

@(private="package")
Test_Allocator :: struct {
	backing:              runtime.Allocator,
	fail_at:              int,
	request_count:        int,
	free_count:           int,
	alive:                bool,
	calls_after_retirement: int,
}

@(private="package")
test_allocator :: proc(data: ^Test_Allocator) -> runtime.Allocator {
	return runtime.Allocator{
		procedure = test_allocator_proc,
		data = data,
	}
}

@(private="package")
test_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	data := (^Test_Allocator)(allocator_data)
	if !data.alive {
		data.calls_after_retirement += 1
		return nil, .Out_Of_Memory
	}
	if mode == .Alloc ||
	   mode == .Alloc_Non_Zeroed ||
	   mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		data.request_count += 1
		if data.fail_at > 0 && data.request_count == data.fail_at {
			return nil, .Out_Of_Memory
		}
	}
	if mode == .Free {
		data.free_count += 1
	}
	return data.backing.procedure(
		data.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

DEEP_NESTING :: "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((("

@(test)
test_every_reachable_allocator_failure_is_terminal_atomic_repeatable :: proc(t: ^testing.T) {
	baseline_data := Test_Allocator{
		backing = context.allocator,
		alive = true,
	}
	baseline_source := diagnostic.borrow_source("<baseline>", DEEP_NESTING)
	baseline_scanner: Scanner
	init_test_scanner(
		t,
		&baseline_scanner,
		baseline_source,
		test_allocator(&baseline_data),
	)
	for {
		outcome := next_token(&baseline_scanner)
		if outcome.kind == .End_Of_Input {
			break
		}
		testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Token)
	}
	allocation_points := baseline_data.request_count
	testing.expect(t, allocation_points > 1)
	destroy_scanner(&baseline_scanner)

	for fail_at in 1 ..= allocation_points {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		allocator_data := Test_Allocator{
			backing = mem.tracking_allocator(&tracker),
			fail_at = fail_at,
			alive = true,
		}
		source := diagnostic.borrow_source("<failure>", DEEP_NESTING)
		scanner: Scanner
		init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))

		for {
			before_offset := scanner.offset
			before_depth := len(scanner.delimiters)
			outcome := next_token(&scanner)
			if outcome.kind == .Resource_Failure {
				testing.expect_value(t, scanner.offset, before_offset)
				testing.expect_value(t, len(scanner.delimiters), before_depth)
				break
			}
			testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Token)
		}

		requests_at_failure := allocator_data.request_count
		offset_at_failure := scanner.offset
		depth_at_failure := len(scanner.delimiters)
		for _ in 0 ..< 3 {
			repeated := next_token(&scanner)
			testing.expect_value(t, repeated.kind, Scan_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, allocator_data.request_count, requests_at_failure)
			testing.expect_value(t, scanner.offset, offset_at_failure)
			testing.expect_value(t, len(scanner.delimiters), depth_at_failure)
		}
		destroy_scanner(&scanner)
		testing.expect(t, len(tracker.allocation_map) == 0)
		mem.tracking_allocator_destroy(&tracker)
	}
}

@(test)
test_allocator_provenance_and_destruction :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	source := diagnostic.borrow_source("<destroy>", "([{")
	scanner: Scanner
	init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))
	for index in 0 ..< 3 {
		_ = expect_token(
			t,
			&scanner,
			source,
			delimiter_open_kind(source.bytes[index]),
			index,
			index+1,
		)
	}
	testing.expect(t, len(tracker.allocation_map) > 0)

	destroy_scanner(&scanner)
	testing.expect(t, len(tracker.allocation_map) == 0)
	allocator_data.alive = false
	destroy_scanner(&scanner)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(private="package")
scanner_copy_death_child_selected :: proc(selector: string) -> bool {
	for arg in os.args[1:] {
		if arg == selector {
			return true
		}
	}
	return false
}

@(test)
test_scanner_copy_advance_death_child :: proc(t: ^testing.T) {
	selector :: "-tests:test_scanner_copy_advance_death_child"
	if !scanner_copy_death_child_selected(selector) {
		return
	}

	source := diagnostic.borrow_source("<copy-advance>", "((")
	scanner: Scanner
	assert(init_scanner(&scanner, source, context.allocator))
	_ = next_token(&scanner)
	copied := scanner
	_ = next_token(&copied)
	testing.expect(t, false)
}

@(test)
test_scanner_copy_destroy_death_child :: proc(t: ^testing.T) {
	selector :: "-tests:test_scanner_copy_destroy_death_child"
	if !scanner_copy_death_child_selected(selector) {
		return
	}

	source := diagnostic.borrow_source("<copy-destroy>", "(")
	scanner: Scanner
	assert(init_scanner(&scanner, source, context.allocator))
	_ = next_token(&scanner)
	copied := scanner
	destroy_scanner(&copied)
	testing.expect(t, false)
}

@(test)
test_shallow_scanner_copy_is_rejected_before_shared_storage_use :: proc(t: ^testing.T) {
	// docs/decisions/0004-syntax-token-contract.md:45-65 forbids Odin `=`
	// copies of a live Scanner owner.
	// Run both hazardous operations in isolated test-runner subprocesses so
	// their required production assertions cannot abort this parent runner.
	selectors := [?]string{
		"-tests:test_scanner_copy_advance_death_child",
		"-tests:test_scanner_copy_destroy_death_child",
	}
	executable, executable_error := os.get_executable_path(context.allocator)
	testing.expect(t, executable_error == nil)
	if executable_error != nil {
		return
	}
	defer delete(executable)

	for selector in selectors {
		state, stdout, stderr, process_error := os.process_exec(
			os.Process_Desc{command = []string{executable, selector}},
			context.allocator,
		)
		testing.expect(t, process_error == nil)
		testing.expect(t, state.exited)
		testing.expect(t, !state.success)
		testing.expect(t, strings.contains(string(stderr), "Scanner"))
		testing.expect(t, strings.contains(string(stderr), "copied"))
		delete(stdout)
		delete(stderr)
	}
}

@(test)
test_init_rejects_stale_source_and_destroyed_scanner_is_reusable :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<test>", ".")
	stale := source
	stale.bytes = "!"
	scanner: Scanner
	testing.expect(t, !init_scanner(&scanner, stale, context.allocator))

	testing.expect(t, init_scanner(&scanner, source, context.allocator))
	expect_token(t, &scanner, source, .Dot, 0, 1)
	destroy_scanner(&scanner)
	destroy_scanner(&scanner)

	testing.expect(t, init_scanner(&scanner, source, context.allocator))
	expect_token(t, &scanner, source, .Dot, 0, 1)
	destroy_scanner(&scanner)
}
