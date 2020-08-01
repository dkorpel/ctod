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
					case "#undef":
						node.replace("");
						break;
					default:
						// unrecognized call
						node.prepend("//! ");
						break;
				}
			}
			return true;
		case "preproc_def":
			if (auto valueNode = node.childField("value")) {
				if (auto c = node.firstChildType("#define")) {
					c.replace("enum");
				}
				if (auto c = node.childField("name")) {
					translateNode(ctu, *c);
					ctu.macroTable[c.output] = MacroType.manifestConstant;
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
					translateNode(ctu, *c);
					ctu.macroTable[c.output] = MacroType.versionId;
				}
			}
			break;
		case "preproc_function_def":
			removeSemicolons(node);
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
			translateNode(ctu, *nameNode);
			ctu.macroTable[nameNode.output] = MacroType.inlineFunc;

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
			removeSemicolons(node);
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
			nameNode.isTranslated = true;
			return false; // name node should not be translated as an identifier, but other children must be translated still
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
			if (auto pathNode = node.childField("path")) {
				if (pathNode.type == "string_literal") {
					pathNode.replace(translateIncludePath(pathNode.source));
				} else {
					// see case for system_lib_string above
					tryTranslatePreprocessor(ctu, *pathNode);
					// note: explicit call not really needed, children are
					// automatically translated by returning false
				}
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
		case "__WIN32__":
		case "WIN32":
		case "__MINGW32__":
		case "_WIN32": return "Windows"; // Win32, Win64?

		case "__linux__": return "linux";
		case "__MACH__":
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

		// todo: verify
		case "sys/inotify.h": return "core.sys.linux.sys.inotify";
		case "sys/timerfd": return "core.sys.linux.sys.timerfd";
		case "linux/limits": return "core.stdc.limits;";

		case "sys/filio.h": return "core.sys.posix.sys.filio";
		case "sys/ioccom.h": return "core.sys.posix.sys.ioccom";
		case "sys/ioctl.h": return "core.sys.posix.sys.ioctl";
		case "sys/ipc.h": return "core.sys.posix.sys.ipc";
		case "sys/mman.h": return "core.sys.posix.sys.mman";
		case "sys/msg.h": return "core.sys.posix.sys.msg";
		case "sys/resource.h": return "core.sys.posix.sys.resource";
		case "sys/select.h": return "core.sys.posix.sys.select";
		case "sys/shm.h": return "core.sys.posix.sys.shm";
		case "sys/socket.h": return "core.sys.posix.sys.socket";
		case "sys/stat.h": return "core.sys.posix.sys.stat";
		case "sys/statvfs.h": return "core.sys.posix.sys.statvfs";
		case "sys/time.h": return "core.sys.posix.sys.time";
		case "sys/ttycom.h": return "core.sys.posix.sys.ttycom";
		case "sys/types.h": return "core.sys.posix.sys.types";
		case "sys/uio.h": return "core.sys.posix.sys.uio";
		case "sys/un.h": return "core.sys.posix.sys.un";
		case "sys/utsname.h": return "core.sys.posix.sys.utsname";
		case "sys/wait.h": return "core.sys.posix.sys.wait";

		// Windows
		case "accctrl.h": return "core.sys.windows.accctrl";
		case "aclapi.h": return "core.sys.windows.aclapi";
		case "aclui.h": return "core.sys.windows.aclui";
		case "basetsd.h": return "core.sys.windows.basetsd";
		case "basetyps.h": return "core.sys.windows.basetyps";
		case "cderr.h": return "core.sys.windows.cderr";
		case "cguid.h": return "core.sys.windows.cguid";
		case "com.h": return "core.sys.windows.com";
		case "comcat.h": return "core.sys.windows.comcat";
		case "commctrl.h": return "core.sys.windows.commctrl";
		case "commdlg.h": return "core.sys.windows.commdlg";
		case "core.h": return "core.sys.windows.core";
		case "cpl.h": return "core.sys.windows.cpl";
		case "cplext.h": return "core.sys.windows.cplext";
		case "custcntl.h": return "core.sys.windows.custcntl";
		case "dbghelp.h": return "core.sys.windows.dbghelp";
		case "dbghelp_types.h": return "core.sys.windows.dbghelp_types";
		case "dbt.h": return "core.sys.windows.dbt";
		case "dde.h": return "core.sys.windows.dde";
		case "ddeml.h": return "core.sys.windows.ddeml";
		case "dhcpcsdk.h": return "core.sys.windows.dhcpcsdk";
		case "dlgs.h": return "core.sys.windows.dlgs";
		case "dll.h": return "core.sys.windows.dll";
		case "docobj.h": return "core.sys.windows.docobj";
		case "errorrep.h": return "core.sys.windows.errorrep";
		case "exdisp.h": return "core.sys.windows.exdisp";
		case "exdispid.h": return "core.sys.windows.exdispid";
		case "httpext.h": return "core.sys.windows.httpext";
		case "idispids.h": return "core.sys.windows.idispids";
		case "imagehlp.h": return "core.sys.windows.imagehlp";
		case "imm.h": return "core.sys.windows.imm";
		case "intshcut.h": return "core.sys.windows.intshcut";
		case "ipexport.h": return "core.sys.windows.ipexport";
		case "iphlpapi.h": return "core.sys.windows.iphlpapi";
		case "ipifcons.h": return "core.sys.windows.ipifcons";
		case "iprtrmib.h": return "core.sys.windows.iprtrmib";
		case "iptypes.h": return "core.sys.windows.iptypes";
		case "isguids.h": return "core.sys.windows.isguids";
		case "lm.h": return "core.sys.windows.lm";
		case "lmaccess.h": return "core.sys.windows.lmaccess";
		case "lmalert.h": return "core.sys.windows.lmalert";
		case "lmapibuf.h": return "core.sys.windows.lmapibuf";
		case "lmat.h": return "core.sys.windows.lmat";
		case "lmaudit.h": return "core.sys.windows.lmaudit";
		case "lmbrowsr.h": return "core.sys.windows.lmbrowsr";
		case "lmchdev.h": return "core.sys.windows.lmchdev";
		case "lmconfig.h": return "core.sys.windows.lmconfig";
		case "lmcons.h": return "core.sys.windows.lmcons";
		case "lmerr.h": return "core.sys.windows.lmerr";
		case "lmerrlog.h": return "core.sys.windows.lmerrlog";
		case "lmmsg.h": return "core.sys.windows.lmmsg";
		case "lmremutl.h": return "core.sys.windows.lmremutl";
		case "lmrepl.h": return "core.sys.windows.lmrepl";
		case "lmserver.h": return "core.sys.windows.lmserver";
		case "lmshare.h": return "core.sys.windows.lmshare";
		case "lmsname.h": return "core.sys.windows.lmsname";
		case "lmstats.h": return "core.sys.windows.lmstats";
		case "lmsvc.h": return "core.sys.windows.lmsvc";
		case "lmuse.h": return "core.sys.windows.lmuse";
		case "lmuseflg.h": return "core.sys.windows.lmuseflg";
		case "lmwksta.h": return "core.sys.windows.lmwksta";
		case "lzexpand.h": return "core.sys.windows.lzexpand";
		case "mapi.h": return "core.sys.windows.mapi";
		case "mciavi.h": return "core.sys.windows.mciavi";
		case "mcx.h": return "core.sys.windows.mcx";
		case "mgmtapi.h": return "core.sys.windows.mgmtapi";
		case "mmsystem.h": return "core.sys.windows.mmsystem";
		case "msacm.h": return "core.sys.windows.msacm";
		case "mshtml.h": return "core.sys.windows.mshtml";
		case "mswsock.h": return "core.sys.windows.mswsock";
		case "nb30.h": return "core.sys.windows.nb30";
		case "nddeapi.h": return "core.sys.windows.nddeapi";
		case "nspapi.h": return "core.sys.windows.nspapi";
		case "ntdef.h": return "core.sys.windows.ntdef";
		case "ntdll.h": return "core.sys.windows.ntdll";
		case "ntldap.h": return "core.sys.windows.ntldap";
		case "ntsecapi.h": return "core.sys.windows.ntsecapi";
		case "ntsecpkg.h": return "core.sys.windows.ntsecpkg";
		case "oaidl.h": return "core.sys.windows.oaidl";
		case "objbase.h": return "core.sys.windows.objbase";
		case "objfwd.h": return "core.sys.windows.objfwd";
		case "objidl.h": return "core.sys.windows.objidl";
		case "objsafe.h": return "core.sys.windows.objsafe";
		case "ocidl.h": return "core.sys.windows.ocidl";
		case "odbcinst.h": return "core.sys.windows.odbcinst";
		case "ole.h": return "core.sys.windows.ole";
		case "ole2.h": return "core.sys.windows.ole2";
		case "ole2ver.h": return "core.sys.windows.ole2ver";
		case "oleacc.h": return "core.sys.windows.oleacc";
		case "oleauto.h": return "core.sys.windows.oleauto";
		case "olectl.h": return "core.sys.windows.olectl";
		case "olectlid.h": return "core.sys.windows.olectlid";
		case "oledlg.h": return "core.sys.windows.oledlg";
		case "oleidl.h": return "core.sys.windows.oleidl";
		case "pbt.h": return "core.sys.windows.pbt";
		case "powrprof.h": return "core.sys.windows.powrprof";
		case "prsht.h": return "core.sys.windows.prsht";
		case "psapi.h": return "core.sys.windows.psapi";
		case "rapi.h": return "core.sys.windows.rapi";
		case "ras.h": return "core.sys.windows.ras";
		case "rasdlg.h": return "core.sys.windows.rasdlg";
		case "raserror.h": return "core.sys.windows.raserror";
		case "rassapi.h": return "core.sys.windows.rassapi";
		case "reason.h": return "core.sys.windows.reason";
		case "regstr.h": return "core.sys.windows.regstr";
		case "richedit.h": return "core.sys.windows.richedit";
		case "richole.h": return "core.sys.windows.richole";
		case "rpc.h": return "core.sys.windows.rpc";
		case "rpcdce.h": return "core.sys.windows.rpcdce";
		case "rpcdce2.h": return "core.sys.windows.rpcdce2";
		case "rpcdcep.h": return "core.sys.windows.rpcdcep";
		case "rpcndr.h": return "core.sys.windows.rpcndr";
		case "rpcnsi.h": return "core.sys.windows.rpcnsi";
		case "rpcnsip.h": return "core.sys.windows.rpcnsip";
		case "rpcnterr.h": return "core.sys.windows.rpcnterr";
		case "schannel.h": return "core.sys.windows.schannel";
		case "sdkddkver.h": return "core.sys.windows.sdkddkver";
		case "secext.h": return "core.sys.windows.secext";
		case "security.h": return "core.sys.windows.security";
		case "servprov.h": return "core.sys.windows.servprov";
		case "setupapi.h": return "core.sys.windows.setupapi";
		case "shellapi.h": return "core.sys.windows.shellapi";
		case "shldisp.h": return "core.sys.windows.shldisp";
		case "shlguid.h": return "core.sys.windows.shlguid";
		case "shlobj.h": return "core.sys.windows.shlobj";
		case "shlwapi.h": return "core.sys.windows.shlwapi";
		case "snmp.h": return "core.sys.windows.snmp";
		case "sql.h": return "core.sys.windows.sql";
		case "sqlext.h": return "core.sys.windows.sqlext";
		case "sqltypes.h": return "core.sys.windows.sqltypes";
		case "sqlucode.h": return "core.sys.windows.sqlucode";
		case "sspi.h": return "core.sys.windows.sspi";
		case "stacktrace.h": return "core.sys.windows.stacktrace";
		case "stat.h": return "core.sys.windows.stat";
		case "subauth.h": return "core.sys.windows.subauth";
		case "threadaux.h": return "core.sys.windows.threadaux";
		case "tlhelp32.h": return "core.sys.windows.tlhelp32";
		case "tmschema.h": return "core.sys.windows.tmschema";
		case "unknwn.h": return "core.sys.windows.unknwn";
		case "uuid.h": return "core.sys.windows.uuid";
		case "vfw.h": return "core.sys.windows.vfw";
		case "w32api.h": return "core.sys.windows.w32api";
		case "winbase.h": return "core.sys.windows.winbase";
		case "winber.h": return "core.sys.windows.winber";
		case "wincon.h": return "core.sys.windows.wincon";
		case "wincrypt.h": return "core.sys.windows.wincrypt";
		case "windef.h": return "core.sys.windows.windef";
		case "winerror.h": return "core.sys.windows.winerror";
		case "wingdi.h": return "core.sys.windows.wingdi";
		case "winhttp.h": return "core.sys.windows.winhttp";
		case "wininet.h": return "core.sys.windows.wininet";
		case "winioctl.h": return "core.sys.windows.winioctl";
		case "winldap.h": return "core.sys.windows.winldap";
		case "winnetwk.h": return "core.sys.windows.winnetwk";
		case "winnls.h": return "core.sys.windows.winnls";
		case "winnt.h": return "core.sys.windows.winnt";
		case "winperf.h": return "core.sys.windows.winperf";
		case "winreg.h": return "core.sys.windows.winreg";
		case "winsock2.h": return "core.sys.windows.winsock2";
		case "winspool.h": return "core.sys.windows.winspool";
		case "winsvc.h": return "core.sys.windows.winsvc";
		case "winuser.h": return "core.sys.windows.winuser";
		case "winver.h": return "core.sys.windows.winver";
		case "wtsapi32.h": return "core.sys.windows.wtsapi32";
		case "wtypes.h": return "core.sys.windows.wtypes";

		//?? case "linux/input": return "";

		default: return null;
	}
}
