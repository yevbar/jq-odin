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
	Null,
	Boolean,
	Number,
	String,
	Negate,
	Variable,
	Binding,
	Reduce,
	// Foreach is appended to preserve existing AST discriminants.
	Foreach,
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
	// Atan is appended to preserve existing AST discriminants.
	Atan,
	// ASCII case filters are appended to preserve existing AST discriminants.
	Ascii_Downcase,
	Ascii_Upcase,
	// Reverse is appended to preserve existing AST discriminants.
	Reverse,
	// Implode is appended to preserve existing AST discriminants.
	Implode,
	// Explode is appended to preserve existing AST discriminants.
	Explode,
	// Keys_Unsorted is appended to preserve existing AST discriminants.
	Keys_Unsorted,
	// Tostring is appended to preserve existing AST discriminants.
	Tostring,
	// From_Entries is appended to preserve existing AST discriminants.
	From_Entries,
	// To_Entries is appended to preserve existing AST discriminants.
	To_Entries,
	// Isnan is appended to preserve existing AST discriminants.
	Isnan,
	// Utf8bytelength is appended to preserve existing AST discriminants.
	Utf8bytelength,
	// Not_Builtin is appended to preserve existing AST discriminants.
	Not_Builtin,
	// Empty is appended to preserve existing AST discriminants.
	Empty,
	// Values is appended to preserve existing AST discriminants.
	Values,
	// Arrays is appended to preserve existing AST discriminants.
	Arrays,
	// Objects is appended to preserve existing AST discriminants.
	Objects,
	// Iterables is appended to preserve existing AST discriminants.
	Iterables,
	// Scalars is appended to preserve existing AST discriminants.
	Scalars,
	// Booleans is appended to preserve existing AST discriminants.
	Booleans,
	// Nulls is appended to preserve existing AST discriminants.
	Nulls,
	// Numbers is appended to preserve existing AST discriminants.
	Numbers,
	// Strings is appended to preserve existing AST discriminants.
	Strings,
	// Finites is appended to preserve existing AST discriminants.
	Finites,
	// Normals is appended to preserve existing AST discriminants.
	Normals,
	// Floor is appended to preserve existing AST discriminants.
	Floor,
	// Round is appended to preserve existing AST discriminants.
	Round,
	// Trunc is appended to preserve existing AST discriminants.
	Trunc,
	// Transpose is appended to preserve existing AST discriminants.
	Transpose,
	// Unique is appended to preserve existing AST discriminants.
	Unique,
	// Sort is appended to preserve existing AST discriminants.
	Sort,
	// Ceil is appended to preserve existing AST discriminants.
	Ceil,
	// Flatten is appended to preserve existing AST discriminants.
	Flatten,
	// Nan is appended to preserve existing AST discriminants.
	Nan,
	// Infinite is appended to preserve existing AST discriminants.
	Infinite,
	// Any is appended to preserve existing AST discriminants.
	Any,
	// All is appended to preserve existing AST discriminants.
	All,
	// Any_Not is appended to preserve existing AST discriminants.
	Any_Not,
	// All_Not is appended to preserve existing AST discriminants.
	All_Not,
	// Isfinite is appended to preserve existing AST discriminants.
	Isfinite,
	// Join is appended to preserve existing AST discriminants.
	Join,
	// Isnormal is appended to preserve existing AST discriminants.
	Isnormal,
	// Contains is appended to preserve existing AST discriminants.
	Contains,
	// Split is appended to preserve existing AST discriminants.
	Split,
	// Index_Builtin is appended to preserve existing AST discriminants.
	Index_Builtin,
	// Rindex_Builtin is appended to preserve existing AST discriminants.
	Rindex_Builtin,
	// Indices_Builtin is appended to preserve existing AST discriminants.
	Indices_Builtin,
	// Startswith is appended to preserve existing AST discriminants.
	Startswith,
	// Endswith is appended to preserve existing AST discriminants.
	Endswith,
	// Has is appended to preserve existing AST discriminants.
	Has,
	// Bsearch is appended to preserve existing AST discriminants.
	Bsearch,
	// Ltrimstr, Rtrimstr, and Trimstr are appended to preserve existing AST discriminants.
	Ltrimstr,
	Rtrimstr,
	Trimstr,
	// Tonumber is appended to preserve existing AST discriminants.
	Tonumber,
	// Min and Max are appended to preserve existing AST discriminants.
	Min,
	Max,
	// Toboolean is appended to preserve existing AST discriminants.
	Toboolean,
	// Builtins is appended to preserve existing AST discriminants.
	Builtins,
	Debug,
	// Base64 and Base64d are appended to preserve existing AST discriminants.
	Base64,
	Base64d,
	// Uri and Urid are appended to preserve existing AST discriminants.
	Uri,
	Urid,
	// Html is appended to preserve existing AST discriminants.
	Html,
	// Text is appended to preserve existing AST discriminants.
	Text,
	// Json is appended to preserve existing AST discriminants.
	Json,
	// Csv is appended to preserve existing AST discriminants.
	Csv,
	// Tsv is appended to preserve existing AST discriminants.
	Tsv,
	// Sh is appended to preserve existing AST discriminants.
	Sh,
	// Tojson is appended to preserve existing AST discriminants.
	Tojson,
	// Fromjson is appended to preserve existing AST discriminants.
	Fromjson,
	// Last is appended to preserve existing AST discriminants.
	Last,
	// First is appended to preserve existing AST discriminants.
	First,
	// Log10 is appended to preserve existing AST discriminants.
	Log10,
	// Log2 is appended to preserve existing AST discriminants.
	Log2,
	// Exp is appended to preserve existing AST discriminants.
	Exp,
	// Exp2 is appended to preserve existing AST discriminants.
	Exp2,
	// Exp10 is appended to preserve existing AST discriminants.
	Exp10,
	// Asin is appended to preserve existing AST discriminants.
	Asin,
	// Acos is appended to preserve existing AST discriminants.
	Acos,
	// Cos is appended to preserve existing AST discriminants.
	Cos,
	// Sin is appended to preserve existing AST discriminants.
	Sin,
	// Tan is appended to preserve existing AST discriminants.
	Tan,
	// Sinh is appended to preserve existing AST discriminants.
	Sinh,
	Cosh,
	Acosh,
	// Asinh is appended to preserve existing AST discriminants.
	Asinh,
	// Atanh is appended to preserve existing AST discriminants.
	Atanh,
	// Error is appended to preserve existing AST discriminants.
	Error,
	// Try is appended to preserve existing AST discriminants.
	Try,
	// IsEmpty is appended to preserve existing AST discriminants.
	IsEmpty,
	// Range is appended to preserve existing AST discriminants.
	Range,
	// In and Inside are appended to preserve existing AST discriminants.
	In,
	Inside,
	// Strftime is appended to preserve existing AST discriminants.
	Strftime,
	// Strptime is appended to preserve existing AST discriminants.
	Strptime,
	// Mktime is appended to preserve existing AST discriminants.
	Mktime,
	// Gmtime is appended to preserve existing AST discriminants.
	Gmtime,
	// Fromdate is appended to preserve existing AST discriminants.
	Fromdate,
	// Todate is appended to preserve existing AST discriminants.
	Todate,
	// Isinfinite is appended to preserve existing AST discriminants.
	Isinfinite,
	// Log is appended to preserve existing AST discriminants.
	Log,
	// Pow is appended to preserve existing AST discriminants.
	Pow,
	// Limit is appended to preserve existing AST discriminants.
	Limit,
	// Skip is appended to preserve existing AST discriminants.
	Skip,
	// Nth is appended to preserve existing AST discriminants.
	Nth,
	// Map is appended to preserve existing AST discriminants.
	Map,
	// Map_Values is appended to preserve existing AST discriminants.
	Map_Values,
	// Slice is appended to preserve existing AST discriminants.
	Slice,
	// If is appended to preserve existing AST discriminants.
	If,
	// Recurse is appended to preserve existing AST discriminants.
	Recurse,
	// Static_Field_Add_Number is appended to preserve existing AST discriminants.
	Static_Field_Add_Number,
	// Static_Field_Set_Number is appended to preserve existing AST discriminants.
	Static_Field_Set_Number,
	// Static_Index_Set_Number is appended to preserve existing AST discriminants.
	Static_Index_Set_Number,
	// Static_Slice_Set_Number is a bounded literal-RHS slice assignment.
	Static_Slice_Set_Number,
	// Path, Paths, and Getpath are explicit path-expression nodes.
	Path,
	Paths,
	Getpath,
	Setpath,
	Delpaths,
	// Dynamic_Field_Set is the bounded filter-valued form `.name = FILTER`.
	// The first implementation accepts identity, fields, and scalar literals as
	// FILTER; generator-valued assignments remain a continuation contract.
	Dynamic_Field_Set,
	// Call invokes a top-level zero-argument definition captured by the parser.
	Call,
	// While and Until are appended to preserve existing AST discriminants.
	While,
	Until,
	// Label and Break carry lexical label names for non-local control flow.
	Label,
	Break,
}

Node_Id :: distinct int

Node_Form :: enum u8 {
	Kinded,
	Binary,
}

Container_Kind :: enum u8 {
	None,
	Array,
	Object,
	Object_Entry,
}

Binary_Operator :: enum u8 {
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
	Defined_Or,
	Or,
	And,
}

// Node is source-level syntax. form selects either a legacy kinded node or the
// explicit Binary payload; kind has no semantic meaning for Binary. All spans
// borrow the Parser's Source. Number's
// number_text and String's string_text are independently allocated,
// length-delimited bytes owned by the Parser. Each is present only when its
// corresponding has_* flag is true and remains valid until Parser destruction
// begins. child and left/right are indices into the Parser-owned node arena.
// Field has child only when it is a postfix suffix; a standalone field applies
// to implicit identity and therefore has no explicit child node. Container
// nodes retain their source role in container_kind and use value/next links
// into this same arena; these links are source syntax, not runtime Values.
// Binary has left and right operands plus an operator_span; for source binary
// operators it is the exact operator token, while parser-lowered format-string
// concatenation uses the source span that begins the newly joined segment.
// Neither span owns source bytes.
Node :: struct {
	form:              Node_Form,
	kind:              Node_Kind,
	container_kind:    Container_Kind,
	span:              diagnostic.Span,
	child:             Node_Id,
	has_child:         bool,
	next:              Node_Id,
	has_next:          bool,
	left:              Node_Id,
	right:             Node_Id,
	name_span:         diagnostic.Span,
	has_name_span:     bool,
	value:             Node_Id,
	has_value:         bool,
	reduce_update:     Node_Id,
	has_reduce_update: bool,
	// Foreach's optional third clause (EXTRACT) is distinct from the
	// accumulator UPDATE clause. Reduce never sets this field.
	reduce_extract:    Node_Id,
	has_reduce_extract: bool,
	if_condition:      Node_Id,
	has_if_condition:  bool,
	if_then:           Node_Id,
	has_if_then:       bool,
	if_else:           Node_Id,
	has_if_else:       bool,
	strflocaltime:     bool,
	key:               Node_Id,
	has_key:           bool,
	// Dynamic postfix indexes retain their key query separately from object
	// constructor key links. This child is evaluated against the original
	// input for every base result.
	index_key:         Node_Id,
	has_index_key:     bool,
	boolean_value:     bool,
	number_text:       string,
	has_number_text:   bool,
	string_text:       string,
	has_string_text:   bool,
	// A quoted object shorthand (e.g. {"name"}) uses the decoded string as
	// its key but evaluates the input field of that name as its value.  Keep
	// this distinction explicit in the source node instead of aliasing the
	// key literal as the value expression.
	string_shorthand:  bool,
	binding_name_span: diagnostic.Span,
	has_binding_name_span: bool,
	binary_operator:   Binary_Operator,
	operator_span:     diagnostic.Span,
	has_operator_span: bool,
	call_name_span: diagnostic.Span,
	has_call_name: bool,
	// Parameterized any/all retain generator and predicate filters as separate
	// source children. The flag distinguishes this two-child form from the
	// existing operand-free builtins and any(not)/all(not) markers.
	predicate: Node_Id,
	has_predicate: bool,
}

Parse_Error_Kind :: enum {
	Unexpected_End,
	Unexpected_Token,
	Lexical_Error,
}

Parse_Expectation :: enum {
	Expression,
	Close_Paren,
	Close_Bracket,
	Close_Brace,
	Close_String,
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
	// message is either empty or a static, non-owning diagnostic string.
	message: string,
}

Parse_Outcome_Kind :: enum {
	Success,
	Input_Error,
	Resource_Failure,
	Misuse,
}

// Parse_Outcome borrows all AST storage from its Parser. root is present only
// for Success and remains valid until destroy_parser begins. resource_error is
// present only for Resource_Failure and preserves the allocator's exact error.
// Misuse reports an invalid Parser identity or lifecycle operation and owns no
// storage.
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

// jq's generated parser caps its shared state/value/location stacks at 10,000
// live entries. These fixed grammar-state costs reproduce that live-stack
// high-water without allocating a second stack or counting completed AST nodes.
JQ_PARSER_STACK_CAP                :: 10_000
// Container parsing shares the generated-parser stack budget below. The
// native guard is retained only to switch arrays to their iterative flattening
// path; it is never an object-depth failure threshold.
JQ_CONTAINER_NESTING_CAP            :: 9_994
JQ_NATIVE_CONTAINER_RECURSION_GUARD :: 512
JQ_PREFIX_STACK_OVERHEAD           :: 5
JQ_GROUP_OR_ORDERED_STACK_OVERHEAD :: 6
JQ_QUERY_OPERATOR_STACK_OVERHEAD   :: 7
JQ_FIRST_POSTFIX_STACK_INCREMENT   :: 1
JQ_OPEN_PIPE_STACK_ENTRIES         :: 2
JQ_OPEN_COMMA_STACK_ENTRIES        :: 2
JQ_OPEN_BINARY_STACK_ENTRIES       :: 2
JQ_STRING_TERM_STACK_INCREMENT     :: 1

@(private="package")
Parse_Frame :: struct {
	parenthesized:             Node_Id,
	outer_current:             Node_Id,
	outer_pipe_root:           Node_Id,
	outer_pipe_tail:           Node_Id,
	outer_binary_boundary:     Node_Id,
	outer_negate_boundary:     Node_Id,
	outer_pipe_count:          int,
	outer_prefix_overhead:     int,
	outer_minus_before_group: bool,
	outer_term_has_postfix:    bool,
}

// Number_Allocation is parser-private ownership authority. Public Node string
// headers are deliberately not consulted during cleanup because parser_nodes
// exposes them for caller mutation.
@(private="package")
Number_Allocation :: struct {
	memory: []byte,
}

@(private="package")
String_Allocation :: struct {
	memory: []byte,
}

// Parser owns its scanner, flat AST arena, parse frames, and every Number node's
// exact source text. source is otherwise borrowed; frames, nodes, numeric text,
// and scanner state use allocator. A live Parser must remain at its initialized
// address and must not be copied. After parse_filter, only parser_nodes,
// parser_source, and destroy_parser are valid.
Parser :: struct {
	source:              diagnostic.Source,
	scanner:             Scanner,
	nodes:               Fallible_Buffer(Node),
	frames:              Fallible_Buffer(Parse_Frame),
	number_allocations:  Fallible_Buffer(Number_Allocation),
	string_allocations:  Fallible_Buffer(String_Allocation),
	container_depth:     int,
	allocator:           runtime.Allocator,
	state:               Parser_State,
	self:                ^Parser,
	lookahead:           Scan_Outcome,
	pending_number_text: []byte,
	pending_string_text: []byte,
	pending_reduce_name: diagnostic.Span,
	has_pending_reduce: bool,
	definition_name: diagnostic.Span,
	has_definition: bool,
	definition_body: Node_Id,
	failed:              bool,
	failure:             Parse_Outcome,
}

@(private="package")
parser_has_live_identity :: proc(parser: ^Parser) -> bool {
	return parser != nil && parser.self == parser
}

// init_parser initializes parser without allocating. It returns false for a
// live shallow copy or an invalid lifecycle state. parser must remain at this
// address and the borrowed source plus allocator backing must stay alive until
// destroy_parser succeeds.
init_parser :: proc(
	parser: ^Parser,
	source: diagnostic.Source,
	allocator: runtime.Allocator,
) -> bool {
	if parser == nil {
		return false
	}
	if parser.state == .Ready ||
	   parser.state == .Finished ||
	   parser.state == .Cleanup_Failed {
		if !parser_has_live_identity(parser) {
			return false
		}
		return false
	}
	if parser.state != .Uninitialized && parser.state != .Destroyed {
		return false
	}

	parser^ = {}
	if !init_scanner(&parser.scanner, source, allocator) {
		return false
	}
	parser.source = source
	parser.allocator = allocator
	init_fallible_buffer(&parser.nodes, allocator)
	init_fallible_buffer(&parser.frames, allocator)
	init_fallible_buffer(&parser.number_allocations, allocator)
	init_fallible_buffer(&parser.string_allocations, allocator)
	parser.state = .Ready
	parser.self = parser
	return true
}

// parse_filter parses exactly one complete filter. It never accepts trailing
// tokens. On any outcome the Parser remains the sole owner of all partial or
// complete AST/scanner storage and must be passed to destroy_parser. Misuse is
// returned without inspecting owned state when parser is not the canonical
// ready handle.
parse_filter :: proc(parser: ^Parser) -> Parse_Outcome {
	if !parser_has_live_identity(parser) || parser.state != .Ready {
		return Parse_Outcome{kind = .Misuse}
	}
	assert(parser.self == parser,
	       "syntax.Parser must be initialized and must not be copied")
	assert(parser.state == .Ready, "syntax.Parser can parse only once")

	advance(parser)
	if token_is(parser, .Def) {
		advance(parser)
		if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Identifier {
			fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure
		}
		name := parser.lookahead.token
		advance(parser)
		if !token_is(parser, .Colon) { fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure }
		advance(parser)
		// Make the definition name visible while parsing its body.  A recursive
		// reference is represented by a Call node with a temporary child; once
		// the body root exists, parse_filter patches those placeholders to the
		// immutable body graph.  This keeps recursion in the syntax/program
		// contract instead of expanding the body textually.
		parser.definition_name = name.span
		parser.has_definition = true
		parser.definition_body = Node_Id(-1)
		body, body_ok := parse_pipe(parser, .Semicolon, false)
		if !body_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure }
		parser.definition_name = name.span
		parser.has_definition = true
		parser.definition_body = body
		for i in 0..<parser.nodes.count {
			if parser.nodes.storage[i].kind == .Call && parser.nodes.storage[i].child < 0 {
				parser.nodes.storage[i].child = body
				parser.nodes.storage[i].has_child = true
			}
		}
		advance(parser)
	}
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

// parser_nodes returns a borrowed view of the Parser-owned arena. It returns
// nil for an invalid identity or lifecycle state. Node indices and this slice
// are invalid once destruction begins.
parser_nodes :: proc(parser: ^Parser) -> []Node {
	if !parser_has_live_identity(parser) || parser.state != .Finished {
		return nil
	}
	assert(parser.self == parser)
	assert(parser.state == .Finished)
	return fallible_buffer_view(&parser.nodes)
}

// parser_source returns the borrowed Source, or a zero Source for an invalid
// identity or lifecycle state.
parser_source :: proc(parser: ^Parser) -> diagnostic.Source {
	if !parser_has_live_identity(parser) ||
	   !(parser.state == .Ready || parser.state == .Finished) {
		return {}
	}
	assert(parser.self == parser)
	assert(parser.state == .Ready || parser.state == .Finished)
	return parser.source
}

