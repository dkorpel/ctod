/**
Translate C macros
*/
module ctod.cpreproc;

nothrow @safe:

import ctod.translate;
import ctod.tree_sitter;
import ctod.util;

package
/// If `node` is a recognized preprocessor node, translate it to D
///
/// Returns: `true` on success
bool ctodTryPreprocessor(ref CtodCtx ctx, ref Node node) {
	switch (node.typeEnum) {
		case Sym.aux_preproc_else_token1: // "#else"
			return node.replace("} else {");
		case Sym.aux_preproc_if_token2: // "#endif"
			return node.replace("}");
		case Sym.aux_preproc_include_token1: // "#include"
			return node.replace("public import");
		case Sym.preproc_call: // #error, #pragma, #undef
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
					if (argument && argument.source.length >= 4 && argument.source[$-4 .. $] == "once") {
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
				if (auto c = node.childField(Field.name)) {
					translateNode(ctx, *c);
					ctx.macroTable[c.output()] = MacroType.manifestConstant;
				}
				auto argNode = node.firstChildType(Sym.preproc_arg);
				assert(argNode);
				const argText = argNode.source;
				size_t p = 0;
				while (p < argText.length && argText[p].isWhite) {
					p++;
				}
				string whitespace = argText[0 .. p];
				string value = argText[p .. $];
				string comment = "";

				// tree sitter doesn't parse line comments inside preproc arg,
				// so we need to manually split it so that:
				// #define X Y // comment
				// Becomes:
				// enum X = Y; // comment
				// Instead of:
				// enum X = Y // comment;
				p = 0;
				while (p+1 < value.length) {
					if (value[p] == '/' && value[p+1] == '/') {
						while (p > 0 && value[p-1].isWhite) {
							p--;
						}
						comment = value[p .. $];
						value = value[0 .. p];
						break;
					}
					p++;
				}

				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					import ctod.ctype: ctodPrimitiveType;
					const newValue = ctodPrimitiveType(value);
					if (newValue != value) {
						c.replace("alias");
						value = newValue;
					} else if (value == "int") { // TODO: generalize to all D types
						c.replace("alias");
					} else {
						c.replace("enum");
					}
				}
				argNode.replace(" =" ~ whitespace ~ value ~ ";" ~ comment);

			} else {
				if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
					c.replace("version =");
				}
				if (auto c = node.childField(Field.name)) {
					c.append(";");
					translateNode(ctx, *c);
					ctx.macroTable[c.output()] = MacroType.versionId;
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
				// #define F(x)
				node.prepend("//");
				ctx.macroTable[nameNode.output()] = MacroType.emptyFunc;
				return true;
			}
			// #define
			if (auto c = node.firstChildType(Sym.aux_preproc_def_token1)) {
				c.replace("enum string");
			}
			translateNode(ctx, *nameNode);
			ctx.macroTable[nameNode.output()] = MacroType.inlineFunc;

			string[] params;
			foreach (ref param; parametersNode.children) {
				if (param.typeEnum == Sym.identifier) {
					ctx.macroFuncParams[param.source] = true;
					params ~= param.source;
					param.prepend("string ");
				}
			}

			valueNode.prepend(" = `");
			valueNode.replace(ctodMacroFunc(ctx, valueNode.source));
			(() @trusted => ctx.macroFuncParams.clear())();
			valueNode.append("`;");
			break;
		case Sym.preproc_ifdef:
			removeSemicolons(node);
			if (ctodHeaderGuard(ctx, node)) {
				return true;
			}
			auto nameNode = node.childField(Field.name);
			if (!nameNode) {
				return true;
			}
			string versionName = nameNode.source;
			if (string s = mapLookup(versionMap, nameNode.source, null)) {
				nameNode.replace(s);
				versionName = s;
			}
			if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token1)) {
				c.replace("version");
				nameNode.prepend("(");
				nameNode.append(") {");
			} else if (auto c = node.firstChildType(Sym.aux_preproc_ifdef_token2)) {
				// Recognize `#ifndef X (#define X Y) #endif`, treat as just `#define X Y`
				if (node.children.length == 4) {
					Node b = node.children[2];
					if (b.typeEnum == Sym.preproc_def) {
						if (auto cc = b.childField(Field.name)) {
							if (cc.source == nameNode.source) {
								translateNode(ctx, b);
								node.replace(b.output);
								return true;
							}
						}
					}
				}

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
			return replaceDefined(ctx, node, false);
		case Sym.preproc_if:
			auto c = node.childField(Field.condition);
			auto ifnode = node.firstChildType(Sym.aux_preproc_if_token1); // "#if"
			if (!c || !ifnode) {
				return true;
			}

			if (c.typeEnum == Sym.preproc_defined) {
				ifnode.replace("version");
				replaceDefined(ctx, *c, true);
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
						replaceDefined(ctx, *c, true);
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
			string lib = node.source[1 .. $-1]; // slice to strip off angle brackets in <stdio.h>
			node.replace(ctodSysLib(lib));
			break;
		case Sym.preproc_include:
			//if (auto c = node.firstChildType("string_literal")) {
			if (auto pathNode = node.childField(Field.path)) {
				if (pathNode.typeEnum == Sym.string_literal) {
					pathNode.replace(ctodIncludePath(pathNode.source));
				} else {
					// see case for system_lib_string above
					ctodTryPreprocessor(ctx, *pathNode);
					// note: explicit call not really needed, children are
					// automatically translated by returning false
				}
			}
			break;
		default: break;
	}
	return false;
}

