/**
Translate C macros
*/
module ctod.cpreproc;

nothrow @safe:

import ctod.translate;
import ctod.tree_sitter;

package
/// If `node` is a recognized preprocessor node, translate it to D
///
/// Returns: `true` on success
bool ctodTryPreprocessor(ref TranslationContext ctu, ref Node node) {
	switch(node.typeEnum) {
		case Sym.aux_preproc_else_token1: // "#else"
			return node.replace("} else {");
		case Sym.aux_preproc_if_token2: // "#endif"
			return node.replace("}");
		case Sym.aux_preproc_include_token1: // "#include"
			return node.replace("public import");
		case Sym.preproc_call:
			auto argument = node.childField(Field.argument);
			if (auto directive = node.childField(Field.directive)) {
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
			if (auto valueNode = node.childField(Field.value)) {
				// aux_sym_preproc_def_token1 = "#define"
				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					c.replace("enum");
				}
				if (auto c = node.childField(Field.name)) {
					translateNode(ctu, *c);
					ctu.macroTable[c.output()] = MacroType.manifestConstant;
				}
				if (auto c = node.firstChildType(Sym.preproc_arg)) {
					c.replace(" ="~c.source~";");
				}

			} else {
				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					c.replace("version =");
				}
				if (auto c = node.childField(Field.name)) {
					c.append(";");
					translateNode(ctu, *c);
					ctu.macroTable[c.output()] = MacroType.versionId;
				}
			}
			break;
		case Sym.preproc_function_def:
			removeSemicolons(node);
			auto nameNode = node.childField(Field.name);
			auto parametersNode = node.childField(Field.parameters);
			auto valueNode = node.childField(Field.value);
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
			ctu.macroTable[nameNode.output()] = MacroType.inlineFunc;

			string[] params;
			foreach(ref param; parametersNode.children) {
				if (param.typeEnum == Sym.identifier) {
					params ~= param.source;
					param.prepend("string ");
				}
			}
			valueNode.replace(" = `" ~ valueNode.source ~ "`;");
			break;
		case Sym.preproc_ifdef:
			removeSemicolons(node);
			if (ctodHeaderGuard(ctu, node)) {
				return true;
			}
			auto nameNode = node.childField(Field.name);
			if (!nameNode) {
				return true;
			}
			string versionName = nameNode.source;
			if (string s = ctodVersion(nameNode.source)) {
				nameNode.replace(s);
				versionName = s;
			}
			if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token1)) {
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {");
			} else if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token2)) {
				// "#ifndef"
				c.replace("version");
				nameNode.prepend("(");
				// D has no boolean logic with versions, so put #ifndef body in an else branch
				nameNode.append(") {} else {");

				// We can't have a double else, so we need to repeat the version name for #else
				if (auto a = node.childField(Field.alternative)) {
					// first token of preproc_else is "#else"
					a.children[0].replace("} version ("~versionName~") {");
				}
			}
			nameNode.isTranslated = true;
			return false; // name node should not be translated as an identifier, but other children must be translated still
		case Sym.preproc_defined:
			return replaceDefined(ctu, node, false);
		case Sym.preproc_if:
			auto c = node.childField(Field.condition);
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
			if (auto c = node.childField(Field.condition)) {
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
			node.replace(ctodSysLib(lib));
			break;
		case Sym.preproc_include:
			//if (auto c = node.firstChildType("string_literal")) {
			if (auto pathNode = node.childField(Field.path)) {
				if (pathNode.typeEnum == Sym.string_literal) {
					pathNode.replace(ctodIncludePath(pathNode.source));
				} else {
					// see case for system_lib_string above
					ctodTryPreprocessor(ctu, *pathNode);
					// note: explicit call not really needed, children are
					// automatically translated by returning false
				}
			}
			break;
		default: break;
	}
	return false;
}


