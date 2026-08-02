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
expect_value_span :: proc(
	t: ^testing.T,
	source: diagnostic.Source,
	token: Token,
	start, end: int,
) {
	testing.expect(t, token.has_value_span)
	expect_span(t, source, token.value_span, start, end)
}

@(private="package")
expect_lexical_error :: proc(
	t: ^testing.T,
	scanner: ^Scanner,
	source: diagnostic.Source,
	start, end: int,
) {
	outcome := next_token(scanner)
	testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Lexical_Error)
	testing.expect(t, outcome.has_error_span)
	expect_span(t, source, outcome.error_span, start, end)
}

@(private="package")
expect_repeated_eof :: proc(t: ^testing.T, scanner: ^Scanner) {
	offset := scanner.offset
	depth := scanner.states.count
	for _ in 0 ..< 2 {
		outcome := next_token(scanner)
		testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.End_Of_Input)
		testing.expect_value(t, scanner.offset, offset)
		testing.expect_value(t, scanner.states.count, depth)
	}
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
test_scalar_keyword_call_delimiters_remain_separate_tokens :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		identifier_end, open_start: int,
	}
	cases := [?]Case{
		{"true(.)", 4, 4},
		{"false ()", 5, 6},
		{"null\n\t(1)", 4, 6},
	}
	for test_case in cases {
		source := diagnostic.borrow_source(test_case.text, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		expect_token(t, &scanner, source, .Identifier, 0, test_case.identifier_end)
		expect_token(t, &scanner, source, .Open_Paren, test_case.open_start, test_case.open_start+1)
		testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	}
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
	testing.expect_value(t, scanner.states.count, 0)
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
		testing.expect_value(t, mismatch_scanner.states.count, 1)

		expect_token(t, &mismatch_scanner, mismatch_source, test_case.closer_kind, 2, 3)
		testing.expect_value(t, mismatch_scanner.states.count, 0)
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
test_unmatched_bytes_and_exact_byte_spans :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<bytes>", "\xffé .x")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	for index in 0 ..< 3 {
		expect_lexical_error(t, &scanner, source, index, index+1)
	}
	expect_token(t, &scanner, source, .Field, 4, 6)
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_numeric_literal_boundaries_and_field_ambiguities :: proc(t: ^testing.T) {
	Case :: struct {
		text:  string,
		kinds: []Token_Kind,
		ends:  []int,
	}
	cases := [?]Case{
		{"01", []Token_Kind{.Number}, []int{2}},
		{"1.", []Token_Kind{.Number}, []int{2}},
		{".1", []Token_Kind{.Number}, []int{2}},
		{"1e2", []Token_Kind{.Number}, []int{3}},
		{"1e-2", []Token_Kind{.Number}, []int{4}},
		{".1E2", []Token_Kind{.Number}, []int{4}},
		{".1e+2", []Token_Kind{.Number}, []int{5}},
		{"-1", []Token_Kind{.Minus, .Number}, []int{1, 2}},
		{"+1", []Token_Kind{.Plus, .Number}, []int{1, 2}},
		{"1e", []Token_Kind{.Number, .Identifier}, []int{1, 2}},
		{"1e+", []Token_Kind{.Number, .Identifier, .Plus}, []int{1, 2, 3}},
		{"1e-", []Token_Kind{.Number, .Identifier, .Minus}, []int{1, 2, 3}},
		{".1e+", []Token_Kind{.Number, .Identifier, .Plus}, []int{2, 3, 4}},
		{"1..2", []Token_Kind{.Number, .Number}, []int{2, 4}},
		{".E-1", []Token_Kind{.Field, .Minus, .Number}, []int{2, 3, 4}},
		{".E+1", []Token_Kind{.Field, .Plus, .Number}, []int{2, 3, 4}},
		{".e0", []Token_Kind{.Field}, []int{3}},
		{".E1", []Token_Kind{.Field}, []int{3}},
	}

	for test_case in cases {
		source := diagnostic.borrow_source(test_case.text, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		start := 0
		for kind, index in test_case.kinds {
			end := test_case.ends[index]
			token := expect_token(t, &scanner, source, kind, start, end)
			if kind == .Number {
				expect_value_span(t, source, token, start, end)
			}
			start = end
		}
		testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
		destroy_scanner(&scanner)
	}
}

@(test)
test_interpolated_strings_use_exact_borrowed_lifo_spans :: proc(t: ^testing.T) {
	text := "\"a\\(([\"b\\(2)c\"]))z\""
	source := diagnostic.borrow_source("<nested-string>", text)
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	Case :: struct {
		kind: Token_Kind,
		start, end: int,
		valued: bool,
	}
	cases := [?]Case{
		{.String_Start, 0, 1, false},
		{.String_Text, 1, 2, true},
		{.String_Interpolation_Start, 2, 4, false},
		{.Open_Paren, 4, 5, false},
		{.Open_Bracket, 5, 6, false},
		{.String_Start, 6, 7, false},
		{.String_Text, 7, 8, true},
		{.String_Interpolation_Start, 8, 10, false},
		{.Number, 10, 11, true},
		{.String_Interpolation_End, 11, 12, false},
		{.String_Text, 12, 13, true},
		{.String_End, 13, 14, false},
		{.Close_Bracket, 14, 15, false},
		{.Close_Paren, 15, 16, false},
		{.String_Interpolation_End, 16, 17, false},
		{.String_Text, 17, 18, true},
		{.String_End, 18, 19, false},
	}
	for test_case in cases {
		token := expect_token(t, &scanner, source, test_case.kind, test_case.start, test_case.end)
		if test_case.valued {
			expect_value_span(t, source, token, test_case.start, test_case.end)
		}
	}
	testing.expect_value(t, scanner.states.count, 0)
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_string_escape_validation_uses_jq_candidate_boundaries :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		error_end: int,
	}
	cases := [?]Case{
		{"\"\\q\"", 3},
		{"\"\\v\"", 3},
		{"\"\\u12!\"", 5},
		{"\"\\uz\"", 4},
		{"\"\\u12xz\"", 7},
		{"\"\\uD800\"", 7},
		{"\"\\uD800\\uD800\"", 13},
		{"\"\\u12_\"", 5},
		{"\"\\\n\"", 3},
		{"\"\\n\\q\\tx\"", 7},
		{"\"\\q\\uD834\\uDD1E\"", 15},
		{"\"\\uD800\\q\"", 9},
		{"\"\\uD834\\uDD1E\\q\"", 15},
		{"\"\\uD800\\uDC00\\uD800\"", 19},
	}
	for test_case in cases {
		source := diagnostic.borrow_source(test_case.text, test_case.text)
		scanner: Scanner
		init_test_scanner(t, &scanner, source)
		expect_token(t, &scanner, source, .String_Start, 0, 1)
		expect_lexical_error(t, &scanner, source, 1, test_case.error_end)
		destroy_scanner(&scanner)
	}

	valid := "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\\uDC00\\uD834\\uDD1E\""
	valid_source := diagnostic.borrow_source("<valid-escapes>", valid)
	valid_scanner: Scanner
	init_test_scanner(t, &valid_scanner, valid_source)
	expect_token(t, &valid_scanner, valid_source, .String_Start, 0, 1)
	text_token := expect_token(t, &valid_scanner, valid_source, .String_Text, 1, len(valid)-1)
	expect_value_span(t, valid_source, text_token, 1, len(valid)-1)
	expect_token(t, &valid_scanner, valid_source, .String_End, len(valid)-1, len(valid))
	destroy_scanner(&valid_scanner)
}

