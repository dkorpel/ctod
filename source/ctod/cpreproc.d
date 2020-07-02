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
		case "#elif":
			return node.replace("} else static if");
		case "#include":
			return node.replace("public import");
		case "preproc_call":
			if (auto directive = node.childField("directive")) {
				if (directive.source == "#error") {
					directive.replace("static assert");
					if (auto argument = node.childField("argument")) {
						argument.prepend("(0, ");
						argument.append(")");
					}
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
					c.replace(c.source~";");
				}
			}
			break;
		case "preproc_function_def":
			if (auto c = node.firstChildType("#define")) {
				c.replace("auto");
			}
			if (auto c = node.firstChildType("preproc_arg")) {
				c.replace("{return"~c.source~";}");
			}
			if (auto c = node.childField("parameters")) {
				/+
				import std.conv, std.algorithm, std.range;
				int paramCount = 0;
				foreach(ref param; c.children) {
					if (param.type == "identifier") {
						param.prepend("T"~paramCount.text~" ");
						paramCount++;
					}
				}
				c.prepend("(" ~ iota(0, paramCount).map!(x => "T" ~ x.text~ (x==paramCount-1) ? ", " : "").joiner.text ~ ")");
				+/
			}
			break;
		case "preproc_ifdef":
			if (auto c = node.firstChildType("#ifdef")) {
				c.replace("version");
			}
			if (auto c = node.childField("name")) {
				c.prepend("(");
				c.append(") {");
				if (string s = findVersion(c.source)) {
					c.replace(s);
				}
			}
			break;
		case "preproc_defined":
			if (auto c = node.firstChildType("identifier")) {
				if (string s = findVersion(c.source)) {
					c.replace(s);
				} else {
					translateNode(ctu, *c);
				}
				ctu.needsHasVersion = true;
				return node.replace(`HasVersion!"` ~ c.replacement ~ `"`);
			}
			break;
		case "preproc_if":
			if (auto c = node.childField("condition")) {
				c.prepend("(");
				c.append(") {");
			}
			if (auto c = node.firstChildType("#if")) {
				c.replace("static if");
			}
			break;
		case "preproc_elif":
			if (auto c = node.childField("condition")) {
				c.prepend("(");
				c.append(") {");
				return false;
			}
			break;
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
