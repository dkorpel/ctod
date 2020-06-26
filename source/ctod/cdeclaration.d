module ctod.cdeclaration;

import ctod.translate;
import tree_sitter.wrapper;

bool tryTranslateDeclaration(ref TranslationContext ctu, ref Node node) {
	const nodeSource = ctu.source[node.start..node.end];
	switch (node.type) {
		case "field_identifier":
		case "identifier":
			if (string s = replaceIdentifier(nodeSource)) {
				return node.replace(s);
			}
			return true;
		/+
		case "{":
			if (node.parent.type == "initializer_list") {
				return "[";
			} else {
				return null;
			}
		case "}":
			if (node.parent.type == "initializer_list") {
				return "]";
			} else {
				return null;
			}
		+/
		default: break;
	}
	return false;
}

/// modify C identifiers that are keywords in D
string replaceIdentifier(string s) {
	switch(s) {
		case "in": return "in_";
		case "out": return "out_";
		case "version": return "version_";
		case "debug": return "debug_";
		case "deprecated": return "deprecated_";

		// unlikely but possible
		case "scope": return "scope_";
		case "foreach": return "foreach_";
		case "pragma": return "pragma_";

		default: return null;
	}
}