@(test)
test_unfinished_string_interpolation_lone_escape_and_mismatch_outcomes :: proc(t: ^testing.T) {
	string_source := diagnostic.borrow_source("<unfinished-string>", "\"abc")
	string_scanner: Scanner
	init_test_scanner(t, &string_scanner, string_source)
	expect_token(t, &string_scanner, string_source, .String_Start, 0, 1)
	expect_token(t, &string_scanner, string_source, .String_Text, 1, 4)
	for _ in 0 ..< 2 {
		testing.expect_value(t, next_token(&string_scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	}
	testing.expect_value(t, string_scanner.states.count, 1)
	destroy_scanner(&string_scanner)

	interp_source := diagnostic.borrow_source("<unfinished-interp>", "\"a\\(1")
	interp_scanner: Scanner
	init_test_scanner(t, &interp_scanner, interp_source)
	expect_token(t, &interp_scanner, interp_source, .String_Start, 0, 1)
	expect_token(t, &interp_scanner, interp_source, .String_Text, 1, 2)
	expect_token(t, &interp_scanner, interp_source, .String_Interpolation_Start, 2, 4)
	expect_token(t, &interp_scanner, interp_source, .Number, 4, 5)
	testing.expect_value(t, next_token(&interp_scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	testing.expect_value(t, interp_scanner.states.count, 2)
	destroy_scanner(&interp_scanner)

	escape_source := diagnostic.borrow_source("<lone-escape>", "\"a\\")
	escape_scanner: Scanner
	init_test_scanner(t, &escape_scanner, escape_source)
	expect_token(t, &escape_scanner, escape_source, .String_Start, 0, 1)
	expect_token(t, &escape_scanner, escape_source, .String_Text, 1, 2)
	expect_lexical_error(t, &escape_scanner, escape_source, 2, 3)
	testing.expect_value(t, next_token(&escape_scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&escape_scanner)

	mismatch_source := diagnostic.borrow_source("<mismatch>", "\"a\\([1)] )z\"")
	mismatch_scanner: Scanner
	init_test_scanner(t, &mismatch_scanner, mismatch_source)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_Start, 0, 1)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_Text, 1, 2)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_Interpolation_Start, 2, 4)
	expect_token(t, &mismatch_scanner, mismatch_source, .Open_Bracket, 4, 5)
	expect_token(t, &mismatch_scanner, mismatch_source, .Number, 5, 6)
	expect_lexical_error(t, &mismatch_scanner, mismatch_source, 6, 7)
	expect_token(t, &mismatch_scanner, mismatch_source, .Close_Bracket, 7, 8)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_Interpolation_End, 9, 10)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_Text, 10, 11)
	expect_token(t, &mismatch_scanner, mismatch_source, .String_End, 11, 12)
	destroy_scanner(&mismatch_scanner)
}