// destroy_parser releases or retires all owned storage. Mode_Not_Implemented
// retires a handle under its allocator's bulk lifetime. A genuine Free error
// preserves the remaining owner for retry; no parse/query operation is valid
// once cleanup has begun. An invalid live copy returns Invalid_Argument before
// any owned state is consulted. Successful destruction is idempotent.
destroy_parser :: proc(parser: ^Parser) -> runtime.Allocator_Error {
	if parser == nil || parser.state == .Uninitialized || parser.state == .Destroyed {
		return nil
	}
	if !parser_has_live_identity(parser) {
		return .Invalid_Argument
	}
	assert(parser.self == parser, "a live syntax.Parser was copied")

	if parser.scanner.state != .Destroyed {
		scanner_error := destroy_scanner(&parser.scanner)
		if scanner_error != nil {
			parser.state = .Cleanup_Failed
			return scanner_error
		}
	}
	if parser.pending_number_text != nil {
		pending_error := runtime.mem_free_bytes(parser.pending_number_text, parser.allocator)
		if pending_error != nil && pending_error != .Mode_Not_Implemented {
			parser.state = .Cleanup_Failed
			return pending_error
		}
		parser.pending_number_text = nil
	}
	if parser.pending_string_text != nil {
		pending_error := runtime.mem_free_bytes(parser.pending_string_text, parser.allocator)
		if pending_error != nil && pending_error != .Mode_Not_Implemented {
			parser.state = .Cleanup_Failed
			return pending_error
		}
		parser.pending_string_text = nil
	}

	if parser.number_allocations.state != .Empty {
		transfer_error := retry_fallible_buffer_transfer(&parser.number_allocations)
		if transfer_error != nil {
			parser.state = .Cleanup_Failed
			return transfer_error
		}
		for index in 0..<parser.number_allocations.count {
			allocation := &parser.number_allocations.storage[index]
			if allocation.memory != nil {
				text_error := runtime.mem_free_bytes(allocation.memory, parser.allocator)
				if text_error != nil && text_error != .Mode_Not_Implemented {
					parser.state = .Cleanup_Failed
					return text_error
				}
				allocation.memory = nil
			}
		}
		allocations_error := destroy_fallible_buffer(&parser.number_allocations)
		if allocations_error != nil {
			parser.state = .Cleanup_Failed
			return allocations_error
		}
	}

	if parser.string_allocations.state != .Empty {
		transfer_error := retry_fallible_buffer_transfer(&parser.string_allocations)
		if transfer_error != nil {
			parser.state = .Cleanup_Failed
			return transfer_error
		}
		for index in 0..<parser.string_allocations.count {
			allocation := &parser.string_allocations.storage[index]
			if allocation.memory != nil {
				text_error := runtime.mem_free_bytes(allocation.memory, parser.allocator)
				if text_error != nil && text_error != .Mode_Not_Implemented {
					parser.state = .Cleanup_Failed
					return text_error
				}
				allocation.memory = nil
			}
		}
		allocations_error := destroy_fallible_buffer(&parser.string_allocations)
		if allocations_error != nil {
			parser.state = .Cleanup_Failed
			return allocations_error
		}
	}

	if parser.nodes.state != .Empty {
		nodes_error := destroy_fallible_buffer(&parser.nodes)
		if nodes_error != nil {
			parser.state = .Cleanup_Failed
			return nodes_error
		}
	}
	if parser.frames.state != .Empty {
		frames_error := destroy_fallible_buffer(&parser.frames)
		if frames_error != nil {
			parser.state = .Cleanup_Failed
			return frames_error
		}
	}

	parser.source = {}
	parser.allocator = {}
	parser.lookahead = {}
	parser.pending_number_text = nil
	parser.pending_string_text = nil
	parser.failed = false
	parser.failure = {}
	parser.state = .Destroyed
	parser.self = nil
	return nil
}

