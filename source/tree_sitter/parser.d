module tree_sitter.parser;

extern (C): @nogc: nothrow:

enum ts_builtin_sym_error = cast(TSSymbol)-1;
enum ts_builtin_sym_end = 0;
enum TREE_SITTER_SERIALIZATION_BUFFER_SIZE = 1024;

alias TSSymbol = ushort;
alias TSFieldId = ushort;

struct TSFieldMapEntry {
    TSFieldId field_id;
    ubyte child_index;
    bool inherited;
}

struct TSFieldMapSlice {
    ushort index;
    ushort length;
}

alias TSStateId = ushort;

struct TSSymbolMetadata {
    import std.bitmanip: bitfields;

    mixin(bitfields!(bool, "visible", 1, bool, "named", 1, uint, "", 6));
}

struct TSLexer {
    int lookahead;
    TSSymbol result_symbol;
    void function(TSLexer*, bool) advance;
    void function(TSLexer*) mark_end;
    uint function(TSLexer*) get_column;
    bool function(const(TSLexer)*) is_at_included_range_start;
    bool function(const(TSLexer)*) eof;
}

enum TSParseActionType {
    TSParseActionTypeShift = 0,
    TSParseActionTypeReduce = 1,
    TSParseActionTypeAccept = 2,
    TSParseActionTypeRecover = 3
}

struct TSParseAction {
    import std.bitmanip: bitfields;

    union _Anonymous_0 {
        struct _Anonymous_1 {
            import std.bitmanip: bitfields;

            TSStateId state;

            mixin(bitfields!(bool, "extra", 1, bool, "repetition", 1, uint, "", 6));
        }

        _Anonymous_1 shift;

        struct _Anonymous_2 {
            TSSymbol symbol;
            short dynamic_precedence;
            ubyte child_count;
            ubyte production_id;
        }

        _Anonymous_2 reduce;
    }

    _Anonymous_0 params;

    mixin(bitfields!(TSParseActionType, "type", 4, uint, "", 4));
}

struct TSLexMode {
    ushort lex_state;
    ushort external_lex_state;
}

union TSParseActionEntry {
    TSParseAction action;

    struct _Anonymous_3 {
        import std.bitmanip: bitfields;

        ubyte count;

        mixin(bitfields!(bool, "reusable", 1, uint, "", 7));
    }

    _Anonymous_3 entry;
}

struct TSLanguage {
    uint version_;
    uint symbol_count;
    uint alias_count;
    uint token_count;
    uint external_token_count;
    const(char*)* symbol_names;
    const(TSSymbolMetadata)* symbol_metadata;
    const(ushort)* parse_table;
    const(TSParseActionEntry)* parse_actions;
    const(TSLexMode)* lex_modes;
    const(TSSymbol)* alias_sequences;
    ushort max_alias_sequence_length;
    bool function(TSLexer*, TSStateId) lex_fn;
    bool function(TSLexer*, TSStateId) keyword_lex_fn;
    TSSymbol keyword_capture_token;

    struct _Anonymous_4 {
        const(bool)* states;
        const(TSSymbol)* symbol_map;
        void* function() create;
        void function(void*) destroy;
        bool function(void*, TSLexer*, const(bool)* symbol_whitelist) scan;
        uint function(void*, char*) serialize;
        void function(void*, const(char)*, uint) deserialize;
    }

    _Anonymous_4 external_scanner;
    uint field_count;
    const(TSFieldMapSlice)* field_map_slices;
    const(TSFieldMapEntry)* field_map_entries;
    const(char*)* field_names;
    uint large_state_count;
    const(ushort)* small_parse_table;
    const(uint)* small_parse_table_map;
    const(TSSymbol)* public_symbol_map;
}

/*
 *  Lexer Macros
 */

/*
 *  Parse Table Macros
 */

extern (D) auto SMALL_STATE(T)(auto ref T id) {
    return id - LARGE_STATE_COUNT;
}

extern (D) auto STATE(T)(auto ref T id) {
    return id;
}

extern (D) auto ACTIONS(T)(auto ref T id) {
    return id;
}

// TREE_SITTER_PARSER_H_