@(test)
test_raw_string_bytes_and_no_temporary_token_text :: proc(t: ^testing.T) {
	raw := "\"\x01\xff\xc3\xc0\x80\xed\xa0\x80\""
	source := diagnostic.borrow_source("<raw-bytes>", raw)
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	scanner: Scanner
	init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))
	expect_token(t, &scanner, source, .String_Start, 0, 1)
	requests_after_state_push := allocator_data.request_count
	text_token := expect_token(t, &scanner, source, .String_Text, 1, len(raw)-1)
	expect_value_span(t, source, text_token, 1, len(raw)-1)
	testing.expect_value(t, allocator_data.request_count, requests_after_state_push)
	expect_token(t, &scanner, source, .String_End, len(raw)-1, len(raw))
	testing.expect_value(t, allocator_data.request_count, requests_after_state_push)
	destroy_scanner(&scanner)
	testing.expect(t, len(tracker.allocation_map) == 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_explicit_length_nul_is_invalid_outside_strings_and_splits_numbers :: proc(t: ^testing.T) {
	punctuation := "\x00.\x00[\x00]\x00"
	punctuation_source := diagnostic.borrow_source("<nul-punctuation>", punctuation)
	punctuation_scanner: Scanner
	init_test_scanner(t, &punctuation_scanner, punctuation_source)
	expect_lexical_error(t, &punctuation_scanner, punctuation_source, 0, 1)
	expect_token(t, &punctuation_scanner, punctuation_source, .Dot, 1, 2)
	expect_lexical_error(t, &punctuation_scanner, punctuation_source, 2, 3)
	expect_token(t, &punctuation_scanner, punctuation_source, .Open_Bracket, 3, 4)
	expect_lexical_error(t, &punctuation_scanner, punctuation_source, 4, 5)
	expect_token(t, &punctuation_scanner, punctuation_source, .Close_Bracket, 5, 6)
	expect_lexical_error(t, &punctuation_scanner, punctuation_source, 6, 7)
	expect_repeated_eof(t, &punctuation_scanner)
	destroy_scanner(&punctuation_scanner)

	number_source := diagnostic.borrow_source("<nul-number>", "12\x0034\x00.5")
	number_scanner: Scanner
	init_test_scanner(t, &number_scanner, number_source)
	number := expect_token(t, &number_scanner, number_source, .Number, 0, 2)
	expect_value_span(t, number_source, number, 0, 2)
	expect_lexical_error(t, &number_scanner, number_source, 2, 3)
	number = expect_token(t, &number_scanner, number_source, .Number, 3, 5)
	expect_value_span(t, number_source, number, 3, 5)
	expect_lexical_error(t, &number_scanner, number_source, 5, 6)
	number = expect_token(t, &number_scanner, number_source, .Number, 6, 8)
	expect_value_span(t, number_source, number, 6, 8)
	expect_repeated_eof(t, &number_scanner)
	destroy_scanner(&number_scanner)
}

@(test)
test_explicit_length_nul_is_retained_in_raw_string_text :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<nul-raw-string>", "\"a\x00b\x00c\"")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .String_Start, 0, 1)
	text := expect_token(t, &scanner, source, .String_Text, 1, 6)
	expect_value_span(t, source, text, 1, 6)
	expect_token(t, &scanner, source, .String_End, 6, 7)
	expect_repeated_eof(t, &scanner)
	destroy_scanner(&scanner)
}

