module ctod.translate;

/// A single .c file
struct CTranslationUnit {

	string fileName;
	string source;

	private string moduleName;

	this(string fileName) {
		import std.file: read;
		const source = cast(string) read(fileName);
		this(fileName, source);
	}

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}
}

void translateFile(string fileName) {

}