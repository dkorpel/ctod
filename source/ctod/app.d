module ctod.app;

import tree_sitter.api;
import core.stdc.stdlib: free;
import core.stdc.string: strlen;

import bops.os.console: Stdout, Stderr, println;
import std.path: withExtension;
import std.file: read, write;
import bops.os.file;
import bops.os.file: baseName, fileExtension, readFile;

import ctod.translate;
private:

int main(string[] args)  {
	if (args.length < 2) {
		Stderr.println("give at least one file argument");
		return -1;
	}
	try {
		//printHelp(args[0]);
		bool stripComments = false;
		foreach(i; 1..args.length) {
			TranslationSettings settings;
			if (args[i] == "--strip") {
				settings.stripComments = true;
			} else if (args[i] == "--help") {
				printHelp(args[0]);
			} else {
				const fname = args[i];
				if (!(fname.fileExtension == ".c" || fname.fileExtension == ".h")) {
					Stderr.println("file shoud have .c or .h extension, not ", fname.fileExtension);
					return -1;
				}
				//readFile(fname);
				scope source = cast(string) read(fname);
				scope(exit) {/*freeM(source)*/}

				const moduleName = fname.baseName;

				if (File f = File.open(fpath!"result", FileAccess.write, FileTranslation.text)) {

				}

				write(fname.withExtension(".d"), translateFile(source, moduleName, settings));
			}
		}
	} catch (Exception e) {
		Stdout.println(e.msg);
		return -1;
	}
	return 0;
}

void printHelp(string name) {
	Stdout.println("Usage: ", name, " [FILES]\nOptions:\n  --strip  strip comments");
}
