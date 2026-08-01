package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"

Node_Kind :: enum {
	Identity,
	Field,
	Parenthesized,
	Comma,
	Pipe,
	Optional,
}

Node_Id :: distinct int

// Node is source-level syntax. All spans borrow the Parser's Source and own no
// text. child and left/right are indices into the Parser-owned node arena.
// Field has child only when it is a postfix suffix; a standalone field applies
// to implicit identity and therefore has no explicit child node.
Node :: struct {
	kind:          Node_Kind,
	span:          diagnostic.Span,
	child:         Node_Id,
	has_child:     bool,
	left:          Node_Id,
	right:         Node_Id,
	name_span:     diagnostic.Span,
	has_name_span: bool,
}

Parse_Error_Kind :: enum {
	Unexpected_End,
	Unexpected_Token,
	Lexical_Error,
}

Parse_Expectation :: enum {
	Expression,
	Close_Paren,
	End_Of_Input,
}

// Parse_Error contains no owned storage. span always belongs to the Parser's
// borrowed Source. actual is present only for Unexpected_Token.
Parse_Error :: struct {
	kind:       Parse_Error_Kind,
	span:       diagnostic.Span,
	expected:   Parse_Expectation,
	actual:     Token_Kind,
	has_actual: bool,
}

Parse_Outcome_Kind :: enum {
	Success,
	Input_Error,
	Resource_Failure,
}

// Parse_Outcome borrows all AST storage from its Parser. root is present only
// for Success and remains valid until destroy_parser begins. resource_error is
// present only for Resource_Failure and preserves the allocator's exact error.
Parse_Outcome :: struct {
	kind:  Parse_Outcome_Kind,
	root:  Node_Id,
	error: Parse_Error,
	resource_error: runtime.Allocator_Error,
}

Parser_State :: enum u8 {
	Uninitialized,
	Ready,
	Finished,
	Cleanup_Failed,
	Destroyed,
}

// Parser owns its scanner and flat AST arena. source is borrowed; nodes and
// scanner state use allocator. A live Parser must remain at its initialized
// address and must not be copied. After parse_filter, only parser_nodes,
// parser_source, and destroy_parser are valid.
Parser :: struct {
	source:       diagnostic.Source,
	scanner:      Scanner,
	nodes:        Fallible_Buffer(Node),
	allocator:    runtime.Allocator,
	state:        Parser_State,
	self:         ^Parser,
	lookahead:    Scan_Outcome,
	failed:       bool,
	failure:      Parse_Outcome,
}

// init_parser initializes parser without allocating. parser must remain at
// this address and the borrowed source plus allocator backing must stay alive
// until destroy_parser succeeds.
init_parser :: proc(
	parser: ^Parser,
	source: diagnostic.Source,
	allocator: runtime.Allocator,
) -> bool {
	if parser == nil ||
	   parser.state == .Ready ||
	   parser.state == .Finished ||
	   parser.state == .Cleanup_Failed {
		return false
	}

	parser^ = {}
	if !init_scanner(&parser.scanner, source, allocator) {
		return false
	}
	parser.source = source
	parser.allocator = allocator
	init_fallible_buffer(&parser.nodes, allocator)
	parser.state = .Ready
	parser.self = parser
	return true
}

// parse_filter parses exactly one complete filter. It never accepts trailing
// tokens. On any outcome the Parser remains the sole owner of all partial or
// complete AST/scanner storage and must be passed to destroy_parser.
parse_filter :: proc(parser: ^Parser) -> Parse_Outcome {
	assert(parser != nil && parser.self == parser,
	       "syntax.Parser must be initialized and must not be copied")
	assert(parser.state == .Ready, "syntax.Parser can parse only once")

	advance(parser)
	root, ok := parse_pipe(parser)
	if !ok {
		parser.state = .Finished
		return parser.failure
	}
	if parser.lookahead.kind != .End_Of_Input {
		fail_from_lookahead(parser, .End_Of_Input)
		parser.state = .Finished
		return parser.failure
	}

	parser.state = .Finished
	return Parse_Outcome{kind = .Success, root = root}
}

// parser_nodes returns a borrowed view of the Parser-owned arena. Node indices
// and this slice are invalid once destruction begins.
parser_nodes :: proc(parser: ^Parser) -> []Node {
	assert(parser != nil && parser.self == parser)
	assert(parser.state == .Finished)
	return fallible_buffer_view(&parser.nodes)
}

parser_source :: proc(parser: ^Parser) -> diagnostic.Source {
	assert(parser != nil && parser.self == parser)
	assert(parser.state == .Ready || parser.state == .Finished)
	return parser.source
}