// parse_if_chain parses an if arm after the leading `if`/`elif` token has
// already been consumed.  Chained elif arms are represented as nested If
// nodes in the preceding arm's else branch, preserving the existing compiler
// and evaluator contract for conditionals.
@(private="package")
parse_if_chain :: proc(parser: ^Parser, if_token: Token) -> (Node_Id, bool) {
	condition, condition_ok := parse_pipe(parser, .Then, false)
	if !condition_ok || !token_is(parser, .Then) {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	advance(parser)

	then_branch, then_ok := parse_pipe(parser, .Else, false)
	if !then_ok || (!token_is(parser, .Else) && !token_is(parser, .Else_If) && !token_is(parser, .End)) {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}

	else_branch: Node_Id
	if token_is(parser, .Else_If) {
		elif_token := parser.lookahead.token
		advance(parser)
		nested_ok: bool
		else_branch, nested_ok = parse_if_chain(parser, elif_token)
		if !nested_ok {
			return {}, false
		}
	} else {
		else_ok: bool
		if token_is(parser, .Else) {
			advance(parser)
			else_branch, else_ok = parse_pipe(parser, .End, false)
			if !else_ok || !token_is(parser, .End) {
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}
		} else {
			// An omitted else is jq's identity fallback.
			else_branch, else_ok = append_node(parser, Node{kind = .Identity, span = if_token.span})
			if !else_ok || !token_is(parser, .End) {
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}
		}
		end_token := parser.lookahead.token
		advance(parser)
		_ = end_token
	}

	span, span_ok := spanning(parser, if_token.span, parser.nodes.storage[int(else_branch)].span)
	assert(span_ok)
	return append_node(parser, Node{
		kind = .If,
		span = span,
		if_condition = condition,
		has_if_condition = true,
		if_then = then_branch,
		has_if_then = true,
		if_else = else_branch,
		has_if_else = true,
	})
}

// parse_pipe is an explicit-state precedence parser. Parenthesized state lives
// in parser.frames; binary, pipe, and comma nodes begin as incomplete arena
// placeholders and are completed before success. Partial state remains owned
// by the Parser on every input or resource failure.
@(private="package")
parse_pipe :: proc(
	parser: ^Parser,
	closing := Token_Kind.Invalid,
	stop_at_comma := false,
	stop_at_catch := false,
	stop_at_binary := false,
	stop_at_pipe := false,
	stop_at_defined_or := false,
) -> (Node_Id, bool) {
	invalid_id := Node_Id(-1)
	entry_frame_depth := parser.frames.count
	current, pipe_root, pipe_tail := invalid_id, invalid_id, invalid_id
	term := invalid_id
	term_ready := false
	negate_frame := invalid_id
	binary_frame := invalid_id
	group_depth := 0
	minus_depth := 0
	// Every unreduced Query or Expr operator contributes two simultaneously-live
	// generated-parser entries while its right operand is being parsed.
	live_pipe_count := 0
	// This local count lets a completed group's pipes leave the live total;
	// the suspended outer chain is recovered from its existing placeholders.
	current_pipe_count := 0
	// Commas reduce before another comma is shifted, but remain live across the
	// tighter binary, grouped, postfix, and pipe states in their right operand.
	live_comma_count := 0
	live_binary_count := 0
	term_prefix_overhead := JQ_PREFIX_STACK_OVERHEAD
	minus_before_group := false
	term_has_postfix := false

	for {
		if !term_ready {
			if closing == .Else && token_is(parser, .End) && current != invalid_id {
				return current, true
			}
			if stop_at_catch && parser.lookahead.kind == .Token && parser.lookahead.token.kind == .Catch {
				return current, current != invalid_id
			}
			if parser.lookahead.kind != .Token {
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}

			token := parser.lookahead.token
			#partial switch token.kind {
			case .Open_Paren:
				outer_prefix_overhead := term_prefix_overhead
				outer_minus_before_group := minus_before_group
				outer_term_has_postfix := term_has_postfix
				group_depth += 1
				if minus_depth > 0 {
					minus_before_group = true
				}
				term_prefix_overhead = JQ_GROUP_OR_ORDERED_STACK_OVERHEAD
				if parser_stack_budget_exhausted(parser,
					group_depth+minus_depth,
					live_pipe_count,
					live_comma_count,
					live_binary_count,
					term_prefix_overhead,
					term_has_postfix,
				) {
					fail_resource(parser, .Out_Of_Memory)
					return {}, false
				}
				parenthesized, ok := append_node(parser, Node{
					kind = .Parenthesized,
					span = token.span,
				})
				if !ok {
					return {}, false
				}
				frame_error := append_fallible_buffer(&parser.frames, Parse_Frame{
					parenthesized = parenthesized,
					outer_current = current,
					outer_pipe_root = pipe_root,
					outer_pipe_tail = pipe_tail,
					outer_binary_boundary = binary_frame,
					outer_negate_boundary = negate_frame,
					outer_pipe_count = current_pipe_count,
					outer_prefix_overhead = outer_prefix_overhead,
					outer_minus_before_group = outer_minus_before_group,
					outer_term_has_postfix = outer_term_has_postfix,
				})
				if frame_error != nil {
					fail_resource(parser, frame_error)
					return {}, false
				}
				current, pipe_root, pipe_tail = invalid_id, invalid_id, invalid_id
				current_pipe_count = 0
				advance(parser)
				continue
			case .Open_Bracket, .Open_Brace:
				new_term, container_ok := parse_container(parser, token.kind)
				if !container_ok {
					return {}, false
				}
				term = new_term
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
			case .Recurse:
				advance(parser)
				new_term, ok := append_node(parser, Node{
					kind = .Recurse,
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
			case .Number:
				advance(parser)
				new_term, number_ok := append_number_node(parser, token.span)
				if !number_ok {
					return {}, false
				}
				term = new_term
			case .String_Start:
				new_term: Node_Id
				string_ok: bool
				if string_has_interpolation(parser, token.span) {
					new_term, string_ok = append_interpolated_string_node(
						parser,
						{},
						token.span,
						.Tostring,
						false,
						group_depth+minus_depth,
						live_pipe_count,
						live_comma_count,
						live_binary_count,
						term_prefix_overhead,
						term_has_postfix,
					)
				} else {
					new_term, string_ok = append_string_node(
						parser,
						token.span,
						group_depth+minus_depth,
						live_pipe_count,
						live_comma_count,
						live_binary_count,
						term_prefix_overhead,
						term_has_postfix,
					)
				}
				if !string_ok {
					return {}, false
				}
				term = new_term
			case .Format:
				format := token_spelling(parser, token)
				if format != "@base64" && format != "@base64d" && format != "@uri" && format != "@urid" && format != "@html" && format != "@text" && format != "@json" && format != "@csv" && format != "@tsv" && format != "@sh" {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				kind := Node_Kind.Base64 if format == "@base64" else .Base64d
				if format == "@uri" do kind = .Uri
				if format == "@urid" do kind = .Urid
				if format == "@html" do kind = .Html
				if format == "@text" do kind = .Text
				if format == "@json" do kind = .Json
				if format == "@csv" do kind = .Csv
				if format == "@tsv" do kind = .Tsv
				if format == "@sh" do kind = .Sh
				advance(parser)
				if kind == .Html && token_is(parser, .String_Start) {
					new_term, format_ok := append_interpolated_string_node(
						parser,
						token.span,
						parser.lookahead.token.span,
						.Html,
						true,
						group_depth+minus_depth,
						live_pipe_count,
						live_comma_count,
						live_binary_count,
						term_prefix_overhead,
						term_has_postfix,
					)
					if !format_ok do return {}, false
					term = new_term
					break
				}
				new_term, format_ok := append_node(parser, Node{kind = kind, span = token.span})
				if !format_ok do return {}, false
				term = new_term
			case .Try:
				advance(parser)
				// `try EXP` is jq's implicit-error-suppression form. Keep the
				// existing expression parser boundary so explicit catch filters
				// and established binary expressions retain their precedence.
				// A zero-catch try ends at the surrounding comma, just like an
				// explicit catch filter.  Otherwise `1, try error(2), 3` would
				// absorb the trailing comma and suppress `3` with the erroring
				// expression.
				// jq's unparenthesized `try EXP` captures one pipeline term.  The
				// following binary/comma/pipe operators remain outside the try,
				// while parentheses can still group a complete expression.  In
				// particular, `try error(0) // 1` must let the defined-or fallback
				// observe the suppressed error rather than swallowing the fallback
				// inside the try expression.
				expression, expression_ok := parse_pipe(parser, closing, true, true, false, false, true)
				if !expression_ok {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				catch_filter: Node_Id
				catch_ok: bool
				if token_is(parser, .Catch) {
					advance(parser)
					// A catch filter binds through binary and pipe operators, but a
					// comma at this level starts the surrounding query stream.
					catch_filter, catch_ok = parse_pipe(parser, closing, true, false, true, true)
				} else {
					// The evaluator already treats an empty catch as suppression;
					// materialize that existing opcode rather than adding a second
					// try-frame contract.
					catch_filter, catch_ok = append_node(parser, Node{kind=.Empty, span=parser.nodes.storage[int(expression)].span})
				}
				if !catch_ok do return {}, false
				span, span_ok := spanning(parser, parser.nodes.storage[int(expression)].span, parser.nodes.storage[int(catch_filter)].span)
				assert(span_ok)
				new_term, try_ok := append_node(parser, Node{kind = .Try, span = span, left = expression, right = catch_filter})
				if !try_ok do return {}, false
				term = new_term
			case .Label:
				label_token := token
				advance(parser)
				if !token_is(parser, .Binding) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				name := parser.lookahead.token
				advance(parser)
				if !token_is(parser, .Pipe) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				advance(parser)
				body, body_ok := parse_pipe(parser, closing, false)
				if !body_ok { return {}, false }
				span, span_ok := spanning(parser, label_token.span, parser.nodes.storage[int(body)].span)
				assert(span_ok)
				new_term, label_ok := append_node(parser, Node{kind=.Label, span=span, child=body, has_child=true, name_span=name.value_span, has_name_span=true})
				if !label_ok { return {}, false }
				term = new_term
			case .Break:
				break_token := token
				advance(parser)
				if !token_is(parser, .Binding) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				name := parser.lookahead.token
				advance(parser)
				new_term, break_ok := append_node(parser, Node{kind=.Break, span=break_token.span, name_span=name.value_span, has_name_span=true})
				if !break_ok { return {}, false }
				term = new_term
			case .If:
				if_token := token
				advance(parser)
				new_term, ok := parse_if_chain(parser, if_token)
				if !ok { return {}, false }
				term = new_term
			case .Minus:
				minus_depth += 1
				if group_depth > 0 && !minus_before_group {
					term_prefix_overhead = JQ_PREFIX_STACK_OVERHEAD
				} else if minus_before_group {
					term_prefix_overhead = JQ_GROUP_OR_ORDERED_STACK_OVERHEAD
				}
				if parser_stack_budget_exhausted(parser,
					group_depth+minus_depth,
					live_pipe_count,
					live_comma_count,
					live_binary_count,
					term_prefix_overhead,
					term_has_postfix,
				) {
					fail_resource(parser, .Out_Of_Memory)
					return {}, false
				}
				new_frame, ok := append_node(parser, Node{
					kind = .Negate,
					span = token.span,
					left = negate_frame,
				})
				if !ok {
					return {}, false
				}
				negate_frame = new_frame
				advance(parser)
				if !lookahead_starts_supported_term(parser) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				continue
			case .Identifier:
				spelling := token_spelling(parser, token)
				if parser.has_definition && spelling == token_spelling(parser, Token{span=parser.definition_name}) && !token_is(parser, .Open_Paren) {
					advance(parser)
					new_term, call_ok := append_node(parser, Node{kind=.Call, span=token.span, child=parser.definition_body, has_child=true, call_name_span=token.value_span, has_call_name=true})
					if !call_ok { return {}, false }
					term = new_term
					term_ready = true
					continue
				}
				if spelling == "select" {
					advance(parser)
					if !token_is(parser, .Open_Paren) { fail_from_lookahead(parser, .Expression); return {}, false }
					advance(parser)
					predicate, predicate_ok := parse_pipe(parser, .Close_Paren, true)
					if !predicate_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					identity, identity_ok := append_node(parser, Node{kind=.Identity, span=token.span})
					empty, empty_ok := append_node(parser, Node{kind=.Empty, span=close.span})
					if !identity_ok || !empty_ok { return {}, false }
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					new_term, select_ok := append_node(parser, Node{kind=.If, span=span, if_condition=predicate, has_if_condition=true, if_then=identity, has_if_then=true, if_else=empty, has_if_else=true})
					if !select_ok do return {}, false
					term = new_term; term_ready = true
					continue
				}
				kind := Node_Kind.Null
				boolean_value := false
				if spelling == "true" || spelling == "have_decnum" {
					kind = .Boolean
					boolean_value = true
				} else if spelling == "false" {
					kind = .Boolean
				} else if spelling == "length" {
					kind = .Length
				} else if spelling == "keys" {
					kind = .Keys
				} else if spelling == "type" {
					kind = .Type
				} else if spelling == "abs" {
					kind = .Abs
				} else if spelling == "sqrt" {
					kind = .Sqrt
				} else if spelling == "fabs" {
					kind = .Fabs
				} else if spelling == "add" {
					kind = .Add_Builtin
				} else if spelling == "trim" {
					kind = .Trim
				} else if spelling == "ltrim" {
					kind = .Ltrim
				} else if spelling == "rtrim" {
					kind = .Rtrim
				} else if spelling == "atan" {
					kind = .Atan
				} else if spelling == "ascii_downcase" {
					kind = .Ascii_Downcase
				} else if spelling == "ascii_upcase" {
					kind = .Ascii_Upcase
				} else if spelling == "reverse" {
					kind = .Reverse
				} else if spelling == "implode" {
					kind = .Implode
				} else if spelling == "explode" {
					kind = .Explode
				} else if spelling == "keys_unsorted" {
					kind = .Keys_Unsorted
				} else if spelling == "tostring" {
					kind = .Tostring
				} else if spelling == "from_entries" {
					kind = .From_Entries
				} else if spelling == "to_entries" {
					kind = .To_Entries
				} else if spelling == "isnan" {
					kind = .Isnan
				} else if spelling == "utf8bytelength" {
					kind = .Utf8bytelength
				} else if spelling == "not" {
					kind = .Not_Builtin
				} else if spelling == "empty" {
					kind = .Empty
				} else if spelling == "values" {
					kind = .Values
				} else if spelling == "arrays" {
					kind = .Arrays
				} else if spelling == "objects" {
					kind = .Objects
				} else if spelling == "iterables" {
					kind = .Iterables
				} else if spelling == "scalars" {
					kind = .Scalars
				} else if spelling == "booleans" {
					kind = .Booleans
				} else if spelling == "nulls" {
					kind = .Nulls
				} else if spelling == "numbers" {
					kind = .Numbers
				} else if spelling == "strings" {
					kind = .Strings
				} else if spelling == "finites" {
					kind = .Finites
				} else if spelling == "normals" {
					kind = .Normals
				} else if spelling == "floor" {
					kind = .Floor
				} else if spelling == "round" {
					kind = .Round
				} else if spelling == "trunc" {
					kind = .Trunc
				} else if spelling == "transpose" {
					kind = .Transpose
				} else if spelling == "unique" {
					kind = .Unique
				} else if spelling == "sort" {
					kind = .Sort
				} else if spelling == "ceil" {
					kind = .Ceil
				} else if spelling == "flatten" {
					kind = .Flatten
				} else if spelling == "nan" {
					kind = .Nan
				} else if spelling == "infinite" {
					kind = .Infinite
				} else if spelling == "any" {
					kind = .Any
				} else if spelling == "all" {
					kind = .All
				} else if spelling == "isfinite" {
					kind = .Isfinite
				} else if spelling == "join" {
					kind = .Join
				} else if spelling == "isnormal" {
					kind = .Isnormal
				} else if spelling == "contains" {
					kind = .Contains
				} else if spelling == "split" {
					kind = .Split
				} else if spelling == "index" {
					kind = .Index_Builtin
				} else if spelling == "rindex" {
					kind = .Rindex_Builtin
				} else if spelling == "indices" {
					kind = .Indices_Builtin
				} else if spelling == "startswith" {
					kind = .Startswith
				} else if spelling == "endswith" {
					kind = .Endswith
				} else if spelling == "has" {
					kind = .Has
				} else if spelling == "bsearch" {
					kind = .Bsearch
				} else if spelling == "ltrimstr" {
					kind = .Ltrimstr
				} else if spelling == "rtrimstr" {
					kind = .Rtrimstr
				} else if spelling == "trimstr" {
					kind = .Trimstr
				} else if spelling == "tonumber" {
					kind = .Tonumber
				} else if spelling == "min" {
					kind = .Min
				} else if spelling == "max" {
					kind = .Max
				} else if spelling == "toboolean" {
					kind = .Toboolean
				} else if spelling == "builtins" {
					kind = .Builtins
				} else if spelling == "debug" {
					kind = .Debug
				} else if spelling == "tojson" {
					kind = .Tojson
				} else if spelling == "fromjson" {
					kind = .Fromjson
				} else if spelling == "last" {
					kind = .Last
				} else if spelling == "first" {
					kind = .First
				} else if spelling == "log10" {
					kind = .Log10
				} else if spelling == "log2" {
					kind = .Log2
				} else if spelling == "exp" {
					kind = .Exp
				} else if spelling == "exp2" {
					kind = .Exp2
				} else if spelling == "exp10" {
					kind = .Exp10
				} else if spelling == "asin" {
					kind = .Asin
				} else if spelling == "acos" {
					kind = .Acos
				} else if spelling == "cos" {
					kind = .Cos
				} else if spelling == "sin" {
					kind = .Sin
				} else if spelling == "tan" {
					kind = .Tan
				} else if spelling == "sinh" {
					kind = .Sinh
				} else if spelling == "cosh" {
					kind = .Cosh
				} else if spelling == "acosh" {
					kind = .Acosh
				} else if spelling == "asinh" {
					kind = .Asinh
				} else if spelling == "atanh" {
					kind = .Atanh
				} else if spelling == "recurse" {
					// jq's zero-argument recurse builtin is the same
					// preorder traversal as the standalone `..` spelling.
					// Keep it on the existing operand-free Recurse contract;
					// parameterized recurse calls remain unsupported here.
					kind = .Recurse
				} else if spelling == "error" {
					kind = .Error
				} else if spelling == "in" {
					kind = .In
				} else if spelling == "inside" {
					kind = .Inside
				} else if spelling == "isempty" {
					kind = .IsEmpty
				} else if spelling == "range" {
					kind = .Range
				} else if spelling == "limit" {
					kind = .Limit
				} else if spelling == "skip" {
					kind = .Skip
				} else if spelling == "nth" {
					kind = .Nth
				} else if spelling == "map" {
					kind = .Map
				} else if spelling == "map_values" {
					kind = .Map_Values
				} else if spelling == "path" {
					kind = .Path
				} else if spelling == "getpath" {
					kind = .Getpath
				} else if spelling == "setpath" {
					kind = .Setpath
				} else if spelling == "delpaths" {
					kind = .Delpaths
				} else if spelling == "del" {
					kind = .Delpaths
				} else if spelling == "paths" {
					kind = .Paths
				} else if spelling == "strftime" || spelling == "strflocaltime" {
					kind = .Strftime
				} else if spelling == "strptime" {
					kind = .Strptime
				} else if spelling == "mktime" {
					kind = .Mktime
				} else if spelling == "gmtime" {
					kind = .Gmtime
				} else if spelling == "fromdateiso8601" || spelling == "fromdate" {
					kind = .Fromdate
				} else if spelling == "todateiso8601" || spelling == "todate" {
					kind = .Todate
				} else if spelling == "isinfinite" {
					kind = .Isinfinite
				} else if spelling == "log" {
					kind = .Log
				} else if spelling == "pow" {
					kind = .Pow
				} else if spelling == "while" {
					kind = .While
				} else if spelling == "until" {
					kind = .Until
				} else if spelling == "label" {
					kind = .Label
				} else if spelling == "break" {
					kind = .Break
				} else if spelling != "null" {
					fail_at_current(parser, .Unexpected_Token, .Expression)
					return {}, false
				}
				advance(parser)
				if (spelling == "path" || spelling == "getpath") && token_is(parser, .Open_Paren) {
					advance(parser)
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					term_ok: bool
					term, term_ok = append_node(parser, Node{kind=kind, span=span, child=argument, has_child=true})
					if !term_ok { return {}, false }
					term_ready = true
					continue
				}
				if spelling == "setpath" && token_is(parser, .Open_Paren) {
					advance(parser)
					path_arg, path_ok := parse_pipe(parser, .Semicolon, true)
					if !path_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					advance(parser)
					value_arg, value_ok := parse_pipe(parser, .Close_Paren, false)
					if !value_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					term_ok: bool
					term, term_ok = append_node(parser, Node{kind=.Setpath, span=span, left=path_arg, right=value_arg})
					if !term_ok { return {}, false }
					term_ready = true
					continue
				}
				if spelling == "delpaths" && token_is(parser, .Open_Paren) {
					advance(parser)
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					term_ok: bool
					term, term_ok = append_node(parser, Node{kind=.Delpaths, span=span, child=argument, has_child=true})
					if !term_ok { return {}, false }
					term_ready = true
					continue
				}
				if spelling == "del" && token_is(parser, .Open_Paren) {
					advance(parser)
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					advance(parser)
					lowered, paths_ok := lower_static_del_filter(parser, argument)
					if !paths_ok { fail_from_lookahead(parser, .Expression); return {}, false }
					term = lowered
					term_ready = true
					continue
				}
				if spelling == "paths" && !token_is(parser, .Open_Paren) {
					term_ok: bool
					term, term_ok = append_node(parser, Node{kind=.Paths, span=token.span})
					if !term_ok { return {}, false }
					term_ready = true
					continue
				}
				if spelling == "error" && !token_is(parser, .Open_Paren) {
					identity, identity_ok := append_node(parser, Node{kind=.Identity, span=token.span})
					if !identity_ok { return {}, false }
					new_term, error_ok := append_node(parser, Node{kind=.Error, span=token.span, child=identity, has_child=true})
					if !error_ok { return {}, false }
					term = new_term
				} else if spelling == "label" {
					// `label $name | EXP` binds a lexical target to the whole
					// following filter.  Keep the name as source text; runtime
					// label identity is resolved by the compiler/evaluator.
					if !token_is(parser, .Binding) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					name := parser.lookahead.token
					advance(parser)
					if !token_is(parser, .Pipe) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					advance(parser)
					body, body_ok := parse_pipe(parser, closing, false)
					if !body_ok {
						return {}, false
					}
					span, span_ok := spanning(parser, token.span, parser.nodes.storage[int(body)].span)
					assert(span_ok)
					new_term, label_ok := append_node(parser, Node{kind=.Label, span=span, child=body, has_child=true, name_span=name.value_span, has_name_span=true})
					if !label_ok { return {}, false }
					term = new_term
					term_ready = true
					continue
				} else if spelling == "break" {
					if !token_is(parser, .Binding) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					name := parser.lookahead.token
					advance(parser)
					new_term, break_ok := append_node(parser, Node{kind=.Break, span=token.span, name_span=name.value_span, has_name_span=true})
					if !break_ok { return {}, false }
					term = new_term
					term_ready = true
					continue
				} else if spelling == "range" && token_is(parser, .Open_Paren) {
					advance(parser)
					first, first_ok := parse_pipe(parser, .Close_Paren, false)
					if !first_ok { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					if token_is(parser, .Close_Paren) {
						close := parser.lookahead.token; advance(parser)
						first_node := parser.nodes.storage[int(first)]
						if first_node.kind == .Comma && !first_node.has_child {
							new_term, sequence_ok := literal_call_sequence(parser, first, .Range)
							if !sequence_ok { fail_from_lookahead(parser, .Expression); return {}, false }
							term = new_term
						} else {
							first_identity := first_node.kind == .Identity && !first_node.has_child && !first_node.has_value && first_node.container_kind == .None
							first_negative := first_node.kind == .Negate && first_node.has_child && !first_node.has_value && parser.nodes.storage[int(first_node.child)].kind == .Number
							if (first_node.kind != .Number && !first_identity && first_node.kind != .Range && !first_negative) || first_node.has_child && !first_negative || first_node.has_value { fail_from_lookahead(parser, .Expression); return {}, false }
							span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
							new_term, ok := append_node(parser, Node{kind=.Range, span=span, left=first, right=Node_Id(-1)}); if !ok { return {}, false }; term = new_term
						}
						// `range(n)` is the shorthand for `range(0;n)`.
					} else {
						if !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Close_Paren); return {}, false }; advance(parser)
					second, second_ok := parse_pipe(parser, .Close_Paren, false)
					third := Node_Id(-1)
					has_third := false
					if token_is(parser, .Semicolon) {
						advance(parser)
						third_ok: bool
						third, third_ok = parse_pipe(parser, .Close_Paren, false)
						has_third = third_ok
					}
					if !second_ok || (token_is(parser, .Semicolon) && !has_third) || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					first_numeric := range_numeric_bound_node(parser, first)
					second_numeric := range_numeric_bound_node(parser, second)
					if parser.nodes.storage[int(first)].kind == .Comma || parser.nodes.storage[int(second)].kind == .Comma || (has_third && parser.nodes.storage[int(third)].kind == .Comma) {
						combined, combined_ok := range_literal_cartesian(parser, first, second, third, has_third)
						if !combined_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						term = combined
						term_ready = true
						continue
					}
					third_numeric := !has_third || range_numeric_bound_node(parser, third)
					if !first_numeric || !second_numeric || !third_numeric { fail_from_lookahead(parser, .Expression); return {}, false }
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					new_term, ok := append_node(parser, Node{kind=.Range, span=span, left=first, right=second, reduce_update=third, has_reduce_update=has_third}); if !ok { return {}, false }; term = new_term
					}
				} else if spelling == "limit" && token_is(parser, .Open_Paren) {
					advance(parser)
					count, count_ok := parse_pipe(parser, .Semicolon, false)
					if !count_ok || !token_is(parser, .Semicolon) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					advance(parser)
					generator, generator_ok := parse_pipe(parser, .Close_Paren, false)
					if !generator_ok || !token_is(parser, .Close_Paren) {
						fail_from_lookahead(parser, .Close_Paren)
						return {}, false
					}
					close := parser.lookahead.token
					advance(parser)
					count_node := parser.nodes.storage[int(count)]
					if count_node.kind == .Comma {
						sequence, sequence_ok := literal_numeric_sequence(parser, count)
						if !sequence_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						combined, combined_ok := numeric_count_call_sequence(parser, sequence, generator, .Limit)
						if !combined_ok { return {}, false }; term = combined
						term_ready = true
						continue
					}
					negative_literal := count_node.kind == .Negate && count_node.has_child &&
						parser.nodes.storage[int(count_node.child)].kind == .Number
					if (count_node.kind != .Number && !negative_literal) || count_node.has_value {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					span, span_ok := spanning(parser, token.span, close.span)
					assert(span_ok)
					new_term, ok := append_node(parser, Node{kind=.Limit, span=span, left=count, right=generator})
					if !ok { return {}, false }
					term = new_term
				} else if spelling == "skip" && token_is(parser, .Open_Paren) {
					advance(parser)
					count, count_ok := parse_pipe(parser, .Semicolon, false)
					if !count_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }
					advance(parser)
					generator, generator_ok := parse_pipe(parser, .Close_Paren, false)
					if !generator_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					count_node := parser.nodes.storage[int(count)]
					if count_node.kind == .Comma {
						sequence, sequence_ok := literal_numeric_sequence(parser, count)
						if !sequence_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						combined, combined_ok := numeric_count_call_sequence(parser, sequence, generator, .Skip)
						if !combined_ok { return {}, false }; term = combined
						term_ready = true
						continue
					}
					negative_literal := count_node.kind == .Negate && count_node.has_child &&
						parser.nodes.storage[int(count_node.child)].kind == .Number
					if (count_node.kind != .Number && !negative_literal) || count_node.has_value { fail_from_lookahead(parser, .Expression); return {}, false }
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					new_term, ok := append_node(parser, Node{kind=.Skip, span=span, left=count, right=generator})
					if !ok { return {}, false }; term = new_term
				} else if spelling == "nth" && token_is(parser, .Open_Paren) {
					advance(parser)
					count, count_ok := parse_pipe(parser, .Semicolon, false)
					if !count_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }
					advance(parser)
					generator, generator_ok := parse_pipe(parser, .Close_Paren, false)
					if !generator_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					count_node := parser.nodes.storage[int(count)]
					if count_node.kind == .Comma {
						sequence, sequence_ok := literal_numeric_sequence(parser, count)
						if !sequence_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						combined, combined_ok := numeric_count_call_sequence(parser, sequence, generator, .Nth)
						if !combined_ok { return {}, false }; term = combined
						term_ready = true
						continue
					}
					negative_literal := count_node.kind == .Negate && count_node.has_child &&
						parser.nodes.storage[int(count_node.child)].kind == .Number
					if (count_node.kind != .Number && !negative_literal) || count_node.has_value { fail_from_lookahead(parser, .Expression); return {}, false }
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					new_term, ok := append_node(parser, Node{kind=.Nth, span=span, left=count, right=generator})
					if !ok { return {}, false }; term = new_term
				} else if (spelling == "add" || spelling == "pow" || spelling == "join" || spelling == "contains" || spelling == "inside" || spelling == "in" || spelling == "split" || spelling == "index" || spelling == "rindex" || spelling == "indices" || spelling == "startswith" || spelling == "endswith" || spelling == "has" || spelling == "bsearch" || spelling == "flatten" || spelling == "ltrimstr" || spelling == "rtrimstr" || spelling == "trimstr" || spelling == "error" || spelling == "isempty" || spelling == "strftime" || spelling == "strflocaltime" || spelling == "strptime" || spelling == "any" || spelling == "all" || spelling == "first" || spelling == "last" || spelling == "map" || spelling == "map_values") && token_is(parser, .Open_Paren) {
					advance(parser)
					if spelling == "pow" {
						left, left_ok := parse_pipe(parser, .Semicolon, false)
						if !left_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }
						advance(parser)
						right, right_ok := parse_pipe(parser, .Close_Paren, false)
						if !right_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
						close := parser.lookahead.token; advance(parser)
						span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
						pow_term, pow_ok := append_node(parser, Node{kind=.Pow, span=span, left=left, right=right}); if !pow_ok { return {}, false }
						term = pow_term
						term_ready = true
						continue
					}
					if spelling == "add" {
						argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
						if !argument_ok || !token_is(parser, .Close_Paren) {
							fail_from_lookahead(parser, .Close_Paren)
							return {}, false
						}
						close := parser.lookahead.token
						advance(parser)
						span, span_ok := spanning(parser, token.span, close.span)
						assert(span_ok)
						new_term, ok := append_node(parser, Node{kind=.Add_Builtin, span=span, child=argument, has_child=true})
						if !ok do return {}, false
						term = new_term
						term_ready = true
						continue
					}
					if spelling == "any" || spelling == "all" {
						generator, generator_ok := parse_pipe(parser, .Semicolon, false)
						if !generator_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						if token_is(parser, .Semicolon) {
							advance(parser)
							predicate, predicate_ok := parse_pipe(parser, .Close_Paren, false)
							if !predicate_ok || !token_is(parser, .Close_Paren) {
								fail_from_lookahead(parser, .Close_Paren)
								return {}, false
							}
							close := parser.lookahead.token
							advance(parser)
							span, span_ok := spanning(parser, token.span, close.span)
							assert(span_ok)
							call_kind := Node_Kind.Any if spelling == "any" else .All
							new_term, ok := append_node(parser, Node{kind=call_kind, span=span, child=generator, has_child=true, predicate=predicate, has_predicate=true})
							if !ok { return {}, false }
							term = new_term
							term_ready = true
							continue
						}
						// No semicolon: fall through to the existing one-argument
						// validation and marker handling below.
						if !token_is(parser, .Close_Paren) {
							fail_from_lookahead(parser, .Close_Paren)
							return {}, false
						}
						close := parser.lookahead.token
						advance(parser)
						generator_node := parser.nodes.storage[int(generator)]
						if generator_node.kind != .Not_Builtin || generator_node.has_child || generator_node.has_value {
							fail_from_lookahead(parser, .Expression)
							return {}, false
						}
						span, span_ok := spanning(parser, token.span, close.span)
						assert(span_ok)
						marker_kind := Node_Kind.Any_Not if spelling == "any" else .All_Not
						new_term, ok := append_node(parser, Node{kind=marker_kind, span=span})
						if !ok { return {}, false }
						term = new_term
						term_ready = true
						continue
					}
					argument_closing := Token_Kind.Close_Paren
					if spelling == "map" || spelling == "map_values" do argument_closing = .Invalid
					stop_argument_at_comma := spelling != "bsearch" && spelling != "join" && spelling != "flatten" && spelling != "index" && spelling != "rindex" && spelling != "indices" && spelling != "first" && spelling != "last" && spelling != "isempty" && spelling != "map" && spelling != "map_values"
					argument, argument_ok := parse_pipe(parser, argument_closing, stop_argument_at_comma)
					if !argument_ok || !token_is(parser, .Close_Paren) {
						fail_from_lookahead(parser, .Close_Paren)
						return {}, false
					}
					close := parser.lookahead.token
					advance(parser)
					argument_node := parser.nodes.storage[int(argument)]
					contains_dynamic := spelling == "contains" && argument_node.kind != .Number && argument_node.kind != .String && argument_node.kind != .Boolean && argument_node.kind != .Null && argument_node.kind != .Nan && !(argument_node.kind == .Identity && argument_node.has_value)
					stream_selector := spelling == "first" || spelling == "last" || spelling == "map" || spelling == "map_values" || contains_dynamic
					bsearch_comma := spelling == "bsearch" && argument_node.kind == .Comma
					join_comma := spelling == "join" && argument_node.kind == .Comma
					flatten_comma := spelling == "flatten" && argument_node.kind == .Comma
					index_comma := (spelling == "index" || spelling == "rindex" || spelling == "indices") && argument_node.kind == .Comma
					literal_sequence := bsearch_comma || join_comma || flatten_comma || index_comma
					// The validation below is shared with scalar index calls. Keep a
					// literal comma sequence eligible for that path while retaining the
					// original AST for literal_call_sequence lowering.
					if index_comma {
						argument_node.kind = .String
						argument_node.has_child = false
						argument_node.has_value = false
					}
					any_not_literal := (spelling == "any" || spelling == "all") && argument_node.kind == .Not_Builtin && !argument_node.has_child && !argument_node.has_value
					index_family := spelling == "index" || spelling == "rindex" || spelling == "indices"
					array_literal := argument_node.kind == .Identity && argument_node.container_kind == .Array && argument_node.has_value
					contains_object_literal := spelling == "contains" && argument_node.kind == .Identity && argument_node.container_kind == .Object
					contains_array_literal := spelling == "contains" && array_literal
					contains_scalar_literal := spelling == "contains" &&
						(argument_node.kind == .Null || argument_node.kind == .Boolean || argument_node.kind == .Number ||
						 argument_node.kind == .String || argument_node.kind == .Nan || argument_node.kind == .Infinite)
					contains_variable := spelling == "contains" && argument_node.kind == .Variable
					// `in`/`inside` accept any static JSON value as their haystack,
					// not only array/object literals. The evaluator's containment
					// kernel already handles scalar equality and string substrings;
					// keep dynamic expressions deferred while admitting literal
					// null/boolean/number/string/NaN operands here.
					in_container_literal := (spelling == "in" || spelling == "inside") && (
						(argument_node.kind == .Identity && (argument_node.container_kind == .Array || argument_node.container_kind == .Object)) ||
						argument_node.kind == .Null || argument_node.kind == .Boolean || argument_node.kind == .Number ||
						argument_node.kind == .String || argument_node.kind == .Nan)
					if spelling == "in" && !(argument_node.kind == .Identity && (argument_node.container_kind == .Array || argument_node.container_kind == .Object)) {
						in_container_literal = false
					}
					error_literal := spelling == "error" && (argument_node.kind == .String || argument_node.kind == .Number || argument_node.kind == .Boolean || argument_node.kind == .Null)
					// jq parses scalar trimstr separators and reports their type
					// mismatch at runtime (so `try ltrimstr(1) catch .` can
					// observe the error). Preserve the literal kind for lowering.
					trimstr_literal := (spelling == "ltrimstr" || spelling == "rtrimstr" || spelling == "trimstr") &&
						(argument_node.kind == .Number || argument_node.kind == .Boolean || argument_node.kind == .Null || argument_node.kind == .Nan || argument_node.kind == .Infinite ||
						 (argument_node.kind == .Negate && argument_node.has_child && parser.nodes.storage[int(argument_node.child)].kind == .Number))
					// Dynamic trimstr separators are valid filters; mark them as
					// trimstr-admissible for the shared scalar-call checks while
					// retaining the original child node for evaluator lowering.
					if (spelling == "ltrimstr" || spelling == "rtrimstr" || spelling == "trimstr") && !trimstr_literal do trimstr_literal = true
					isempty_literal := spelling == "isempty" && (argument_node.kind == .Empty || argument_node.kind == .Null || argument_node.kind == .Boolean || argument_node.kind == .Number || argument_node.kind == .String || argument_node.kind == .Range || argument_node.kind == .Comma || (argument_node.kind == .Identity && argument_node.container_kind == .Array))
					 isempty_array_literal := spelling == "isempty" && argument_node.kind == .Identity && (argument_node.container_kind == .Array || argument_node.container_kind == .Object)
					strftime_literal := (spelling == "strftime" || spelling == "strflocaltime") && (argument_node.kind == .Identity || argument_node.kind == .Null || argument_node.kind == .Boolean || argument_node.kind == .Number || argument_node.kind == .String || argument_node.kind == .Nan || argument_node.kind == .Empty || (argument_node.kind == .Identity && argument_node.container_kind == .Object))
					argument_is_literal := argument_node.kind == .String || argument_node.kind == .Number || isempty_literal || isempty_array_literal || strftime_literal || error_literal || trimstr_literal || (index_family && array_literal) || contains_object_literal || contains_array_literal || contains_scalar_literal || contains_variable || in_container_literal || literal_sequence || any_not_literal || (spelling == "has" && (argument_node.kind == .Nan || argument_node.kind == .Null)) || (spelling == "bsearch" && argument_node.kind == .Identity && argument_node.container_kind == .Object && argument_node.has_value)
					flatten_negative_literal := spelling == "flatten" && argument_node.kind == .Negate && argument_node.has_child && !argument_node.has_value && parser.nodes.storage[int(argument_node.child)].kind == .Number
					// The shared validation below historically required error() arguments
					// to be strings. Scalar literals are safe static operands too; present
					// them as string-shaped only for validation while retaining the original
					// AST node (and its literal kind) for evaluator lowering.
					if error_literal && argument_node.kind != .String do argument_node.kind = .String
					if !stream_selector && !isempty_array_literal && (!argument_is_literal && !flatten_negative_literal || (spelling == "error" && argument_node.kind != .String) || (spelling != "bsearch" && spelling != "join" && spelling != "flatten" && spelling != "error" && spelling != "isempty" && spelling != "strftime" && spelling != "strflocaltime" && spelling != "any" && spelling != "all" && spelling != "in" && spelling != "inside" && (spelling != "ltrimstr" && spelling != "rtrimstr" && spelling != "trimstr") && argument_node.has_child) || (spelling == "bsearch" && !bsearch_comma && !(argument_node.kind == .Identity && argument_node.container_kind == .Object) && argument_node.has_child) || (spelling == "join" && !join_comma && argument_node.has_child) || (spelling != "bsearch" && spelling != "join" && spelling != "flatten" && spelling != "error" && spelling != "strftime" && spelling != "strflocaltime" && !index_family && !contains_object_literal && !contains_array_literal && !contains_scalar_literal && !contains_variable && !in_container_literal && !trimstr_literal && argument_node.has_value) || (spelling == "bsearch" && !bsearch_comma && !(argument_node.kind == .Identity && argument_node.container_kind == .Object) && argument_node.has_value) || (spelling == "join" && !join_comma && argument_node.has_value) || (spelling == "flatten" && !flatten_comma && argument_node.has_value) || (spelling == "flatten" && !flatten_comma && argument_node.kind != .Number && !flatten_negative_literal) || ((spelling != "flatten" && spelling != "bsearch" && spelling != "join" && spelling != "has" && spelling != "error" && spelling != "isempty" && spelling != "strftime" && spelling != "strflocaltime" && spelling != "any" && spelling != "all" && !index_family && !contains_object_literal && !contains_array_literal && !contains_scalar_literal && !contains_variable && !in_container_literal && !trimstr_literal) && argument_node.kind != .String) || (index_family && argument_node.kind != .String && argument_node.kind != .Number && !array_literal) || (contains_object_literal && argument_node.container_kind != .Object) || (contains_array_literal && argument_node.container_kind != .Array) || (contains_scalar_literal && argument_node.kind != .Null && argument_node.kind != .Boolean && argument_node.kind != .Number && argument_node.kind != .String && argument_node.kind != .Nan && argument_node.kind != .Infinite) || (contains_variable && argument_node.kind != .Variable) || (spelling == "has" && argument_node.kind != .String && argument_node.kind != .Number && argument_node.kind != .Nan && argument_node.kind != .Null) || (spelling == "bsearch" && !bsearch_comma && argument_node.kind != .Number && !(argument_node.kind == .Identity && argument_node.container_kind == .Object)) || (spelling == "join" && !join_comma && argument_node.kind != .String) || (spelling == "flatten" && flatten_comma && argument_node.kind != .Comma) || ((spelling == "any" || spelling == "all") && !any_not_literal)) {
						// The closing paren has already been consumed, so lookahead may
						// be End_Of_Input. Route through the boundary-aware helper to
						// report a parse error instead of asserting on a non-token.
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					span, span_ok := spanning(parser, token.span, close.span)
					assert(span_ok)
					call_kind := Node_Kind.Join
					if spelling == "contains" do call_kind = .Contains
					if spelling == "in" do call_kind = .In
					if spelling == "inside" do call_kind = .Inside
					if spelling == "split" do call_kind = .Split
					if spelling == "index" do call_kind = .Index_Builtin
					if spelling == "rindex" do call_kind = .Rindex_Builtin
					if spelling == "indices" do call_kind = .Indices_Builtin
					if spelling == "startswith" do call_kind = .Startswith
					if spelling == "endswith" do call_kind = .Endswith
					if spelling == "has" do call_kind = .Has
					if spelling == "bsearch" do call_kind = .Bsearch
					if spelling == "flatten" do call_kind = .Flatten
					if spelling == "ltrimstr" do call_kind = .Ltrimstr
					if spelling == "rtrimstr" do call_kind = .Rtrimstr
					if spelling == "trimstr" do call_kind = .Trimstr
					if spelling == "error" do call_kind = .Error
					if spelling == "isempty" do call_kind = .IsEmpty
					if spelling == "first" do call_kind = .First
					if spelling == "last" do call_kind = .Last
					if spelling == "map" do call_kind = .Map
					if spelling == "map_values" do call_kind = .Map_Values
					if spelling == "strftime" || spelling == "strflocaltime" do call_kind = .Strftime
					if spelling == "strptime" do call_kind = .Strptime
					if spelling == "any" && any_not_literal do call_kind = .Any_Not
					if spelling == "all" && any_not_literal do call_kind = .All_Not
					if any_not_literal {
						new_term, marker_ok := append_node(parser, Node{kind=call_kind, span=span})
						if !marker_ok { return {}, false }
						term = new_term
					} else if literal_sequence {
						sequence_kind := call_kind
						new_term, sequence_ok := literal_call_sequence(parser, argument, sequence_kind)
						if !sequence_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						term = new_term
					} else {
						new_term, ok := append_node(parser, Node{kind=call_kind, span=span, child=argument, has_child=true, strflocaltime=spelling == "strflocaltime"})
						if !ok { return {}, false }
						term = new_term
					}
				} else if (spelling == "while" || spelling == "until") && token_is(parser, .Open_Paren) {
					advance(parser)
					condition, condition_ok := parse_pipe(parser, .Semicolon, false)
					if !condition_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }
					advance(parser)
					update, update_ok := parse_pipe(parser, .Close_Paren, false)
					if !update_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token
					advance(parser)
					span, span_ok := spanning(parser, token.span, close.span); assert(span_ok)
					loop_kind := Node_Kind.While if spelling == "while" else .Until
					new_term, ok := append_node(parser, Node{kind=loop_kind, span=span, left=condition, right=update})
					if !ok { return {}, false }
					term = new_term
				} else {
				// The same identifier spellings select jq's call production when
				// followed by `(`. Calls have no node/lowering contract in this
				// slice, so reject at that delimiter before allocating a literal.
				if token_is(parser, .Open_Paren) {
					fail_at_current(parser, .Unexpected_Token, .Expression)
					return {}, false
				}
				new_term, ok := append_node(parser, Node{
					kind = kind,
					span = token.span,
					boolean_value = boolean_value,
				})
				if !ok {
					return {}, false
				}
				term = new_term
				}
			case .Binding:
				// A binding reference is a filter term.  The lexer keeps the
				// `$` outside value_span; retain only the identifier span so the
				// compiler can own the name without borrowing parser storage.
				advance(parser)
				new_term, ok := append_node(parser, Node{
					kind = .Variable,
					span = token.span,
					name_span = token.value_span,
					has_name_span = true,
				})
				if !ok { return {}, false }
				term = new_term
			case .Reduce:
				// reduce EXP as $name (INIT; UPDATE)
				reduce_span := token.span
				advance(parser)
				exp, exp_ok := parse_pipe(parser, .Close_Paren, true)
				if !exp_ok || !parser.has_pending_reduce { fail_from_lookahead(parser, .Expression); return {}, false }
				name := parser.pending_reduce_name; parser.has_pending_reduce = false
				if !token_is(parser, .Open_Paren) { fail_from_lookahead(parser, .Expression); return {}, false }; advance(parser)
				init, init_ok := parse_pipe(parser, .Close_Paren, true)
				if !init_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }; advance(parser)
				update, update_ok := parse_pipe(parser, .Close_Paren, true)
				if !update_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }; close := parser.lookahead.token; advance(parser)
				span, _ := spanning(parser, reduce_span, close.span)
				new_term, ok := append_node(parser, Node{kind=.Reduce, span=span, left=exp, right=init, reduce_update=update, has_reduce_update=true, name_span=name, has_name_span=true})
				if !ok { return {}, false }; term = new_term
			case .Foreach:
				foreach_span := token.span
				advance(parser)
				exp, exp_ok := parse_pipe(parser, .Close_Paren, true)
				if !exp_ok || !parser.has_pending_reduce { fail_from_lookahead(parser, .Expression); return {}, false }
				name := parser.pending_reduce_name; parser.has_pending_reduce = false
				if !token_is(parser, .Open_Paren) { fail_from_lookahead(parser, .Expression); return {}, false }; advance(parser)
				// The initializer is a jq filter, not a single literal.  In
				// particular `foreach ... (0, 1; ...)` uses a comma stream of
				// seeds; keep commas live until the semicolon so the evaluator can
				// preserve that Cartesian seed ordering.
				init, init_ok := parse_pipe(parser, .Close_Paren, false)
				if !init_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); return {}, false }; advance(parser)
				update, update_ok := parse_pipe(parser, .Close_Paren, true)
				if !update_ok { fail_from_lookahead(parser, .Close_Paren); return {}, false }
				extract: Node_Id = -1
				has_extract := false
				if token_is(parser, .Semicolon) {
					advance(parser)
					extract_value, extract_ok := parse_pipe(parser, .Close_Paren, true)
					if !extract_ok { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					extract = extract_value
					has_extract = true
				}
				if !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }; close := parser.lookahead.token; advance(parser)
				span, _ := spanning(parser, foreach_span, close.span)
				new_term, ok := append_node(parser, Node{kind=.Foreach, span=span, left=exp, right=init, reduce_update=update, has_reduce_update=true, reduce_extract=extract, has_reduce_extract=has_extract, name_span=name, has_name_span=true})
				if !ok { return {}, false }; term = new_term
			case:
				fail_at_current(parser, .Unexpected_Token, .Expression)
				return {}, false
			}
			term_ready = true
		}

		ok: bool
		term, ok = append_postfix(
			parser,
			term,
			group_depth+minus_depth,
			live_pipe_count,
			live_comma_count,
			live_binary_count,
			term_prefix_overhead,
			&term_has_postfix,
		)
		if !ok {
			return {}, false
		}
		negate_boundary := invalid_id
		binary_boundary := invalid_id
		// Recursive parse_pipe calls (for call arguments, interpolation, and
		// similar subexpressions) can inherit parenthesis frames from their
		// caller, but their operator stacks always start empty.  Only a frame
		// opened by this invocation can delimit its local pending operators.
		if parser.frames.count > entry_frame_depth {
			active_frame := parser.frames.storage[parser.frames.count-1]
			negate_boundary = active_frame.outer_negate_boundary
			binary_boundary = active_frame.outer_binary_boundary
		}
		for negate_frame != negate_boundary {
			frame_id := negate_frame
			frame_node := &parser.nodes.storage[int(frame_id)]
			previous_frame := frame_node.left
			span, span_ok := spanning(parser, frame_node.span, parser.nodes.storage[int(term)].span)
			assert(span_ok)
			frame_node^ = Node{
				kind = .Negate,
				span = span,
				child = term,
				has_child = true,
			}
			term = frame_id
			negate_frame = previous_frame
			minus_depth -= 1
		}

		next_operator, next_precedence, has_binary_operator := binary_from_token(parser)
		term = reduce_binary_nodes(
			parser,
			term,
			&binary_frame,
			binary_boundary,
			next_precedence,
			has_binary_operator,
			&live_binary_count,
		)
		if has_binary_operator && binary_frame != binary_boundary &&
		   binary_is_comparison(next_operator) &&
		   binary_is_comparison(parser.nodes.storage[int(binary_frame)].binary_operator) {
			expected := Parse_Expectation.Close_Paren if parser.frames.count > 0 else .End_Of_Input
			fail_at_current(parser, .Unexpected_Token, expected)
			return {}, false
		}
		if stop_at_binary && has_binary_operator {
			result := current if current != invalid_id else term
			return result, result != invalid_id
		}
		if stop_at_defined_or && has_binary_operator && next_operator == .Defined_Or {
			result := current if current != invalid_id else term
			return result, result != invalid_id
		}
		if has_binary_operator {
			if parser_stack_budget_exhausted(parser,
				group_depth+minus_depth,
				live_pipe_count,
				live_comma_count,
				live_binary_count,
				JQ_QUERY_OPERATOR_STACK_OVERHEAD,
				false,
			) {
				fail_resource(parser, .Out_Of_Memory)
				return {}, false
			}
			operator_token := parser.lookahead.token
			binary, binary_ok := append_node(parser, Node{
				form = .Binary,
				span = operator_token.span,
				child = binary_frame,
				has_child = true, // transient link to the next lower pending operator
				left = term,
				binary_operator = next_operator,
				operator_span = operator_token.span,
				has_operator_span = true,
			})
			if !binary_ok {
				return {}, false
			}
			binary_frame = binary
			live_binary_count += 1
			advance(parser)
			term_ready = false
			term_prefix_overhead = JQ_GROUP_OR_ORDERED_STACK_OVERHEAD if group_depth > 0 else JQ_PREFIX_STACK_OVERHEAD
			minus_before_group = minus_depth > 0
			term_has_postfix = false
			continue
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
			live_comma_count -= 1
		}
		term_ready = false

		if (!stop_at_comma || group_depth > 0) && token_is(parser, .Comma) {
			if parser_stack_budget_exhausted(parser,
				group_depth+minus_depth,
				live_pipe_count,
				live_comma_count,
				live_binary_count,
				JQ_QUERY_OPERATOR_STACK_OVERHEAD,
				false,
			) {
				fail_resource(parser, .Out_Of_Memory)
				return {}, false
			}
			comma, comma_ok := append_node(parser, Node{
				kind = .Comma,
				left = current,
				has_child = true, // transiently marks a missing right operand
			})
			if !comma_ok {
				return {}, false
			}
			current = comma
			live_comma_count += 1
			advance(parser)
			term_prefix_overhead = JQ_GROUP_OR_ORDERED_STACK_OVERHEAD if group_depth > 0 else JQ_PREFIX_STACK_OVERHEAD
			minus_before_group = minus_depth > 0
			term_has_postfix = false
			continue
		}

		if token_is(parser, .Pipe) {
			if stop_at_pipe {
				result := current if current != invalid_id else term
				return result, result != invalid_id
			}
			if parser_stack_budget_exhausted(parser,
				group_depth+minus_depth,
				live_pipe_count,
				live_comma_count,
				live_binary_count,
				JQ_QUERY_OPERATOR_STACK_OVERHEAD,
				false,
			) {
				fail_resource(parser, .Out_Of_Memory)
				return {}, false
			}
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
			live_pipe_count += 1
			current_pipe_count += 1
			current = invalid_id
			advance(parser)
			term_prefix_overhead = JQ_GROUP_OR_ORDERED_STACK_OVERHEAD if group_depth > 0 else JQ_PREFIX_STACK_OVERHEAD
			minus_before_group = minus_depth > 0
			term_has_postfix = false
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

		if token_is(parser, .Assign_Pipe) {
			return parse_static_field_add_update(
				parser,
				current if pipe_root != invalid_id else result,
				pipe_root,
				pipe_tail,
				closing,
			)
		}
		if token_is(parser, .Assign) {
			if current >= 0 && parser.nodes.storage[int(current)].kind == .Slice {
				slice := parser.nodes.storage[int(current)]
				start_ok := slice.left >= 0 && parser.nodes.storage[int(slice.left)].kind == .Number
				end_ok := slice.right >= 0 && parser.nodes.storage[int(slice.right)].kind == .Number
				if start_ok && end_ok && slice.has_child && slice.child >= 0 {
					advance(parser)
					rhs, rhs_ok := parse_pipe(parser, closing, true, false, false, true)
					if !rhs_ok do return {}, false
					for rhs >= 0 && parser.nodes.storage[int(rhs)].kind == .Parenthesized && parser.nodes.storage[int(rhs)].has_child {
						rhs = parser.nodes.storage[int(rhs)].child
					}
					rhs_node := parser.nodes.storage[int(rhs)]
					if rhs_node.form != .Kinded || rhs_node.kind == .Variable || rhs_node.kind == .Call || rhs_node.has_child {
						fail_from_lookahead(parser, .Expression); return {}, false
					}
					span, span_ok := spanning(parser, slice.span, rhs_node.span); assert(span_ok)
					update, update_ok := append_node(parser, Node{kind=.Static_Slice_Set_Number, span=span, child=slice.child, has_child=true, left=slice.left, right=slice.right, value=rhs, has_value=true})
					if !update_ok do return {}, false
					if int(pipe_root) < 0 do return update, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
					return pipe_root, true
				}
			}
			if current >= 0 && parser.nodes.storage[int(current)].kind == .Index {
				index_base := parser.nodes.storage[int(current)].child
				if index_base < 0 || parser.nodes.storage[int(index_base)].kind != .Index {
					return parse_static_index_set_number(parser, current, pipe_root, pipe_tail, closing)
				}
			}
			left := current if pipe_root != invalid_id else result
			left_node := parser.nodes.storage[int(left)]
			if left_node.form == .Kinded && (left_node.kind == .Field || left_node.kind == .Index) && left_node.has_child {
				path, path_ok := static_assignment_path(parser, left)
				if path_ok {
					advance(parser)
					right, right_ok := parse_pipe(parser, closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized &&
						parser.nodes.storage[int(right)].has_child {
						right = parser.nodes.storage[int(right)].child
					}
					rhs := parser.nodes.storage[int(right)]
				if rhs.form != .Kinded || (rhs.kind != .Number && rhs.kind != .Boolean && rhs.kind != .Null && rhs.kind != .String) || rhs.has_child || rhs.has_value {
					fail_from_lookahead(parser, .Expression); return {}, false
				}
				span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
				setpath, setpath_ok := append_node(parser, Node{kind=.Setpath, span=span, left=path, right=right})
				if !setpath_ok do return {}, false
				if int(pipe_root) < 0 do return setpath, true
				tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = setpath; tail.has_child = false
				return pipe_root, true
				}
			}
			if left_node.form == .Kinded && left_node.kind == .Field && left_node.container_kind == .None &&
				left_node.has_name_span && !left_node.has_child {
				return parse_dynamic_field_set(parser, left, pipe_root, pipe_tail, closing)
			}
			return parse_static_field_set_number(parser, left, pipe_root, pipe_tail, closing)
		}

		// jq's `expr as $name | body` is a low-precedence lexical binding.
		// Parse the body with a fresh precedence state so the binding covers
		// the complete remaining filter, while the caller's closing delimiter
		// remains honored by the recursive parse.
		if token_is(parser, .As) {
			// A pipe to the left binds more tightly than `as`: in
			// `input | .[] as $x | body`, only `.[]` is bound and the
			// resulting Binding node becomes the pipe's right child. The
			// previous parser wrapped the entire pipe root here, causing the
			// binding body to see the pre-pipe input instead of the piped value.
			left := current if pipe_root != invalid_id else result
			advance(parser)
			// A bounded, literal array destructuring form is lowered into
			// ordinary lexical bindings over static indexes.  This keeps the
			// existing Binding/Variable evaluator contract intact while covering
			// the common `. as [$a, $b] | ...` jq idiom. General patterns and
			// nested destructuring remain outside this narrow contract.
			if token_is(parser, .Open_Bracket) {
				// The producer may itself be a generator (`.[] as [$a, $b]`).
				// Keep the bounded pattern lowering restricted to a single left
				// expression, but do not require that producer to be literal `.`.
				// The generated index filters then run once for each producer item,
				// matching jq's destructuring binding semantics.
				pattern, pattern_ok := parse_container(parser, .Open_Bracket)
				if !pattern_ok || pattern < 0 || int(pattern) >= len(parser.nodes.storage) {
					return {}, false
				}
				pattern_node := parser.nodes.storage[int(pattern)]
				if pattern_node.container_kind != .Array || !pattern_node.has_value {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				entries := parser.nodes.storage[int(pattern_node.value)]
				if entries.kind != .Comma || entries.left < 0 || int(entries.left) >= len(parser.nodes.storage) ||
				   entries.right < 0 || int(entries.right) >= len(parser.nodes.storage) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				variables := [2]Node_Id{entries.left, entries.right}
				for variable in variables {
					if parser.nodes.storage[int(variable)].kind != .Variable {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
				}
				if !token_is(parser, .Pipe) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				advance(parser)
				body, body_ok := parse_pipe(parser, closing, stop_at_comma)
				if !body_ok do return {}, false
				nested := body
				// Bind the produced item once, then project both slots from that
				// lexical value. Reusing `left` for each slot would restart a
				// generator and duplicate its outputs (`.[] as [...]`). The
				// temporary item binding deliberately reuses the first user name;
				// the innermost slot binding shadows it with the first element.
				first := parser.nodes.storage[int(variables[0])]
				second := parser.nodes.storage[int(variables[1])]
				first_ref, first_ref_ok := append_node(parser, Node{kind=.Variable, span=first.span, name_span=first.name_span, has_name_span=true})
				if !first_ref_ok do return {}, false
				first_index, first_index_ok := append_node(parser, Node{kind=.Index, span=first.span, number_text="0", has_number_text=true, child=first_ref, has_child=true})
				if !first_index_ok do return {}, false
				bound_span, span_ok := spanning(parser, parser.nodes.storage[int(first_index)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
				bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=first_index, right=nested, name_span=first.name_span, has_name_span=true})
				if !bound_ok do return {}, false
				nested = bound
				first_ref, first_ref_ok = append_node(parser, Node{kind=.Variable, span=first.span, name_span=first.name_span, has_name_span=true})
				if !first_ref_ok do return {}, false
				second_index, second_index_ok := append_node(parser, Node{kind=.Index, span=second.span, number_text="1", has_number_text=true, child=first_ref, has_child=true})
				if !second_index_ok do return {}, false
				bound_span, span_ok = spanning(parser, parser.nodes.storage[int(second_index)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
				bound, bound_ok = append_node(parser, Node{kind=.Binding, span=bound_span, left=second_index, right=nested, name_span=second.name_span, has_name_span=true})
				if !bound_ok do return {}, false
				nested = bound
				bound_span, span_ok = spanning(parser, parser.nodes.storage[int(left)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
				bound, bound_ok = append_node(parser, Node{kind=.Binding, span=bound_span, left=left, right=nested, name_span=first.name_span, has_name_span=true})
				if !bound_ok do return {}, false
				if pipe_root != invalid_id {
					tail := &parser.nodes.storage[int(pipe_tail)]
					tail.right = bound
					tail.has_child = false
					return pipe_root, true
				}
				return bound, true
			}
			// A bounded object pattern reuses the normal Field and Binding
			// instructions: each named entry extracts a field from the producer,
			// then binds that result to its `$name`. Restrict
			// this slice to one or two simple `name:$var` entries.
			if token_is(parser, .Open_Brace) {
				// As with array patterns, permit a generator producer such as
				// `.[] as {a:$a}` while retaining a narrow direct-field pattern.
				pattern, pattern_ok := parse_container(parser, .Open_Brace)
				if !pattern_ok || pattern < 0 || int(pattern) >= len(parser.nodes.storage) {
					return {}, false
				}
				pattern_node := parser.nodes.storage[int(pattern)]
				if pattern_node.container_kind != .Object || !pattern_node.has_value {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				entry_id := pattern_node.value
				variables: [2]Node_Id
				keys: [2]Node_Id
				count := 0
				for entry_id >= 0 {
					if count >= 2 || int(entry_id) >= len(parser.nodes.storage) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					entry := parser.nodes.storage[int(entry_id)]
					if entry.kind != .Field || entry.container_kind != .Object_Entry || !entry.has_key ||
					   !entry.has_value || int(entry.key) >= len(parser.nodes.storage) || int(entry.value) >= len(parser.nodes.storage) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					key := parser.nodes.storage[int(entry.key)]
					variable := parser.nodes.storage[int(entry.value)]
					if key.kind != .Field || !key.has_name_span || variable.kind != .Variable || !variable.has_name_span {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					keys[count] = entry.key
					variables[count] = entry.value
					count += 1
					entry_id = entry.next if entry.has_next else Node_Id(-1)
				}
				if count == 0 || !token_is(parser, .Pipe) {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				advance(parser)
				body, body_ok := parse_pipe(parser, closing, stop_at_comma)
				if !body_ok do return {}, false
				nested := body
				first := parser.nodes.storage[int(variables[0])]
				first_ref, first_ref_ok := append_node(parser, Node{kind=.Variable, span=first.span, name_span=first.name_span, has_name_span=true})
				if !first_ref_ok do return {}, false
				for index := 0; index < count; index += 1 {
					key := parser.nodes.storage[int(keys[index])]
					variable := parser.nodes.storage[int(variables[index])]
					field, field_ok := append_node(parser, Node{kind=.Field, span=key.span, child=first_ref, has_child=true, name_span=key.name_span, has_name_span=true})
					if !field_ok do return {}, false
					bound_span, bound_span_ok := spanning(parser, parser.nodes.storage[int(field)].span, parser.nodes.storage[int(nested)].span); assert(bound_span_ok)
					bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=field, right=nested, name_span=variable.name_span, has_name_span=true})
					if !bound_ok do return {}, false
					nested = bound
				}
				bound_span, bound_span_ok := spanning(parser, parser.nodes.storage[int(left)].span, parser.nodes.storage[int(nested)].span); assert(bound_span_ok)
				bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=left, right=nested, name_span=first.name_span, has_name_span=true})
				if !bound_ok do return {}, false
				if pipe_root != invalid_id {
					tail := &parser.nodes.storage[int(pipe_tail)]
					tail.right = bound
					tail.has_child = false
					return pipe_root, true
				}
				return bound, true
			}
			if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Binding {
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}
			binding_token := parser.lookahead.token
			advance(parser)
			if !token_is(parser, .Pipe) {
				if token_is(parser, .Open_Paren) {
					parser.pending_reduce_name = binding_token.value_span
					parser.has_pending_reduce = true
					return left, true
				}
				fail_from_lookahead(parser, .Expression)
				return {}, false
			}
			advance(parser)
			right, body_ok := parse_pipe(parser, closing, stop_at_comma)
			if !body_ok { return {}, false }
			span, span_ok := spanning(parser, parser.nodes.storage[int(left)].span, parser.nodes.storage[int(right)].span)
			assert(span_ok)
			bound, bound_ok := append_node(parser, Node{
				kind = .Binding,
				span = span,
				left = left,
				right = right,
				name_span = binding_token.value_span,
				has_name_span = true,
			})
			if !bound_ok { return {}, false }
			if pipe_root != invalid_id {
				tail := &parser.nodes.storage[int(pipe_tail)]
				tail.right = bound
				tail.has_child = false
				pipe := pipe_root
				for {
					pipe_node := &parser.nodes.storage[int(pipe)]
					pipe_span, pipe_span_ok := spanning(
						parser,
						parser.nodes.storage[int(pipe_node.left)].span,
						parser.nodes.storage[int(bound)].span,
					)
					assert(pipe_span_ok)
					pipe_node.span = pipe_span
					if pipe == pipe_tail do break
					pipe = pipe_node.right
				}
				return pipe_root, true
			}
			return bound, true
		}

		if (closing != .Invalid &&
			(token_is(parser, closing) || (closing == .Else && token_is(parser, .Else_If))) &&
			parser.frames.count == entry_frame_depth) ||
		   (stop_at_comma && token_is(parser, .Comma)) {
			return result, true
		}

		if token_is(parser, .Close_Paren) && parser.frames.count > 0 {
			close := parser.lookahead.token
			advance(parser)

			frame_state := parser.frames.storage[parser.frames.count-1]
			parser.frames.count -= 1
			frame_node := &parser.nodes.storage[int(frame_state.parenthesized)]
			span, span_ok := spanning(parser, frame_node.span, close.span)
			assert(span_ok)
			frame_node^ = Node{
				kind = .Parenthesized,
				span = span,
				child = result,
				has_child = true,
			}

			live_pipe_count -= current_pipe_count
			current = frame_state.outer_current
			pipe_root = frame_state.outer_pipe_root
			pipe_tail = frame_state.outer_pipe_tail
			current_pipe_count = frame_state.outer_pipe_count
			term_prefix_overhead = frame_state.outer_prefix_overhead
			minus_before_group = frame_state.outer_minus_before_group
			term_has_postfix = frame_state.outer_term_has_postfix
			assert(binary_frame == frame_state.outer_binary_boundary)
			term = frame_state.parenthesized
			term_ready = true
			group_depth -= 1
			continue
		}

		if parser.frames.count > entry_frame_depth {
			fail_from_lookahead(parser, .Close_Paren)
			return {}, false
		}
		return result, true
	}
}

@(private="package")
parse_dynamic_field_set :: proc(parser: ^Parser, left, pipe_root, pipe_tail: Node_Id, closing: Token_Kind) -> (Node_Id, bool) {
	left_node := parser.nodes.storage[int(left)]
	advance(parser)
	right, right_ok := parse_pipe(parser, closing, true, false, false, true)
	if !right_ok do return {}, false
	for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
		right = parser.nodes.storage[int(right)].child
	}
	right_node := parser.nodes.storage[int(right)]
	valid_rhs := right_node.kind == .Identity || right_node.kind == .Field ||
		right_node.kind == .Number || right_node.kind == .Boolean ||
		right_node.kind == .Null || right_node.kind == .String
	if right_node.form != .Kinded || right_node.container_kind != .None || right_node.has_child || right_node.has_value || !valid_rhs {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	span, span_ok := spanning(parser, left_node.span, right_node.span); assert(span_ok)
	kind := Node_Kind.Dynamic_Field_Set
	if right_node.kind == .Number || right_node.kind == .Boolean || right_node.kind == .Null || right_node.kind == .String {
		kind = .Static_Field_Set_Number
	}
	update, update_ok := append_node(parser, Node{kind=kind, span=span, right=right, name_span=left_node.name_span, has_name_span=true})
	if !update_ok do return {}, false
	if int(pipe_root) < 0 do return update, true
	tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
	return pipe_root, true
}

@(private="package")
parse_static_field_add_update :: proc(
	parser: ^Parser,
	left, pipe_root, pipe_tail: Node_Id,
	closing: Token_Kind,
) -> (Node_Id, bool) {
	left_node := parser.nodes.storage[int(left)]
	if left_node.form != .Kinded || left_node.kind != .Field ||
	   left_node.container_kind != .None || left_node.has_child ||
	   !left_node.has_name_span {
		fail_at_current(parser, .Unexpected_Token, .Expression)
		return {}, false
	}
	advance(parser)
	right, right_ok := parse_pipe(parser, closing, true, false, false, true)
	if !right_ok do return {}, false
	right_node := parser.nodes.storage[int(right)]
	if right_node.form != .Binary || right_node.binary_operator != .Add ||
	   int(right_node.left) < 0 || int(right_node.right) < 0 {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	identity := parser.nodes.storage[int(right_node.left)]
	number := parser.nodes.storage[int(right_node.right)]
	if identity.form != .Kinded || identity.kind != .Identity ||
	   identity.container_kind != .None || identity.has_child ||
	   number.form != .Kinded || number.kind != .Number ||
	   !number.has_number_text {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	span, span_ok := spanning(parser, left_node.span, right_node.span)
	assert(span_ok)
	update, update_ok := append_node(parser, Node{
		kind = .Static_Field_Add_Number,
		span = span,
		right = right_node.right,
		name_span = left_node.name_span,
		has_name_span = true,
	})
	if !update_ok do return {}, false
	if int(pipe_root) < 0 do return update, true
	tail := &parser.nodes.storage[int(pipe_tail)]
	tail.right = update
	pipe := pipe_root
	for {
		pipe_node := &parser.nodes.storage[int(pipe)]
		pipe_span, pipe_span_ok := spanning(
			parser,
			parser.nodes.storage[int(pipe_node.left)].span,
			parser.nodes.storage[int(update)].span,
		)
		assert(pipe_span_ok)
		pipe_node.span = pipe_span
		if pipe == pipe_tail do break
		pipe = pipe_node.right
	}
	return pipe_root, true
}

@(private="package")
static_assignment_path :: proc(parser: ^Parser, root: Node_Id) -> (Node_Id, bool) {
	components: [dynamic]Node_Id
	append_component :: proc(parser: ^Parser, components: ^[dynamic]Node_Id, node: Node_Id) -> bool {
		if node < 0 || int(node) >= len(parser.nodes.storage) do return false
		n := parser.nodes.storage[int(node)]
		#partial switch n.kind {
		case .Field:
			if n.has_child {
				if !append_component(parser, components, n.child) do return false
			}
			copy, ok := append_node(parser, Node{kind=.Field, span=n.span, name_span=n.name_span, has_name_span=n.has_name_span, string_text=n.string_text, has_string_text=n.has_string_text})
			if !ok do return false
		append(&components^, copy)
			return true
		case .Index:
			if !n.has_child || !n.has_number_text do return false
			if !append_component(parser, components, n.child) do return false
			copy, ok := append_node(parser, Node{kind=.Number, span=n.span, number_text=n.number_text, has_number_text=true})
			if !ok do return false
			append(&components^, copy)
			return true
		case .Identity:
			return !n.has_child && !n.has_value
		}
		return false
	}
	if !append_component(parser, &components, root) { delete(components); return {}, false }
	if len(components) == 0 { delete(components); return {}, false }
	path_value := components[0]
	for i in 1..<len(components) {
		span, span_ok := spanning(parser, parser.nodes.storage[int(path_value)].span, parser.nodes.storage[int(components[i])].span)
		assert(span_ok)
		next_value, next_ok := append_node(parser, Node{kind=.Comma, span=span, left=path_value, right=components[i]})
		if !next_ok { delete(components); return {}, false }
		path_value = next_value
	}
	span, span_ok := spanning(parser, parser.nodes.storage[int(root)].span, parser.nodes.storage[int(components[len(components)-1])].span)
	assert(span_ok)
	path, ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=span, value=path_value, has_value=true})
	delete(components)
	return path, ok
}

@(private="package")
parse_static_field_set_number :: proc(parser: ^Parser, left, pipe_root, pipe_tail: Node_Id, closing: Token_Kind) -> (Node_Id, bool) {
	left_node := parser.nodes.storage[int(left)]
	if left_node.form != .Kinded || left_node.kind != .Field || left_node.container_kind != .None || left_node.has_child || !left_node.has_name_span {
		fail_at_current(parser, .Unexpected_Token, .Expression); return {}, false
	}
	advance(parser)
	right, right_ok := parse_pipe(parser, closing, true, false, false, true)
	if !right_ok do return {}, false
	// A static assignment nested in `try (...) catch .` is parsed while the
	// parenthesis frame is still active, so the RHS arrives wrapped in the
	// source-preserving Parenthesized node.  The static assignment contract is
	// intentionally scalar-only; unwrap only these transparent wrappers and
	// continue rejecting compound/dynamic RHS expressions below.
	for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized &&
		parser.nodes.storage[int(right)].has_child {
		right = parser.nodes.storage[int(right)].child
	}
	number := parser.nodes.storage[int(right)]
	if number.form != .Kinded || (number.kind != .Number && number.kind != .Boolean && number.kind != .Null && number.kind != .String) || number.has_child || number.has_value {
		fail_from_lookahead(parser, .Expression); return {}, false
	}
	span, span_ok := spanning(parser, left_node.span, number.span); assert(span_ok)
	update, update_ok := append_node(parser, Node{kind=.Static_Field_Set_Number, span=span, right=right, name_span=left_node.name_span, has_name_span=true})
	if !update_ok do return {}, false
	if int(pipe_root) < 0 do return update, true
	tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update
	return pipe_root, true
}

@(private="package")
parse_static_index_set_number :: proc(parser: ^Parser, left, pipe_root, pipe_tail: Node_Id, closing: Token_Kind) -> (Node_Id, bool) {
	index_node := &parser.nodes.storage[int(left)]
	base := parser.nodes.storage[int(index_node.child)]
	if !index_node.has_child || index_node.container_kind != .None || !index_node.has_number_text ||
	   base.form != .Kinded || (base.kind != .Identity && base.kind != .Field) ||
	   (base.kind == .Identity && (base.has_child || base.has_value)) ||
	   (base.kind == .Field && !base.has_name_span) {
		fail_at_current(parser, .Unexpected_Token, .Expression); return {}, false
	}
	advance(parser)
	right, right_ok := parse_pipe(parser, closing, true, false, false, true)
	if !right_ok do return {}, false
	for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized &&
		parser.nodes.storage[int(right)].has_child {
		right = parser.nodes.storage[int(right)].child
	}
	number := parser.nodes.storage[int(right)]
	if number.form != .Kinded || (number.kind != .Number && number.kind != .Boolean && number.kind != .Null && number.kind != .String) || number.has_child || number.has_value {
		fail_from_lookahead(parser, .Expression); return {}, false
	}
	span, span_ok := spanning(parser, index_node.span, number.span); assert(span_ok)
	if base.kind == .Field {
		// A nested static index assignment is represented as the existing
		// literal `setpath` form.  This keeps the assignment evaluator's
		// copy-on-write path semantics in one place while retaining the
		// bounded scalar-RHS contract of this parser entry point.
		index_literal, index_literal_ok := append_node(parser, Node{
			kind = .Number,
			span = index_node.span,
			number_text = index_node.number_text,
			has_number_text = true,
		})
		if !index_literal_ok do return {}, false
		components, components_ok := append_node(parser, Node{
			kind = .Comma,
			span = index_node.span,
			left = index_node.child,
			right = index_literal,
		})
		if !components_ok do return {}, false
		path, path_ok := append_node(parser, Node{
			kind = .Identity,
			container_kind = .Array,
			span = index_node.span,
			value = components,
			has_value = true,
		})
		if !path_ok do return {}, false
		setpath, setpath_ok := append_node(parser, Node{
			kind = .Setpath,
			span = span,
			left = path,
			right = right,
		})
		if !setpath_ok do return {}, false
		if int(pipe_root) < 0 do return setpath, true
		tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = setpath; tail.has_child = false
		return pipe_root, true
	}
	index_node^ = Node{kind=.Static_Index_Set_Number, span=span, child=index_node.child, has_child=true, right=right, number_text=index_node.number_text, has_number_text=true}
	if int(pipe_root) < 0 do return left, true
	tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = left
	return pipe_root, true
}

@(private="package")
parse_deep_array_chain :: proc(parser: ^Parser) -> (Node_Id, bool) {
	invalid_id := Node_Id(-1)
	head := invalid_id
	count := 0

	for {
		if parser.lookahead.kind != .Token ||
		   parser.lookahead.token.kind != .Open_Bracket {
			break
		}
		count += 1
		if parser.container_depth + count - 1 > JQ_CONTAINER_NESTING_CAP {
			fail_resource(parser, .Out_Of_Memory)
			return {}, false
		}
		open_span := parser.lookahead.token.span
		advance(parser)
		node, ok := append_node(parser, Node{
			kind = .Identity,
			container_kind = .Array,
			span = open_span,
			next = head,
			has_next = head != invalid_id,
		})
		if !ok {
			return {}, false
		}
		head = node
	}

	// The flattened openers are all still live while their contents are parsed.
	// Charge them to the same budget used by the precedence parser; otherwise a
	// deep container prefix could be combined with an independently accepted
	// deep expression prefix.
	parser.container_depth += count - 1
	value: Node_Id
	ok: bool
	first_close_consumed := false
	if token_is(parser, .Close_Bracket) {
		close_span := parser.lookahead.token.span
		advance(parser)
		node := &parser.nodes.storage[int(head)]
		value = head
		span, span_ok := spanning(parser, node.span, close_span)
		assert(span_ok)
		node.span = span
		node.has_value = false
		next := node.next if node.has_next else invalid_id
		node.next = 0
		node.has_next = false
		head = next
		first_close_consumed = true
	} else {
		value, ok = parse_pipe(parser, .Close_Bracket, false)
		if !ok {
			parser.container_depth -= count - 1
			return {}, false
		}
	}
	if !first_close_consumed {
		if !token_is(parser, .Close_Bracket) {
			fail_from_lookahead(parser, .Close_Bracket)
			parser.container_depth -= count - 1
			return {}, false
		}
		close_span := parser.lookahead.token.span
		advance(parser)
		node := &parser.nodes.storage[int(head)]
		next := node.next if node.has_next else invalid_id
		span, span_ok := spanning(parser, node.span, close_span)
		assert(span_ok)
		node.value = value
		node.has_value = true
		node.span = span
		node.next = 0
		node.has_next = false
		value = head
		head = next
	}
	// The first close belongs to the innermost flattened array. If its enclosing
	// array query continues, reduce that continuation here before unwinding the
	// remaining closers. This is the iterative equivalent of returning to the
	// general query parser after an inner array term.
	postfix_seen := false
	for head != invalid_id {
		if token_is(parser, .Question) || token_is(parser, .Field) {
			value, ok = append_postfix(parser, value, 0, 0, 0, 0, 0, &postfix_seen)
			if !ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			continue
		}
		if token_is(parser, .Comma) {
			operator := parser.lookahead.token
			advance(parser)
			right, right_ok := parse_pipe(parser, .Close_Bracket, false)
			if !right_ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			value, ok = append_node(parser, Node{
				kind = .Comma,
				span = operator.span,
				left = value,
				right = right,
				has_child = false,
			})
			if !ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			continue
		}
		if token_is(parser, .Pipe) {
			operator := parser.lookahead.token
			advance(parser)
			right, right_ok := parse_pipe(parser, .Close_Bracket, false)
			if !right_ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			value, ok = append_node(parser, Node{
				kind = .Pipe,
				span = operator.span,
				left = value,
				right = right,
				has_child = false,
			})
			if !ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			continue
		}
		binary_operator, _, has_binary := binary_from_token(parser)
		if has_binary {
			operator := parser.lookahead.token
			advance(parser)
			right, right_ok := parse_pipe(parser, .Close_Bracket, false)
			if !right_ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			span, span_ok := spanning(parser, parser.nodes.storage[int(value)].span,
				parser.nodes.storage[int(right)].span)
			assert(span_ok)
			value, ok = append_node(parser, Node{
				form = .Binary,
				span = span,
				left = value,
				right = right,
				binary_operator = binary_operator,
				operator_span = operator.span,
				has_operator_span = true,
			})
			if !ok {
				parser.container_depth -= count - 1
				return {}, false
			}
			continue
		}
		// Each flattened frame owns the next close independently.  Close it
		// immediately after its query continuation has been reduced so the
		// next enclosing frame gets a fresh lookahead check.  Deferring all
		// closes until after this loop loses continuations after the first one.
		if !token_is(parser, .Close_Bracket) {
			fail_from_lookahead(parser, .Close_Bracket)
			parser.container_depth -= count - 1
			return {}, false
		}
		close_span := parser.lookahead.token.span
		advance(parser)
		node := &parser.nodes.storage[int(head)]
		next := node.next if node.has_next else invalid_id
		span, span_ok := spanning(parser, node.span, close_span)
		assert(span_ok)
		node.value = value
		node.has_value = true
		node.span = span
		node.next = 0
		node.has_next = false
		value = head
		head = next
	}
	parser.container_depth -= count - 1
	return value, true
}

@(private="package")
parse_container :: proc(parser: ^Parser, opener: Token_Kind) -> (Node_Id, bool) {
	// Check before incrementing: the cap is the number of live container
	// entries, so the 9,995th opener must fail when 9,994 are already live.
	if parser.container_depth >= JQ_CONTAINER_NESTING_CAP {
		fail_resource(parser, .Out_Of_Memory)
		return {}, false
	}
	parser.container_depth += 1
	if opener == .Open_Bracket &&
	   parser.container_depth >= JQ_NATIVE_CONTAINER_RECURSION_GUARD {
		value, ok := parse_deep_array_chain(parser)
		parser.container_depth -= 1
		return value, ok
	}
	close := Token_Kind.Close_Bracket if opener == .Open_Bracket else .Close_Brace
	expectation := Parse_Expectation.Close_Bracket if opener == .Open_Bracket else .Close_Brace
	open_span := parser.lookahead.token.span
	advance(parser)

	if token_is(parser, close) {
		close_span := parser.lookahead.token.span
		advance(parser)
		container_kind := Container_Kind.Array if opener == .Open_Bracket else .Object
		node, ok := append_node(parser, Node{
			kind = .Identity,
			container_kind = container_kind,
			span = open_span,
		})
		if !ok {
			parser.container_depth -= 1
			return {}, false
		}
		span, span_ok := spanning(parser, open_span, close_span)
		assert(span_ok)
		parser.nodes.storage[int(node)].span = span
		parser.container_depth -= 1
		return node, true
	}

	if opener == .Open_Bracket {
		contents, ok := parse_pipe(parser, close, false)
		if !ok {
			parser.container_depth -= 1
			return {}, false
		}
		if !token_is(parser, close) {
			fail_from_lookahead(parser, expectation)
			parser.container_depth -= 1
			return {}, false
		}
		close_span := parser.lookahead.token.span
		advance(parser)
		span, span_ok := spanning(parser, open_span, close_span)
		assert(span_ok)
		node, node_ok := append_node(parser, Node{
			kind = .Identity,
			container_kind = .Array,
			span = span,
			value = contents,
			has_value = true,
		})
		parser.container_depth -= 1
		return node, node_ok
	}

	first_entry := Node_Id(-1)
	last_entry := Node_Id(-1)
	for {
		if parser.lookahead.kind != .Token {
			fail_from_lookahead(parser, expectation)
			parser.container_depth -= 1
			return {}, false
		}
		key: Node_Id
		shorthand := false
		#partial switch parser.lookahead.token.kind {
		case .Identifier, .As, .Import, .Include, .Module, .Def,
		     .If, .Then, .Else, .Else_If, .And, .Or, .End, .Reduce,
		     .Foreach, .Try, .Catch, .Label, .Break:
			key_token := parser.lookahead.token
			key_ok: bool
			key, key_ok = append_node(parser, Node{
				kind = .Field,
				span = key_token.span,
				name_span = key_token.value_span if key_token.has_value_span else key_token.span,
				has_name_span = true,
			})
			if !key_ok {
				parser.container_depth -= 1
				return {}, false
			}
			advance(parser)
			shorthand = !token_is(parser, .Colon)
		case .Binding:
			// In object position `$x` is a dynamic key expression. If the
			// colon is omitted the shorthand branch below will replace the key
			// with the literal name while retaining this Variable as its value.
			key_token := parser.lookahead.token
			key_ok: bool
			key, key_ok = append_node(parser, Node{
				kind = .Variable,
				span = key_token.span,
				name_span = key_token.value_span,
				has_name_span = key_token.has_value_span,
			})
			if !key_ok {
				parser.container_depth -= 1
				return {}, false
			}
			advance(parser)
			shorthand = !token_is(parser, .Colon)
		case .String_Start:
			key_ok: bool
			key, key_ok = append_string_node(parser, parser.lookahead.token.span, 0, 0, 0, 0, 0, false)
			if !key_ok {
				parser.container_depth -= 1
				return {}, false
			}
			shorthand = !token_is(parser, .Colon)
		case .Open_Paren:
			// Keep a parenthesized query as source syntax, not a runtime key.
			key_ok: bool
			key, key_ok = parse_pipe(parser)
			if !key_ok {
				parser.container_depth -= 1
				return {}, false
			}
		case:
			fail_from_lookahead(parser, expectation)
			parser.container_depth -= 1
			return {}, false
		}

		value: Node_Id
		if shorthand {
			if parser.nodes.storage[int(key)].kind == .String {
				key_node := parser.nodes.storage[int(key)]
				value_ok: bool
				value, value_ok = append_node(parser, Node{
					kind = .Field,
					span = key_node.span,
					name_span = key_node.span,
					has_name_span = true,
					string_text = key_node.string_text,
					has_string_text = true,
					string_shorthand = true,
				})
				if !value_ok {
					parser.container_depth -= 1
					return {}, false
				}
			} else if parser.nodes.storage[int(key)].kind == .Variable {
				// {$x} is jq's binding shorthand: the key is the lexical name
				// "x", while the value is the variable reference $x. Keep both
				// nodes distinct so lowering does not evaluate $x as a key.
				variable := key
				variable_node := parser.nodes.storage[int(variable)]
				key_ok: bool
				key, key_ok = append_node(parser, Node{
					kind = .Field,
					span = variable_node.span,
					name_span = variable_node.name_span,
					has_name_span = variable_node.has_name_span,
				})
				if !key_ok {
					parser.container_depth -= 1
					return {}, false
				}
				value = variable
			} else {
				value = key
			}
		} else {
			if !token_is(parser, .Colon) {
				fail_from_lookahead(parser, .Expression)
				parser.container_depth -= 1
				return {}, false
			}
			advance(parser)
			value_ok: bool
			value, value_ok = parse_pipe(parser, close, true)
			if !value_ok {
				parser.container_depth -= 1
				return {}, false
			}
		}
		entry_span, entry_span_ok := spanning(parser, parser.nodes.storage[int(key)].span, parser.nodes.storage[int(value)].span)
		assert(entry_span_ok)
		entry, entry_ok := append_node(parser, Node{
			kind = .Field,
			container_kind = .Object_Entry,
			span = entry_span,
			name_span = parser.nodes.storage[int(key)].span,
			has_name_span = true,
			value = value,
			has_value = true,
			key = key,
			has_key = true,
		})
		if !entry_ok {
			parser.container_depth -= 1
			return {}, false
		}
		if first_entry == Node_Id(-1) {
			first_entry = entry
		} else {
			parser.nodes.storage[int(last_entry)].next = entry
			parser.nodes.storage[int(last_entry)].has_next = true
		}
		last_entry = entry
		if token_is(parser, .Comma) {
			advance(parser)
			continue
		}
		if !token_is(parser, close) {
			fail_from_lookahead(parser, expectation)
			parser.container_depth -= 1
			return {}, false
		}
		close_span := parser.lookahead.token.span
		advance(parser)
		span, span_ok := spanning(parser, open_span, close_span)
		assert(span_ok)
		object, object_ok := append_node(parser, Node{
			kind = .Identity,
			container_kind = .Object,
			span = span,
			value = first_entry,
			has_value = true,
		})
		parser.container_depth -= 1
		return object, object_ok
	}
}

@(private="package")
lookahead_starts_supported_term :: proc(parser: ^Parser) -> bool {
	if parser.lookahead.kind != .Token {
		return false
	}
	token := parser.lookahead.token
	#partial switch token.kind {
	case .Dot, .Recurse, .Field, .Number, .String_Start, .Format, .Minus, .Open_Paren,
	     .Open_Bracket, .Open_Brace, .Binding, .Try, .Reduce, .Foreach:
		return true
	case .If:
		return true
	case .Identifier:
		spelling := token_spelling(parser, token)
		return spelling == "false" || spelling == "true" || spelling == "null" || spelling == "nan" || spelling == "infinite"
	case:
		return false
	}
}

@(private="package")
binary_precedence :: proc(operator: Binary_Operator) -> int {
	switch operator {
	case .Defined_Or:
		return 0
	case .Or:
		return 1
	case .And:
		return 2
	case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return 3
	case .Add, .Subtract:
		return 4
	case .Multiply, .Divide, .Modulo:
		return 5
	}
	return 0
}

@(private="package")
binary_is_comparison :: proc(operator: Binary_Operator) -> bool {
	switch operator {
	case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return true
	case .Add, .Subtract, .Multiply, .Divide, .Modulo,
	     .Defined_Or, .Or, .And:
		return false
	}
	return false
}

@(private="package")
binary_from_token :: proc(parser: ^Parser) -> (Binary_Operator, int, bool) {
	if parser.failed || parser.lookahead.kind != .Token {
		return {}, 0, false
	}
	#partial switch parser.lookahead.token.kind {
	case .Defined_Or:
		return .Defined_Or, 0, true
	case .Or:
		return .Or, 1, true
	case .And:
		return .And, 2, true
	case .Equal:
		return .Equal, 3, true
	case .Not_Equal:
		return .Not_Equal, 3, true
	case .Less:
		return .Less, 3, true
	case .Less_Equal:
		return .Less_Equal, 3, true
	case .Greater:
		return .Greater, 3, true
	case .Greater_Equal:
		return .Greater_Equal, 3, true
	case .Plus:
		return .Add, 4, true
	case .Minus:
		return .Subtract, 4, true
	case .Multiply:
		return .Multiply, 5, true
	case .Divide:
		return .Divide, 5, true
	case .Modulo:
		return .Modulo, 5, true
	case:
		return {}, 0, false
	}
}

@(private="package")
reduce_binary_nodes :: proc(
	parser: ^Parser,
	initial: Node_Id,
	frame: ^Node_Id,
	boundary: Node_Id,
	next_precedence: int,
	has_next: bool,
	live_binary_count: ^int,
) -> Node_Id {
	node := initial
	for frame^ != boundary {
		binary := &parser.nodes.storage[int(frame^)]
		assert(binary.form == .Binary && binary.has_child)
		if has_next && binary_is_comparison(binary.binary_operator) &&
		   binary_precedence(binary.binary_operator) == next_precedence {
			break
		}
		if has_next && binary.binary_operator == .Defined_Or &&
		   binary_precedence(binary.binary_operator) == next_precedence {
			break
		}
		if has_next && binary_precedence(binary.binary_operator) < next_precedence {
			break
		}
		previous := binary.child
		span, span_ok := spanning(
			parser,
			parser.nodes.storage[int(binary.left)].span,
			parser.nodes.storage[int(node)].span,
		)
		assert(span_ok)
		binary.span = span
		binary.right = node
		binary.child = 0
		binary.has_child = false
		node = frame^
		frame^ = previous
		live_binary_count^ -= 1
	}
	return node
}

@(private="package")
parser_stack_budget_exhausted :: proc(
	parser: ^Parser,
	live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead: int,
	has_postfix: bool,
) -> bool {
	// Checks happen exactly where jq would push another grammar state. Earlier
	// peaks have already been checked and must not be charged after reduction.
	postfix_increment := 0
	if has_postfix {
		postfix_increment = JQ_FIRST_POSTFIX_STACK_INCREMENT
	}
	return parser.container_depth+
	       live_prefix_depth+
	       live_pipe_count*JQ_OPEN_PIPE_STACK_ENTRIES+
	       live_comma_count*JQ_OPEN_COMMA_STACK_ENTRIES+
	       live_binary_count*JQ_OPEN_BINARY_STACK_ENTRIES+
	       event_overhead+
	       postfix_increment > JQ_PARSER_STACK_CAP
}

@(private="package")
append_number_node :: proc(parser: ^Parser, span: diagnostic.Span) -> (Node_Id, bool) {
	node, ok := append_node(parser, Node{kind = .Number, span = span})
	if !ok {
		return {}, false
	}
	start, end, span_ok := diagnostic.span_offsets(parser.source, span)
	assert(span_ok && end > start)
	spelling := diagnostic.source_bytes(parser.source)[start:end]
	memory, allocation_error := runtime.mem_alloc_bytes(len(spelling), 1, parser.allocator)
	if allocation_error != nil || len(memory) != len(spelling) || raw_data(memory) == nil {
		resource_error := allocation_error
		if resource_error == nil {
			resource_error = .Out_Of_Memory
		}
		if raw_data(memory) != nil {
			free_error := runtime.mem_free_bytes(memory, parser.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				parser.pending_number_text = memory
				resource_error = free_error
			}
		}
		fail_resource(parser, resource_error)
		return {}, false
	}
	copy(memory, spelling)
	registry_error := append_fallible_buffer(
		&parser.number_allocations,
		Number_Allocation{memory = memory},
	)
	if registry_error != nil {
		free_error := runtime.mem_free_bytes(memory, parser.allocator)
		resource_error := registry_error
		if free_error != nil && free_error != .Mode_Not_Implemented {
			parser.pending_number_text = memory
			resource_error = free_error
		}
		fail_resource(parser, resource_error)
		return {}, false
	}
	stored := &parser.nodes.storage[int(node)]
	stored.number_text = string(memory)
	stored.has_number_text = true
	return node, true
}

// append_string_node consumes one complete, non-interpolated quoted string.
// Validation and decoding are iterative. The node is appended only after its
// decoded storage and private ownership record have both committed.
@(private="package")
append_string_node :: proc(
	parser: ^Parser,
	open_span: diagnostic.Span,
	live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead: int,
	has_postfix: bool,
) -> (Node_Id, bool) {
	open_start, open_end, open_ok := diagnostic.span_offsets(parser.source, open_span)
	assert(open_ok && open_end == open_start+1)
	advance(parser)
	if parser.failed {
		return {}, false
	}
	// A valid StringStart reduction and the empty QQString state add one live
	// generated-parser entry beyond an ordinary one-token Term. A lexical error
	// discovered while fetching the first string lookahead wins before that
	// state is entered, matching jq's event-local parser-stack behavior.
	if parser.lookahead.kind != .Lexical_Error &&
	   parser_stack_budget_exhausted(parser,
		live_prefix_depth,
		live_pipe_count,
		live_comma_count,
		live_binary_count,
		event_overhead+JQ_STRING_TERM_STACK_INCREMENT,
		has_postfix,
	) {
		fail_resource(parser, .Out_Of_Memory)
		return {}, false
	}
	close_span: diagnostic.Span
	for {
		if token_is(parser, .String_Text) {
			advance(parser)
			continue
		}
		if token_is(parser, .String_End) {
			close_span = parser.lookahead.token.span
			break
		}
		if token_is(parser, .String_Interpolation_Start) {
			fail_at_current(parser, .Unexpected_Token, .Close_String)
			parser.failure.error.message = "string interpolation is not supported"
			return {}, false
		}
		if parser.lookahead.kind == .End_Of_Input {
			fail_unterminated_string(parser, open_span)
			return {}, false
		}
		fail_from_lookahead(parser, .Close_String)
		return {}, false
	}

	close_start, _, close_ok := diagnostic.span_offsets(parser.source, close_span)
	assert(close_ok && close_start >= open_end)
	contents := diagnostic.source_bytes(parser.source)[open_end:close_start]
	span, span_ok := spanning(parser, open_span, close_span)
	assert(span_ok)
	node, node_ok := append_decoded_string_node(parser, contents, span, open_end)
	if !node_ok {
		return {}, false
	}
	advance(parser)
	return node, true
}

// string_has_interpolation only selects between two parser implementations;
// the scanner remains the authority for tokenization and diagnostics. Skipping
// one byte after a non-interpolation backslash is sufficient because neither
// byte can be an unescaped quote or the start of a later interpolation.
@(private="package")
string_has_interpolation :: proc(parser: ^Parser, open_span: diagnostic.Span) -> bool {
	_, at, ok := diagnostic.span_offsets(parser.source, open_span)
	assert(ok)
	bytes := diagnostic.source_bytes(parser.source)
	for at < len(bytes) {
		if bytes[at] == '"' do return false
		if bytes[at] == '\\' {
			if at+1 < len(bytes) && bytes[at+1] == '(' do return true
			at += 2
			continue
		}
		at += 1
	}
	return false
}

// append_interpolated_string_node lowers a quoted jq string directly into
// existing syntax. Literal fragments remain constants; interpolation queries
// pipe through format_kind; adjacent segments concatenate with Add. Plain jq
// strings use Tostring while the bounded @html form uses Html. This preserves
// package boundaries and requires no new program opcode.
@(private="package")
append_interpolated_string_node :: proc(
	parser: ^Parser,
	format_span, open_span: diagnostic.Span,
	format_kind: Node_Kind,
	has_format: bool,
	live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead: int,
	has_postfix: bool,
) -> (Node_Id, bool) {
	invalid_id := Node_Id(-1)
	advance(parser)
	if parser.failed do return {}, false
	if parser.lookahead.kind != .Lexical_Error &&
	   parser_stack_budget_exhausted(parser,
		live_prefix_depth,
		live_pipe_count,
		live_comma_count,
		live_binary_count,
		event_overhead+JQ_STRING_TERM_STACK_INCREMENT,
		has_postfix,
	) {
		fail_resource(parser, .Out_Of_Memory)
		return {}, false
	}

	root := invalid_id
	join_anchor := open_span
	close_span: diagnostic.Span
	for {
		segment := invalid_id
		if token_is(parser, .String_Text) {
			first_token := parser.lookahead.token
			start, end, ok := diagnostic.span_offsets(parser.source, first_token.span)
			assert(ok && end >= start)
			text_span := first_token.span
			advance(parser)
			for token_is(parser, .String_Text) {
				text_token := parser.lookahead.token
				_, next_end, next_ok := diagnostic.span_offsets(parser.source, text_token.span)
				assert(next_ok && next_end >= end)
				end = next_end
				text_span, next_ok = spanning(parser, text_span, text_token.span)
				assert(next_ok)
				advance(parser)
			}
			contents := diagnostic.source_bytes(parser.source)[start:end]
			segment_ok: bool
			segment, segment_ok = append_decoded_string_node(parser, contents, text_span, start)
			if !segment_ok do return {}, false
			join_anchor = first_token.span
		} else if token_is(parser, .String_Interpolation_Start) {
			interpolation_start := parser.lookahead.token
			advance(parser)
			query, query_ok := parse_pipe(parser, .String_Interpolation_End)
			if !query_ok do return {}, false
			if !token_is(parser, .String_Interpolation_End) {
				fail_from_lookahead(parser, .Close_String)
				return {}, false
			}
			interpolation_end := parser.lookahead.token
			formatter_span := interpolation_start.span
			if has_format do formatter_span = format_span
			formatter, formatter_ok := append_node(parser, Node{kind = format_kind, span = formatter_span})
			if !formatter_ok do return {}, false
			interpolation_span, interpolation_span_ok := spanning(parser, interpolation_start.span, interpolation_end.span)
			assert(interpolation_span_ok)
			segment, query_ok = append_node(parser, Node{
				kind = .Pipe,
				span = interpolation_span,
				left = query,
				right = formatter,
			})
			if !query_ok do return {}, false
			join_anchor = interpolation_start.span
			advance(parser)
		} else if token_is(parser, .String_End) {
			close_span = parser.lookahead.token.span
			break
		} else if parser.lookahead.kind == .End_Of_Input {
			fail_unterminated_string(parser, open_span)
			return {}, false
		} else {
			fail_from_lookahead(parser, .Close_String)
			return {}, false
		}

		if root == invalid_id {
			root = segment
		} else {
			span, span_ok := spanning(parser, parser.nodes.storage[int(root)].span, parser.nodes.storage[int(segment)].span)
			assert(span_ok)
			joined, joined_ok := append_node(parser, Node{
				form = .Binary,
				span = span,
				left = root,
				right = segment,
				binary_operator = .Add,
				operator_span = join_anchor,
				has_operator_span = true,
			})
			if !joined_ok do return {}, false
			root = joined
		}
	}

	full_start_span := open_span
	if has_format do full_start_span = format_span
	full_span, full_span_ok := spanning(parser, full_start_span, close_span)
	assert(full_span_ok)
	if root == invalid_id {
		full_start, _, offsets_ok := diagnostic.span_offsets(parser.source, full_span)
		assert(offsets_ok)
		empty, empty_ok := append_decoded_string_node(parser, "", full_span, full_start)
		if !empty_ok do return {}, false
		root = empty
	} else {
		parser.nodes.storage[int(root)].span = full_span
	}
	advance(parser)
	return root, true
}

@(private="package")
append_decoded_string_node :: proc(
	parser: ^Parser,
	contents: string,
	span: diagnostic.Span,
	contents_start: int,
) -> (Node_Id, bool) {
	sizing := decoded_string_size(contents)
	if sizing.kind == .Size_Overflow {
		fail_resource(parser, .Out_Of_Memory)
		return {}, false
	}
	if sizing.kind == .Invalid {
		error_span, span_ok := diagnostic.make_span(
			parser.source,
			contents_start+sizing.error_offset,
			contents_start+sizing.error_offset+1,
		)
		assert(span_ok)
		fail_string(parser, error_span, sizing.error_message)
		return {}, false
	}
	decoded_count, narrow_ok := narrow_decoded_string_size(sizing.decoded_bytes)
	if !narrow_ok {
		fail_resource(parser, .Out_Of_Memory)
		return {}, false
	}

	allocation_size := decoded_count
	if allocation_size == 0 {
		// Empty strings still receive independent parser-owned backing.
		allocation_size = 1
	}
	memory, allocation_error := runtime.mem_alloc_bytes(allocation_size, 1, parser.allocator)
	if allocation_error != nil || len(memory) != allocation_size || raw_data(memory) == nil {
		resource_error := allocation_error
		if resource_error == nil {
			resource_error = .Out_Of_Memory
		}
		if raw_data(memory) != nil {
			free_error := runtime.mem_free_bytes(memory, parser.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				parser.pending_string_text = memory
				resource_error = free_error
			}
		}
		fail_resource(parser, resource_error)
		return {}, false
	}

	decoded := memory[:decoded_count]
	decode_string(contents, decoded)
	registry_error := append_fallible_buffer(
		&parser.string_allocations,
		String_Allocation{memory = memory},
	)
	if registry_error != nil {
		free_error := runtime.mem_free_bytes(memory, parser.allocator)
		resource_error := registry_error
		if free_error != nil && free_error != .Mode_Not_Implemented {
			parser.pending_string_text = memory
			resource_error = free_error
		}
		fail_resource(parser, resource_error)
		return {}, false
	}

	node, node_ok := append_node(parser, Node{
		kind = .String,
		span = span,
		string_text = string(decoded),
		has_string_text = true,
	})
	if !node_ok {
		return {}, false
	}
	return node, true
}

@(private="package")
Decoded_String_Size_Kind :: enum {
	Success,
	Invalid,
	Size_Overflow,
}

@(private="package")
Decoded_String_Size :: struct {
	kind:          Decoded_String_Size_Kind,
	decoded_bytes: u64,
	error_offset:  int,
	error_message: string,
}

@(private="package")
decoded_string_source_size_fits :: proc(source_bytes: u64) -> bool {
	return source_bytes <= u64(max(int))
}

@(private="package")
checked_decoded_string_size_add :: proc(
	total: ^u64,
	unit_count, encoded_bytes_per_unit: u64,
) -> bool {
	limit := u64(max(int))
	if encoded_bytes_per_unit != 0 && unit_count > limit/encoded_bytes_per_unit {
		return false
	}
	increment := unit_count*encoded_bytes_per_unit
	if total^ > limit-increment {
		return false
	}
	total^ += increment
	return true
}

@(private="package")
narrow_decoded_string_size :: proc(decoded_bytes: u64) -> (int, bool) {
	if decoded_bytes > u64(max(int)) {
		return 0, false
	}
	return int(decoded_bytes), true
}

@(private="package")
decoded_string_size :: proc(contents: string) -> Decoded_String_Size {
	if !decoded_string_source_size_fits(u64(len(contents))) {
		return Decoded_String_Size{kind = .Size_Overflow}
	}
	decoded_count: u64
	index := 0
	for index < len(contents) {
		byte := contents[index]
		if byte == '\\' {
			if index+1 >= len(contents) {
				return Decoded_String_Size{
					kind = .Invalid,
					error_offset = index,
					error_message = "Expected escape character at end of string",
				}
			}
			escape := contents[index+1]
			switch escape {
			case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
				if !checked_decoded_string_size_add(&decoded_count, 1, 1) {
					return Decoded_String_Size{kind = .Size_Overflow}
				}
				index += 2
			case 'u':
				codepoint, ok := parse_unicode_escape(contents, index)
				if !ok {
					return Decoded_String_Size{
						kind = .Invalid,
						error_offset = index,
						error_message = "Invalid \\uXXXX escape",
					}
				}
				index += 6
				if codepoint >= 0xd800 && codepoint <= 0xdbff {
					low, low_ok := parse_unicode_escape(contents, index)
					if !low_ok || low < 0xdc00 || low > 0xdfff {
						return Decoded_String_Size{
							kind = .Invalid,
							error_offset = index-6,
							error_message = "Invalid \\uXXXX\\uXXXX surrogate pair escape",
						}
					}
					codepoint = 0x10000 + ((codepoint-0xd800)<<10) + (low-0xdc00)
					index += 6
				} else if codepoint >= 0xdc00 && codepoint <= 0xdfff {
					// jq's JSON decoder first emits the surrogate encoding, then
					// jv_string_sized replaces that invalid UTF-8 point with U+FFFD.
					codepoint = 0xfffd
				}
				if !checked_decoded_string_size_add(
					&decoded_count,
					1,
					u64(utf8_encoded_size(codepoint)),
				) {
					return Decoded_String_Size{kind = .Size_Overflow}
				}
			case:
				return Decoded_String_Size{
					kind = .Invalid,
					error_offset = index,
					error_message = "Invalid escape",
				}
			}
			continue
		}
		source_width, codepoint, utf8_ok := utf8_decode_unit(contents, index)
		encoded_width := u64(utf8_encoded_size(codepoint)) if utf8_ok else u64(3)
		if !checked_decoded_string_size_add(&decoded_count, 1, encoded_width) {
			return Decoded_String_Size{kind = .Size_Overflow}
		}
		index += source_width
	}
	return Decoded_String_Size{kind = .Success, decoded_bytes = decoded_count}
}

@(private="package")
decode_string :: proc(contents: string, output: []byte) {
	in_at, out_at := 0, 0
	for in_at < len(contents) {
		if contents[in_at] != '\\' {
			source_width, _, ok := utf8_decode_unit(contents, in_at)
			if ok {
				copy(output[out_at:out_at+source_width], contents[in_at:in_at+source_width])
				out_at += source_width
			} else {
				out_at += encode_utf8(0xfffd, output[out_at:])
			}
			in_at += source_width
			continue
		}
		escape := contents[in_at+1]
		switch escape {
		case '"', '\\', '/': output[out_at] = escape
		case 'b': output[out_at] = '\b'
		case 'f': output[out_at] = '\f'
		case 'n': output[out_at] = '\n'
		case 'r': output[out_at] = '\r'
		case 't': output[out_at] = '\t'
		case 'u':
			codepoint, ok := parse_unicode_escape(contents, in_at)
			assert(ok)
			in_at += 4
			if codepoint >= 0xd800 && codepoint <= 0xdbff {
				low, low_ok := parse_unicode_escape(contents, in_at+2)
				assert(low_ok)
				codepoint = 0x10000 + ((codepoint-0xd800)<<10) + (low-0xdc00)
				in_at += 6
			} else if codepoint >= 0xdc00 && codepoint <= 0xdfff {
				codepoint = 0xfffd
			}
			out_at += encode_utf8(codepoint, output[out_at:]) - 1
		}
		in_at += 2
		out_at += 1
	}
	assert(out_at == len(output))
}

@(private="package")
utf8_decode_unit :: proc(text: string, at: int) -> (int, u32, bool) {
	first := text[at]
	if first < 0x80 {
		return 1, u32(first), true
	}
	continuation := proc(byte: u8) -> bool { return byte >= 0x80 && byte <= 0xbf }
	width := 1
	codepoint := u32(0)
	minimum := u32(0)
	if first >= 0xc2 && first <= 0xdf {
		width, codepoint, minimum = 2, u32(first&0x1f), 0x80
	} else if first >= 0xe0 && first <= 0xef {
		width, codepoint, minimum = 3, u32(first&0x0f), 0x800
	} else if first >= 0xf0 && first <= 0xf4 {
		width, codepoint, minimum = 4, u32(first&0x07), 0x10000
	} else {
		return 1, 0, false
	}
	if at+width > len(text) {
		return len(text)-at, 0, false
	}
	for offset in 1..<width {
		byte := text[at+offset]
		if !continuation(byte) {
			return offset, 0, false
		}
		codepoint = (codepoint<<6) | u32(byte&0x3f)
	}
	if codepoint < minimum ||
	   (codepoint >= 0xd800 && codepoint <= 0xdfff) ||
	   codepoint > 0x10ffff {
		return width, 0, false
	}
	return width, codepoint, true
}

@(private="package")
utf8_encoded_size :: proc(codepoint: u32) -> int {
	if codepoint <= 0x7f do return 1
	if codepoint <= 0x7ff do return 2
	if codepoint <= 0xffff do return 3
	return 4
}

@(private="package")
encode_utf8 :: proc(codepoint: u32, output: []byte) -> int {
	width := utf8_encoded_size(codepoint)
	assert(len(output) >= width)
	switch width {
	case 1:
		output[0] = u8(codepoint)
	case 2:
		output[0] = 0xc0 | u8(codepoint>>6)
		output[1] = 0x80 | u8(codepoint&0x3f)
	case 3:
		output[0] = 0xe0 | u8(codepoint>>12)
		output[1] = 0x80 | u8((codepoint>>6)&0x3f)
		output[2] = 0x80 | u8(codepoint&0x3f)
	case 4:
		output[0] = 0xf0 | u8(codepoint>>18)
		output[1] = 0x80 | u8((codepoint>>12)&0x3f)
		output[2] = 0x80 | u8((codepoint>>6)&0x3f)
		output[3] = 0x80 | u8(codepoint&0x3f)
	}
	return width
}

@(private="package")
token_spelling :: proc(parser: ^Parser, token: Token) -> string {
	start, end, ok := diagnostic.span_offsets(parser.source, token.span)
	assert(ok)
	return diagnostic.source_bytes(parser.source)[start:end]
}

@(private="package")
append_postfix :: proc(
	parser: ^Parser,
	initial: Node_Id,
	live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead: int,
	has_postfix: ^bool,
) -> (Node_Id, bool) {
	node := initial
	ok: bool
	for token_is(parser, .Question) || token_is(parser, .Field) || token_is(parser, .Open_Bracket) || token_is(parser, .String_Start) || token_is(parser, .Dot) {
		dotted_bracket := false
		if token_is(parser, .Dot) {
			advance(parser)
			if token_is(parser, .Open_Bracket) {
				dotted_bracket = true
			} else if !token_is(parser, .String_Start) {
				// Preserve jq's existing standalone-dot diagnostic boundary:
				// the dot is consumed before a non-quoted suffix is reported.
				fail_from_lookahead(parser, .End_Of_Input)
				return {}, false
			}
		}
		if token_is(parser, .String_Start) {
			quoted, quoted_ok := append_string_node(parser, parser.lookahead.token.span, live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead, has_postfix^)
			if !quoted_ok do return {}, false
			quoted_node := parser.nodes.storage[int(quoted)]
			if quoted_node.kind != .String || !quoted_node.has_string_text do return {}, false
			span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, quoted_node.span)
			assert(span_ok)
			node, ok = append_node(parser, Node{
				kind = .Field,
				span = span,
				child = node,
				has_child = true,
				name_span = quoted_node.span,
				has_name_span = true,
				string_text = quoted_node.string_text,
				has_string_text = true,
				string_shorthand = true,
			})
			if !ok do return {}, false
			continue
		}
		// The canonical reduction slice uses `.[]`.  Preserve it as the
		// identity term for now; Reduce's evaluator consumes the input array
		// directly, while this parser acceptance keeps the source shape intact.
		if token_is(parser, .Open_Bracket) || dotted_bracket {
			open := parser.lookahead.token
			advance(parser)
			if token_is(parser, .String_Start) {
				quoted, quoted_ok := append_string_node(parser, parser.lookahead.token.span, live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead, has_postfix^)
				if !quoted_ok do return {}, false
				quoted_node := parser.nodes.storage[int(quoted)]
				if quoted_node.kind != .String || !quoted_node.has_string_text do return {}, false
				if !token_is(parser, .Close_Bracket) {
					fail_from_lookahead(parser, .Close_Bracket)
					return {}, false
				}
				close := parser.lookahead.token
				advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
				assert(span_ok)
				node, ok = append_node(parser, Node{
					kind = .Field,
					span = span,
					child = node,
					has_child = true,
					name_span = quoted_node.span,
					has_name_span = true,
					string_text = quoted_node.string_text,
					has_string_text = true,
					string_shorthand = true,
				})
				if !ok do return {}, false
				continue
			}
			if token_is(parser, .Close_Bracket) {
				close := parser.lookahead.token
				advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
				assert(span_ok)
				empty_at, _, empty_ok := diagnostic.span_offsets(parser.source, close.span)
				assert(empty_ok)
				empty_name, empty_name_ok := diagnostic.make_span(parser.source, empty_at, empty_at)
				assert(empty_name_ok)
				node, ok = append_node(parser, Node{
					kind = .Field,
					span = span,
					child = node,
					has_child = true,
					name_span = empty_name,
					has_name_span = true,
				})
				if !ok do return {}, false
				_ = open
				continue
			}
			negative_index := false
			negative_span := diagnostic.Span{}
			if token_is(parser, .Minus) {
				negative_span = parser.lookahead.token.span
				advance(parser)
				negative_index = true
			}
			// Numeric read-only slices use the same postfix brackets as indexes.
			if token_is(parser, .Colon) {
				advance(parser)
				start_index := Node_Id(-1)
				end_index := Node_Id(-1)
				if !token_is(parser, .Close_Bracket) {
					end_negative := false
					end_span := diagnostic.Span{}
					if token_is(parser, .Minus) { end_span = parser.lookahead.token.span; advance(parser); end_negative = true }
					if token_is(parser, .Number) || (token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "nan") {
						end_number_span := parser.lookahead.token.span
						if end_negative { end_number_span, _ = spanning(parser, end_span, end_number_span) }
						end_index, ok = append_number_node(parser, end_number_span)
						if !ok do return {}, false
						advance(parser)
					} else {
						if end_negative { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
						end_index, ok = parse_pipe(parser, .Close_Bracket, false)
						if !ok do return {}, false
					}
				}
				if !token_is(parser, .Close_Bracket) { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
				close := parser.lookahead.token; advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span); assert(span_ok)
				new_term, slice_ok := append_node(parser, Node{kind=.Slice, span=span, child=node, has_child=true, left=start_index, right=end_index})
				if !slice_ok do return {}, false
				node = new_term
				continue
			}
			// Dynamic start bounds (for example `[.:1]`) are filters evaluated
			// against the pre-slice input.  Keep the filter as an instruction
			// operand while retaining the ordinary numeric end lowering.
			if token_is(parser, .Dot) || token_is(parser, .Open_Paren) || (token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "length") {
				start_filter, filter_ok := parse_pipe(parser, .Colon, false)
				if filter_ok && token_is(parser, .Colon) {
					advance(parser)
					end_index := Node_Id(-1)
					if !token_is(parser, .Close_Bracket) {
						if token_is(parser, .Number) || (token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "nan") {
							end_index, filter_ok = append_number_node(parser, parser.lookahead.token.span)
							if !filter_ok do return {}, false
							advance(parser)
						} else {
							end_index, filter_ok = parse_pipe(parser, .Close_Bracket, false)
							if !filter_ok do return {}, false
						}
					}
					if !token_is(parser, .Close_Bracket) { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
					close := parser.lookahead.token; advance(parser)
					span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span); assert(span_ok)
					new_term, slice_ok := append_node(parser, Node{kind=.Slice, span=span, child=node, has_child=true, left=start_filter, right=end_index})
					if !slice_ok do return {}, false
					node = new_term
					continue
				}
			}
			if !token_is(parser, .Number) && !(token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "nan") {
				key, key_ok := parse_pipe(parser, .Close_Bracket, false)
				if !key_ok || !token_is(parser, .Close_Bracket) {
					fail_from_lookahead(parser, .Close_Bracket)
					return {}, false
				}
				close := parser.lookahead.token
				advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
				assert(span_ok)
				node, ok = append_node(parser, Node{
					kind = .Index,
					span = span,
					child = node,
					has_child = true,
					index_key = key,
					has_index_key = true,
				})
				if !ok do return {}, false
				continue
			}
			number_span := parser.lookahead.token.span
			index_span := number_span
			if negative_index {
				index_span, _ = spanning(parser, negative_span, number_span)
			}
			index_node, index_ok := append_number_node(parser, index_span)
			if !index_ok do return {}, false
			advance(parser)
			if token_is(parser, .Colon) {
				advance(parser)
				end_index := Node_Id(-1)
				if !token_is(parser, .Close_Bracket) {
					end_negative := false
					end_span := diagnostic.Span{}
					if token_is(parser, .Minus) { end_span = parser.lookahead.token.span; advance(parser); end_negative = true }
					if token_is(parser, .Number) || (token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "nan") {
						end_number_span := parser.lookahead.token.span
						if end_negative { end_number_span, _ = spanning(parser, end_span, end_number_span) }
						end_index, ok = append_number_node(parser, end_number_span)
						if !ok do return {}, false
						advance(parser)
					} else {
						if end_negative { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
						end_index, ok = parse_pipe(parser, .Close_Bracket, false)
						if !ok do return {}, false
					}
				}
				if !token_is(parser, .Close_Bracket) { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
				close := parser.lookahead.token; advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span); assert(span_ok)
				new_term, slice_ok := append_node(parser, Node{kind=.Slice, span=span, child=node, has_child=true, left=index_node, right=end_index})
				if !slice_ok do return {}, false
				node = new_term
				continue
			}
			// Reuse the allocated number node as the index node. Its owned
			// spelling remains valid for the parser lifetime and is copied by
			// the compiler into Program text storage.
			stored := &parser.nodes.storage[int(index_node)]
			stored.kind = .Index
			stored.span = index_span
			stored.child = node
			stored.has_child = true
			sequence := index_node
			for token_is(parser, .Comma) {
				advance(parser)
				next_negative := false
				next_negative_span := diagnostic.Span{}
				if token_is(parser, .Minus) {
					next_negative_span = parser.lookahead.token.span
					advance(parser)
					next_negative = true
				}
				if !token_is(parser, .Number) {
					fail_from_lookahead(parser, .Close_Bracket)
					return {}, false
				}
				next_number_span := parser.lookahead.token.span
				next_index_span := next_number_span
				if next_negative {
					next_index_span, _ = spanning(parser, next_negative_span, next_number_span)
				}
				next_index, next_ok := append_number_node(parser, next_index_span)
				if !next_ok do return {}, false
				advance(parser)
				next_stored := &parser.nodes.storage[int(next_index)]
				next_stored.kind = .Index
				next_stored.span = next_index_span
				next_stored.child = node
				next_stored.has_child = true
				sequence_span, sequence_span_ok := spanning(parser,
					parser.nodes.storage[int(sequence)].span,
					next_index_span,
				)
				assert(sequence_span_ok)
				sequence_ok: bool
				sequence, sequence_ok = append_node(parser, Node{
					kind = .Comma,
					span = sequence_span,
					left = sequence,
					right = next_index,
					has_child = false,
				})
				if !sequence_ok do return {}, false
			}
			if !token_is(parser, .Close_Bracket) {
				fail_from_lookahead(parser, .Close_Bracket)
				return {}, false
			}
			close := parser.lookahead.token
			advance(parser)
			span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
			assert(span_ok)
			parser.nodes.storage[int(sequence)].span = span
			node = sequence
			_ = open
			continue
		}
		if !has_postfix^ {
			has_postfix^ = true
			if parser_stack_budget_exhausted(parser,
				live_prefix_depth,
				live_pipe_count,
				live_comma_count,
				live_binary_count,
				event_overhead,
				has_postfix^,
			) {
				fail_resource(parser, .Out_Of_Memory)
				return {}, false
			}
		}
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

// literal_call_sequence lowers comma-separated literal arguments into a
// normal comma sequence of single-argument builtin nodes. This preserves each
// evaluator's existing ownership contract while covering bounded variadic
// literal forms; dynamic arguments remain deferred.
literal_call_sequence :: proc(parser: ^Parser, node_id: Node_Id, call_kind: Node_Kind) -> (Node_Id, bool) {
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Comma && !node.has_child {
		left, left_ok := literal_call_sequence(parser, node.left, call_kind)
		right, right_ok := literal_call_sequence(parser, node.right, call_kind)
		if !left_ok || !right_ok { return {}, false }
		combined, combined_ok := append_node(parser, Node{kind=.Comma, span=node.span, left=left, right=right})
		return combined, combined_ok
	}
	if node.has_child || node.has_value { return {}, false }
	if call_kind == .Bsearch && node.kind != .Number { return {}, false }
	if call_kind == .Join && node.kind != .String { return {}, false }
	if (call_kind == .Flatten || call_kind == .Range) && node.kind != .Number { return {}, false }
	if (call_kind == .Index_Builtin || call_kind == .Rindex_Builtin || call_kind == .Indices_Builtin) && node.kind != .String && node.kind != .Number { return {}, false }
	if call_kind == .Range {
		needle, needle_ok := append_node(parser, Node{kind=call_kind, span=node.span, left=node_id, right=Node_Id(-1)})
		return needle, needle_ok
	}
	needle, needle_ok := append_node(parser, Node{kind=call_kind, span=node.span, child=node_id, has_child=true})
	return needle, needle_ok
}

// range_literal_cartesian expands comma-separated literal range arguments
// into the ordered Cartesian stream jq produces. Dynamic arguments remain
// outside this bounded parser slice.
range_literal_cartesian :: proc(parser: ^Parser, first, second, third: Node_Id, has_third: bool) -> (Node_Id, bool) {
	first_node := parser.nodes.storage[int(first)]
	if first_node.kind == .Comma {
		left, left_ok := range_literal_cartesian(parser, first_node.left, second, third, has_third)
		right, right_ok := range_literal_cartesian(parser, first_node.right, second, third, has_third)
		if !left_ok || !right_ok { return {}, false }
		combined, ok := append_node(parser, Node{kind=.Comma, span=first_node.span, left=left, right=right})
		return combined, ok
	}
	second_node := parser.nodes.storage[int(second)]
	if second_node.kind == .Comma {
		left, left_ok := range_literal_cartesian(parser, first, second_node.left, third, has_third)
		right, right_ok := range_literal_cartesian(parser, first, second_node.right, third, has_third)
		if !left_ok || !right_ok { return {}, false }
		combined, ok := append_node(parser, Node{kind=.Comma, span=second_node.span, left=left, right=right})
		return combined, ok
	}
	if has_third {
		third_node := parser.nodes.storage[int(third)]
		if third_node.kind == .Comma {
			left, left_ok := range_literal_cartesian(parser, first, second, third_node.left, true)
			right, right_ok := range_literal_cartesian(parser, first, second, third_node.right, true)
			if !left_ok || !right_ok { return {}, false }
			combined, ok := append_node(parser, Node{kind=.Comma, span=third_node.span, left=left, right=right})
			return combined, ok
		}
	}
	candidates := [3]Node_Id{first, second, third}
	for candidate_index in 0..<3 {
		if !has_third && candidate_index == 2 { continue }
		candidate := candidates[candidate_index]
		node := parser.nodes.storage[int(candidate)]
		if node.has_value || (node.kind != .Number && !(node.kind == .Negate && node.has_child)) { return {}, false }
	}
	span, span_ok := spanning(parser, parser.nodes.storage[int(first)].span, parser.nodes.storage[int(second)].span)
	if !span_ok { return {}, false }
	range_node, ok := append_node(parser, Node{kind=.Range, span=span, left=first, right=second, reduce_update=third, has_reduce_update=has_third})
	return range_node, ok
}

@(private)
range_numeric_bound_node :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
	node := parser.nodes.storage[int(node_id)]
	if node.has_value { return false }
	if node.kind == .Number || (node.kind == .Identity && !node.has_child && node.container_kind == .None) { return true }
	if node.kind == .Negate && node.has_child {
		child := parser.nodes.storage[int(node.child)]
		return child.kind == .Number && !child.has_child && !child.has_value
	}
	if node.form == .Binary && node.has_child {
		return node.binary_operator == .Add || node.binary_operator == .Subtract || node.binary_operator == .Multiply || node.binary_operator == .Divide || node.binary_operator == .Modulo
	}
	return false
}

literal_numeric_sequence :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Comma {
		left, left_ok := literal_numeric_sequence(parser, node.left)
		right, right_ok := literal_numeric_sequence(parser, node.right)
		if !left_ok || !right_ok { return {}, false }
		return append_node(parser, Node{kind=.Comma, span=node.span, left=left, right=right})
	}
	if node.has_child || node.has_value || (node.kind != .Number && !(node.kind == .Negate && node.has_child)) { return {}, false }
	return node_id, true
}

// lower_static_del_paths converts the bounded static path grammar accepted by
// `del(...)` into the existing Delpaths literal-array ABI.  Each inner Array
// is one path; a top-level comma becomes the outer array's stream of paths.
// Dynamic filters and computed indexes deliberately remain rejected until the
// general path continuation contract exists; literal root slices are grouped
// here for the evaluator's coordinate-mask continuation.
@(private="package")
lower_static_del_filter :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	invalid := Node_Id(-1)
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return invalid, false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return lower_static_del_filter(parser, node.child)
	if node.kind == .Comma {
		// Keep scalar-only comma selectors on their legacy sequential lowering.
		// Once a literal slice is present, retain all selectors in one Delpaths
		// operand so the evaluator can resolve them against one immutable input.
		if static_del_selector_has_slice(parser, node_id) {
			paths, paths_ok := lower_static_del_group_paths(parser, node_id)
			if !paths_ok do return invalid, false
			grouped, grouped_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=paths, has_value=true})
			if !grouped_ok do return invalid, false
			return append_node(parser, Node{kind=.Delpaths, span=node.span, child=grouped, has_child=true})
		}
		left, left_ok := lower_static_del_filter(parser, node.left)
		right, right_ok := lower_static_del_filter(parser, node.right)
		if !left_ok || !right_ok do return invalid, false
		sequence, sequence_ok := append_node(parser, Node{kind=.Pipe, span=node.span, left=left, right=right})
		if !sequence_ok do return invalid, false
		return sequence, true
	}
	paths, paths_ok := lower_static_del_paths(parser, node_id)
	if !paths_ok do return invalid, false
	return append_node(parser, Node{kind=.Delpaths, span=node.span, child=paths, has_child=true})
}

