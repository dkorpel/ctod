module ctod.cdeclaration;

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