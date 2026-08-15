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
	// Sort_By_Key is an internal stable-key helper used by the bounded driver
	// lowering for static sort_by(.field). It compares only pair keys and keeps
	// input order for equal keys; general sort_by key streams remain separate.
	Sort_By_Key,
	// Group_By_Key is an internal stable-key grouping helper used by the
	// bounded parser lowering for static group_by(.field).
	Group_By_Key,
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
	Input,
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
	// Static_Iterator_Set_Number is a bounded `.[] = scalar` path update.
	Static_Iterator_Set_Number,
	// Static_Index_Set_Number is appended to preserve existing AST discriminants.
	Static_Index_Set_Number,
	// Static_Slice_Set_Number is a bounded literal-RHS slice assignment.
	Static_Slice_Set_Number,
	// Path, Paths, and Getpath are explicit path-expression nodes.
	Path,
	Paths,
	Getpath,
	Setpath,
	// Path_Assign updates every path emitted by a bounded path filter with a literal RHS.
	Path_Assign,
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
	// Static_Iterator_Delete is a bounded root `.[] |= empty` update.
	Static_Iterator_Delete,
	// Static_Field_Add_Field is a bounded `.name += .other` update.
	Static_Field_Add_Field,
	// Static_Field_Optional_Identity is a bounded `.name |= .?` update.
	Static_Field_Optional_Identity,
	// Static_Field_Delete is a bounded `.name |= empty` update.
	Static_Field_Delete,
	// Static_Field_Update is a resumable root `.name |= FILTER` update.
	Static_Field_Update,
	// Static_Field_Index_Update is a bounded `.name[index] |= FILTER` update.
	Static_Field_Index_Update,
	// Static_Index_Field_Update is a bounded `.[index].name |= FILTER` update.
	Static_Index_Field_Update,
	// Static_Field_Index_Field_Update is a bounded `.name[index].name |= FILTER` update.
	Static_Field_Index_Field_Update,
	// Static_Iterator_Update preserves a filter-valued root iterator RHS.
	Static_Iterator_Update,
	// Dynamic_Index_Assign captures one root instruction-valued index key.
	Dynamic_Index_Assign,
	// Parameter_Identity_Update is the bounded `x |= .` callable body.
	Parameter_Identity_Update,
}

Node_Id :: distinct int

// Definition records one top-level zero-argument declaration in source order.
// name_span borrows the Parser's Source; body points into the same parser-owned
// node arena. ordinal is stable for the lifetime of this parse and starts at 0.
Definition :: struct {
	name_span: diagnostic.Span,
	body:      Node_Id,
	ordinal:   u32,
	scope_depth: u32,
	parameter_span: diagnostic.Span,
	has_parameter: bool,
}

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
	base_name_span:    diagnostic.Span,
	has_base_name_span: bool,
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
	iterator_compound: bool,
	call_name_span: diagnostic.Span,
	has_call_name: bool,
	call_argument: Node_Id,
	has_call_argument: bool,
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

// Parser owns its scanner, flat AST arena, parse frames, definition table, and every Number node's
// exact source text. source is otherwise borrowed; frames, nodes, numeric text,
// and scanner state use allocator. A live Parser must remain at its initialized
// address and must not be copied. After parse_filter, only parser_nodes,
// parser_source, parser_definitions, and destroy_parser are valid.
Parser :: struct {
	source:              diagnostic.Source,
	scanner:             Scanner,
	nodes:               Fallible_Buffer(Node),
	frames:              Fallible_Buffer(Parse_Frame),
	number_allocations:  Fallible_Buffer(Number_Allocation),
	string_allocations:  Fallible_Buffer(String_Allocation),
	definitions:         Fallible_Buffer(Definition),
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
	definition_scope_depth: u32,
	definition_parameter: diagnostic.Span,
	has_definition_parameter: bool,
	failed:              bool,
	failure:             Parse_Outcome,
}

@(private="package")
parser_has_live_identity :: proc(parser: ^Parser) -> bool {
	return parser != nil && parser.self == parser
}

Pattern_Path_Segment :: struct {
	kind: enum {Field, Index, Dynamic},
	node: Node_Id,
	index: int,
}

Pattern_Leaf :: struct {
	variable: Node_Id,
	segments: [8]Pattern_Path_Segment,
	count: int,
}

// collect_pattern_leaves accepts the bounded ordinary-binding destructuring
// subset. It deliberately excludes filters and literals in pattern values;
// those remain the existing unsupported syntax rather than silently changing
// the Binding ABI.
collect_pattern_leaves :: proc(parser: ^Parser, id: Node_Id, path: [8]Pattern_Path_Segment, depth: int, leaves: ^[16]Pattern_Leaf, count: ^int) -> bool {
	if id < 0 || int(id) >= len(parser.nodes.storage) || depth > 8 || count^ >= 16 do return false
	node := parser.nodes.storage[int(id)]
	if node.kind == .Variable {
		leaf := Pattern_Leaf{variable=id, segments=path, count=depth}
		leaves[count^] = leaf; count^ += 1
		return true
	}
	if node.container_kind == .Array && node.has_value {
		entry := node.value; index := 0
		for {
			if entry < 0 || int(entry) >= len(parser.nodes.storage) do return false
			child := parser.nodes.storage[int(entry)]
			next_path := path
			if depth >= len(next_path) do return false
			next_path[depth] = Pattern_Path_Segment{kind=.Index, index=index}
			if !collect_pattern_leaves(parser, entry if child.kind != .Comma else child.left, next_path, depth+1, leaves, count) do return false
			if child.kind != .Comma do break
			entry = child.right; index += 1
		}
		return true
	}
	if node.container_kind == .Object && node.has_value {
		entry := node.value
		for entry >= 0 {
			if int(entry) >= len(parser.nodes.storage) do return false
			e := parser.nodes.storage[int(entry)]
			if e.kind != .Field || !e.has_key || !e.has_value do return false
			key := parser.nodes.storage[int(e.key)]
			kind: enum {Field, Index, Dynamic} = .Dynamic
			if key.kind == .Field && key.has_name_span { kind = .Field }
			else if key.kind == .Variable && key.has_name_span { kind = .Field }
			else if key.kind == .String { kind = .Field }
			if depth >= 8 do return false
			next_path := path
			next_path[depth] = Pattern_Path_Segment{kind=kind, node=e.key}
			if key.kind == .Variable {
				if count^ >= 16 do return false
				leaves[count^] = Pattern_Leaf{variable=e.key, segments=next_path, count=depth+1}; count^ += 1
			}
			if !collect_pattern_leaves(parser, e.value, next_path, depth+1, leaves, count) do return false
			entry = e.next if e.has_next else Node_Id(-1)
		}
		return true
	}
	return false
}

append_pattern_projection :: proc(parser: ^Parser, variable: Node_Id, leaf: Pattern_Leaf) -> (Node_Id, bool) {
	if variable < 0 || int(variable) >= len(parser.nodes.storage) do return {}, false
	base := parser.nodes.storage[int(variable)]
	current, ok := append_node(parser, Node{kind=.Variable, span=base.span, name_span=base.name_span, has_name_span=true})
	if !ok do return {}, false
	for segment_index in 0..<leaf.count {
		segment := leaf.segments[segment_index]
		if segment.kind == .Field {
			key := parser.nodes.storage[int(segment.node)]
			if key.kind == .String {
				current, ok = append_node(parser, Node{kind=.Field, span=key.span, child=current, has_child=true, name_span=key.span, has_name_span=true, string_text=key.string_text, has_string_text=true, string_shorthand=true})
			} else if key.kind == .Variable {
				current, ok = append_node(parser, Node{kind=.Field, span=key.span, child=current, has_child=true, name_span=key.name_span, has_name_span=true})
			} else {
				current, ok = append_node(parser, Node{kind=.Field, span=key.span, child=current, has_child=true, name_span=key.name_span, has_name_span=true})
			}
		} else {
			span := parser.nodes.storage[int(segment.node)].span if segment.node >= 0 && int(segment.node) < len(parser.nodes.storage) else base.span
			if segment.kind == .Index {
				index_text := "0"
				switch segment.index {
				case 1: index_text = "1"
				case 2: index_text = "2"
				case 3: index_text = "3"
				case 4: index_text = "4"
				case 5: index_text = "5"
				case 6: index_text = "6"
				case 7: index_text = "7"
				}
				current, ok = append_node(parser, Node{kind=.Index, span=span, child=current, has_child=true, number_text=index_text, has_number_text=true})
			} else {
				current, ok = append_node(parser, Node{kind=.Index, span=span, child=current, has_child=true, index_key=segment.node, has_index_key=true})
			}
		}
		if !ok do return {}, false
	}
	return current, true
}