// static_del_selector_has_slice identifies the bounded grammar that must stay
// grouped. It deliberately does not inspect arbitrary filter expressions.
static_del_selector_has_slice :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return static_del_selector_has_slice(parser, node.child)
	if node.kind == .Comma do return static_del_selector_has_slice(parser, node.left) || static_del_selector_has_slice(parser, node.right)
	return node.kind == .Slice
}

// lower_static_del_group_paths flattens selector commas into the existing
// outer-array stream of path arrays, without introducing a new AST or opcode.
lower_static_del_group_paths :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	invalid := Node_Id(-1)
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return invalid, false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return lower_static_del_group_paths(parser, node.child)
	if node.kind == .Comma {
		left, left_ok := lower_static_del_group_paths(parser, node.left)
		right, right_ok := lower_static_del_group_paths(parser, node.right)
		if !left_ok || !right_ok do return invalid, false
		span, span_ok := spanning(parser, parser.nodes.storage[int(left)].span, parser.nodes.storage[int(right)].span)
		assert(span_ok)
		return append_node(parser, Node{kind=.Comma, span=span, left=left, right=right})
	}
	wrapped, wrapped_ok := lower_static_del_paths(parser, node_id)
	if !wrapped_ok do return invalid, false
	wrapped_node := parser.nodes.storage[int(wrapped)]
	if !wrapped_node.has_value do return invalid, false
	return wrapped_node.value, true
}

