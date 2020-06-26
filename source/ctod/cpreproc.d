/**
Translate C macros
*/
module ctod.cpreproc;

import ctod.translate;
import tree_sitter.wrapper;

bool tryTranslatePreprocessor(ref TranslationContext ctu, ref Node node) {
	const nodeSource = ctu.source[node.start..node.end];
	switch (node.type) {
			// return translateNodeChildren(ctu, node) ~ ") {";
		case "#endif":
			return node.replace("}");
		case "#elif":
			return node.replace("} else static if (");
		case "#else":
			return node.replace("} else {");
		case "#if":
			return node.replace("static if (");
		case "#ifdef":
			return node.replace("version(");
		case "#include":
			return node.replace("import");
		case "identifier":
			// semicolon after version = X translation
			version(none)
			switch (node.parent.type) {
				case "preproc_def":
					if (ctu.macroType == MacroType.versionId) {
						return nodeSource ~ ";";
					}
					break;
				case "preproc_function_def":
					return nodeSource ~ "(T)";
				case "preproc_ifdef":
					return nodeSource ~ ") {";
				default: break;
			}
			return false;
		case "preproc_def":
			//if (auto valueNode = node.childByField("value")) {
			version(none)
			if (true) {
				ctu.macroType = MacroType.manifestConstant;
			} else {
				ctu.macroType = MacroType.versionId;
			}
			break;
		case "preproc_arg":
			version(none)
			with(MacroType) switch (ctu.macroType) {
				case manifestConstant: return "=" ~ nodeSource ~ ";";
				case inlineFunc: return "{return "~nodeSource~";}";
				default: break;
			}
			return false;
		case "preproc_function_def":
			ctu.macroType = MacroType.inlineFunc;
			break;
		case "preproc_if":
		case "preproc_elif":
			// TODO
			break;
		case "preproc_params":
			break;
		case "#define":
			with(MacroType) switch (ctu.macroType) {
				case manifestConstant: return node.replace("enum");
				case inlineFunc: return node.replace("auto");
				case versionId: return node.replace("version =");
				default: return false;
			}
		case "system_lib_string":
			if (nodeSource.length < "<>".length) {
				return false; // to short to slice
			}
			string lib = nodeSource[1..$-1]; // slice to strip off angle brackets in <stdio.h>
			if (string importName = translateSysLib(lib)) {
				return node.replace(importName~";");
			} else {
				import std.path: stripExtension;
				return node.replace(lib.stripExtension~";");
			}
		case "preproc_include":
		default: break;
	}
	return false;
}

/// Find version string to e.g. replace `#ifdef _WIN32` with `version(Windows)`
string findVersion(string s) {
	switch (s) {
		case "_WIN32": return "Windows"; // Win32, Win64?
		case "__APPLE__": return "OSX"; // MacOS?
		case "__cplusplus": return "none";
		default: return null;
	}
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
