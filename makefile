# Build the two C dependencies:
#   - the tree-sitter runtime
#   - the tree-sitter-c parser language

# Platform specific file extension
ifeq ($(OS),Windows_NT)
    TARGET_EXT := .obj
else
    TARGET_EXT := .a
endif

# C compiler to use
CC := gcc
# (Optimization) flags
FLAGS := -O2 -fPIC

.PHONY: all
all:
	$(CC) $(FLAGS) -c -Isource source/ctod/c_parser.c -o lib/libc-parser$(TARGET_EXT);
	$(CC) $(FLAGS) -Ilib-tree-sitter-src/src -Ilib-tree-sitter-src/include -O2 -fPIC -c lib-tree-sitter-src/src/lib.c -o lib/libtree-sitter$(TARGET_EXT)