try_parse_ordinary_pattern_binding :: proc(parser: ^Parser, left, pattern, pipe_root, pipe_tail: Node_Id, closing: Token_Kind, stop_at_comma: bool) -> (Node_Id, bool) {
	if !token_is(parser, .Pipe) do return {}, false
	path: [8]Pattern_Path_Segment
	leaves: [16]Pattern_Leaf
	count := 0
	if !collect_pattern_leaves(parser, pattern, path, 0, &leaves, &count) || count == 0 {
		return {}, false
	}
	advance(parser)
	body, body_ok := parse_pipe(parser, closing, stop_at_comma)
	if !body_ok do return {}, false
	nested := body
	first := parser.nodes.storage[int(leaves[0].variable)]
	for index := 0; index < count; index += 1 {
		projection, projection_ok := append_pattern_projection(parser, leaves[0].variable, leaves[index])
		if !projection_ok do return {}, false
		variable := parser.nodes.storage[int(leaves[index].variable)]
		span, span_ok := spanning(parser, parser.nodes.storage[int(projection)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
		bound, bound_ok := append_node(parser, Node{kind=.Binding, span=span, left=projection, right=nested, name_span=variable.name_span, has_name_span=true})
		if !bound_ok do return {}, false
		nested = bound
	}
	span, span_ok := spanning(parser, parser.nodes.storage[int(left)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
	bound, bound_ok := append_node(parser, Node{kind=.Binding, span=span, left=left, right=nested, name_span=first.name_span, has_name_span=true})
	if !bound_ok do return {}, false
	if pipe_root != Node_Id(-1) {
		tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = bound; tail.has_child = false
		return pipe_root, true
	}
	return bound, true
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
	init_fallible_buffer(&parser.definitions, allocator)
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
	for token_is(parser, .Def) {
		advance(parser)
		if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Identifier {
			fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure
		}
		name := parser.lookahead.token
		advance(parser)
		parameter := diagnostic.Span{}
		has_parameter := false
		if token_is(parser, .Open_Paren) {
			advance(parser)
			if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Identifier {
				fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure
			}
			parameter = parser.lookahead.token.span
			has_parameter = true
			advance(parser)
			if !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); parser.state = .Finished; return parser.failure }
			advance(parser)
		}
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
		parser.definition_parameter = parameter
		parser.has_definition_parameter = has_parameter
		body, body_ok := parse_pipe(parser, .Semicolon, false)
		if !body_ok || !token_is(parser, .Semicolon) { fail_from_lookahead(parser, .Expression); parser.state = .Finished; return parser.failure }
		parser.definition_body = body
		for i in 0..<parser.nodes.count {
			if parser.nodes.storage[i].kind == .Call && parser.nodes.storage[i].child < 0 {
				parser.nodes.storage[i].child = body
				parser.nodes.storage[i].has_child = true
			}
		}
		definition_error := append_fallible_buffer(&parser.definitions, Definition{
			name_span = name.span,
			body = body,
			ordinal = u32(parser.definitions.count),
			scope_depth = parser.definition_scope_depth,
			parameter_span = parameter,
			has_parameter = has_parameter,
		})
		if definition_error != nil {
			fail_resource(parser, definition_error)
			parser.state = .Finished
			return parser.failure
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

// parser_definitions returns ordered top-level zero-argument declarations.
// Names borrow parser_source and bodies index parser_nodes; both expire when
// destruction begins.
parser_definitions :: proc(parser: ^Parser) -> []Definition {
	if !parser_has_live_identity(parser) || parser.state != .Finished {
		return nil
	}
	assert(parser.self == parser)
	assert(parser.state == .Finished)
	return fallible_buffer_view(&parser.definitions)
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
	if parser.definitions.state != .Empty {
		definitions_error := destroy_fallible_buffer(&parser.definitions)
		if definitions_error != nil {
			parser.state = .Cleanup_Failed
			return definitions_error
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

@(private="package")
definition_name_matches :: proc(parser: ^Parser, span: diagnostic.Span, spelling: string) -> bool {
	start, end, ok := diagnostic.span_offsets(parser.source, span)
	if !ok || end < start do return false
	bytes := diagnostic.source_bytes(parser.source)
	return bytes[start:end] == spelling
}

// visible_definition returns the latest declaration already visible at the
// current source position. A declaration being parsed is represented by an
// unresolved body edge so recursive calls can be patched after its body root
// is known; forward references therefore remain ordinary unknown identifiers.
visible_definition :: proc(parser: ^Parser, spelling: string) -> (Node_Id, bool, bool) {
	if parser.has_definition && parser.definition_body < 0 &&
	   definition_name_matches(parser, parser.definition_name, spelling) {
		return Node_Id(-1), true, parser.has_definition_parameter
	}
	for count := parser.definitions.count; count > 0; {
		count -= 1
		definition := parser.definitions.storage[count]
		if definition.scope_depth > parser.definition_scope_depth do continue
		if definition_name_matches(parser, definition.name_span, spelling) {
			return definition.body, true, definition.has_parameter
		}
	}
	return {}, false, false
}

// parse_nested_definition handles jq's query-local zero-argument definitions.
// The generated Call edges already carry immutable body roots, so this phase
// only needs to maintain lexical visibility while parsing the declaration and
// its following query. Nested declarations are recorded with their scope depth
// and become invisible when the enclosing query resumes.
@(private="package")
parse_nested_definition :: proc(
	parser: ^Parser,
	closing: Token_Kind,
	stop_at_comma: bool,
	stop_at_catch: bool,
	stop_at_binary: bool,
	stop_at_pipe: bool,
	stop_at_defined_or: bool,
) -> (Node_Id, bool) {
	if !token_is(parser, .Def) do return {}, false
	advance(parser)
	if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Identifier {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	name := parser.lookahead.token
	advance(parser)
	parameter := diagnostic.Span{}
	has_parameter := false
	if token_is(parser, .Open_Paren) {
		advance(parser)
		if parser.lookahead.kind != .Token || parser.lookahead.token.kind != .Identifier { fail_from_lookahead(parser, .Expression); return {}, false }
		parameter = parser.lookahead.token.span
		has_parameter = true
		advance(parser)
		if !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
		advance(parser)
	}
	if !token_is(parser, .Colon) {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	advance(parser)

	previous_name := parser.definition_name
	previous_has := parser.has_definition
	previous_body := parser.definition_body
	previous_depth := parser.definition_scope_depth
	previous_parameter := parser.definition_parameter
	previous_has_parameter := parser.has_definition_parameter
	parser.definition_scope_depth = previous_depth + 1
	parser.definition_name = name.span
	parser.has_definition = true
	parser.definition_body = Node_Id(-1)
	parser.definition_parameter = parameter
	parser.has_definition_parameter = has_parameter
	start_node := parser.nodes.count
	body, body_ok := parse_pipe(parser, .Semicolon, false)
	if !body_ok || !token_is(parser, .Semicolon) {
		parser.definition_name = previous_name
		parser.has_definition = previous_has
		parser.definition_body = previous_body
		parser.definition_scope_depth = previous_depth
		parser.definition_parameter = previous_parameter
		parser.has_definition_parameter = previous_has_parameter
		if !body_ok { return {}, false }
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	parser.definition_body = body
	for i in start_node..<parser.nodes.count {
		if parser.nodes.storage[i].kind == .Call && parser.nodes.storage[i].child < 0 {
			parser.nodes.storage[i].child = body
			parser.nodes.storage[i].has_child = true
		}
	}
	definition_error := append_fallible_buffer(&parser.definitions, Definition{
		name_span = name.span,
		body = body,
		ordinal = u32(parser.definitions.count),
		scope_depth = parser.definition_scope_depth,
		parameter_span = parameter,
		has_parameter = has_parameter,
	})
	if definition_error != nil {
		fail_resource(parser, definition_error)
		parser.definition_name = previous_name
		parser.has_definition = previous_has
		parser.definition_body = previous_body
		parser.definition_scope_depth = previous_depth
		return {}, false
	}
	advance(parser)
	continuation, continuation_ok := parse_pipe(
		parser,
		closing,
		stop_at_comma,
		stop_at_catch,
		stop_at_binary,
		stop_at_pipe,
		stop_at_defined_or,
	)
	parser.definition_name = previous_name
	parser.has_definition = previous_has
	parser.definition_body = previous_body
	parser.definition_scope_depth = previous_depth
	parser.definition_parameter = previous_parameter
	parser.has_definition_parameter = previous_has_parameter
	return continuation, continuation_ok
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
			if token_is(parser, .Def) {
				nested: Node_Id
				nested_ok: bool
				nested, nested_ok = parse_nested_definition(
					parser,
					closing,
					stop_at_comma,
					stop_at_catch,
					stop_at_binary,
					stop_at_pipe,
					stop_at_defined_or,
				)
				if !nested_ok do return {}, false
				term = nested
				term_ready = nested != invalid_id
				continue
			}
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
				try_closing := closing
				if parser.frames.count > entry_frame_depth {
					try_closing = .Close_Paren
				}
				expression, expression_ok := parse_pipe(parser, try_closing, true, true, false, false, true)
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
					catch_filter, catch_ok = parse_pipe(parser, try_closing, true, false, true, true)
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
				body_closing := closing
				if parser.frames.count > entry_frame_depth do body_closing = .Close_Paren
				body, body_ok := parse_pipe(parser, body_closing, false)
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
				// jq exposes uppercase IN as the generator-membership builtin;
				// normalize its spelling before the regular call dispatch.
				uppercase_in := spelling == "IN"
				if uppercase_in do spelling = "in"
				if parser.has_definition_parameter && definition_name_matches(parser, parser.definition_parameter, spelling) && !token_is(parser, .Open_Paren) {
					advance(parser)
					new_term, parameter_ok := append_node(parser, Node{kind=.Identity, span=token.span})
					if !parameter_ok { return {}, false }
					term = new_term
					term_ready = true
					continue
				}
				call_body, is_definition_call, call_has_parameter := visible_definition(parser, spelling)
				if is_definition_call {
					advance(parser)
					if token_is(parser, .Open_Paren) {
						if !call_has_parameter {
							fail_at_current(parser, .Unexpected_Token, .Expression)
							return {}, false
						}
					advance(parser)
					// A comma inside the parentheses is jq's generator operator and
					// remains part of this single filter-valued argument. Semicolon
					// separated formal arguments are outside this one-parameter ABI
					// and are rejected by the parser's normal call boundary.
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					advance(parser)
					new_term, call_ok := append_node(parser, Node{kind=.Call, span=token.span, child=call_body, has_child=call_body >= 0, call_name_span=token.span, has_call_name=true, call_argument=argument, has_call_argument=true})
					if !call_ok { return {}, false }
					term = new_term
					term_ready = true
					continue
					}
					if !call_has_parameter {
						new_term, call_ok := append_node(parser, Node{kind=.Call, span=token.span, child=call_body, has_child=call_body >= 0, call_name_span=token.span, has_call_name=true})
						if !call_ok { return {}, false }
						term = new_term
						term_ready = true
						continue
					}
					fail_at_current(parser, .Unexpected_Token, .Expression)
					return {}, false
				}
				if spelling == "sort_by" || spelling == "group_by" {
					advance(parser)
				}
				if (spelling == "sort_by" || spelling == "group_by") && token_is(parser, .Open_Paren) {
					keyed_term: Node_Id
					keyed_ok: bool
					keyed_term, keyed_ok = lower_static_keyed_call(parser, token, spelling)
					if !keyed_ok { return {}, false }
					term = keyed_term
					term_ready = true
					continue
				}
				if spelling == "with_entries" && !is_definition_call {
					advance(parser)
				}
				if spelling == "with_entries" && !is_definition_call && token_is(parser, .Open_Paren) {
					advance(parser)
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
					close := parser.lookahead.token; advance(parser)
					to_entries, to_ok := append_node(parser, Node{kind=.To_Entries, span=token.span})
					map_node, map_ok := append_node(parser, Node{kind=.Map, span=parser.nodes.storage[int(argument)].span, child=argument, has_child=true})
					from_entries, from_ok := append_node(parser, Node{kind=.From_Entries, span=close.span})
					if !to_ok || !map_ok || !from_ok do return {}, false
					first_span, first_span_ok := spanning(parser, parser.nodes.storage[int(to_entries)].span, parser.nodes.storage[int(map_node)].span); assert(first_span_ok)
					first_pipe, first_pipe_ok := append_node(parser, Node{kind=.Pipe, span=first_span, left=to_entries, right=map_node}); if !first_pipe_ok do return {}, false
					full_span, full_span_ok := spanning(parser, parser.nodes.storage[int(first_pipe)].span, parser.nodes.storage[int(from_entries)].span); assert(full_span_ok)
					new_term, term_ok := append_node(parser, Node{kind=.Pipe, span=full_span, left=first_pipe, right=from_entries}); if !term_ok do return {}, false
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
				if spelling == "walk" && !is_definition_call {
					advance(parser)
					if !token_is(parser, .Open_Paren) {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					advance(parser)
					argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
					if !argument_ok || !token_is(parser, .Close_Paren) {
						fail_from_lookahead(parser, .Close_Paren)
						return {}, false
					}
					close := parser.lookahead.token
					advance(parser)
					span, span_ok := spanning(parser, token.span, close.span)
					assert(span_ok)
					walk_term, term_ok := lower_walk_filter(parser, argument, span)
					if !term_ok do return {}, false
					term = walk_term
					term_ready = true
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
					} else if spelling == "sort_by_key" {
						kind = .Sort_By_Key
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
				} else if spelling == "input" {
					kind = .Input
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
				} else if spelling != "null" && spelling != "JOIN" && spelling != "INDEX" {
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
					body_closing := closing
					if parser.frames.count > entry_frame_depth do body_closing = .Close_Paren
					body, body_ok := parse_pipe(parser, body_closing, false)
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
				} else if (spelling == "add" || spelling == "pow" || spelling == "join" || spelling == "JOIN" || spelling == "INDEX" || spelling == "contains" || spelling == "inside" || spelling == "in" || spelling == "split" || spelling == "index" || spelling == "rindex" || spelling == "indices" || spelling == "startswith" || spelling == "endswith" || spelling == "has" || spelling == "bsearch" || spelling == "flatten" || spelling == "ltrimstr" || spelling == "rtrimstr" || spelling == "trimstr" || spelling == "error" || spelling == "isempty" || spelling == "strftime" || spelling == "strflocaltime" || spelling == "strptime" || spelling == "any" || spelling == "all" || spelling == "first" || spelling == "last" || spelling == "map" || spelling == "map_values") && token_is(parser, .Open_Paren) {
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
					if spelling == "in" {
						first, first_ok := parse_pipe(parser, .Semicolon, false)
						if !first_ok { fail_from_lookahead(parser, .Expression); return {}, false }
						if token_is(parser, .Semicolon) {
							advance(parser)
							second, second_ok := parse_pipe(parser, .Close_Paren, false)
							if !second_ok || !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
							close := parser.lookahead.token
							advance(parser)
							span, span_ok := spanning(parser, token.span, close.span)
							assert(span_ok)
							new_term, ok := append_node(parser, Node{kind=.In, span=span, child=first, has_child=true, predicate=second, has_predicate=true})
							if !ok { return {}, false }
							term = new_term
							term_ready = true
							continue
						}
						if uppercase_in && parser.nodes.storage[int(first)].kind == .Comma {
							if !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
							close := parser.lookahead.token
							advance(parser)
							identity, identity_ok := append_node(parser, Node{kind=.Identity, span=token.span})
							if !identity_ok do return {}, false
							span, span_ok := spanning(parser, token.span, close.span)
							assert(span_ok)
							new_term, new_ok := append_node(parser, Node{kind=.In, span=span, child=first, has_child=true, predicate=identity, has_predicate=true})
							if !new_ok do return {}, false
							term = new_term
							term_ready = true
							continue
						}
						if !token_is(parser, .Close_Paren) { fail_from_lookahead(parser, .Close_Paren); return {}, false }
						close := parser.lookahead.token
						advance(parser)
						span, span_ok := spanning(parser, token.span, close.span)
						assert(span_ok)
						new_term, ok := append_node(parser, Node{kind=.In, span=span, child=first, has_child=true})
						if !ok { return {}, false }
						term = new_term
						term_ready = true
						continue
					}
					if spelling == "JOIN" {
						// Bounded JOIN($idx; idx_expr): lower the jq
						// definition `[.[] | [., $idx[idx_expr]]]` into
						// existing Map/Index/array instructions.  The
						// object index and key filter are intentionally limited
						// to this two-argument form; JOIN/3 and JOIN/4 need
						// resumable stream contracts of their own.
						idx, idx_ok := parse_pipe(parser, .Semicolon, false)
						if !idx_ok || !token_is(parser, .Semicolon) {
							fail_from_lookahead(parser, .Expression)
							return {}, false
						}
						advance(parser)
						idx_expr, expr_ok := parse_pipe(parser, .Close_Paren, false)
						if !expr_ok || !token_is(parser, .Close_Paren) {
							fail_from_lookahead(parser, .Close_Paren)
							return {}, false
						}
						close := parser.lookahead.token
						advance(parser)
						idx_node := parser.nodes.storage[int(idx)]
						if idx_node.kind != .Identity || idx_node.container_kind != .Object || !idx_node.has_value || idx_node.has_child {
							fail_from_lookahead(parser, .Expression)
							return {}, false
						}
						identity := Node{kind=.Identity, span=idx_node.span}
						row, row_ok := append_node(parser, identity)
						if !row_ok do return {}, false
						lookup, lookup_ok := append_node(parser, Node{kind=.Index, span=idx_node.span, child=idx, has_child=true, index_key=idx_expr, has_index_key=true})
						if !lookup_ok do return {}, false
						pair_value, pair_value_ok := append_node(parser, Node{kind=.Comma, span=idx_node.span, left=row, right=lookup})
						if !pair_value_ok do return {}, false
						pair, pair_ok := append_node(parser, Node{kind=.Identity, span=idx_node.span, container_kind=.Array, value=pair_value, has_value=true})
						if !pair_ok do return {}, false
						mapped_span, mapped_span_ok := spanning(parser, idx_node.span, close.span)
						assert(mapped_span_ok)
						mapped, mapped_ok := append_node(parser, Node{kind=.Map, span=mapped_span, child=pair, has_child=true})
						if !mapped_ok do return {}, false
						term = mapped
						term_ready = true
						continue
					}
					if spelling == "INDEX" {
						// Bounded INDEX(stream; key): collect the source stream,
						// compute one key filter per source item, and reuse the
						// existing from_entries materializer. This is a genuine AST
						// lowering, not a driver rewrite; arbitrary key filters and
						// stream producers retain normal evaluator semantics.
						source_filter, source_ok := parse_pipe(parser, .Semicolon, false)
						if !source_ok || !token_is(parser, .Semicolon) {
							fail_from_lookahead(parser, .Expression)
							return {}, false
						}
						advance(parser)
						key_filter, key_ok := parse_pipe(parser, .Close_Paren, false)
						if !key_ok || !token_is(parser, .Close_Paren) {
							fail_from_lookahead(parser, .Close_Paren)
							return {}, false
						}
						close := parser.lookahead.token
						advance(parser)
						item, item_ok := append_node(parser, Node{kind=.Identity, span=token.span})
						if !item_ok do return {}, false
						source_array, source_array_ok := append_node(parser, Node{
							kind=.Identity, span=token.span, container_kind=.Array,
							value=source_filter, has_value=true,
						})
						if !source_array_ok do return {}, false
						key_name, key_name_ok := append_decoded_string_node(parser, "key", token.span, 0)
						value_name, value_name_ok := append_decoded_string_node(parser, "value", token.span, 0)
						if !key_name_ok || !value_name_ok do return {}, false
						key_text, key_text_ok := append_node(parser, Node{kind=.Tostring, span=token.span})
						if !key_text_ok do return {}, false
						key_filter_text, key_filter_text_ok := append_node(parser, Node{kind=.Pipe, span=token.span, left=key_filter, right=key_text})
						if !key_filter_text_ok do return {}, false
						key_entry, key_entry_ok := append_node(parser, Node{
							kind=.Field, container_kind=.Object_Entry, span=token.span,
							name_span=parser.nodes.storage[int(key_name)].span, has_name_span=true, key=key_name, has_key=true, value=key_filter_text, has_value=true,
						})
						if !key_entry_ok do return {}, false
						value_entry, value_entry_ok := append_node(parser, Node{
			kind=.Field, container_kind=.Object_Entry, span=token.span,
							name_span=parser.nodes.storage[int(value_name)].span, has_name_span=true, key=value_name, has_key=true, value=item, has_value=true,
						})
						if !value_entry_ok do return {}, false
						parser.nodes.storage[int(key_entry)].next = value_entry
						parser.nodes.storage[int(key_entry)].has_next = true
						pair, pair_ok := append_node(parser, Node{
							kind=.Identity, span=token.span, container_kind=.Object,
							value=key_entry, has_value=true,
						})
						if !pair_ok do return {}, false
						mapped, mapped_ok := append_node(parser, Node{
							kind=.Map, span=token.span, child=pair, has_child=true,
						})
						if !mapped_ok do return {}, false
						result_span, result_span_ok := spanning(parser, token.span, close.span)
						assert(result_span_ok)
						// Feed the collected source into map(pair), then materialize
						// the pairs as an object with existing from_entries semantics.
						mapped_pipe, mapped_pipe_ok := append_node(parser, Node{
							kind=.Pipe, span=token.span, left=source_array, right=mapped,
						})
						if !mapped_pipe_ok do return {}, false
						from_entries, from_entries_ok := append_node(parser, Node{
							kind=.From_Entries, span=result_span,
						})
						if !from_entries_ok do return {}, false
						result, result_ok := append_node(parser, Node{
							kind=.Pipe, span=result_span,
							left=mapped_pipe, right=from_entries,
						})
						if !result_ok do return {}, false
						term = result
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
				// IN(generator) consumes a filter-valued stream and therefore needs
				// the same admission path as other resumable selectors. Literal IN
				// operands still use the existing synchronous evaluator path.
				stream_selector := spelling == "first" || spelling == "last" || spelling == "map" || spelling == "map_values" || contains_dynamic || spelling == "in"
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
			optional_left := current if pipe_root != invalid_id else result
			if optional_left >= 0 {
				left_id := optional_left
				left_node := parser.nodes.storage[int(left_id)]
				if left_node.kind == .Parenthesized && left_node.has_child {
					left_id = left_node.child
					left_node = parser.nodes.storage[int(left_id)]
				}
				// A bounded filtered-iterator deletion such as
				// `(.[] | select(. >= 2)) |= empty` is equivalent to applying
				// `if predicate then empty else . end` to every iterator item.
				// Lower it into the existing resumable Static_Iterator_Update
				// contract; arbitrary filtered path updates remain deferred.
				if left_node.kind == .Pipe && left_node.left >= 0 && left_node.right >= 0 {
					iterator := parser.nodes.storage[int(left_node.left)]
					selector := parser.nodes.storage[int(left_node.right)]
					selector_then := parser.nodes.storage[int(selector.if_then)] if selector.if_then >= 0 && int(selector.if_then) < len(parser.nodes.storage) else Node{}
					selector_else := parser.nodes.storage[int(selector.if_else)] if selector.if_else >= 0 && int(selector.if_else) < len(parser.nodes.storage) else Node{}
					iterator_name_start, iterator_name_end, iterator_name_ok := diagnostic.span_offsets(parser.source, iterator.name_span)
					iterator_child := parser.nodes.storage[int(iterator.child)] if iterator.child >= 0 && int(iterator.child) < len(parser.nodes.storage) else Node{}
					if iterator.kind == .Field && iterator.has_child && iterator.has_name_span && iterator_child.kind == .Identity &&
						iterator_name_ok && iterator_name_start == iterator_name_end &&
						selector.kind == .If && selector.has_if_condition && selector.has_if_then && selector.has_if_else &&
						selector_then.kind == .Identity && !selector_then.has_child && !selector_then.has_value && selector_then.container_kind == .None &&
						selector_else.kind == .Empty && !selector_else.has_child && !selector_else.has_value {
						advance(parser)
						rhs, rhs_ok := parse_pipe(parser, closing, true, false, false, true)
						if !rhs_ok do return {}, false
						for rhs >= 0 && parser.nodes.storage[int(rhs)].kind == .Parenthesized && parser.nodes.storage[int(rhs)].has_child {
							rhs = parser.nodes.storage[int(rhs)].child
						}
						rhs_node := parser.nodes.storage[int(rhs)]
						if rhs_node.kind == .Empty && rhs_node.form == .Kinded && !rhs_node.has_child && !rhs_node.has_value {
							empty_node, empty_ok := append_node(parser, Node{kind=.Empty, span=rhs_node.span})
							identity_node, identity_ok := append_node(parser, Node{kind=.Identity, span=rhs_node.span})
							if !empty_ok || !identity_ok do return {}, false
							filtered_update, filtered_ok := append_node(parser, Node{
								kind=.If, span=rhs_node.span,
								if_condition=selector.if_condition, has_if_condition=true,
								if_then=empty_node, has_if_then=true,
								if_else=identity_node, has_if_else=true,
							})
							if !filtered_ok do return {}, false
							span, span_ok := spanning(parser, left_node.span, rhs_node.span); assert(span_ok)
							update, update_ok := append_node(parser, Node{kind=.Static_Iterator_Update, span=span, right=filtered_update})
							if !update_ok do return {}, false
							if int(pipe_root) < 0 do return update, true
							tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
							return pipe_root, true
						}
					}
				}
				// A numeric selector list such as `.foo[1,4,2,3] |= empty`
				// is deletion of several static paths against one input.  The
				// postfix parser already represents the selector list as a Comma
				// of Index nodes, and Delpaths already owns the required
				// copy-on-write multi-path deletion semantics.  Lower only this
				// empty-RHS shape; filter-valued selector updates remain outside
				// this bounded contract.
				static_nonnegative_integer :: proc(text: string) -> bool {
					if len(text) == 0 do return false
					for byte in text { if byte < '0' || byte > '9' do return false }
					return true
				}
				static_index_selector_group :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
					if node_id < 0 || int(node_id) >= len(parser.nodes.storage) do return false
					n := parser.nodes.storage[int(node_id)]
					if n.kind == .Parenthesized && n.has_child do return static_index_selector_group(parser, n.child)
					if n.kind == .Comma {
						return static_index_selector_group(parser, n.left) && static_index_selector_group(parser, n.right)
					}
					if n.kind != .Index || !n.has_child || !n.has_number_text || !static_nonnegative_integer(n.number_text) do return false
					base := parser.nodes.storage[int(n.child)]
					return base.kind == .Field && !base.has_child && base.has_name_span
				}
				if left_node.kind == .Comma && static_index_selector_group(parser, optional_left) {
					advance(parser)
					right, right_ok := parse_pipe(parser, closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
						right = parser.nodes.storage[int(right)].child
					}
					rhs := parser.nodes.storage[int(right)]
					if rhs.form != .Kinded || rhs.kind != .Empty || rhs.has_child || rhs.has_value {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
					selector_ids: [16]Node_Id
					selector_count := 0
					collect_selector_ids :: proc(parser: ^Parser, node_id: Node_Id, ids: ^[16]Node_Id, count: ^int) -> bool {
						if node_id < 0 || int(node_id) >= len(parser.nodes.storage) || count^ >= len(ids) do return false
						n := parser.nodes.storage[int(node_id)]
						if n.kind == .Parenthesized && n.has_child do return collect_selector_ids(parser, n.child, ids, count)
						if n.kind == .Comma {
							return collect_selector_ids(parser, n.left, ids, count) && collect_selector_ids(parser, n.right, ids, count)
						}
						if n.kind != .Index || !n.has_number_text || !static_nonnegative_integer(n.number_text) do return false
						ids[count^] = node_id; count^ += 1
						return true
					}
					if !collect_selector_ids(parser, optional_left, &selector_ids, &selector_count) || selector_count < 2 do return {}, false
					// Sort positive decimal indexes by numeric value descending. This
					// keeps deletion coordinates anchored to the original array.
					for left in 0..<selector_count {
						best := left
						for right_index in (left+1)..<selector_count {
							a := parser.nodes.storage[int(selector_ids[best])].number_text
							b := parser.nodes.storage[int(selector_ids[right_index])].number_text
							if len(a) < len(b) || (len(a) == len(b) && b > a) { best = right_index }
						}
						if best != left { selector_ids[left], selector_ids[best] = selector_ids[best], selector_ids[left] }
					}
					paths: Node_Id = invalid_id
					for selector_index in 0..<selector_count {
						path, path_ok := lower_static_del_paths(parser, selector_ids[selector_index])
						if !path_ok do return {}, false
						if paths == invalid_id { paths = parser.nodes.storage[int(path)].value } else {
							span := left_node.span
							paths, path_ok = append_node(parser, Node{kind=.Comma, span=span, left=paths, right=parser.nodes.storage[int(path)].value})
							if !path_ok do return {}, false
						}
					}
					grouped, grouped_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=left_node.span, value=paths, has_value=true})
					if !grouped_ok do return {}, false
					span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
					update, update_ok := append_node(parser, Node{kind=.Delpaths, span=span, child=grouped, has_child=true})
					if !update_ok do return {}, false
					if pipe_root == invalid_id do return update, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
					return pipe_root, true
				}
				// A bounded bridge for jq's literal-path `getpath(...) |= scalar`
				// form.  The existing Setpath evaluator already owns copy-on-write
				// path updates; lower only literal string/number path arrays so
				// dynamic path filters do not get mistaken for this contract.
				if left_node.form == .Kinded && left_node.kind == .Getpath && left_node.has_child {
					path_node := parser.nodes.storage[int(left_node.child)]
					static_path_item :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
						if node_id < 0 || int(node_id) >= len(parser.nodes.storage) do return false
						n := parser.nodes.storage[int(node_id)]
						if n.kind == .Parenthesized && n.has_child do return static_path_item(parser, n.child)
						if n.kind == .Comma && n.left >= 0 && n.right >= 0 {
							return static_path_item(parser, n.left) && static_path_item(parser, n.right)
						}
						return n.form == .Kinded && (n.kind == .Number || n.kind == .String) &&
							!n.has_child && !n.has_value
					}
					path_is_static := path_node.form == .Kinded && path_node.kind == .Identity &&
						path_node.container_kind == .Array && path_node.has_value &&
						(path_node.value < 0 || static_path_item(parser, path_node.value))
					if path_is_static {
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
							right = parser.nodes.storage[int(right)].child
						}
						rhs := parser.nodes.storage[int(right)]
						if rhs.form != .Kinded || (rhs.kind != .Number && rhs.kind != .Boolean && rhs.kind != .Null && rhs.kind != .String) || rhs.has_child || rhs.has_value {
							fail_from_lookahead(parser, .Expression); return {}, false
						}
						span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
						setpath, setpath_ok := append_node(parser, Node{kind=.Setpath, span=span, left=left_node.child, right=right})
						if !setpath_ok do return {}, false
						if int(pipe_root) < 0 do return setpath, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = setpath; tail.has_child = false
						return pipe_root, true
					}
				}
				if left_node.form == .Kinded && left_node.kind == .Field && left_node.has_child && left_node.has_name_span {
					index_node := parser.nodes.storage[int(left_node.child)]
					if index_node.form == .Kinded && index_node.kind == .Index && index_node.has_child && index_node.has_number_text && static_nonnegative_integer(index_node.number_text) {
						base := parser.nodes.storage[int(index_node.child)]
						if base.form == .Kinded && base.kind == .Field && !base.has_child && base.has_name_span {
							advance(parser)
							right, right_ok := parse_pipe(parser, closing, true, false, false, true)
							if !right_ok do return {}, false
							for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
							span, span_ok := spanning(parser, left_node.span, parser.nodes.storage[int(right)].span); assert(span_ok)
							update, update_ok := append_node(parser, Node{kind=.Static_Field_Index_Field_Update, span=span, right=right, number_text=index_node.number_text, has_number_text=true, name_span=left_node.name_span, has_name_span=true, base_name_span=base.name_span, has_base_name_span=true})
							if !update_ok do return {}, false
							if pipe_root == invalid_id do return update, true
							tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
							return pipe_root, true
						}
						if base.form == .Kinded && base.kind == .Identity && !base.has_child && !base.has_value {
							advance(parser)
							right, right_ok := parse_pipe(parser, closing, true, false, false, true)
							if !right_ok do return {}, false
							for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
							span, span_ok := spanning(parser, left_node.span, parser.nodes.storage[int(right)].span); assert(span_ok)
							update, update_ok := append_node(parser, Node{kind=.Static_Index_Field_Update, span=span, right=right, number_text=index_node.number_text, has_number_text=true, name_span=left_node.name_span, has_name_span=true})
							if !update_ok do return {}, false
							if pipe_root == invalid_id do return update, true
							tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
							return pipe_root, true
						}
					}
				}
				if left_node.form == .Kinded && left_node.kind == .Index && left_node.has_child && left_node.has_number_text {
					base := parser.nodes.storage[int(left_node.child)]
					if base.form == .Kinded && base.kind == .Field && !base.has_child && base.has_name_span {
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
						span, span_ok := spanning(parser, left_node.span, parser.nodes.storage[int(right)].span); assert(span_ok)
						update, update_ok := append_node(parser, Node{kind=.Static_Field_Index_Update, span=span, right=right, number_text=left_node.number_text, has_number_text=true, name_span=base.name_span, has_name_span=true})
						if !update_ok do return {}, false
						if pipe_root == invalid_id do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
				}
				if left_node.form == .Kinded && left_node.kind == .Field && !left_node.has_child && left_node.has_name_span {
					advance(parser)
					right, right_ok := parse_pipe(parser, closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
					rhs := parser.nodes.storage[int(right)]
					if rhs.form == .Kinded && rhs.kind == .Empty && !rhs.has_child && !rhs.has_value {
						span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
						update, update_ok := append_node(parser, Node{kind=.Static_Field_Delete, span=span, name_span=left_node.name_span, has_name_span=true})
						if !update_ok do return {}, false
						if pipe_root == invalid_id do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
					if rhs.form == .Kinded && rhs.kind == .Optional && rhs.has_child {
						child := parser.nodes.storage[int(rhs.child)]
						if child.form == .Kinded && child.kind == .Identity && !child.has_child && !child.has_value {
							span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
							update, update_ok := append_node(parser, Node{kind=.Static_Field_Optional_Identity, span=span, name_span=left_node.name_span, has_name_span=true})
							if !update_ok do return {}, false
							if pipe_root == invalid_id do return update, true
							tail := &parser.nodes.storage[int(pipe_tail)]
							tail.right = update
							tail.has_child = false
							return pipe_root, true
						}
					}
					// Preserve the existing bounded `.field |= .+number` lowering
					// after this exact optional-identity probe has consumed the RHS.
					if rhs.form == .Binary && rhs.binary_operator == .Add && rhs.left >= 0 && rhs.right >= 0 {
						identity := parser.nodes.storage[int(rhs.left)]
						number := parser.nodes.storage[int(rhs.right)]
						if identity.form == .Kinded && identity.kind == .Identity && !identity.has_child &&
							number.form == .Kinded && number.kind == .Number && number.has_number_text {
							span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
							update, update_ok := append_node(parser, Node{kind=.Static_Field_Add_Number, span=span, right=rhs.right, name_span=left_node.name_span, has_name_span=true})
							if !update_ok do return {}, false
							if pipe_root == invalid_id do return update, true
							tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
							return pipe_root, true
						}
					}
					// Preserve the complete RHS filter as a child instruction for
					// root static-field updates. The evaluator consumes the first
					// output, deletes on an empty stream, and cancels later outputs.
					span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
					update, update_ok := append_node(parser, Node{kind=.Static_Field_Update, span=span, right=right, name_span=left_node.name_span, has_name_span=true})
					if !update_ok do return {}, false
					if pipe_root == invalid_id do return update, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
					return pipe_root, true
				}
				// A filter-valued callable parameter is parsed as Identity while its
				// declaration is active. Preserve the update operator as a dedicated
				// node instead of confusing it with a root identity assignment.
				if parser.has_definition_parameter && left_node.form == .Kinded && left_node.kind == .Identity &&
					!left_node.has_child && !left_node.has_value {
					left_start, left_end, left_ok := diagnostic.span_offsets(parser.source, left_node.span)
					param_start, param_end, param_ok := diagnostic.span_offsets(parser.source, parser.definition_parameter)
					bytes := diagnostic.source_bytes(parser.source)
					if left_ok && param_ok && left_end-left_start == param_end-param_start && bytes[left_start:left_end] == bytes[param_start:param_end] {
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
							right = parser.nodes.storage[int(right)].child
						}
						rhs := parser.nodes.storage[int(right)]
						if rhs.form != .Kinded || rhs.kind != .Identity || rhs.has_child || rhs.has_value {
							fail_from_lookahead(parser, .Expression)
							return {}, false
						}
						span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
						update, update_ok := append_node(parser, Node{kind=.Parameter_Identity_Update, span=span})
						if !update_ok do return {}, false
						if pipe_root == invalid_id do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
				}
			}
			// Root `.[] |= empty` has jq's deletion semantics: every array
			// element/object value is removed. Keep this as a dedicated AST
			// contract rather than lowering it through a textual rewrite.
			left := current if pipe_root != invalid_id else result
			if left >= 0 {
				left_node := parser.nodes.storage[int(left)]
				if left_node.form == .Kinded && left_node.kind == .Field && left_node.has_child && left_node.has_name_span {
					name_start, name_end, name_ok := diagnostic.span_offsets(parser.source, left_node.name_span)
					child := parser.nodes.storage[int(left_node.child)]
					if name_ok && name_start == name_end && child.kind == .Identity && !child.has_child && !child.has_value {
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
							right = parser.nodes.storage[int(right)].child
						}
						rhs := parser.nodes.storage[int(right)]
						span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
						update_kind := Node_Kind.Static_Iterator_Update
						if rhs.form == .Kinded && rhs.kind == .Empty && !rhs.has_child && !rhs.has_value {
							update_kind = .Static_Iterator_Delete
						}
						update_node := Node{kind=update_kind, span=span}
						if update_kind == .Static_Iterator_Update { update_node.right = right }
						update, update_ok := append_node(parser, update_node)
						if !update_ok do return {}, false
						if int(pipe_root) < 0 do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
				}
			}
			return parse_static_field_add_update(
				parser,
				current if pipe_root != invalid_id else result,
				pipe_root,
				pipe_tail,
				closing,
			)
		}
		if token_is(parser, .Assign_Plus) || token_is(parser, .Assign_Minus) ||
			token_is(parser, .Assign_Multiply) || token_is(parser, .Assign_Divide) ||
			token_is(parser, .Assign_Modulo) {
			left := current
			if left >= 0 {
				left_node := parser.nodes.storage[int(left)]
				op := parser.lookahead.token.kind
				if op == .Assign_Plus && left_node.form == .Kinded && left_node.kind == .Field && !left_node.has_child && left_node.has_name_span {
					advance(parser)
					right, right_ok := parse_pipe(parser, closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
					rhs := parser.nodes.storage[int(right)]
					if rhs.form != .Kinded || rhs.kind != .Field || rhs.has_child || !rhs.has_name_span { fail_from_lookahead(parser, .Expression); return {}, false }
					span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
					update, update_ok := append_node(parser, Node{kind=.Static_Field_Add_Field, span=span, right=right, name_span=left_node.name_span, has_name_span=true})
					if !update_ok do return {}, false
					if int(pipe_root) < 0 do return update, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false; return pipe_root, true
				}
				if left_node.form == .Kinded && left_node.kind == .Field && left_node.has_child && left_node.has_name_span {
					name_start, name_end, name_ok := diagnostic.span_offsets(parser.source, left_node.name_span)
					child := parser.nodes.storage[int(left_node.child)]
					if name_ok && name_start == name_end && child.kind == .Identity && !child.has_child && !child.has_value {
						operator := Binary_Operator.Add
						#partial switch op {
						case .Assign_Minus: operator = .Subtract
						case .Assign_Multiply: operator = .Multiply
						case .Assign_Divide: operator = .Divide
						case .Assign_Modulo: operator = .Modulo
						}
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
							right = parser.nodes.storage[int(right)].child
						}
						rhs := parser.nodes.storage[int(right)]
						if rhs.form != .Kinded || rhs.kind != .Number || rhs.has_child || rhs.has_value {
							fail_from_lookahead(parser, .Expression); return {}, false
						}
						span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
						update, update_ok := append_node(parser, Node{kind=.Static_Iterator_Set_Number, span=span, right=right, binary_operator=operator, iterator_compound=true})
						if !update_ok do return {}, false
						// A compound update may be one arm of a comma stream.  The
						// ordinary assignment fast path returns immediately, so consume
						// the comma here and recursively parse the remaining arms while
						// retaining the existing Comma/Sequence ABI.
						if token_is(parser, .Comma) {
							advance(parser)
							rest, rest_ok := parse_pipe(parser, closing, false, false, false, true)
							if !rest_ok do return {}, false
							combined_span, combined_span_ok := spanning(parser, parser.nodes.storage[int(update)].span, parser.nodes.storage[int(rest)].span)
							assert(combined_span_ok)
							combined, combined_ok := append_node(parser, Node{kind=.Comma, span=combined_span, left=update, right=rest})
							if !combined_ok do return {}, false
							return combined, true
						}
						if int(pipe_root) < 0 do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
				}
				}
				return parse_static_field_set_number(parser, left, pipe_root, pipe_tail, closing)
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
				index_node := parser.nodes.storage[int(current)]
				// Root-only instruction-valued index assignment has a dedicated
				// key-stream continuation. Nested dynamic paths remain deferred.
				if index_node.has_index_key && index_node.has_child &&
					parser.nodes.storage[int(index_node.child)].kind == .Identity {
					advance(parser)
					// A RHS parser nested inside an open parenthesized frame must stop at
					// that frame's close token. Passing an invalid closing token would let
					// the RHS consume the group's close itself, losing the assignment node
					// before the outer frame can apply its optional suffix.
					rhs_closing := closing
					if parser.frames.count > entry_frame_depth do rhs_closing = .Close_Paren
					right, right_ok := parse_pipe(parser, rhs_closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
						right = parser.nodes.storage[int(right)].child
					}
					rhs := parser.nodes.storage[int(right)]
					if rhs.form != .Kinded || (rhs.kind != .Number && rhs.kind != .Boolean && rhs.kind != .Null && rhs.kind != .String) || rhs.has_child || rhs.has_value {
						fail_from_lookahead(parser, .Expression); return {}, false
					}
					span, span_ok := spanning(parser, index_node.span, rhs.span); assert(span_ok)
					assign, assign_ok := append_node(parser, Node{kind=.Dynamic_Index_Assign, span=span, left=index_node.child, right=index_node.index_key, reduce_update=right, has_reduce_update=true})
					if !assign_ok do return {}, false
					if parser.frames.count > entry_frame_depth {
						// The assignment replaces the current term; it is not a
						// comma node awaiting a right-hand term.
						current = invalid_id
						result = assign
						term = assign
						term_ready = true
						continue
					}
					if int(pipe_root) < 0 do return assign, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = assign; tail.has_child = false
					return pipe_root, true
				}
				index_base := parser.nodes.storage[int(current)].child
				if index_base < 0 || parser.nodes.storage[int(index_base)].kind != .Index {
					return parse_static_index_set_number(parser, current, pipe_root, pipe_tail, closing)
				}
			}
			left := current if pipe_root != invalid_id else result
			left_node := parser.nodes.storage[int(left)]
			// Bounded generated-path assignment: retain a path filter (including a
			// zero-argument definition call) and its RHS stream. The evaluator owns
			// stream collection and copy-on-write application.
			if left_node.form == .Kinded && (left_node.kind == .Index || left_node.kind == .Comma || left_node.kind == .Call) {
				advance(parser)
				right, right_ok := parse_pipe(parser, closing, true, false, false, true)
				if !right_ok do return {}, false
				for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child { right = parser.nodes.storage[int(right)].child }
				path_span, path_span_ok := spanning(parser, left_node.span, left_node.span); assert(path_span_ok)
				path_node, path_node_ok := append_node(parser, Node{kind=.Path, span=path_span, child=left, has_child=true})
				if !path_node_ok do return {}, false
				right_span := parser.nodes.storage[int(right)].span
				span, span_ok := spanning(parser, left_node.span, right_span); assert(span_ok)
				assign, assign_ok := append_node(parser, Node{kind=.Path_Assign, span=span, left=path_node, right=right})
				if !assign_ok do return {}, false
				if int(pipe_root) < 0 do return assign, true
				tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = assign; tail.has_child = false
				return pipe_root, true
			}
			// `.[] = scalar` is the first genuine iterator-path assignment
			// contract.  Keep it separate from field/setpath lowering: the empty
			// field name denotes an array/object value iterator, not an object key.
			// Restrict this vertical slice to a root iterator and scalar RHS so the
			// existing resumable path ABI is not widened accidentally.
			if left_node.form == .Kinded &&
				left_node.kind == .Field && left_node.has_child && left_node.has_name_span {
				name_start, name_end, name_ok := diagnostic.span_offsets(parser.source, left_node.name_span)
				child := parser.nodes.storage[int(left_node.child)]
				if name_ok && name_start == name_end && child.kind == .Identity && !child.has_child && !child.has_value {
					advance(parser)
					right, right_ok := parse_pipe(parser, closing, true, false, false, true)
					if !right_ok do return {}, false
					for right >= 0 && parser.nodes.storage[int(right)].kind == .Parenthesized && parser.nodes.storage[int(right)].has_child {
						right = parser.nodes.storage[int(right)].child
					}
					rhs := parser.nodes.storage[int(right)]
					if rhs.form != .Kinded || (rhs.kind != .Number && rhs.kind != .Boolean && rhs.kind != .Null && rhs.kind != .String) || rhs.has_child || rhs.has_value {
						fail_from_lookahead(parser, .Expression); return {}, false
					}
					span, span_ok := spanning(parser, left_node.span, rhs.span); assert(span_ok)
					update, update_ok := append_node(parser, Node{kind=.Static_Iterator_Set_Number, span=span, right=right})
					if !update_ok do return {}, false
					if int(pipe_root) < 0 do return update, true
					tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
					return pipe_root, true
				}
			}
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
		if token_is(parser, .Assign_Defined_Or) {
			left := current if pipe_root != invalid_id else result
			if left >= 0 {
				left_node := parser.nodes.storage[int(left)]
				if left_node.form == .Kinded && left_node.kind == .Field && left_node.has_child && left_node.has_name_span {
					name_start, name_end, name_ok := diagnostic.span_offsets(parser.source, left_node.name_span)
					child := parser.nodes.storage[int(left_node.child)]
					if name_ok && name_start == name_end && child.kind == .Identity && !child.has_child && !child.has_value {
						advance(parser)
						right, right_ok := parse_pipe(parser, closing, true, false, false, true)
						if !right_ok do return {}, false
						span, span_ok := spanning(parser, left_node.span, parser.nodes.storage[int(right)].span); assert(span_ok)
						update, update_ok := append_node(parser, Node{kind=.Static_Iterator_Update, span=span, right=right, binary_operator=.Defined_Or, iterator_compound=true})
						if !update_ok do return {}, false
						if int(pipe_root) < 0 do return update, true
						tail := &parser.nodes.storage[int(pipe_tail)]; tail.right = update; tail.has_child = false
						return pipe_root, true
					}
				}
			}
			return parse_static_field_set_number(parser, current if pipe_root != invalid_id else result, pipe_root, pipe_tail, closing)
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
				ordinary, ordinary_ok := try_parse_ordinary_pattern_binding(parser, left, pattern, pipe_root, pipe_tail, closing, stop_at_comma)
				if ordinary_ok do return ordinary, true
				entries := parser.nodes.storage[int(pattern_node.value)]
				entry_count := 0
				if entries.kind == .Variable {
					entry_count = 1
				} else if entries.kind == .Comma && entries.left >= 0 && int(entries.left) < len(parser.nodes.storage) &&
				          entries.right >= 0 && int(entries.right) < len(parser.nodes.storage) {
					entry_count = 2
				} else {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				variables := [2]Node_Id{entries.left, entries.right}
				if entry_count == 1 do variables[0] = pattern_node.value
				for variable in variables[:entry_count] {
					pattern_variable_ok := parser.nodes.storage[int(variable)].kind == .Variable
					if !pattern_variable_ok && token_is(parser, .Open_Paren) && entry_count == 2 && variable == variables[1] {
						nested := parser.nodes.storage[int(variable)]
						if nested.container_kind == .Object && nested.has_value {
							entry := parser.nodes.storage[int(nested.value)]
							if entry.kind == .Field && entry.container_kind == .Object_Entry && entry.has_key && entry.has_value {
								key := parser.nodes.storage[int(entry.key)]
								val := parser.nodes.storage[int(entry.value)]
								pattern_variable_ok = key.kind == .Field && key.has_name_span && val.kind == .Variable && val.has_name_span
							}
						}
					}
					if !pattern_variable_ok {
						fail_from_lookahead(parser, .Expression)
						return {}, false
					}
				}
				if token_is(parser, .Open_Paren) {
					// Foreach keeps the pattern as the right child of a synthetic
					// Binding generator. The evaluator can then materialize the
					// original producer while retaining the pattern metadata without
					// changing the legacy four/five-operand Foreach ABI.
					first := parser.nodes.storage[int(variables[0])]
					bound_span, bound_span_ok := spanning(parser, parser.nodes.storage[int(left)].span, pattern_node.span); assert(bound_span_ok)
					bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=left, right=pattern, name_span=first.name_span, has_name_span=true})
					if !bound_ok do return {}, false
					parser.pending_reduce_name = first.name_span
					parser.has_pending_reduce = true
					if pipe_root != invalid_id {
						tail := &parser.nodes.storage[int(pipe_tail)]
						tail.right = bound
						tail.has_child = false
						return pipe_root, true
					}
					return bound, true
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
				first_ref, first_ref_ok := append_node(parser, Node{kind=.Variable, span=first.span, name_span=first.name_span, has_name_span=true})
				if !first_ref_ok do return {}, false
				first_index, first_index_ok := append_node(parser, Node{kind=.Index, span=first.span, number_text="0", has_number_text=true, child=first_ref, has_child=true})
				if !first_index_ok do return {}, false
				bound_span, span_ok := spanning(parser, parser.nodes.storage[int(first_index)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
				bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=first_index, right=nested, name_span=first.name_span, has_name_span=true})
				if !bound_ok do return {}, false
				nested = bound
				if entry_count == 2 {
					second := parser.nodes.storage[int(variables[1])]
					first_ref, first_ref_ok = append_node(parser, Node{kind=.Variable, span=first.span, name_span=first.name_span, has_name_span=true})
					if !first_ref_ok do return {}, false
					second_index, second_index_ok := append_node(parser, Node{kind=.Index, span=second.span, number_text="1", has_number_text=true, child=first_ref, has_child=true})
					if !second_index_ok do return {}, false
					bound_span, span_ok = spanning(parser, parser.nodes.storage[int(second_index)].span, parser.nodes.storage[int(nested)].span); assert(span_ok)
					bound, bound_ok = append_node(parser, Node{kind=.Binding, span=bound_span, left=second_index, right=nested, name_span=second.name_span, has_name_span=true})
					if !bound_ok do return {}, false
					nested = bound
				}
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
				ordinary, ordinary_ok := try_parse_ordinary_pattern_binding(parser, left, pattern, pipe_root, pipe_tail, closing, stop_at_comma)
				if ordinary_ok do return ordinary, true
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
				if count == 0 {
					fail_from_lookahead(parser, .Expression)
					return {}, false
				}
				if token_is(parser, .Open_Paren) {
					first := parser.nodes.storage[int(variables[0])]
					bound_span, bound_span_ok := spanning(parser, parser.nodes.storage[int(left)].span, pattern_node.span); assert(bound_span_ok)
					bound, bound_ok := append_node(parser, Node{kind=.Binding, span=bound_span, left=left, right=pattern, name_span=first.name_span, has_name_span=true})
					if !bound_ok do return {}, false
					parser.pending_reduce_name = first.name_span
					parser.has_pending_reduce = true
					if pipe_root != invalid_id {
						tail := &parser.nodes.storage[int(pipe_tail)]
						tail.right = bound
						tail.has_child = false
						return pipe_root, true
					}
					return bound, true
				}
				if !token_is(parser, .Pipe) {
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
			// When the parenthesized group was opened as the right operand of
			// an already-live pipe, the outer current is intentionally empty.
			// Carry the completed group into that pipe now; otherwise the old
			// tail remains an open placeholder and lowering rejects the valid
			// filter as an invalid AST.
			current_pipe_count = frame_state.outer_pipe_count
			term_prefix_overhead = frame_state.outer_prefix_overhead
			minus_before_group = frame_state.outer_minus_before_group
			term_has_postfix = frame_state.outer_term_has_postfix
			assert(binary_frame == frame_state.outer_binary_boundary)
			term = frame_state.parenthesized
			// Assignment parsing returns before the regular postfix loop. Allow
			// the narrow dynamic-index assignment wrapper `(.[key] = value)?`
			// to consume its question suffix at the group boundary.
			if token_is(parser, .Question) && result >= 0 {
				child_node := parser.nodes.storage[int(result)]
				if child_node.kind == .Dynamic_Index_Assign {
					advance(parser)
					optional_span, optional_span_ok := spanning(parser, frame_node.span, child_node.span); assert(optional_span_ok)
					optional, optional_ok := append_node(parser, Node{kind=.Optional, span=optional_span, child=frame_state.parenthesized, has_child=true})
					if !optional_ok do return {}, false
					term = optional
				}
			}
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
	valid_prefix_add := right_node.form == .Binary && right_node.binary_operator == .Add && right_node.left >= 0 && right_node.right >= 0 &&
		parser.nodes.storage[int(right_node.left)].kind == .String &&
		parser.nodes.storage[int(right_node.right)].kind == .Identity
	valid_rhs := valid_prefix_add || right_node.kind == .Identity || right_node.kind == .Field ||
		right_node.kind == .Number || right_node.kind == .Boolean ||
		right_node.kind == .Null || right_node.kind == .String
	if right_node.form != .Kinded || (right_node.form == .Kinded && right_node.container_kind != .None) || (!valid_prefix_add && (right_node.has_child || right_node.has_value)) || !valid_rhs {
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
		return spelling == "false" || spelling == "true" || spelling == "null" || spelling == "nan" || spelling == "infinite" || spelling == "sort_by" || spelling == "group_by" || spelling == "INDEX"
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
			// A bare dot is a valid dynamic index key.  The generic filter
			// parser routes a standalone dot through the postfix diagnostic
			// guard, which is correct at top level but loses the identity key
			// when the dot is immediately closed by this bracket.  Lower the
			// identity directly and keep the existing Index instruction ABI.
			// If a suffix follows, let append_postfix preserve the already
			// supported `.foo`/`.[]` dynamic-key forms; arithmetic expressions
			// still fail at the enclosing close-bracket check.
			if token_is(parser, .Dot) {
				dot_span := parser.lookahead.token.span
				advance(parser)
				identity, identity_ok := append_node(parser, Node{kind=.Identity, span=dot_span})
				if !identity_ok do return {}, false
				// A bounded arithmetic key such as `[. + 0]` can reuse the
				// existing Binary and dynamic-Index instruction contracts.  The
				// general parser cannot restart with an already-built left term,
				// so consume the first operator here and let the ordinary parser
				// handle the complete right operand up to the closing bracket.
				binary_operator, _, has_binary_operator := binary_from_token(parser)
				if has_binary_operator {
					operator := parser.lookahead.token
					advance(parser)
					right, right_ok := parse_pipe(parser, .Close_Bracket, false)
					if !right_ok || !token_is(parser, .Close_Bracket) {
						fail_from_lookahead(parser, .Close_Bracket)
						return {}, false
					}
					binary_span, binary_span_ok := spanning(parser, dot_span, parser.nodes.storage[int(right)].span)
					assert(binary_span_ok)
					binary, binary_ok := append_node(parser, Node{
						form = .Binary,
						span = binary_span,
						left = identity,
						right = right,
						binary_operator = binary_operator,
						operator_span = operator.span,
						has_operator_span = true,
					})
					if !binary_ok do return {}, false
					close := parser.lookahead.token
					advance(parser)
					span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
					assert(span_ok)
					node, ok = append_node(parser, Node{
						kind = .Index,
						span = span,
						child = node,
						has_child = true,
						index_key = binary,
						has_index_key = true,
					})
					if !ok do return {}, false
					continue
				}
				if token_is(parser, .Close_Bracket) {
					close := parser.lookahead.token
					advance(parser)
					span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
					assert(span_ok)
					node, ok = append_node(parser, Node{
						kind = .Index,
						span = span,
						child = node,
						has_child = true,
						index_key = identity,
						has_index_key = true,
					})
					if !ok do return {}, false
					continue
				}
				if token_is(parser, .Colon) {
					// Preserve the existing bounded dynamic-start slice form
					// (`[.:end]`) after recognizing the dot as identity.
					advance(parser)
					end_index := Node_Id(-1)
					if !token_is(parser, .Close_Bracket) {
						if token_is(parser, .Number) || (token_is(parser, .Identifier) && token_spelling(parser, parser.lookahead.token) == "nan") {
							end_index, ok = append_number_node(parser, parser.lookahead.token.span)
							if !ok do return {}, false
							advance(parser)
						} else {
							end_index, ok = parse_pipe(parser, .Close_Bracket, false)
							if !ok do return {}, false
						}
					}
					if !token_is(parser, .Close_Bracket) { fail_from_lookahead(parser, .Close_Bracket); return {}, false }
					close := parser.lookahead.token
					advance(parser)
					span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
					assert(span_ok)
					new_term, slice_ok := append_node(parser, Node{kind=.Slice, span=span, child=node, has_child=true, left=identity, right=end_index})
					if !slice_ok do return {}, false
					node = new_term
					continue
				}
				key, key_ok := append_postfix(parser, identity, live_prefix_depth, live_pipe_count, live_comma_count, live_binary_count, event_overhead, has_postfix)
				if !key_ok || !token_is(parser, .Close_Bracket) {
					fail_from_lookahead(parser, .Close_Bracket)
					return {}, false
				}
				close := parser.lookahead.token
				advance(parser)
				span, span_ok := spanning(parser, parser.nodes.storage[int(node)].span, close.span)
				assert(span_ok)
				node, ok = append_node(parser, Node{kind=.Index, span=span, child=node, has_child=true, index_key=key, has_index_key=true})
				if !ok do return {}, false
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
				// A standalone identity is a valid dynamic index key in jq
				// (`[][.]`, `[1][.]`).  The general postfix-dot guard below
				// intentionally rejects a trailing dot, so recognize this
				// immediate key here without broadening filter parsing.
				key: Node_Id
				key_ok: bool
				if token_is(parser, .Dot) {
					dot := parser.lookahead.token
					advance(parser)
					key, key_ok = append_node(parser, Node{kind=.Identity, span=dot.span})
				} else {
					key, key_ok = parse_pipe(parser, .Close_Bracket, false)
				}
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

// lower_walk_filter builds jq's recursive walk definition directly in the
// syntax arena.  The generated Call edge points back to the body root, so the
// compiler/program recursion contract remains intact; no source-text rewrite
// or evaluator special case is involved.  The filter argument is shared as the
// final pipe child and therefore retains its normal stream/error semantics.
@(private="package")
lower_walk_filter :: proc(parser: ^Parser, filter: Node_Id, span: diagnostic.Span) -> (Node_Id, bool) {
	if filter < 0 || int(filter) >= parser.nodes.count do return {}, false

	ok: bool
	type_object: Node_Id
	type_object, ok = append_node(parser, Node{kind=.Type, span=span})
	if !ok do return {}, false
	object_name: Node_Id
	object_name, ok = append_node(parser, Node{kind=.String, span=span, string_text="object", has_string_text=true})
	if !ok do return {}, false
	is_object: Node_Id
	is_object, ok = append_node(parser, Node{
		form=.Binary, span=span, left=type_object, right=object_name,
		binary_operator=.Equal, operator_span=span, has_operator_span=true,
	})
	if !ok do return {}, false

	type_array: Node_Id
	type_array, ok = append_node(parser, Node{kind=.Type, span=span})
	if !ok do return {}, false
	array_name: Node_Id
	array_name, ok = append_node(parser, Node{kind=.String, span=span, string_text="array", has_string_text=true})
	if !ok do return {}, false
	is_array: Node_Id
	is_array, ok = append_node(parser, Node{
		form=.Binary, span=span, left=type_array, right=array_name,
		binary_operator=.Equal, operator_span=span, has_operator_span=true,
	})
	if !ok do return {}, false

	identity: Node_Id
	identity, ok = append_node(parser, Node{kind=.Identity, span=span})
	if !ok do return {}, false
	recursive_call: Node_Id
	recursive_call, ok = append_node(parser, Node{kind=.Call, span=span, child=Node_Id(-1)})
	if !ok do return {}, false
	map_values: Node_Id
	map_values, ok = append_node(parser, Node{kind=.Map_Values, span=span, child=recursive_call, has_child=true})
	if !ok do return {}, false
	map_array: Node_Id
	map_array, ok = append_node(parser, Node{kind=.Map, span=span, child=recursive_call, has_child=true})
	if !ok do return {}, false
	array_branch: Node_Id
	array_branch, ok = append_node(parser, Node{
		kind=.If, span=span,
		if_condition=is_array, has_if_condition=true,
		if_then=map_array, has_if_then=true,
		if_else=identity, has_if_else=true,
	})
	if !ok do return {}, false
	object_branch: Node_Id
	object_branch, ok = append_node(parser, Node{
		kind=.If, span=span,
		if_condition=is_object, has_if_condition=true,
		if_then=map_values, has_if_then=true,
		if_else=array_branch, has_if_else=true,
	})
	if !ok do return {}, false
	body: Node_Id
	body, ok = append_node(parser, Node{kind=.Pipe, span=span, left=object_branch, right=filter})
	if !ok do return {}, false
	parser.nodes.storage[int(recursive_call)].child = body
	parser.nodes.storage[int(recursive_call)].has_child = true
	root_call: Node_Id
	root_call, ok = append_node(parser, Node{kind=.Call, span=span, child=body, has_child=true})
	if !ok do return {}, false
	return root_call, true
}

@(private="package")
static_key_filter :: proc(parser: ^Parser, node_id: Node_Id) -> bool {
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Field && node.has_name_span && !node.has_child && !node.has_value do return true
	if (node.kind == .Number || node.kind == .Boolean || node.kind == .Null) && !node.has_child && !node.has_value do return true
	if node.form == .Binary && node.has_operator_span {
		switch node.binary_operator {
		case .Add, .Subtract, .Multiply, .Divide, .Modulo, .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
			return static_key_filter(parser, node.left) && static_key_filter(parser, node.right)
		case .Defined_Or, .Or, .And:
			return false
		}
	}
	if node.kind == .Comma && !node.has_child && !node.has_value {
		return static_key_filter(parser, node.left) && static_key_filter(parser, node.right)
	}
	return false
}

// lower_static_keyed_call materializes the bounded static forms
// sort_by(.field[, .field]) and group_by(.field) using the stable keyed sort
// and grouping opcodes. Dynamic key filters remain parser-owned and are not
// admitted by this narrow lowering.
lower_static_keyed_call :: proc(parser: ^Parser, token: Token, spelling: string) -> (Node_Id, bool) {
	if !token_is(parser, .Open_Paren) do return {}, false
	advance(parser)
	argument, argument_ok := parse_pipe(parser, .Close_Paren, false)
	if !argument_ok || !token_is(parser, .Close_Paren) {
		fail_from_lookahead(parser, .Close_Paren)
		return {}, false
	}
	close := parser.lookahead.token
	advance(parser)
	if !static_key_filter(parser, argument) {
		fail_from_lookahead(parser, .Expression)
		return {}, false
	}
	key := argument
	argument_node := parser.nodes.storage[int(argument)]
	if argument_node.kind == .Comma {
		key_span := parser.nodes.storage[int(argument)].span
		key_ok: bool
		key, key_ok = append_node(parser, Node{kind=.Identity, container_kind=.Array, span=key_span, value=argument, has_value=true})
		if !key_ok do return {}, false
	}
	identity, identity_ok := append_node(parser, Node{kind=.Identity, span=token.span})
	if !identity_ok do return {}, false
	pair_span := token.span
	pair_value, pair_ok := append_node(parser, Node{kind=.Comma, span=pair_span, left=key, right=identity})
	if !pair_ok do return {}, false
	array_span := token.span
	pair_array, pair_array_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=array_span, value=pair_value, has_value=true})
	if !pair_array_ok do return {}, false
	map_span, map_span_ok := spanning(parser, token.span, close.span)
	assert(map_span_ok)
	mapped, mapped_ok := append_node(parser, Node{kind=.Map, span=map_span, child=pair_array, has_child=true})
	if !mapped_ok do return {}, false
	sorted, sorted_ok := append_node(parser, Node{kind=.Sort_By_Key, span=map_span})
	if !sorted_ok do return {}, false
	pipe_span, pipe_span_ok := spanning(parser, parser.nodes.storage[int(mapped)].span, parser.nodes.storage[int(sorted)].span)
	assert(pipe_span_ok)
	ordered, ordered_ok := append_node(parser, Node{kind=.Pipe, span=pipe_span, left=mapped, right=sorted})
	if !ordered_ok do return {}, false
	if spelling == "sort_by" {
		one := parser.nodes.storage[int(identity)].span
		extract, extract_ok := append_node(parser, Node{kind=.Index, span=one, child=identity, has_child=true, number_text="1", has_number_text=true})
		if !extract_ok do return {}, false
		unmap, unmap_ok := append_node(parser, Node{kind=.Map, span=map_span, child=extract, has_child=true})
		if !unmap_ok do return {}, false
		final_span, final_span_ok := spanning(parser, parser.nodes.storage[int(ordered)].span, parser.nodes.storage[int(unmap)].span)
		assert(final_span_ok)
		return append_node(parser, Node{kind=.Pipe, span=final_span, left=ordered, right=unmap})
	}
	grouped, grouped_ok := append_node(parser, Node{kind=.Group_By_Key, span=map_span})
	if !grouped_ok do return {}, false
	final_span, final_span_ok := spanning(parser, parser.nodes.storage[int(ordered)].span, parser.nodes.storage[int(grouped)].span)
	assert(final_span_ok)
	return append_node(parser, Node{kind=.Pipe, span=final_span, left=ordered, right=grouped})
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
static_nonnegative_integer :: proc(text: string) -> bool {
	if len(text) == 0 do return false
	for byte in text { if byte < '0' || byte > '9' do return false }
	return true
}

@(private="package")
lower_static_del_filter :: proc(parser: ^Parser, node_id: Node_Id) -> (Node_Id, bool) {
	invalid := Node_Id(-1)
	if int(node_id) < 0 || int(node_id) >= parser.nodes.count do return invalid, false
	node := parser.nodes.storage[int(node_id)]
	if node.kind == .Parenthesized && node.has_child do return lower_static_del_filter(parser, node.child)
	if node.kind == .Empty {
		return append_node(parser, Node{kind=.Identity, span=node.span})
	}
	if node.kind == .Identity && !node.has_child && !node.has_value {
		empty_path, empty_path_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span})
		if !empty_path_ok do return invalid, false
		outer, outer_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=empty_path, has_value=true})
		if !outer_ok do return invalid, false
		return append_node(parser, Node{kind=.Delpaths, span=node.span, child=outer, has_child=true})
	}
	if node.kind == .Pipe {
		left_paths, left_ok := lower_static_del_group_paths(parser, node.left)
		right_selector := node.right
		// A piped numeric selector stream is applied to each base path in
		// original coordinates, so lower its leaves in descending order before
		// forming the Cartesian product.
		selector_ids: [16]Node_Id
		selector_count := 0
		collect_pipe_indices :: proc(parser: ^Parser, id: Node_Id, ids: ^[16]Node_Id, count: ^int) -> bool {
			if id < 0 || int(id) >= parser.nodes.count || count^ >= len(ids) do return false
			n := parser.nodes.storage[int(id)]
			if n.kind == .Parenthesized && n.has_child do return collect_pipe_indices(parser, n.child, ids, count)
			if n.kind == .Comma { return collect_pipe_indices(parser, n.left, ids, count) && collect_pipe_indices(parser, n.right, ids, count) }
			if n.kind != .Index || !n.has_number_text || !static_nonnegative_integer(n.number_text) do return false
			ids[count^] = id; count^ += 1
			return true
		}
		if collect_pipe_indices(parser, node.right, &selector_ids, &selector_count) && selector_count > 1 {
			for left in 0..<selector_count {
				best := left
				for right_index in (left+1)..<selector_count {
					a := parser.nodes.storage[int(selector_ids[best])].number_text
					b := parser.nodes.storage[int(selector_ids[right_index])].number_text
					if len(a) < len(b) || (len(a) == len(b) && b > a) { best = right_index }
				}
				if best != left { selector_ids[left], selector_ids[best] = selector_ids[best], selector_ids[left] }
			}
			right_selector = selector_ids[0]
			for selector_index in 1..<selector_count {
				span := node.span
				right_selector, _ = append_node(parser, Node{kind=.Comma, span=span, left=right_selector, right=selector_ids[selector_index]})
			}
		}
		right_paths, right_ok := lower_static_del_group_paths(parser, right_selector)
		if !left_ok || !right_ok do return invalid, false
		product, product_ok := lower_static_del_path_product(parser, left_paths, right_paths)
		if !product_ok do return invalid, false
		grouped, grouped_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=product, has_value=true})
		if !grouped_ok do return invalid, false
		return append_node(parser, Node{kind=.Delpaths, span=node.span, child=grouped, has_child=true})
	}
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

// lower_static_del_path_product forms the Cartesian product of two static
// path streams. Each leaf is an inner path array; concatenating its component
// comma trees yields the path used by Delpaths. Filters, dynamic keys, and
// non-array path leaves fail closed in the callers that build these streams.
lower_static_del_path_product :: proc(parser: ^Parser, left, right: Node_Id) -> (Node_Id, bool) {
	invalid := Node_Id(-1)
	if left < 0 || right < 0 || int(left) >= parser.nodes.count || int(right) >= parser.nodes.count do return invalid, false
	left_node := parser.nodes.storage[int(left)]
	right_node := parser.nodes.storage[int(right)]
	if left_node.kind == .Comma {
		l, lok := lower_static_del_path_product(parser, left_node.left, right)
		r, rok := lower_static_del_path_product(parser, left_node.right, right)
		if !lok || !rok do return invalid, false
		span, span_ok := spanning(parser, parser.nodes.storage[int(l)].span, parser.nodes.storage[int(r)].span); assert(span_ok)
		return append_node(parser, Node{kind=.Comma, span=span, left=l, right=r})
	}
	if right_node.kind == .Comma {
		l, lok := lower_static_del_path_product(parser, left, right_node.left)
		r, rok := lower_static_del_path_product(parser, left, right_node.right)
		if !lok || !rok do return invalid, false
		span, span_ok := spanning(parser, parser.nodes.storage[int(l)].span, parser.nodes.storage[int(r)].span); assert(span_ok)
		return append_node(parser, Node{kind=.Comma, span=span, left=l, right=r})
	}
	if !left_node.has_value || left_node.container_kind != .Array || !right_node.has_value || right_node.container_kind != .Array do return invalid, false
	components, component_ok := append_node(parser, Node{kind=.Comma, span=left_node.span, left=left_node.value, right=right_node.value})
	if !component_ok do return invalid, false
	span, span_ok := spanning(parser, left_node.span, right_node.span); assert(span_ok)
	return append_node(parser, Node{kind=.Identity, container_kind=.Array, span=span, value=components, has_value=true})
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
		return append_node(parser, Node{kind=.Comma, span=node.span, left=left, right=right})
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
	} else if node.kind == .Field {
		if !node.has_name_span do return invalid, false
		if node.has_child {
			nested_components, nested_components_ok := lower_static_del_path_components(parser, node_id)
			if !nested_components_ok do return invalid, false
			inner, inner_ok := append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=nested_components, has_value=true})
			if !inner_ok do return invalid, false
			return append_node(parser, Node{kind=.Identity, container_kind=.Array, span=node.span, value=inner, has_value=true})
		}
	} else {
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
	if node.kind == .Field && node.has_name_span {
		if !node.has_child do return node_id, true
		base := parser.nodes.storage[int(node.child)]
		if base.kind == .Identity && !base.has_child && !base.has_value do return node_id, true
		prefix, prefix_ok := lower_static_del_path_components(parser, node.child)
		if !prefix_ok do return {}, false
		span, span_ok := spanning(parser, parser.nodes.storage[int(prefix)].span, node.span); assert(span_ok)
		return append_node(parser, Node{kind=.Comma, span=span, left=prefix, right=node_id})
	}
	if node.kind == .Index && node.has_child && node.has_number_text {
		base, base_ok := lower_static_del_path_components(parser, node.child)
		if !base_ok do return {}, false
		component, component_ok := append_node(parser, Node{kind=.Number, span=node.span, number_text=node.number_text, has_number_text=true})
		if !component_ok do return {}, false
		span, span_ok := spanning(parser, parser.nodes.storage[int(base)].span, node.span); assert(span_ok)
		return append_node(parser, Node{kind=.Comma, span=span, left=base, right=component})
	}
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
