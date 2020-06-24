module ctod.util;

import tree_sitter.api;
import core.stdc.stdio: printf;

/// print all field names in a language
///
/// fields are specific names given to certain children,
/// e.g. the 2nd child of an if-statement node can have name "condition"
void printFields(TSLanguage* language) {
	printf("Fields:\n");
	const count = cast(ushort) ts_language_field_count(language);
	foreach(ushort i; 0..count) {
		const char* str = ts_language_field_name_for_id(language, i);
		printf("%d: %s\n", i, str);
	}
}

/// print all symbols in a language
void printSymbols(TSLanguage* language) {
	printf("Symbols:\n");
	const count = cast(ushort) ts_language_symbol_count(language);
	foreach(ushort i; 0..count) {
		const char* str = ts_language_symbol_name(language, i);
		printf("%d: %s\n", i, str);
	}
}