@(test)
test_explicit_length_nul_completes_escape_candidate_and_scanning_resumes :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<nul-escape>", "\"\\\x00x\\\x00\\n\"")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .String_Start, 0, 1)
	expect_lexical_error(t, &scanner, source, 1, 3)
	text := expect_token(t, &scanner, source, .String_Text, 3, 4)
	expect_value_span(t, source, text, 3, 4)
	expect_lexical_error(t, &scanner, source, 4, 8)
	expect_token(t, &scanner, source, .String_End, 8, 9)
	expect_repeated_eof(t, &scanner)
	destroy_scanner(&scanner)
}

@(test)
test_explicit_length_nul_is_comment_content_until_newline :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<nul-comment>", "#a\x00b\n.\x00+")
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .Dot, 5, 6)
	expect_lexical_error(t, &scanner, source, 6, 7)
	expect_token(t, &scanner, source, .Plus, 7, 8)
	expect_repeated_eof(t, &scanner)
	destroy_scanner(&scanner)
}

@(test)
test_explicit_length_nul_respects_nested_interpolation_states :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source(
		"<nul-nested-interpolation>",
		"\"a\\(\x00[\"b\x00c\"]\x00)\x00z\"",
	)
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .String_Start, 0, 1)
	expect_token(t, &scanner, source, .String_Text, 1, 2)
	expect_token(t, &scanner, source, .String_Interpolation_Start, 2, 4)
	expect_lexical_error(t, &scanner, source, 4, 5)
	expect_token(t, &scanner, source, .Open_Bracket, 5, 6)
	expect_token(t, &scanner, source, .String_Start, 6, 7)
	inner_text := expect_token(t, &scanner, source, .String_Text, 7, 10)
	expect_value_span(t, source, inner_text, 7, 10)
	expect_token(t, &scanner, source, .String_End, 10, 11)
	expect_token(t, &scanner, source, .Close_Bracket, 11, 12)
	expect_lexical_error(t, &scanner, source, 12, 13)
	expect_token(t, &scanner, source, .String_Interpolation_End, 13, 14)
	outer_text := expect_token(t, &scanner, source, .String_Text, 14, 16)
	expect_value_span(t, source, outer_text, 14, 16)
	expect_token(t, &scanner, source, .String_End, 16, 17)
	testing.expect_value(t, scanner.states.count, 0)
	expect_repeated_eof(t, &scanner)
	destroy_scanner(&scanner)
}

