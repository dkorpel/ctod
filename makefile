# Build the two C dependencies:
#   - the tree-sitter runtime
#   - the tree-sitter-c parser language

ifeq ($(OS),Windows_NT)
	FLAGS := -O2
    TARGET_EXT := .obj
	CC := clang
else
	FLAGS := -O2 -fPIC
    TARGET_EXT := .a
	CC := gcc
endif

.PHONY: all
all:
	$(CC) $(FLAGS) -c -Isource source/ctod/c_parser.c -o lib/libc-parser$(TARGET_EXT);
	$(CC) $(FLAGS) -Ilib-tree-sitter-src/src -Ilib-tree-sitter-src/include -c lib-tree-sitter-src/src/lib.c -o lib/libtree-sitter$(TARGET_EXT)

# WIP: Compile to WebAssembly with emscripten
.PHONY: wasm
wasm:
	emcc -O2 -Ilib-tree-sitter-src/src -Ilib-tree-sitter-src/include lib-tree-sitter-src/src/lib.c -o docs/test.html
