/**
Translate C macros
*/
module ctod.cpreproc;

import std.stdio;
import ctod.translate;
import tree_sitter.wrapper;

bool tryTranslatePreprocessor(ref TranslationContext ctu, ref Node node) {
	switch (node.type) {
		case "#else":
			return node.replace("} else {");
		case "#endif":
			return node.replace("}");
		case "#include":
			return node.replace("public import");
		case "preproc_call":
			auto argument = node.childField("argument");
			if (auto directive = node.childField("directive")) {
				switch(directive.source) {
					case "#error":
						directive.replace("static assert");
						if (argument) {
							argument.prepend("(0,");
							argument.append(");");
						}
						break;
					case "#pragma":
						// preceeding whitespace is part of the argument node
						if (argument && argument.source.length >= 4 && argument.source[$-4..$] == "once") {
							node.prepend("//");
							return true;
						}
						break;
					default:
						break;
				}
			}
			return true;
		case "preproc_def":
			if (auto valueNode = node.childField("value")) {
				if (auto c = node.firstChildType("#define")) {
					c.replace("enum");
				}
				if (auto c = node.firstChildType("preproc_arg")) {
					c.replace(" ="~c.source~";");
				}

			} else {
				if (auto c = node.firstChildType("#define")) {
					c.replace("version =");
				}
				if (auto c = node.childField("name")) {
					c.append(";");
				}
			}
			break;
		case "preproc_function_def":
			auto nameNode = node.childField("name");
			auto parametersNode = node.childField("parameters");
			auto valueNode = node.childField("value");
			if (!nameNode || !parametersNode) {
				return true;
			}
			if (!valueNode) {
				node.prepend("//");
				return true;
			}
			if (auto c = node.firstChildType("#define")) {
				c.replace("enum string");
			}
			string[] params;
			foreach(ref param; parametersNode.children) {
				if (param.type == "identifier") {
					params ~= param.source;
					param.prepend("string ");
				}
			}

			const result = lexMacroText(valueNode.source);
			valueNode.replace(" = " ~ result ~ ";");
			/+
			import std.conv, std.algorithm, std.range;
			int paramCount = 0;
			c.prepend("(" ~ iota(0, paramCount).map!(x => "T" ~ x.text~ (x==paramCount-1) ? ", " : "").joiner.text ~ ")");
			+/
			break;
		case "preproc_ifdef":
			auto nameNode = node.childField("name");
			if (!nameNode) {
				return true;
			}
			if (string s = findVersion(nameNode.source)) {
				nameNode.replace(s);
			}
			if (auto c = node.firstChildType("#ifdef")) {
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {");
			} else if (auto c = node.firstChildType("#ifndef")) {
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {} else {");
			}
			break;
		case "preproc_defined":
			return replaceDefined(ctu, node, false);
		case "preproc_if":
			auto c = node.childField("condition");
			auto ifnode = node.firstChildType("#if");
			if (!c || !ifnode) {
				return true;
			}

			if (c.type == "preproc_defined") {
				ifnode.replace("version");
				replaceDefined(ctu, *c, true);
				c.isTranslated = true;
				c.prepend("(");
				c.append(") {");
			} else {
				if (c.source == "0") {
					ifnode.replace("version");
					c.replace("(none) {");
				} else {
					ifnode.replace("static if");
					c.prepend("(");
					c.append(") {");
				}
			}
			break;
		case "preproc_elif":
			if (auto c = node.childField("condition")) {
				c.prepend("(");
				c.append(") {");
				if (auto ifnode = node.firstChildType("#elif")) {
					if (c.type == "preproc_defined") {
						ifnode.replace("} else version");
						replaceDefined(ctu, *c, true);
						c.isTranslated = true;
					} else {
						ifnode.replace("} else static if");
					}
					//c.replace("} else static if");
				}
			}
			return false;
		case "preproc_params":
			break;
		case "system_lib_string":
			if (node.source.length < "<>".length) {
				return false; // to short to slice
			}
			string lib = node.source[1..$-1]; // slice to strip off angle brackets in <stdio.h>
			if (string importName = translateSysLib(lib)) {
				return node.replace(importName~";");
			} else {
				import std.path: stripExtension;
				return node.replace(lib.stripExtension~";");
			}
		case "preproc_include":
			//if (auto c = node.firstChildType("string_literal")) {
			if (auto c = node.childField("path")) {
				c.replace(translateIncludePath(c.source));
			}
			break;
		default: break;
	}
	return false;
}

string lexMacroText(string s) {

	enum TokType { id, stringLit, other }

	string next() {
		// import std.regex:
		scope(exit) s = s[$..$];
		return s;
		/+
		while(i < s.length) {
			switch(s[i]) {
				case '\n', '\r', '\t', ' ':
					break;
				case '\\':

					break;
				default:
					break;
			}
		}
		+/
	}

	string result = "`";
	while(s.length) {
		result ~= next();
	}
	return result ~ "`";
	// notes: #x turns x into string literal
	// x in string literal not replaced
	/+
	import std.ascii: isAlphaNum;
	string s = valueNode.source;
	string result = "";

	bool bound = isAlphaNum(s[0]);
	size_t wordBegin = 0;
	foreach(i; 1..s.length) {

		const n = isAlphaNum(s[i]);
		if (n != bound) {
			const word = s[wordBegin..i];
			wordBegin = i;
			result ~= word;
		}
	}
	result ~= s[wordBegin..$];
	string result = "";
	size_t wordIndex = 0;
	for (size_t i = 0; i < s.length; i++) {
		bool inWord = false;
		switch(s[i]) {
			case 'a': .. case 'z':
			case 'A': .. case 'Z':
			case '0': .. case '9':
			case '_':
				inWord = true;
				goto default;
				// identifier
			case '#':
				// string
				break;
			case '\\':
				//if (i + 1 < s.length) switch (s[i+1])
				break;
			case '"':
				// in / out string literal
				goto default;
			default:
				result ~= s[i];
		}
	}
	+/
}

/// replace a defined(__WIN32__) to either `HasVersion!"Windows"` (in a `static if`) or just `Windows` (in a `version()`)
bool replaceDefined(ref TranslationContext ctu, ref Node node, bool inVersionStatement) {
	if (auto c = node.firstChildType("identifier")) {
		if (string s = findVersion(c.source)) {
			c.replace(s); // known #define translation
		} else {
			translateNode(ctu, *c); // reserved identifier replacement
		}
		if (inVersionStatement) {
			return node.replace(c.replacement);
		} else {
			ctu.needsHasVersion = true;
			return node.replace(`HasVersion!"` ~ c.replacement ~ `"`);
		}
	}
	return false;
}

/// Find version string to e.g. replace `#ifdef _WIN32` with `version(Windows)`
string findVersion(string s) {
	switch (s) {
		case "_WIN32": return "Windows"; // Win32, Win64?
		case "__APPLE__": return "OSX"; // MacOS?
		case "__CYGWIN__": return "Cygwin";
		case "__cplusplus": return "none";
		default: return null;
	}
}

string translateIncludePath(string s) {
	import std.array: replace;
	if (s.length < 5) return s;
	return s[1..$-3].replace("/", ".") ~ ";";
}

/// translate #include<> to an import in druntime.
string translateSysLib(string s) {
	switch (s) {
		// libc
		case "assert.h":  return "core.stdc.assert_";
		case "complex.h": return "core.stdc.complex";
		case "config.h":  return "core.stdc.config";
		case "ctype.h":   return "core.stdc.ctype";
		case "errno.h":   return "core.stdc.errno";
		case "fenv.h":    return "core.stdc.fenv";
		case "float_.h":  return "core.stdc.float_";
		case "inttypes.h":return "core.stdc.inttypes";
		case "limits.h":  return "core.stdc.limits";
		case "locale.h":  return "core.stdc.locale";
		case "math.h":    return "core.stdc.math";
		case "signal.h":  return "core.stdc.signal";
		case "stdarg.h":  return "core.stdc.stdarg";
		case "stddef.h":  return "core.stdc.stddef";
		case "stdint.h":  return "core.stdc.stdint";
		case "stdio.h":   return "core.stdc.stdio";
		case "stdlib.h":  return "core.stdc.stdlib";
		case "string.h":  return "core.stdc.string";
		case "tgmath.h":  return "core.stdc.tgmath";
		case "time.h":    return "core.stdc.time";
		case "wchar.h":   return "core.stdc.wchar_";
		case "wctype.h":  return "core.stdc.wctype";

		// windows
		case "windows.h": return "core.sys.windows.windows";

		// posix
		case "aio.h": return "core.sys.posix.aio";
		case "ar.h": return "core.sys.posix.ar";
		//case "config.h": return "core.sys.posix.config";
		case "dirent.h": return "core.sys.posix.dirent";
		case "dlfcn.h": return "core.sys.posix.dlfcn";
		case "fcntl.h": return "core.sys.posix.fcntl";
		case "grp.h": return "core.sys.posix.grp";
		case "iconv.h": return "core.sys.posix.iconv";
		//case "inttypes.h": return "core.sys.posix.inttypes";
		case "libgen.h": return "core.sys.posix.libgen";
		case "n.h": return "core.sys.posix.n";
		case "netdb.h": return "core.sys.posix.netdb";
		case "netin.h": return "core.sys.posix.netin";
		case "poll.h": return "core.sys.posix.poll";
		case "pthread.h": return "core.sys.posix.pthread";
		case "pwd.h": return "core.sys.posix.pwd";
		case "sched.h": return "core.sys.posix.sched";
		case "semaphore.h": return "core.sys.posix.semaphore";
		case "setjmp.h": return "core.sys.posix.setjmp";
		//case "signal.h": return "core.sys.posix.signal";
		//case "stdio.h": return "core.sys.posix.stdio";
		//case "stdlib.h": return "core.sys.posix.stdlib";
		case "s.h": return "core.sys.posix.s";
		case "syslog.h": return "core.sys.posix.syslog";
		case "termios.h": return "core.sys.posix.termios";
		//case "time.h": return "core.sys.posix.time";
		case "ucontext.h": return "core.sys.posix.ucontext";
		case "unistd.h": return "core.sys.posix.unistd";
		case "utime.h": return "core.sys.posix.utime";

		default: return null;
	}
}
