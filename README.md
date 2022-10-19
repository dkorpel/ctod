![ctod logo](https://github.com/dkorpel/ctod/blob/master/ctod-logo.png)
# C to D code converter

A tool that does the boring parts of translating C to D.

### Usage

From the root of this repository:
```console
dub run --arch=x86_64 -- ../test/main.c
```

Arguments are `.c` or `.h` files, for which it outputs a translated `.d` file next to it.
This `.d` file may not compile yet, but it's supposed to get you 90% there.
The remaining errors are usually because of non-trivial macros, initializers, or because of D's stricter type system.

### Compatibility

The program depends on C libraries that are currently included in binary form in the `/lib` folder for x86-64 Windows and Linux.
By editing the `makefile` and running `make` you might make it work for other platforms as well.
In the future the aim is to use [ImportC](https://dlang.org/spec/importc.html) for this.

### Installation

You can copy the built binary to a folder in your `PATH`, for example on linux:
```console
dub build
sudo cp build/ctod /usr/local/bin/
```
This allows you to simply invoke `ctod` from anywhere.

### Motivation
This was written before [ImportC](https://dlang.org/spec/importc.html).
Statically linking C libraries with dub is clumsy: while there's usually C bindings in the package repository, you still need to grab release binaries for each build target / configration, include them in the repo, and fiddle with dub flags until there are no linker errors anymore.

That's why I like to translate C code to D.
While this requires some intelligence, a lot of the work is simple syntactic find-and-replace actions, and converting declaration syntax.
Even with VIM macros it was getting tedious, so I wrote this tool.
I used it for translating [glfw](https://github.com/dkorpel/glfw-d) and [libsoundio](https://github.com/dkorpel/libsoundio-d), as well as some single-file C libs.

### How it works
The [tree-sitter parser for C](https://github.com/tree-sitter/tree-sitter-c) is used to parse C code, including macros.
tree-sitter is a parser generator with a focus on incremental parsing and error recovery, useful for IDE tools.
Error recovery is particularly useful for this tool: it always gives a best-effort translated output, even when it encounters what it thinks is a parse error.
If you want, you can convert broken C code to similarly broken D code.

This tool makes use of the fact that in general, if D code looks like C, it either behaves the same as C or doesn't compile.
Also, D has almost all features that C has.
The tool doesn't need a deep understanding of C code, and a lot of things are passed through without any change:

```D
// Identical in both C and D
float fabs(float x) {
    if (x < 0.0)
        return -x;
    return x;
}
```

However, there's also a lot of things that are different between C and D.
This ranges from simple syntax changes:
- `x->y` => `x.y`
- `(float) 1lu` => `cast(float) 1Lu`
- `"con" "cat"` => `"con" ~ "cat"`

To more difficult translations, such as declarations with complex types:
```C
char *(*(*fun)[5])(int);
```
D:
```D
char* function(int)[5]* fun;
```

It's being developed like this:

- Run `ctod` on a C file
- Look at the output, notice something that needs to be adjusted to be valid D
- Enter the C code in the [tree-sitter playground](https://tree-sitter.github.io/tree-sitter/playground) to see what it looks like in the AST
- Add code to recognize and translate the pattern
- Repeat for as many patterns as possible

So this is really just a big find-and-replace tool that operates on an AST provided by tree-sitter.

### Alternatives

If you only need to translate C headers and not actual code, there are also these tools available:

- [dpp](https://code.dlang.org/packages/dpp)
- [dstep](https://code.dlang.org/packages/dstep)
- [ohmygentool](https://github.com/Superbelko/ohmygentool)

Those tools use libclang (the LLVM C parser api) to parse C instead of tree-sitter.

### See also

- [Programming in D for C Programmers](https://dlang.org/articles/ctod.html)
