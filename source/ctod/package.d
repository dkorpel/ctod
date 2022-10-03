module ctod;


public {
	//import ctod.cdeclaration;
	//import ctod.cpreproc;
	//import ctod.translate;
	import ctod.ctype;
}
version(none):
private {
	version(WebAssembly) {} else import ctod.app;
	import ctod.test;
	import ctod.translate;
}
