/**
Translate C macros
*/
module ctod.cpreproc;

import ctod.translate;
import tree_sitter.wrapper;

/// Returns: true if a replacement was added
bool preprocReplacements(ref CTranslationUnit ctu, const Node node, ref Replacement[] replacements) {
	const nodeSource = ctu.source[node.start..node.end];
	switch (node.type) {
		case "preproc_if":
			//replacements ~= Replacement(node.start, node.start + "#if".length, "static if");
			if (auto conditionNode = node.childByField("condition")) {
				replacements ~= Replacement(conditionNode.start, conditionNode.start, "(");
				replacements ~= Replacement(conditionNode.end, conditionNode.end, ") {");
			}
			//getReplacements(ctu, node, replacements);
			//replacements ~= Replacement(node.end - "#endif".length, node.end, "}");
			break;
		case "#endif":
			replacements ~= Replacement(node.start, node.end, "}");
			break;
		case "#elif":
			replacements ~= Replacement(node.start, node.end, "else static if");
			break;
		case "#else":
			replacements ~= Replacement(node.start, node.end, "else");
			break;
		case "#if":
			replacements ~= Replacement(node.start, node.end, "static if");
			break;
		case "preproc_include":
			//replacements ~= Replacement(node.start, node.start + "#include".length, "import");
			break;
		case "#include":
			replacements ~= Replacement(node.start, node.end, "import");
			break;
		case "preproc_def":
			//TSNode valueNode = ts_node_child_by_field_name(node, "value".ptr, "value".length);
			if (auto valueNode = node.childByField("value")) {
				// todo
				//replacements ~= Replacement(node.start, node.start, "enum x = 0;");
			} else {
				//replacements ~= Replacement(node.start, node.start, "//");
			}
			break;
		case "#define":
			replacements ~= Replacement(node.start, node.end, "enum");
			break;
		case "system_lib_string":
			string lib = nodeSource[1..$-1]; // slice to strip off angle brackets in <stdio.h>
			if (string importName = translateSysLib(lib)) {
				replacements ~= Replacement(node.start, node.end, importName~";");
			} else {
				//assert(0, nodeSource);
			}
			break;
		default: return false;
	}
	return true;
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