/// Try to remove a header guard
///
/// A header guard has this pattern:
/// ---
/// #ifndef NAME_H
/// #define NAME_H
/// ...actual code
/// #endif
/// ---
private bool ctodHeaderGuard(ref TranslationContext ctu, ref Node ifdefNode) {

	assert(ifdefNode.typeEnum == Sym.preproc_ifdef);

	// The grammar has the same node type for `#ifdef` and `#ifndef`
	if (ifdefNode.children[0].typeEnum != Sym.aux_preproc_ifdef_token2) {
		return false;
	}

	int commentCount = 0;
	// second node is always field `name` with a `Sym.identifier`
	string id = ifdefNode.children[1].source;

	foreach(i; 0..ifdefNode.children.length) {
		switch(ifdefNode.children[i].typeEnum) {
			case Sym.comment:
				commentCount++;
				continue;
			case Sym.preproc_def:
				// preproc can only be preceded by comments, or else it's no header guard
				// 2 for `#ifndef` and identifier tokens
				if (i > 2 + commentCount) {
					return false;
				}
				if (auto valueNode = ifdefNode.children[i].childField(Field.value)) {
					// Header guard defines have no value, no `#define NAME_H 3`
					return false;
				}
				if (auto defIdNode = ifdefNode.children[i].childField(Field.name)) {
					// `#define` must match the `#ifndef`
					if (defIdNode.source != id) {
						return false;
					}
					// put remaining children under translation unit instead of the ifdef
					foreach(j; 0..ifdefNode.children.length) {
						if (j <= i || j + 1 == ifdefNode.children.length) {
							ifdefNode.children[j].replace(""); // header guard nodes
						} else {
							translateNode(ctu, ifdefNode.children[j]); // content nodes
						}
					}
					return true;
				}
				return false;
			default:
				break;
		}
	}
	return false;
}

