/**
Translate C types
*/
module ctod.ctype;

/// replace C primitive types
string replacePrimitiveType(string original) {
	switch(original) {
		case "int8_t": return "byte";
		case "uint8_t": return "ubyte";
		case "int16_t": return "short";
		case "uint16_t": return "ushort";
		case "int32_t": return "int";
		case "uint32_t": return "uint";
		case "int64_t": return "long";
		case "uint64_t": return "ulong";
		default: return null;
	}
}

string replaceSemantic() {
	return null;
}