/// Find params in macroText, and surround them with ~""~
string ctodMacroFunc(ref CtodCtx ctx, string macroText) {
	while (macroText.length > 0 && macroText[0].isWhite) {
		macroText = macroText[1 .. $];
	}
	// Assume the macro expand to an expression, statement, or variable declaration
	// We need to wrap it in a function because tree-sitter parses a translation unit
	// Then extract the function body and remove braces
	string funcStr = "void __macroFunc(void) {"~macroText~"}";
	auto root = parseCtree(ctx.parser, funcStr);
	if (!root || !root.children.length > 0) {
		return macroText;
	}
	translateNode(ctx, *root);
	auto f = root.children[0].childField(Field.body_);
	if (!f || !f.children.length > 0) {
		return macroText;
	}
	foreach (ref c; f.children) {
		if (c.typeEnum == Sym.anon_LBRACE || c.typeEnum == Sym.anon_RBRACE) {
			c.replace("");
		}
	}
	return f.output();
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
private bool ctodHeaderGuard(ref CtodCtx ctx, ref Node ifdefNode) {

	assert(ifdefNode.typeEnum == Sym.preproc_ifdef);

	// The grammar has the same node type for `#ifdef` and `#ifndef`
	if (ifdefNode.children[0].typeEnum != Sym.aux_preproc_ifdef_token2) {
		return false;
	}

	int commentCount = 0;
	// second node is always field `name` with a `Sym.identifier`
	string id = ifdefNode.children[1].source;

	foreach (i; 0 .. ifdefNode.children.length) {
		switch (ifdefNode.children[i].typeEnum) {
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
					foreach (j; 0 .. ifdefNode.children.length) {
						if (j <= i || j + 1 == ifdefNode.children.length) {
							ifdefNode.children[j].replace(""); // header guard nodes
						} else {
							translateNode(ctx, ifdefNode.children[j]); // content nodes
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
bool replaceDefined(ref CtodCtx ctx, ref Node node, bool inVersionStatement) {
	if (auto c = node.firstChildType(Sym.identifier)) {
		string replacement = c.source;
		if (string s = mapLookup(versionMap, c.source, null)) {
			c.replace(s); // known #define translation
			replacement = s;
		} else {
			translateNode(ctx, *c); // reserved identifier replacement
		}
		if (inVersionStatement) {
			return node.replace(replacement);
		} else {
			ctx.needsHasVersion = true;
			return node.replace(`HasVersion!"` ~ replacement ~ `"`);
		}
	}
	return false;
}

/// Map C define to D version identifier, to replace e.g. `#ifdef _WIN32` with `version(Windows)`
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

/// Translate the include <> or "" path, for:
///
/// #include <folder/file.h> => import folder.file;
string ctodIncludePath(string s) pure {
	if (s.length < 5) {
		return null; // <a.h>
	}
	s = s[1 .. $-2];
	auto res = s.dup;
	replaceChar(res, '/', '.');
	res[$-1] = ';';
	return (() @trusted => cast(immutable) res)();
}

/// Replace all occurences of `from` with `to` in `s`
void replaceChar(char[] s, char from, char to) pure {
	foreach (i; 0 .. s.length) {
		if (s[i] == from) {
			s[i] = to;
		}
	}
}

@("ctodIncludePath") unittest
{
	assert(ctodIncludePath("<folder/file.h>") == "folder.file;");
}

// C standard lib header translation
// prefix: core.stdc.
private immutable string[] libcMap = [
	"complex", "config", "ctype", "errno", "fenv",
	"inttypes", "limits", "locale", "math", "signal",
	"stdarg", "stddef", "stdint", "stdio", "stdlib",
	"string", "tgmath", "time", "wctype",
];

// Windows header translation
// prefix: core.sys.windows
private immutable string[] windowsMap = [
	"accctrl", "aclapi", "aclui", "basetsd", "basetyps", "cderr", "cguid", "com", "comcat", "commctrl", "commdlg",
	"core", "cpl", "cplext", "custcntl", "dbghelp", "dbghelp_types", "dbt", "dde", "ddeml", "dhcpcsdk", "dlgs",
	"dll", "docobj", "errorrep", "exdisp", "exdispid", "httpext", "idispids", "imagehlp", "imm", "intshcut",
	"ipexport", "iphlpapi", "ipifcons", "iprtrmib", "iptypes", "isguids", "lm", "lmaccess", "lmalert", "lmapibuf",
	"lmat", "lmaudit", "lmbrowsr", "lmchdev", "lmconfig", "lmcons", "lmerr", "lmerrlog", "lmmsg", "lmremutl",
	"lmrepl", "lmserver", "lmshare", "lmsname", "lmstats", "lmsvc", "lmuse", "lmuseflg", "lmwksta", "lzexpand",
	"mapi", "mciavi", "mcx", "mgmtapi", "mmsystem", "msacm", "mshtml", "mswsock", "nb30", "nddeapi", "nspapi",
	"ntdef", "ntdll", "ntldap", "ntsecapi", "ntsecpkg", "oaidl", "objbase", "objfwd", "objidl", "objsafe", "ocidl",
	"odbcinst", "ole", "ole2", "ole2ver", "oleacc", "oleauto", "olectl", "olectlid", "oledlg", "oleidl", "pbt",
	"powrprof", "prsht", "psapi", "rapi", "ras", "rasdlg", "raserror", "rassapi", "reason", "regstr", "richedit",
	"richole", "rpc", "rpcdce", "rpcdce2", "rpcdcep", "rpcndr", "rpcnsi", "rpcnsip", "rpcnterr", "schannel",
	"sdkddkver", "secext", "security", "servprov", "setupapi", "shellapi", "shldisp", "shlguid", "shlobj",
	"shlwapi", "snmp", "sql", "sqlext", "sqltypes", "sqlucode", "sspi", "stacktrace", "stat", "subauth",
	"threadaux", "tlhelp32", "tmschema", "unknwn", "uuid", "vfw", "w32api", "winbase", "winber", "wincon",
	"wincrypt", "windef", "windows", "winerror", "wingdi", "winhttp", "wininet", "winioctl", "winldap",
	"winnetwk", "winnls", "winnt", "winperf", "winreg", "winsock2", "winspool", "winsvc", "winuser",
	"winver", "wtsapi32", "wtypes"
];

// prefix: core.sys.posix
private immutable string[] posixMap = [
	"aio", "ar", "dirent", "dlfcn", "fcntl", "grp", "iconv", "libgen", "n",
	"netdb", "netin", "poll", "pthread", "pwd", "s", "sched", "semaphore",
	"setjmp",
	"syslog", "termios", "ucontext", "unistd", "utime"
];

private immutable string[] posixSysMap = [
	"sys/filio", "sys/ioccom", "sys/ioctl", "sys/ipc", "sys/mman", "sys/msg",
	"sys/resource", "sys/select", "sys/shm", "sys/socket", "sys/stat",
	"sys/statvfs", "sys/time", "sys/ttycom", "sys/types", "sys/uio", "sys/un",
	"sys/utsname", "sys/wait"
];

private immutable string[2][] miscMap = [
	["assert",   "core.stdc.assert_"],
	["float_",   "core.stdc.float_"],
	["wchar",    "core.stdc.wchar_"],
	["linux/limits" ,  "core.stdc.limits"],
	["sys/inotify",    "core.sys.linux.sys.inotify"],
	["sys/timerfd",    "core.sys.linux.sys.timerfd"],
];

/// translate #include<> to an import in druntime.
string ctodSysLib(string s) {
	if (s.length < 2) {
		return s ~ ";";
	}
	// strip .h or .c extension
	const ext = s[$-1];
	if (s[$-2] == '.' && ext == 'h' || ext == 'i' || ext == 'c') {
		s = s[0 .. $-2];
		if (ext != 'h') {
			return s ~ ";";
		}
	}

	if (auto r = mapLookup(libcMap, s, null)) {
		return "core.stdc." ~ r ~ ";";
	}
	if (auto r = mapLookup(windowsMap, s, null)) {
		return "core.sys.windows." ~ r ~ ";";
	}
	if (auto r = mapLookup(posixMap, s, null)) {
		return "core.sys.posix." ~ r ~ ";";
	}
	if (auto r = mapLookup(posixSysMap, s, null)) {
		return "core.sys.posix.sys." ~ r["sys/".length .. $] ~ ";";
	}
	if (auto r = mapLookup(miscMap, s, null)) {
		return r ~ ";";
	}

	return s ~ ";";
}

// Remove `#ifdef __cplusplus \n extern "C" { \n #endif` blocks since tree-sitter can't parse the unmatched braces inside them
string filterCppBlocks(string source) {
	size_t[3] s = 0; // loop over line triples by keeping 3 indices of the start of a line
	for (size_t i = 0; i < source.length; i++) {
		if (source[i] == '\n') {
			const s3 = i + 1;
			if (source[s[0] .. s[1]].startsWith("#ifdef __cplusplus") && source[s[2] .. s3].startsWith("#endif")) {
				source = source[0 .. s[0]] ~ source[s3 .. $];
				i = s[0];
				s[] = 0;
				continue;
			} else {
				s[0] = s[1];
				s[1] = s[2];
				s[2] = s3;
			}
		}
	}
	return source;
}

unittest
{
	string source = "
#ifdef __cplusplus
extern \"C\" {
#endif
int main() {
	return 0;
}
#ifdef __cplusplus
}
#endif
";

	string expected = "
int main() {
	return 0;
}
";
	import ctod.util: assertEq;
	assertEq(filterCppBlocks(source), expected);
}