// destroy_parser releases or retires all owned storage. Mode_Not_Implemented
// retires a handle under its allocator's bulk lifetime. A genuine Free error
// preserves the remaining owner for retry; no parse/query operation is valid
// once cleanup has begun. Successful destruction is idempotent.
destroy_parser :: proc(parser: ^Parser) -> runtime.Allocator_Error {
	if parser == nil || parser.state == .Uninitialized || parser.state == .Destroyed {
		return nil
	}
	assert(parser.self == parser, "a live syntax.Parser was copied")

	if parser.scanner.state != .Destroyed {
		scanner_error := destroy_scanner(&parser.scanner)
		if scanner_error != nil {
			parser.state = .Cleanup_Failed
			return scanner_error
		}
	}

	if parser.nodes.state != .Empty {
		nodes_error := destroy_fallible_buffer(&parser.nodes)
		if nodes_error != nil {
			parser.state = .Cleanup_Failed
			return nodes_error
		}
	}

	parser.source = {}
	parser.allocator = {}
	parser.lookahead = {}
	parser.failed = false
	parser.failure = {}
	parser.state = .Destroyed
	parser.self = nil
	return nil
}

// parse_pipe is an explicit-state precedence parser. Parenthesized nodes hold
// the suspended outer state while their child is parsed, then become ordinary
// AST nodes in place. Pipe and comma nodes similarly begin as incomplete
// placeholders and are completed before success. Partial placeholders remain
// owned by parser.nodes on every input or resource failure.
@(private="package")
parse_pipe :: proc(parser: ^Parser) -> (Node_Id, bool) {
	invalid_id := Node_Id(-1)
	current, pipe_root, pipe_tail := invalid_id, invalid_id, invalid_id
	frame := invalid_id
	term := invalid_id
	term_ready := false

	for {
		if !term_ready {
			if parser.lookahead.kind != .Token {
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}

			token := parser.lookahead.token
			#partial switch token.kind {
			case .Open_Paren:
				new_frame, ok := append_node(parser, Node{
					kind = .Parenthesized,
					span = token.span,
					child = frame,
					left = current,
					right = pipe_root,
					has_child = current != invalid_id,
					has_name_span = pipe_root != invalid_id,
				})
				if !ok {
					return {}, false
				}
				frame = new_frame
				current, pipe_root, pipe_tail = invalid_id, invalid_id, invalid_id
				advance(parser)
				continue
			case .Dot:
				advance(parser)
				new_term, ok := append_node(parser, Node{
					kind = .Identity,
					span = token.span,
				})
				if !ok {
					return {}, false
				}
				term = new_term
			case .Field:
				assert(token.has_value_span)
				advance(parser)
				new_term, ok := append_node(parser, Node{
					kind = .Field,
					span = token.span,
					name_span = token.value_span,
					has_name_span = true,
				})
				if !ok {
					return {}, false
				}
				term = new_term
			case:
				fail_at_current(parser, .Unexpected_Token, .Expression)
				return {}, false
			}
			term_ready = true
		}

		ok: bool
		term, ok = append_postfix(parser, term)
		if !ok {
			return {}, false
		}

		if current == invalid_id {
			current = term
		} else {
			comma := &parser.nodes.storage[int(current)]
			assert(comma.kind == .Comma && comma.has_child)
			comma.right = term
			comma.has_child = false
			span, span_ok := spanning(
				parser,
				parser.nodes.storage[int(comma.left)].span,
				parser.nodes.storage[int(term)].span,
			)
			assert(span_ok)
			comma.span = span
		}
		term_ready = false

		if token_is(parser, .Comma) {
			comma, comma_ok := append_node(parser, Node{
				kind = .Comma,
				left = current,
				has_child = true, // transiently marks a missing right operand
			})
			if !comma_ok {
				return {}, false
			}
			current = comma
			advance(parser)
			continue
		}

		if token_is(parser, .Pipe) {
			pipe, pipe_ok := append_node(parser, Node{
				kind = .Pipe,
				left = current,
				has_child = true, // transiently marks the open pipe tail
			})
			if !pipe_ok {
				return {}, false
			}
			if pipe_root == invalid_id {
				pipe_root = pipe
			} else {
				old_tail := &parser.nodes.storage[int(pipe_tail)]
				old_tail.right = pipe
				old_tail.has_child = false
			}
			pipe_tail = pipe
			current = invalid_id
			advance(parser)
			continue
		}

		result := current
		if pipe_root != invalid_id {
			tail := &parser.nodes.storage[int(pipe_tail)]
			tail.right = current
			tail.has_child = false
			pipe := pipe_root
			for {
				pipe_node := &parser.nodes.storage[int(pipe)]
				span, span_ok := spanning(
					parser,
					parser.nodes.storage[int(pipe_node.left)].span,
					parser.nodes.storage[int(current)].span,
				)
				assert(span_ok)
				pipe_node.span = span
				if pipe == pipe_tail {
					break
				}
				pipe = pipe_node.right
			}
			result = pipe_root
		}

		if token_is(parser, .Close_Paren) && frame != invalid_id {
			close := parser.lookahead.token
			advance(parser)

			frame_id := frame
			frame_node := &parser.nodes.storage[int(frame_id)]
			previous_frame := frame_node.child
			outer_current := frame_node.left
			outer_pipe_root := frame_node.right
			outer_has_current := frame_node.has_child
			outer_has_pipe := frame_node.has_name_span
			span, span_ok := spanning(parser, frame_node.span, close.span)
			assert(span_ok)
			frame_node^ = Node{
				kind = .Parenthesized,
				span = span,
				child = result,
				has_child = true,
			}

			frame = previous_frame
			current = outer_current if outer_has_current else invalid_id
			pipe_root = outer_pipe_root if outer_has_pipe else invalid_id
			pipe_tail = invalid_id
			if outer_has_pipe {
				pipe_tail = pipe_root
				for !parser.nodes.storage[int(pipe_tail)].has_child {
					pipe_tail = parser.nodes.storage[int(pipe_tail)].right
				}
			}
			term = frame_id
			term_ready = true
			continue
		}

		if frame != invalid_id {
			fail_from_lookahead(parser, .Close_Paren)
			return {}, false
		}
		return result, true
	}
}

