/**
Translate C macros
*/
module ctod.cpreproc;

import dbg;
import ctod: Sym; // Sym enum
import ctod.translate;
import tree_sitter.wrapper;

package
/// If `node` is a recognized preprocessor node, translate it to D
///
/// Returns: `true` on success
bool tryTranslatePreprocessor(ref TranslationContext ctu, ref Node node) {
	switch(node.typeEnum) {
		case Sym.aux_preproc_else_token1: // "#else"
			return node.replace("} else {");
		case Sym.aux_preproc_if_token2: // "#endif"
			return node.replace("}");
		case Sym.aux_preproc_include_token1: // "#include"
			return node.replace("public import");
		case Sym.preproc_call:
			auto argument = node.childField("argument");
			if (auto directive = node.childField("directive")) {
				if (directive.source == "#error") {
					directive.replace("static assert");
					if (argument) {
						argument.prepend("(0,");
						argument.append(");");
					}
				} else if (directive.source == "#pragma") {
					// preceeding whitespace is part of the argument node
					if (argument && argument.source.length >= 4 && argument.source[$-4..$] == "once") {
						node.prepend("//");
						return true;
					}
				} else if (directive.source == "#undef") {
					node.replace(""); // no undef in D
				} else {
					// unrecognized call
					node.prepend("//! ");
				}
			}
			return true;
		case Sym.preproc_def:
			if (auto valueNode = node.childField("value")) {
				// aux_sym_preproc_def_token1 = "#define"
				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					c.replace("enum");
				}
				if (auto c = node.childField("name")) {
					translateNode(ctu, *c);
					ctu.macroTable[c.output] = MacroType.manifestConstant;
				}
				if (auto c = node.firstChildType(Sym.preproc_arg)) {
					c.replace(" ="~c.source~";");
				}

			} else {
				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					c.replace("version =");
				}
				if (auto c = node.childField("name")) {
					c.append(";");
					translateNode(ctu, *c);
					ctu.macroTable[c.output] = MacroType.versionId;
				}
			}
			break;
		case Sym.preproc_function_def:
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
			// #define
			if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
				c.replace("enum string");
			}
			translateNode(ctu, *nameNode);
			ctu.macroTable[nameNode.output] = MacroType.inlineFunc;

			string[] params;
			foreach(ref param; parametersNode.children) {
				if (param.typeEnum == Sym.identifier) {
					params ~= param.source;
					param.prepend("string ");
				}
			}

			const result = lexMacroText(valueNode.source);
			valueNode.replace(" = " ~ result ~ ";");
			break;
		case Sym.preproc_ifdef:
			removeSemicolons(node);
			auto nameNode = node.childField("name");
			if (!nameNode) {
				return true;
			}
			if (string s = findVersion(nameNode.source)) {
				nameNode.replace(s);
			}
			if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token1)) {
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {");
			} else if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token2)) {
				// "#ifndef"
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {} else {");
			}
			nameNode.isTranslated = true;
			return false; // name node should not be translated as an identifier, but other children must be translated still
		case Sym.preproc_defined:
			return replaceDefined(ctu, node, false);
		case Sym.preproc_if:
			auto c = node.childField("condition");
			auto ifnode = node.firstChildType(Sym.aux_preproc_if_token1); // "#if"
			if (!c || !ifnode) {
				return true;
			}

			if (c.typeEnum == Sym.preproc_defined) {
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
		case Sym.preproc_elif:
			if (auto c = node.childField("condition")) {
				c.prepend("(");
				c.append(") {");
				if (auto ifnode = node.firstChildType(Sym.aux_preproc_elif_token1)) {
					// "#elif"
					if (c.typeEnum == Sym.preproc_defined) {
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
		case Sym.preproc_params:
			break;
		case Sym.system_lib_string:
			if (node.source.length < "<>".length) {
				return false; // to short to slice
			}
			string lib = node.source[1..$-1]; // slice to strip off angle brackets in <stdio.h>
			if (string importName = translateSysLib(lib)) {
				return node.replace(importName~";");
			} else {
				import bops.os.file: stripExtension;
				return node.replace(lib.stripExtension~";");
			}
		case Sym.preproc_include:
			//if (auto c = node.firstChildType("string_literal")) {
			if (auto pathNode = node.childField("path")) {
				if (pathNode.typeEnum == Sym.string_literal) {
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
		scope(exit) s = s[$..$];
		return s;
	}

	string result = "`";
	while (s.length) {
		result ~= next();
	}
	return result ~ "`";
	// notes: #x turns x into string literal
	// x in string literal not replaced
	/*
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
				//if (i + 1 < s.length) switch(s[i+1])
				break;
			case '"':
				// in / out string literal
				goto default;
			default:
				result ~= s[i];
		}
	}
	*/
}

/// Replace a defined(__WIN32__) to either `HasVersion!"Windows"` (in a `static if`)
/// or just `Windows` (in a `version()`)
bool replaceDefined(ref TranslationContext ctu, ref Node node, bool inVersionStatement) {
	if (auto c = node.firstChildType(Sym.identifier)) {
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

private immutable string[2][] versionMap = [
	["__WIN32__",   "Windows"],
	["WIN32",       "Windows"],
	["__MINGW32__", "Windows"],
	["_WIN32",      "Windows"],
	["__linux__",   "linux"],
	["__MACH__",    "OSX"],
	["__APPLE__",   "OSX"],
	["__CYGWIN__",  "Cygwin"],
	["__cplusplus", "none"],
];

/// Find version string to e.g. replace `#ifdef _WIN32` with `version(Windows)`
string findVersion(string s) {
	switch(s) {
		static foreach(p; versionMap) {
			case p[0]: return p[1];
		}
		case "FIXME": return null; // remove string switch
		default: return null;
	}
}

unittest {
	assert(findVersion("__WIN32__") == "Windows");
}

/// Translate the include <> or "" path, for:
///
/// #include <folder/file.h> => import folder.file;
string translateIncludePath(string s) {
	import std.array: replace;
	if (s.length < 5) {
		return s;
	}
	return s[1..$-3].replace("/", ".") ~ ";";
}

unittest {
	assert(translateIncludePath("<folder/file.h>") == "folder.file;");
}

// C standard lib header translation
private immutable string[2][] libcMap = [
	["assert.h",   "core.stdc.assert_"],
	["complex.h",  "core.stdc.complex"],
	["config.h",   "core.stdc.config"],
	["ctype.h",    "core.stdc.ctype"],
	["errno.h",    "core.stdc.errno"],
	["fenv.h",     "core.stdc.fenv"],
	["float_.h",   "core.stdc.float_"],
	["inttypes.h", "core.stdc.inttypes"],
	["limits.h",   "core.stdc.limits"],
	["locale.h",   "core.stdc.locale"],
	["math.h",     "core.stdc.math"],
	["signal.h",   "core.stdc.signal"],
	["stdarg.h",   "core.stdc.stdarg"],
	["stddef.h",   "core.stdc.stddef"],
	["stdint.h",   "core.stdc.stdint"],
	["stdio.h",    "core.stdc.stdio"],
	["stdlib.h",   "core.stdc.stdlib"],
	["string.h",   "core.stdc.string"],
	["tgmath.h",   "core.stdc.tgmath"],
	["time.h",     "core.stdc.time"],
	["wchar.h",    "core.stdc.wchar_"],
	["wctype.h",   "core.stdc.wctype"],
];

// Windows header translation
// Optimization: this is just prepending `core.sys.windows.`, de-duplicate strings
private immutable string[2][] windowsMap = [
	["accctrl.h",       "core.sys.windows.accctrl"],
	["aclapi.h",        "core.sys.windows.aclapi"],
	["aclui.h",         "core.sys.windows.aclui"],
	["basetsd.h",       "core.sys.windows.basetsd"],
	["basetyps.h",      "core.sys.windows.basetyps"],
	["cderr.h",         "core.sys.windows.cderr"],
	["cguid.h",         "core.sys.windows.cguid"],
	["com.h",           "core.sys.windows.com"],
	["comcat.h",        "core.sys.windows.comcat"],
	["commctrl.h",      "core.sys.windows.commctrl"],
	["commdlg.h",       "core.sys.windows.commdlg"],
	["core.h",          "core.sys.windows.core"],
	["cpl.h",           "core.sys.windows.cpl"],
	["cplext.h",        "core.sys.windows.cplext"],
	["custcntl.h",      "core.sys.windows.custcntl"],
	["dbghelp.h",       "core.sys.windows.dbghelp"],
	["dbghelp_types.h", "core.sys.windows.dbghelp_types"],
	["dbt.h",           "core.sys.windows.dbt"],
	["dde.h",           "core.sys.windows.dde"],
	["ddeml.h",         "core.sys.windows.ddeml"],
	["dhcpcsdk.h",      "core.sys.windows.dhcpcsdk"],
	["dlgs.h",          "core.sys.windows.dlgs"],
	["dll.h",           "core.sys.windows.dll"],
	["docobj.h",        "core.sys.windows.docobj"],
	["errorrep.h",      "core.sys.windows.errorrep"],
	["exdisp.h",        "core.sys.windows.exdisp"],
	["exdispid.h",      "core.sys.windows.exdispid"],
	["httpext.h",       "core.sys.windows.httpext"],
	["idispids.h",      "core.sys.windows.idispids"],
	["imagehlp.h",      "core.sys.windows.imagehlp"],
	["imm.h",           "core.sys.windows.imm"],
	["intshcut.h",      "core.sys.windows.intshcut"],
	["ipexport.h",      "core.sys.windows.ipexport"],
	["iphlpapi.h",      "core.sys.windows.iphlpapi"],
	["ipifcons.h",      "core.sys.windows.ipifcons"],
	["iprtrmib.h",      "core.sys.windows.iprtrmib"],
	["iptypes.h",       "core.sys.windows.iptypes"],
	["isguids.h",       "core.sys.windows.isguids"],
	["lm.h",            "core.sys.windows.lm"],
	["lmaccess.h",      "core.sys.windows.lmaccess"],
	["lmalert.h",       "core.sys.windows.lmalert"],
	["lmapibuf.h",      "core.sys.windows.lmapibuf"],
	["lmat.h",          "core.sys.windows.lmat"],
	["lmaudit.h",       "core.sys.windows.lmaudit"],
	["lmbrowsr.h",      "core.sys.windows.lmbrowsr"],
	["lmchdev.h",       "core.sys.windows.lmchdev"],
	["lmconfig.h",      "core.sys.windows.lmconfig"],
	["lmcons.h",        "core.sys.windows.lmcons"],
	["lmerr.h",         "core.sys.windows.lmerr"],
	["lmerrlog.h",      "core.sys.windows.lmerrlog"],
	["lmmsg.h",         "core.sys.windows.lmmsg"],
	["lmremutl.h",      "core.sys.windows.lmremutl"],
	["lmrepl.h",        "core.sys.windows.lmrepl"],
	["lmserver.h",      "core.sys.windows.lmserver"],
	["lmshare.h",       "core.sys.windows.lmshare"],
	["lmsname.h",       "core.sys.windows.lmsname"],
	["lmstats.h",       "core.sys.windows.lmstats"],
	["lmsvc.h",         "core.sys.windows.lmsvc"],
	["lmuse.h",         "core.sys.windows.lmuse"],
	["lmuseflg.h",      "core.sys.windows.lmuseflg"],
	["lmwksta.h",       "core.sys.windows.lmwksta"],
	["lzexpand.h",      "core.sys.windows.lzexpand"],
	["mapi.h",          "core.sys.windows.mapi"],
	["mciavi.h",        "core.sys.windows.mciavi"],
	["mcx.h",           "core.sys.windows.mcx"],
	["mgmtapi.h",       "core.sys.windows.mgmtapi"],
	["mmsystem.h",      "core.sys.windows.mmsystem"],
	["msacm.h",         "core.sys.windows.msacm"],
	["mshtml.h",        "core.sys.windows.mshtml"],
	["mswsock.h",       "core.sys.windows.mswsock"],
	["nb30.h",          "core.sys.windows.nb30"],
	["nddeapi.h",       "core.sys.windows.nddeapi"],
	["nspapi.h",        "core.sys.windows.nspapi"],
	["ntdef.h",         "core.sys.windows.ntdef"],
	["ntdll.h",         "core.sys.windows.ntdll"],
	["ntldap.h",        "core.sys.windows.ntldap"],
	["ntsecapi.h",      "core.sys.windows.ntsecapi"],
	["ntsecpkg.h",      "core.sys.windows.ntsecpkg"],
	["oaidl.h",         "core.sys.windows.oaidl"],
	["objbase.h",       "core.sys.windows.objbase"],
	["objfwd.h",        "core.sys.windows.objfwd"],
	["objidl.h",        "core.sys.windows.objidl"],
	["objsafe.h",       "core.sys.windows.objsafe"],
	["ocidl.h",         "core.sys.windows.ocidl"],
	["odbcinst.h",      "core.sys.windows.odbcinst"],
	["ole.h",           "core.sys.windows.ole"],
	["ole2.h",          "core.sys.windows.ole2"],
	["ole2ver.h",       "core.sys.windows.ole2ver"],
	["oleacc.h",        "core.sys.windows.oleacc"],
	["oleauto.h",       "core.sys.windows.oleauto"],
	["olectl.h",        "core.sys.windows.olectl"],
	["olectlid.h",      "core.sys.windows.olectlid"],
	["oledlg.h",        "core.sys.windows.oledlg"],
	["oleidl.h",        "core.sys.windows.oleidl"],
	["pbt.h",           "core.sys.windows.pbt"],
	["powrprof.h",      "core.sys.windows.powrprof"],
	["prsht.h",         "core.sys.windows.prsht"],
	["psapi.h",         "core.sys.windows.psapi"],
	["rapi.h",          "core.sys.windows.rapi"],
	["ras.h",           "core.sys.windows.ras"],
	["rasdlg.h",        "core.sys.windows.rasdlg"],
	["raserror.h",      "core.sys.windows.raserror"],
	["rassapi.h",       "core.sys.windows.rassapi"],
	["reason.h",        "core.sys.windows.reason"],
	["regstr.h",        "core.sys.windows.regstr"],
	["richedit.h",      "core.sys.windows.richedit"],
	["richole.h",       "core.sys.windows.richole"],
	["rpc.h",           "core.sys.windows.rpc"],
	["rpcdce.h",        "core.sys.windows.rpcdce"],
	["rpcdce2.h",       "core.sys.windows.rpcdce2"],
	["rpcdcep.h",       "core.sys.windows.rpcdcep"],
	["rpcndr.h",        "core.sys.windows.rpcndr"],
	["rpcnsi.h",        "core.sys.windows.rpcnsi"],
	["rpcnsip.h",       "core.sys.windows.rpcnsip"],
	["rpcnterr.h",      "core.sys.windows.rpcnterr"],
	["schannel.h",      "core.sys.windows.schannel"],
	["sdkddkver.h",     "core.sys.windows.sdkddkver"],
	["secext.h",        "core.sys.windows.secext"],
	["security.h",      "core.sys.windows.security"],
	["servprov.h",      "core.sys.windows.servprov"],
	["setupapi.h",      "core.sys.windows.setupapi"],
	["shellapi.h",      "core.sys.windows.shellapi"],
	["shldisp.h",       "core.sys.windows.shldisp"],
	["shlguid.h",       "core.sys.windows.shlguid"],
	["shlobj.h",        "core.sys.windows.shlobj"],
	["shlwapi.h",       "core.sys.windows.shlwapi"],
	["snmp.h",          "core.sys.windows.snmp"],
	["sql.h",           "core.sys.windows.sql"],
	["sqlext.h",        "core.sys.windows.sqlext"],
	["sqltypes.h",      "core.sys.windows.sqltypes"],
	["sqlucode.h",      "core.sys.windows.sqlucode"],
	["sspi.h",          "core.sys.windows.sspi"],
	["stacktrace.h",    "core.sys.windows.stacktrace"],
	["stat.h",          "core.sys.windows.stat"],
	["subauth.h",       "core.sys.windows.subauth"],
	["threadaux.h",     "core.sys.windows.threadaux"],
	["tlhelp32.h",      "core.sys.windows.tlhelp32"],
	["tmschema.h",      "core.sys.windows.tmschema"],
	["unknwn.h",        "core.sys.windows.unknwn"],
	["uuid.h",          "core.sys.windows.uuid"],
	["vfw.h",           "core.sys.windows.vfw"],
	["w32api.h",        "core.sys.windows.w32api"],
	["winbase.h",       "core.sys.windows.winbase"],
	["winber.h",        "core.sys.windows.winber"],
	["wincon.h",        "core.sys.windows.wincon"],
	["wincrypt.h",      "core.sys.windows.wincrypt"],
	["windef.h",        "core.sys.windows.windef"],
	["winerror.h",      "core.sys.windows.winerror"],
	["wingdi.h",        "core.sys.windows.wingdi"],
	["winhttp.h",       "core.sys.windows.winhttp"],
	["wininet.h",       "core.sys.windows.wininet"],
	["winioctl.h",      "core.sys.windows.winioctl"],
	["winldap.h",       "core.sys.windows.winldap"],
	["winnetwk.h",      "core.sys.windows.winnetwk"],
	["winnls.h",        "core.sys.windows.winnls"],
	["winnt.h",         "core.sys.windows.winnt"],
	["winperf.h",       "core.sys.windows.winperf"],
	["winreg.h",        "core.sys.windows.winreg"],
	["winsock2.h",      "core.sys.windows.winsock2"],
	["winspool.h",      "core.sys.windows.winspool"],
	["winsvc.h",        "core.sys.windows.winsvc"],
	["winuser.h",       "core.sys.windows.winuser"],
	["winver.h",        "core.sys.windows.winver"],
	["wtsapi32.h",      "core.sys.windows.wtsapi32"],
	["wtypes.h",        "core.sys.windows.wtypes"],
];

private immutable string[2][] posixMap = [
	["aio.h",          "core.sys.posix.aio"],
	["ar.h",           "core.sys.posix.ar"],
	["dirent.h",       "core.sys.posix.dirent"],
	["dlfcn.h",        "core.sys.posix.dlfcn"],
	["fcntl.h",        "core.sys.posix.fcntl"],
	["grp.h",          "core.sys.posix.grp"],
	["iconv.h",        "core.sys.posix.iconv"],
	["libgen.h",       "core.sys.posix.libgen"],
	["n.h",            "core.sys.posix.n"],
	["netdb.h",        "core.sys.posix.netdb"],
	["netin.h",        "core.sys.posix.netin"],
	["poll.h",         "core.sys.posix.poll"],
	["pthread.h",      "core.sys.posix.pthread"],
	["pwd.h",          "core.sys.posix.pwd"],
	["s.h",            "core.sys.posix.s"],
	["sched.h",        "core.sys.posix.sched"],
	["semaphore.h",    "core.sys.posix.semaphore"],
	["setjmp.h",       "core.sys.posix.setjmp"],
	["sys/filio.h",    "core.sys.posix.sys.filio"],
	["sys/ioccom.h",   "core.sys.posix.sys.ioccom"],
	["sys/ioctl.h",    "core.sys.posix.sys.ioctl"],
	["sys/ipc.h",      "core.sys.posix.sys.ipc"],
	["sys/mman.h",     "core.sys.posix.sys.mman"],
	["sys/msg.h",      "core.sys.posix.sys.msg"],
	["sys/resource.h", "core.sys.posix.sys.resource"],
	["sys/select.h",   "core.sys.posix.sys.select"],
	["sys/shm.h",      "core.sys.posix.sys.shm"],
	["sys/socket.h",   "core.sys.posix.sys.socket"],
	["sys/stat.h",     "core.sys.posix.sys.stat"],
	["sys/statvfs.h",  "core.sys.posix.sys.statvfs"],
	["sys/time.h",     "core.sys.posix.sys.time"],
	["sys/ttycom.h",   "core.sys.posix.sys.ttycom"],
	["sys/types.h",    "core.sys.posix.sys.types"],
	["sys/uio.h",      "core.sys.posix.sys.uio"],
	["sys/un.h",       "core.sys.posix.sys.un"],
	["sys/utsname.h",  "core.sys.posix.sys.utsname"],
	["sys/wait.h",     "core.sys.posix.sys.wait"],
	["syslog.h",       "core.sys.posix.syslog"],
	["termios.h",      "core.sys.posix.termios"],
	["ucontext.h",     "core.sys.posix.ucontext"],
	["unistd.h",       "core.sys.posix.unistd"],
	["utime.h",        "core.sys.posix.utime"],
	["config.h",       "core.sys.posix.config"],
	["inttypes.h",     "core.sys.posix.inttypes"],
	["signal.h",       "core.sys.posix.signal"],
	["stdio.h",        "core.sys.posix.stdio"],
	["stdlib.h",       "core.sys.posix.stdlib"],
	["time.h",         "core.sys.posix.time"],
];

/// translate #include<> to an import in druntime.
string translateSysLib(string s) {
	switch(s) {
		static foreach(p; libcMap) {
			case p[0]: return p[1];
		}
		default: break;
	}

	switch(s) {
		// windows
		case "windows.h": return "core.sys.windows.windows";

		// misc
		case "linux/limits": return "core.stdc.limits;";
		case "sys/inotify.h": return "core.sys.linux.sys.inotify";
		case "sys/timerfd":   return "core.sys.linux.sys.timerfd";
		//?? case "linux/input":  return "";

		default: break;
	}

	// posix
	switch(s) {
		static foreach(p; posixMap) {
			case p[0]: return p[1]; // "core.sys.posix"
		}
		default: break;
	}
	return null;
}