/// Replace a defined(__WIN32__) to either `HasVersion!"Windows"` (in a `static if`)
/// or just `Windows` (in a `version()`)
bool replaceDefined(ref TranslationContext ctu, ref Node node, bool inVersionStatement) {
	if (auto c = node.firstChildType(Sym.identifier)) {
		string replacement = c.source;
		if (string s = ctodVersion(c.source)) {
			c.replace(s); // known #define translation
			replacement = s;
		} else {
			translateNode(ctu, *c); // reserved identifier replacement
		}
		if (inVersionStatement) {
			return node.replace(replacement);
		} else {
			ctu.needsHasVersion = true;
			return node.replace(`HasVersion!"` ~ replacement ~ `"`);
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
string ctodVersion(string s) {
	return mapLookup(versionMap, s, null);
}

@("ctodVersion") unittest {
	assert(ctodVersion("__WIN32__") == "Windows");
}

/// Translate the include <> or "" path, for:
///
/// #include <folder/file.h> => import folder.file;
string ctodIncludePath(string s) pure {
	if (s.length < 5) {
		return null; // <a.h>
	}
	auto res = s[1..$-2].dup;
	foreach(i; 0..res.length) {
		if (res[i] == '/') {
			res[i] = '.';
		}
	}
	res[$-1] = ';';
	return (() @trusted => cast(immutable) res)();
}

@("ctodIncludePath") unittest {
	assert(ctodIncludePath("<folder/file.h>") == "folder.file;");
}

// C standard lib header translation
// prefix: core.stdc.
private immutable string[2][] libcMap = [
	["assert.h",   "assert_"],
	["complex.h",  "complex"],
	["config.h",   "config"],
	["ctype.h",    "ctype"],
	["errno.h",    "errno"],
	["fenv.h",     "fenv"],
	["float_.h",   "float_"],
	["inttypes.h", "inttypes"],
	["limits.h",   "limits"],
	["locale.h",   "locale"],
	["math.h",     "math"],
	["signal.h",   "signal"],
	["stdarg.h",   "stdarg"],
	["stddef.h",   "stddef"],
	["stdint.h",   "stdint"],
	["stdio.h",    "stdio"],
	["stdlib.h",   "stdlib"],
	["string.h",   "string"],
	["tgmath.h",   "tgmath"],
	["time.h",     "time"],
	["wchar.h",    "wchar_"],
	["wctype.h",   "wctype"],
];

// Windows header translation
// prefix: core.sys.windows
private immutable string[2][] windowsMap = [
	["accctrl.h",       "accctrl"],
	["aclapi.h",        "aclapi"],
	["aclui.h",         "aclui"],
	["basetsd.h",       "basetsd"],
	["basetyps.h",      "basetyps"],
	["cderr.h",         "cderr"],
	["cguid.h",         "cguid"],
	["com.h",           "com"],
	["comcat.h",        "comcat"],
	["commctrl.h",      "commctrl"],
	["commdlg.h",       "commdlg"],
	["core.h",          "core"],
	["cpl.h",           "cpl"],
	["cplext.h",        "cplext"],
	["custcntl.h",      "custcntl"],
	["dbghelp.h",       "dbghelp"],
	["dbghelp_types.h", "dbghelp_types"],
	["dbt.h",           "dbt"],
	["dde.h",           "dde"],
	["ddeml.h",         "ddeml"],
	["dhcpcsdk.h",      "dhcpcsdk"],
	["dlgs.h",          "dlgs"],
	["dll.h",           "dll"],
	["docobj.h",        "docobj"],
	["errorrep.h",      "errorrep"],
	["exdisp.h",        "exdisp"],
	["exdispid.h",      "exdispid"],
	["httpext.h",       "httpext"],
	["idispids.h",      "idispids"],
	["imagehlp.h",      "imagehlp"],
	["imm.h",           "imm"],
	["intshcut.h",      "intshcut"],
	["ipexport.h",      "ipexport"],
	["iphlpapi.h",      "iphlpapi"],
	["ipifcons.h",      "ipifcons"],
	["iprtrmib.h",      "iprtrmib"],
	["iptypes.h",       "iptypes"],
	["isguids.h",       "isguids"],
	["lm.h",            "lm"],
	["lmaccess.h",      "lmaccess"],
	["lmalert.h",       "lmalert"],
	["lmapibuf.h",      "lmapibuf"],
	["lmat.h",          "lmat"],
	["lmaudit.h",       "lmaudit"],
	["lmbrowsr.h",      "lmbrowsr"],
	["lmchdev.h",       "lmchdev"],
	["lmconfig.h",      "lmconfig"],
	["lmcons.h",        "lmcons"],
	["lmerr.h",         "lmerr"],
	["lmerrlog.h",      "lmerrlog"],
	["lmmsg.h",         "lmmsg"],
	["lmremutl.h",      "lmremutl"],
	["lmrepl.h",        "lmrepl"],
	["lmserver.h",      "lmserver"],
	["lmshare.h",       "lmshare"],
	["lmsname.h",       "lmsname"],
	["lmstats.h",       "lmstats"],
	["lmsvc.h",         "lmsvc"],
	["lmuse.h",         "lmuse"],
	["lmuseflg.h",      "lmuseflg"],
	["lmwksta.h",       "lmwksta"],
	["lzexpand.h",      "lzexpand"],
	["mapi.h",          "mapi"],
	["mciavi.h",        "mciavi"],
	["mcx.h",           "mcx"],
	["mgmtapi.h",       "mgmtapi"],
	["mmsystem.h",      "mmsystem"],
	["msacm.h",         "msacm"],
	["mshtml.h",        "mshtml"],
	["mswsock.h",       "mswsock"],
	["nb30.h",          "nb30"],
	["nddeapi.h",       "nddeapi"],
	["nspapi.h",        "nspapi"],
	["ntdef.h",         "ntdef"],
	["ntdll.h",         "ntdll"],
	["ntldap.h",        "ntldap"],
	["ntsecapi.h",      "ntsecapi"],
	["ntsecpkg.h",      "ntsecpkg"],
	["oaidl.h",         "oaidl"],
	["objbase.h",       "objbase"],
	["objfwd.h",        "objfwd"],
	["objidl.h",        "objidl"],
	["objsafe.h",       "objsafe"],
	["ocidl.h",         "ocidl"],
	["odbcinst.h",      "odbcinst"],
	["ole.h",           "ole"],
	["ole2.h",          "ole2"],
	["ole2ver.h",       "ole2ver"],
	["oleacc.h",        "oleacc"],
	["oleauto.h",       "oleauto"],
	["olectl.h",        "olectl"],
	["olectlid.h",      "olectlid"],
	["oledlg.h",        "oledlg"],
	["oleidl.h",        "oleidl"],
	["pbt.h",           "pbt"],
	["powrprof.h",      "powrprof"],
	["prsht.h",         "prsht"],
	["psapi.h",         "psapi"],
	["rapi.h",          "rapi"],
	["ras.h",           "ras"],
	["rasdlg.h",        "rasdlg"],
	["raserror.h",      "raserror"],
	["rassapi.h",       "rassapi"],
	["reason.h",        "reason"],
	["regstr.h",        "regstr"],
	["richedit.h",      "richedit"],
	["richole.h",       "richole"],
	["rpc.h",           "rpc"],
	["rpcdce.h",        "rpcdce"],
	["rpcdce2.h",       "rpcdce2"],
	["rpcdcep.h",       "rpcdcep"],
	["rpcndr.h",        "rpcndr"],
	["rpcnsi.h",        "rpcnsi"],
	["rpcnsip.h",       "rpcnsip"],
	["rpcnterr.h",      "rpcnterr"],
	["schannel.h",      "schannel"],
	["sdkddkver.h",     "sdkddkver"],
	["secext.h",        "secext"],
	["security.h",      "security"],
	["servprov.h",      "servprov"],
	["setupapi.h",      "setupapi"],
	["shellapi.h",      "shellapi"],
	["shldisp.h",       "shldisp"],
	["shlguid.h",       "shlguid"],
	["shlobj.h",        "shlobj"],
	["shlwapi.h",       "shlwapi"],
	["snmp.h",          "snmp"],
	["sql.h",           "sql"],
	["sqlext.h",        "sqlext"],
	["sqltypes.h",      "sqltypes"],
	["sqlucode.h",      "sqlucode"],
	["sspi.h",          "sspi"],
	["stacktrace.h",    "stacktrace"],
	["stat.h",          "stat"],
	["subauth.h",       "subauth"],
	["threadaux.h",     "threadaux"],
	["tlhelp32.h",      "tlhelp32"],
	["tmschema.h",      "tmschema"],
	["unknwn.h",        "unknwn"],
	["uuid.h",          "uuid"],
	["vfw.h",           "vfw"],
	["w32api.h",        "w32api"],
	["winbase.h",       "winbase"],
	["winber.h",        "winber"],
	["wincon.h",        "wincon"],
	["wincrypt.h",      "wincrypt"],
	["windef.h",        "windef"],
	["windows.h",       "windows"],
	["winerror.h",      "winerror"],
	["wingdi.h",        "wingdi"],
	["winhttp.h",       "winhttp"],
	["wininet.h",       "wininet"],
	["winioctl.h",      "winioctl"],
	["winldap.h",       "winldap"],
	["winnetwk.h",      "winnetwk"],
	["winnls.h",        "winnls"],
	["winnt.h",         "winnt"],
	["winperf.h",       "winperf"],
	["winreg.h",        "winreg"],
	["winsock2.h",      "winsock2"],
	["winspool.h",      "winspool"],
	["winsvc.h",        "winsvc"],
	["winuser.h",       "winuser"],
	["winver.h",        "winver"],
	["wtsapi32.h",      "wtsapi32"],
	["wtypes.h",        "wtypes"],
];

// prefix: core.sys.posix
private immutable string[2][] posixMap = [
	["aio.h",          "aio"],
	["ar.h",           "ar"],
	["dirent.h",       "dirent"],
	["dlfcn.h",        "dlfcn"],
	["fcntl.h",        "fcntl"],
	["grp.h",          "grp"],
	["iconv.h",        "iconv"],
	["libgen.h",       "libgen"],
	["n.h",            "n"],
	["netdb.h",        "netdb"],
	["netin.h",        "netin"],
	["poll.h",         "poll"],
	["pthread.h",      "pthread"],
	["pwd.h",          "pwd"],
	["s.h",            "s"],
	["sched.h",        "sched"],
	["semaphore.h",    "semaphore"],
	["setjmp.h",       "setjmp"],
	["sys/filio.h",    "sys.filio"],
	["sys/ioccom.h",   "sys.ioccom"],
	["sys/ioctl.h",    "sys.ioctl"],
	["sys/ipc.h",      "sys.ipc"],
	["sys/mman.h",     "sys.mman"],
	["sys/msg.h",      "sys.msg"],
	["sys/resource.h", "sys.resource"],
	["sys/select.h",   "sys.select"],
	["sys/shm.h",      "sys.shm"],
	["sys/socket.h",   "sys.socket"],
	["sys/stat.h",     "sys.stat"],
	["sys/statvfs.h",  "sys.statvfs"],
	["sys/time.h",     "sys.time"],
	["sys/ttycom.h",   "sys.ttycom"],
	["sys/types.h",    "sys.types"],
	["sys/uio.h",      "sys.uio"],
	["sys/un.h",       "sys.un"],
	["sys/utsname.h",  "sys.utsname"],
	["sys/wait.h",     "sys.wait"],
	["syslog.h",       "syslog"],
	["termios.h",      "termios"],
	["ucontext.h",     "ucontext"],
	["unistd.h",       "unistd"],
	["utime.h",        "utime"],

	// Covered by libc:
	["config.h",   "config"],
	["inttypes.h", "inttypes"],
	["signal.h",   "signal"],
	["stdio.h",    "stdio"],
	["stdlib.h",   "stdlib"],
	["time.h",     "time"],
];

private immutable string[2][] miscMap = [
	["linux/limits" ,  "core.stdc.limits"],
	["sys/inotify.h",  "core.sys.linux.sys.inotify"],
	["sys/timerfd",    "core.sys.linux.sys.timerfd"],
];

/// translate #include<> to an import in druntime.
string ctodSysLib(string s) {
	if (auto r = mapLookup(libcMap, s, null)) {
		return "core.stdc." ~ r ~ ";";
	}
	if (auto r = mapLookup(windowsMap, s, null)) {
		return "core.sys.windows." ~ r ~ ";";
	}
	if (auto r = mapLookup(posixMap, s, null)) {
		return "core.sys.posix." ~ r ~ ";";
	}
	if (auto r = mapLookup(miscMap, s, null)) {
		return r;
	}

	if (s.length < 2) {
		return null;
	}
	// strip .h or .c extension
	const ext = s[$-1];
	if (s[$-2] == '.' && ext == 'h' || ext == 'i' || ext == 'c') {
		return s[0..$-2] ~ ";";
	}

	// unknown extension
	return null;
}