@(private="package")
append_postfix :: proc(parser: ^Parser, initial: Node_Id) -> (Node_Id, bool) {
	node := initial
	ok: bool
	for token_is(parser, .Question) || token_is(parser, .Field) {
		suffix := parser.lookahead.token
		advance(parser)
		operand_span := parser.nodes.storage[int(node)].span
		span, span_ok := spanning(parser, operand_span, suffix.span)
		assert(span_ok)
		if suffix.kind == .Question {
			node, ok = append_node(parser, Node{
				kind = .Optional,
				span = span,
				child = node,
				has_child = true,
			})
		} else {
			assert(suffix.kind == .Field && suffix.has_value_span)
			node, ok = append_node(parser, Node{
				kind = .Field,
				span = span,
				child = node,
				has_child = true,
				name_span = suffix.value_span,
				has_name_span = true,
			})
		}
		if !ok {
			return {}, false
		}
	}
	// jq shifts a standalone postfix dot before diagnosing its following token.
	// This preserves that error boundary without accepting any additional form.
	if token_is(parser, .Dot) {
		advance(parser)
		fail_from_lookahead(parser, .End_Of_Input)
		return {}, false
	}
	return node, true
}

@(private="package")
append_node :: proc(parser: ^Parser, node: Node) -> (Node_Id, bool) {
	append_error := append_fallible_buffer(&parser.nodes, node)
	if append_error != nil {
		fail_resource(parser, append_error)
		return {}, false
	}
	return Node_Id(parser.nodes.count-1), true
}

@(private="package")
advance :: proc(parser: ^Parser) {
	if parser.failed {
		return
	}
	parser.lookahead = next_token(&parser.scanner)
	if parser.lookahead.kind == .Resource_Failure {
		fail_resource(parser, parser.lookahead.resource_error)
	}
}

@(private="package")
token_is :: proc(parser: ^Parser, kind: Token_Kind) -> bool {
	return !parser.failed &&
	       parser.lookahead.kind == .Token &&
	       parser.lookahead.token.kind == kind
}

@(private="package")
fail_resource :: proc(parser: ^Parser, resource_error: runtime.Allocator_Error) {
	if parser.failed {
		return
	}
	assert(resource_error != nil)
	parser.failed = true
	parser.failure = Parse_Outcome{
		kind = .Resource_Failure,
		resource_error = resource_error,
	}
}

@(private="package")
fail_at_current :: proc(
	parser: ^Parser,
	kind: Parse_Error_Kind,
	expected: Parse_Expectation,
) {
	if parser.failed {
		return
	}
	assert(parser.lookahead.kind == .Token)
	parser.failed = true
	parser.failure = Parse_Outcome{
		kind = .Input_Error,
		error = Parse_Error{
			kind = kind,
			span = parser.lookahead.token.span,
			expected = expected,
			actual = parser.lookahead.token.kind,
			has_actual = kind == .Unexpected_Token,
		},
	}
}

@(private="package")
fail_from_lookahead :: proc(parser: ^Parser, expected: Parse_Expectation) {
	if parser.failed {
		return
	}
	switch parser.lookahead.kind {
	case .Token:
		fail_at_current(parser, .Unexpected_Token, expected)
	case .Lexical_Error:
		assert(parser.lookahead.has_error_span)
		parser.failed = true
		parser.failure = Parse_Outcome{
			kind = .Input_Error,
			error = Parse_Error{
				kind = .Lexical_Error,
				span = parser.lookahead.error_span,
				expected = expected,
			},
		}
	case .End_Of_Input:
		span, ok := diagnostic.make_span(
			parser.source,
			len(diagnostic.source_bytes(parser.source)),
			len(diagnostic.source_bytes(parser.source)),
		)
		assert(ok)
		parser.failed = true
		parser.failure = Parse_Outcome{
			kind = .Input_Error,
			error = Parse_Error{
				kind = .Unexpected_End,
				span = span,
				expected = expected,
			},
		}
	case .Resource_Failure:
		fail_resource(parser, parser.lookahead.resource_error)
	}
}

@(private="package")
spanning :: proc(
	parser: ^Parser,
	first, last: diagnostic.Span,
) -> (diagnostic.Span, bool) {
	start, _, first_ok := diagnostic.span_offsets(parser.source, first)
	_, end, last_ok := diagnostic.span_offsets(parser.source, last)
	if !first_ok || !last_ok || end < start {
		return {}, false
	}
	return diagnostic.make_span(parser.source, start, end)
}