@(test)
test_repeated_lexical_error_recovery_preserves_state_boundaries :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source(
		"<recovery>",
		"\"\\qtext\" )]} .",
	)
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	expect_token(t, &scanner, source, .String_Start, 0, 1)
	expect_lexical_error(t, &scanner, source, 1, 3)
	text := expect_token(t, &scanner, source, .String_Text, 3, 7)
	expect_value_span(t, source, text, 3, 7)
	expect_token(t, &scanner, source, .String_End, 7, 8)
	expect_lexical_error(t, &scanner, source, 9, 10)
	expect_lexical_error(t, &scanner, source, 10, 11)
	expect_lexical_error(t, &scanner, source, 11, 12)
	expect_token(t, &scanner, source, .Dot, 13, 14)
	testing.expect_value(t, next_token(&scanner).kind, Scan_Outcome_Kind.End_Of_Input)
	destroy_scanner(&scanner)
}

@(test)
test_literal_value_spans_outlive_scanner_but_borrow_source :: proc(t: ^testing.T) {
	owned, clone_error := strings.clone("123 \"raw\"", context.allocator)
	testing.expect(t, clone_error == nil)
	defer delete(owned)
	source := diagnostic.borrow_source("<literal-owner>", owned)
	scanner: Scanner
	init_test_scanner(t, &scanner, source)
	number := expect_token(t, &scanner, source, .Number, 0, 3)
	expect_token(t, &scanner, source, .String_Start, 4, 5)
	text := expect_token(t, &scanner, source, .String_Text, 5, 8)
	destroy_scanner(&scanner)

	tokens := [?]Token{number, text}
	for token in tokens {
		start, end, ok := diagnostic.span_offsets(source, token.value_span)
		testing.expect(t, ok)
		testing.expect_value(t, diagnostic.source_bytes(source)[start:end], owned[start:end])
	}
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
	free_fail_at:         int,
	alive:                bool,
	calls_after_retirement: int,
	free_failures_remaining: int,
	resize_unsupported:      bool,
	resize_call_count:       int,
	short_success:           bool,
	short_at:                int,
	exact_nil_at:            int,
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
	if data.resize_unsupported &&
	   (mode == .Resize || mode == .Resize_Non_Zeroed) {
		data.resize_call_count += 1
		return nil, .Mode_Not_Implemented
	}
	if mode == .Alloc ||
	   mode == .Alloc_Non_Zeroed ||
	   mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		data.request_count += 1
		if data.fail_at > 0 && data.request_count == data.fail_at {
			return nil, .Out_Of_Memory
		}
		if data.exact_nil_at == data.request_count && size > 0 {
			return transmute([]byte)runtime.Raw_Slice{data = nil, len = size}, nil
		}
		if (data.short_success || data.short_at == data.request_count) && size > 0 {
			return data.backing.procedure(
				data.backing.data,
				mode,
				size-1,
				alignment,
				old_memory,
				old_size,
				location,
			)
		}
	}
	if mode == .Free {
		data.free_count += 1
		if data.free_fail_at == data.free_count {
			return nil, .Invalid_Pointer
		}
		if data.free_failures_remaining > 0 {
			data.free_failures_remaining -= 1
			return nil, .Invalid_Pointer
		}
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

@(test)
test_scanner_growth_free_failure_retains_replacement_for_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
		resize_unsupported = true,
	}
	source := diagnostic.borrow_source("<scanner-growth-release>", "((((((((((")
	scanner: Scanner
	init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))

	for index in 0 ..< 8 {
		expect_token(t, &scanner, source, .Open_Paren, index, index+1)
	}
	active_pointer := raw_data(scanner.states.storage)
	failure := next_token(&scanner)
	testing.expect_value(t, failure.kind, Scan_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, failure.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, scanner.offset, 8)
	testing.expect_value(t, scanner.states.count, 8)
	testing.expect_value(t, scanner.states.state, Fallible_Buffer_State.Transfer_Pending)
	testing.expect(t, raw_data(scanner.states.storage) == active_pointer)
	testing.expect(t, raw_data(scanner.states.replacement) != nil)
	testing.expect(t, raw_data(scanner.states.replacement) != active_pointer)
	testing.expect_value(t, len(tracker.allocation_map), 2)
	testing.expect_value(t, allocator_data.resize_call_count, 0)

	replacement_pointer := raw_data(scanner.states.replacement)
	testing.expect_value(
		t,
		retry_fallible_buffer_transfer(&scanner.states),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, scanner.states.state, Fallible_Buffer_State.Owned)
	testing.expect(t, raw_data(scanner.states.storage) == replacement_pointer)
	testing.expect(t, scanner.states.replacement == nil)
	testing.expect_value(t, scanner.states.count, 8)
	testing.expect_value(t, len(tracker.allocation_map), 1)

	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_fallible_buffer_append_retry_transfers_exact_owner :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
		resize_unsupported = true,
	}
	buffer: Fallible_Buffer(u8)
	init_fallible_buffer(&buffer, test_allocator(&allocator_data))
	for value in u8(0) ..< u8(8) {
		testing.expect_value(
			t,
			append_fallible_buffer(&buffer, value),
			runtime.Allocator_Error.None,
		)
	}
	active_pointer := raw_data(buffer.storage)
	first_error := append_fallible_buffer(&buffer, 8)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, buffer.state, Fallible_Buffer_State.Transfer_Pending)
	testing.expect_value(t, buffer.count, 8)
	testing.expect(t, raw_data(buffer.storage) == active_pointer)
	testing.expect_value(t, len(tracker.allocation_map), 2)

	replacement_pointer := raw_data(buffer.replacement)
	testing.expect_value(
		t,
		append_fallible_buffer(&buffer, 8),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, buffer.state, Fallible_Buffer_State.Owned)
	testing.expect(t, raw_data(buffer.storage) == replacement_pointer)
	testing.expect(t, buffer.replacement == nil)
	testing.expect_value(t, buffer.count, 9)
	testing.expect_value(t, buffer.storage[8], u8(8))
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, allocator_data.resize_call_count, 0)

	testing.expect_value(t, destroy_fallible_buffer(&buffer), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_string_and_interpolation_push_allocation_failures_are_atomic :: proc(t: ^testing.T) {
	string_data := Test_Allocator{
		backing = context.allocator,
		fail_at = 1,
		alive = true,
	}
	string_source := diagnostic.borrow_source("<string-push-failure>", "\"")
	string_scanner: Scanner
	init_test_scanner(t, &string_scanner, string_source, test_allocator(&string_data))
	string_failure := next_token(&string_scanner)
	testing.expect_value(t, string_failure.kind, Scan_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, string_scanner.offset, 0)
	testing.expect_value(t, string_scanner.states.count, 0)
	testing.expect_value(t, string_scanner.state, Scanner_State.Resource_Failed)
	testing.expect_value(t, destroy_scanner(&string_scanner), runtime.Allocator_Error.None)

	interp_data := Test_Allocator{
		backing = context.allocator,
		alive = true,
	}
	interp_source := diagnostic.borrow_source("<interp-push-failure>", "\"\\(")
	interp_scanner: Scanner
	init_test_scanner(t, &interp_scanner, interp_source, test_allocator(&interp_data))
	setup_error := append_fallible_buffer(&interp_scanner.states, Lexer_State.Paren)
	testing.expect(t, setup_error == nil)
	for interp_scanner.states.count < len(interp_scanner.states.storage)-1 {
		append_error := append_fallible_buffer(&interp_scanner.states, Lexer_State.Paren)
		testing.expect(t, append_error == nil)
	}
	interp_data.fail_at = interp_data.request_count + 1
	expect_token(t, &interp_scanner, interp_source, .String_Start, 0, 1)
	depth_before_failure := interp_scanner.states.count
	interp_failure := next_token(&interp_scanner)
	testing.expect_value(t, interp_failure.kind, Scan_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, interp_scanner.offset, 1)
	testing.expect_value(t, interp_scanner.states.count, depth_before_failure)
	testing.expect_value(
		t,
		interp_scanner.states.storage[interp_scanner.states.count-1],
		Lexer_State.String,
	)
	testing.expect_value(t, interp_scanner.state, Scanner_State.Resource_Failed)
	testing.expect_value(t, destroy_scanner(&interp_scanner), runtime.Allocator_Error.None)
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
			before_depth := scanner.states.count
			outcome := next_token(&scanner)
			if outcome.kind == .Resource_Failure {
				testing.expect_value(t, scanner.offset, before_offset)
				testing.expect_value(t, scanner.states.count, before_depth)
				break
			}
			testing.expect_value(t, outcome.kind, Scan_Outcome_Kind.Token)
		}

		requests_at_failure := allocator_data.request_count
		offset_at_failure := scanner.offset
		depth_at_failure := scanner.states.count
		for _ in 0 ..< 3 {
			repeated := next_token(&scanner)
			testing.expect_value(t, repeated.kind, Scan_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, allocator_data.request_count, requests_at_failure)
			testing.expect_value(t, scanner.offset, offset_at_failure)
			testing.expect_value(t, scanner.states.count, depth_at_failure)
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

@(test)
test_bulk_lifetime_scanner_destruction_retires_handle :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil {
		return
	}

	allocator_data := Test_Allocator{
		backing = runtime.arena_allocator(&arena),
		alive = true,
	}
	source := diagnostic.borrow_source("<bulk-destroy>", "(")
	scanner: Scanner
	init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))
	expect_token(t, &scanner, source, .Open_Paren, 0, 1)
	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	testing.expect_value(t, scanner.state, Scanner_State.Destroyed)
	testing.expect_value(t, allocator_data.free_count, 1)

	allocator_data.alive = false
	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	runtime.arena_destroy(&arena)
}

@(test)
test_failed_scanner_destruction_preserves_owner_for_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
	}
	source := diagnostic.borrow_source("<destroy-retry>", "(")
	scanner: Scanner
	init_test_scanner(t, &scanner, source, test_allocator(&allocator_data))
	expect_token(t, &scanner, source, .Open_Paren, 0, 1)
	allocation_count := len(tracker.allocation_map)
	testing.expect(t, allocation_count > 0)

	first_error := destroy_scanner(&scanner)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, len(tracker.allocation_map), allocation_count)
	testing.expect_value(t, scanner.state, Scanner_State.Active)
	testing.expect(t, scanner.self == &scanner)
	testing.expect_value(t, scanner.states.count, 1)
	testing.expect_value(t, scanner.states.storage[0], Lexer_State.Paren)
	testing.expect_value(t, diagnostic.source_bytes(scanner.source), "(")

	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
	testing.expect(t, len(tracker.allocation_map) == 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_scanner(&scanner), runtime.Allocator_Error.None)
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
	when ODIN_DISABLE_ASSERT {
		// This death test verifies the scanner's assertion-based copy guard.
		// There is deliberately no assertion to observe in this build mode.
		return
	}
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
