module ctod.translate;

import ctod;
import tree_sitter.api, tree_sitter.wrapper;
import std.format;
import std.stdio;

private immutable moduleHeader = "/// Translated from C to D
module %s;

extern(C): @nogc: nothrow: __gshared:
";

private immutable hasVersion = q{
private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
};

///
string translateFile(string source, string moduleName) {
	Node* root = parseCtree(source);
	assert(root);
	auto ctx = TranslationContext("foo.c", source);
	translateNode(ctx, *root);
	string result = format(moduleHeader, moduleName);
	if (ctx.needsHasVersion) {
		result ~= hasVersion;
	}
	if (ctx.needsClong) {
		result ~= "import core.stdc.config: c_long, c_ulong;\n";
	}
	if (ctx.needsWchar) {
		result ~= "import core.stdc.stddef: wchar_t;";
	}
	result ~=root.output;
	return result;
}

/// What the C macro is for
enum MacroType {
	none, // und
	manifestConstant, // #define three 3
	inlineFunc, // #define SQR(x) (x*x)
	versionId, // #ifdef _WIN32_
	staticIf,
}

package struct Scope {
	Scope* parent = null;
	Decl[string] table;
}

/// A single .c file
package struct TranslationContext {

	string fileName;
	string source;
	string moduleName;

	bool needsHasVersion = false; // HasVersion(string) template is needed
	bool needsClong = false; // needs c_long types (long has no consistent .sizeof, 4 on 64-bit Windows, 8 on 64-bit Linux)
	bool needsWchar = false; // needs wchar_t type (wchar on Windows, dchar on Linux)

	/// global variables and function declarations
	Decl[string] symbolTable;
	Decl[string] localSymbolTable;

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}

	int uniqueIdCounter = 0;
	string uniqueIdentifier(string suggestion = null) {
		import std.conv: text;
		import std.ascii: toUpper;
		if (suggestion.length > 0) {
			return "_" ~ suggestion[0].toUpper ~ suggestion[1..$];
		} else {
			return "_I"~(uniqueIdCounter++).text;
		}
	}
}

///
void translateNode(ref TranslationContext ctu, ref Node node) {
	if (node.isTranslated) {
		return;
	}
	if (tryTranslatePreprocessor(ctu, node)) {
		return;
	}
	if (tryTranslateDeclaration(ctu, node)) {
		return;
	}
	if (tryTranslateMisc(ctu, node)) {
		return;
	}

	foreach(ref c; node.children) {
		translateNode(ctu, c);
	}
	node.isTranslated = true;
	/+
	return "";
	//writefln("> %20s: %s", node.type, "..."); // nodeSource(node, )
	+/
}

bool tryTranslateMisc(ref TranslationContext ctu, ref Node node) {
	switch (node.type) {
		case "number_literal":
			if (node.source.length >= 2) {
				const suffix = node.source[$-2..$];
				if (suffix == ".f" || suffix == ".F") {
					node.replace(node.source[0..$-2]~".0f");
				}

			}
		case "concatenated_string":
			// "a" "b" "c" => "a"~"b"~"c"
			bool first = true;
			foreach(ref c; node.children) {
				if (c.type == "string_literal") {
					if (first) {
						first = false;
					} else {
						c.prepend("~ ");
					}
				}
			}
			return true;
		case "primitive_type":
			if (string s = replacePrimitiveType(node.source)) {
				node.replace(s);
				return true;
			}
			return false;
		case "null":
			return node.replace("null");

		case "type_definition":
			// Decl[] decls = parseDecls(ctu, *c);
			auto typeField = node.childField("type");
			auto declaratorField = node.childField("declarator");
			if (!declaratorField || !typeField) {
				return true;
			}
			if (auto structId = typeField.childField("name")) {
				if (typeField.type == "struct_specifier" || typeField.type == "union_specifier") {
					if (auto bodyNode = typeField.childField("body")) {
						translateNode(ctu, *bodyNode);
					} if (declaratorField.type == "type_identifier" && declaratorField.source == structId.source) {
						// typedef struct X X; => uncomment, not applicable to D
						node.prepend("/+");
						node.append("+/");
						return true;
					}
				}
				if (typeField.type == "enum_specifier") {
					if (auto bodyNode = typeField.childField("body")) {
						translateNode(ctu, *bodyNode);
					}
					if (auto nameNode = typeField.childField("name")) {

					}
				}
			}
			break;
		case "typedef":
			return node.replace("alias");
		case "sizeof_expression":
			if (auto typeNode = node.childField("type")) {
				// sizeof(short) => (short).sizeof
				translateNode(ctu, *typeNode);
				node.replace("" ~ typeNode.output ~ ".sizeof");
			} else if (auto valueNode = node.childField("value")) {
				translateNode(ctu, *valueNode);
				// `sizeof short` => `short.sizeof`
				if (valueNode.type == "identifier") {
					node.replace("" ~ valueNode.output ~ ".sizeof");
				} else {
					// sizeof(3) => typeof(3).sizeof
					// brackets may be redundant
					node.replace("typeof(" ~ valueNode.output ~ ").sizeof");
				}
			}
			break;

		case "->":
			return node.replace(".");
		case "cast_expression":
			if (auto c = node.firstChildType("(")) {
				c.replace("cast(");
			}
			if (auto c = node.childField("type")) {
				InlineType[] inlineTypes;
				Decl[] decls = parseDecls(ctu, *c, inlineTypes); //todo: emit inline types?
				if (decls.length == 1) {
					c.replace(decls[0].toString());
				}
			}
			return false;
		case "expression_statement":
			// ; as empty statement not allowed in D, for(;;); => for(;;) {}
			if (node.source == ";") {
				return node.replace("{}");
			}
			break;
		case "struct_specifier":
		case "union_specifier":
			// Trailing ; are children of the translation unit, and they are removed
			// However, opaque structs/unions still need them
			if (auto bodyNode = node.childField("body")) {
				//
			} else {
				node.append(";");
			}
			break;
		case "translation_unit":
			// these are trailing ; after union and struct definitions.
			// we don't want them in D
			foreach(ref c; node.children) {
				if (c.type == ";") {
					c.replace("");
				}
			}
			break;
		case "call_expression":
			// TODO: append .ptr to array parameters
			// prepend & to functions converted to function pointers
			break;
		default: break;
	}
	return false;
}