lower_static_del_paths :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	invalid := Node_Id(-1)
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return invalid, false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return lower_static_del_paths(parser, node.child)
	if node.kind == .Comma {
		return invalid, false
	}
	components := node_id
	if node.kind == .Slice {
		// Only root array slices are in this bounded parser contract. Bounds
		// may be omitted, but present bounds must be numeric literals.
		if !node.has_child || !static_del_slice_bound(parser, node.left) || !static_del_slice_bound(parser, node.right) do return invalid, false
		base_node := parser.nodes.storage[int(node.child)]
		if base_node.kind != .Identity || base_node.has_child || base_node.has_value do return invalid, false
	} else if node.kind == .Index {
		if !node.has_child || !node.has_number_text do return invalid, false
		component, component_ok := append_node(parser, Node{kind=.Number, span=node.span, number_text=node.number_text, has_number_text=true})
		if !component_ok do return invalid, false
		base_node := parser.nodes.storage[int(node.child)]
		if base_node.kind == .Identity && !base_node.has_child && !base_node.has_value {
			components = component
		} else {
			base, base_ok := lower_static_del_path_components(parser, node.child)
			if !base_ok do return invalid, false
			span, span_ok := spanning(parser, parser.nodes.storage[int(base)].span, node.span); assert(span_ok)
			component_list_ok: bool
			components, component_list_ok = append_node(parser, Node{kind=.Comma, span=span, left=base, right=component})
			if !component_list_ok do return invalid, false
		}
	} else if node.kind != .Field || node.has_child || !node.has_name_span {
		return invalid, false
	}
	inner, inner_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=components, has_value=true})
	if !inner_ok do return invalid, false
	return append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=inner, has_value=true})
}

