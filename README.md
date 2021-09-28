# C to D code converter

A tool attempts to translate C source code to D.

### Usage
It only works on Linux at the moment unfortunately, I'm still trouble-shooting the Windows build.
```console
dub run -- ../test/main.c
```
Arguments are `.c` or `.h` files. Currently the only option is `--strip` to strip comments, used to remove documentation comments from header files.

Example installation:
```console
dub build
sudo cp build/ctod /usr/local/bin/
```

### Why?
This was written before [ImportC](https://dlang.org/spec/importc.html).
Statically linking C libraries with dub is clumsy: while there's usually C bindings in the package repository, you still need to grab release binaries for each build target / configration, include them in the repo, and fiddle with dub flags until there are no linker errors anymore.

That's why I like to translate C code to D.
While this requires some intelligence, a lot of the work is simple syntactic find-and-replace actions, and converting declaration syntax.
Even with VIM macros it was getting tedious, so I wrote this tool.
I used it for translating [glfw](https://github.com/dkorpel/glfw-d) and [libsoundio](https://github.com/dkorpel/libsoundio-d), as well as some single-file C libs.

### Internal
Instead of using libclang (the LLVM C parser api) it uses the tree-sitter parser for C.
tree-sitter is a parser generator with a focus on incremental parsing and error recovery, useful for IDE tools.
The latter property is also useful for this tool: if you want, you can convert broken C code to similarly broken D code.

To get familiar with how tree-sitter parses C code and how it names its nodes, try out the playground:
https://tree-sitter.github.io/tree-sitter/playground

### Alternatives
- [dpp](https://code.dlang.org/packages/dpp)
- [dstep](https://code.dlang.org/packages/dstep)
- [ohmygentool](https://github.com/Superbelko/ohmygentool)

Those tools use LLVM to parse C instead of tree-sitter. 
They are more robust, but harder to build and they can error out, while Tree-sitter is

### Todo
- #define can be alias, not only enum
- passing function pointers or static arrays to functions
- don't always use [] initializers
- convert arrays in functions to static arrays instead of pointers
- switch statement => add default case if needed
- __declspec(dllexport) => export?
- __stdcall => extern(System)?

### See also

[Programming in D for C Programmers](https://dlang.org/articles/ctod.html)