static_del_slice_bound :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
	if int(node_id) < 0 do return true
	if int(node_id) >= parser.nodes.count do return false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Number && !node.has_child && !node.has_value && node.has_number_text do return node.number_text != "nan"
	if node.kind == .Negate && node.has_child && !node.has_value {
		child := parser.nodes.storage[int(node.child)]
		return child.kind == .Number && !child.has_child && !child.has_value && child.has_number_text && child.number_text != "nan"
	}
	return false
}

lower_static_del_path_components :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return {}, false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return lower_static_del_path_components(parser, node.child)
	if node.kind == .Field && !node.has_child && node.has_name_span do return node_id, true
	return {}, false
}

@(private="package")
scalar_literal_or_identity :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
	if parser == nil || int(node_id) < 0 || int(node_id) >= parser.nodes.count do return false
	node := parser.nodes.storage[int(node_id)]
	if node.form != .Kinded || node.has_child || node.has_value || node.container_kind != .None do return false
	#partial switch node.kind {
	case .Identity, .Null, .Boolean, .Number, .String:
		return true
	}
	return false
}

numeric_count_call_sequence :: proc(parser: ^Parser, counts, generator: Node_Id, kind: Node_Kind) -> (Node_Id, bool) {
	node := parser.nodes.storage[int(counts)]
	if node.kind == .Comma {
		left, left_ok := numeric_count_call_sequence(parser, node.left, generator, kind)
		right, right_ok := numeric_count_call_sequence(parser, node.right, generator, kind)
		if !left_ok || !right_ok { return {}, false }
		return append_node(parser, Node{kind=.Comma, span=node.span, left=left, right=right})
	}
	return append_node(parser, Node{kind=kind, span=node.span, left=counts, right=generator})
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
fail_string :: proc(parser: ^Parser, span: diagnostic.Span, message: string) {
	if parser.failed {
		return
	}
	parser.failed = true
	parser.failure = Parse_Outcome{
		kind = .Input_Error,
		error = Parse_Error{
			kind = .Lexical_Error,
			span = span,
			expected = .Close_String,
			message = message,
		},
	}
}

@(private="package")
fail_unterminated_string :: proc(parser: ^Parser, open_span: diagnostic.Span) {
	if parser.failed {
		return
	}
	parser.failed = true
	parser.failure = Parse_Outcome{
		kind = .Input_Error,
		error = Parse_Error{
			kind = .Unexpected_End,
			span = open_span,
			expected = .Close_String,
			message = "unterminated string literal",
		},
	}
}

@(private="package")
string_lexical_message :: proc(parser: ^Parser, span: diagnostic.Span) -> string {
	start, end, ok := diagnostic.span_offsets(parser.source, span)
	if !ok || end <= start {
		return "Invalid string literal"
	}
	text := diagnostic.source_bytes(parser.source)[start:end]
	index := 0
	for index < len(text) {
		if text[index] != '\\' {
			// This is defensive for a malformed scanner span. Raw string tokens,
			// including invalid UTF-8 units, are accepted and decoded separately.
			source_width, _, _ := utf8_decode_unit(text, index)
			index += source_width
			continue
		}
		if index+1 >= len(text) {
			// A lone reverse-solidus is an INVALID_CHARACTER lexer unit rather
			// than a grouped JSON escape candidate.
			return "Invalid escape"
		}
		switch text[index+1] {
		case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
			index += 2
		case 'u':
			if index+6 > len(text) {
				return "Invalid \\uXXXX escape"
			}
			codepoint, unicode_ok := parse_unicode_escape(text, index)
			if !unicode_ok {
				return "Invalid characters in \\uXXXX escape"
			}
			index += 6
			if codepoint >= 0xd800 && codepoint <= 0xdbff {
				low, low_ok := parse_unicode_escape(text, index)
				if !low_ok || low < 0xdc00 || low > 0xdfff {
					return "Invalid \\uXXXX\\uXXXX surrogate pair escape"
				}
				index += 6
			}
		case:
			return "Invalid escape"
		}
	}
	return "Invalid string literal"
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
					message = string_lexical_message(parser, parser.lookahead.error_span) if expected == .Close_String else "",
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
					message = "unterminated string literal" if expected == .Close_String else "",
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
