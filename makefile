
ifeq ($(OS),Windows_NT)
	TARGET_EXT := .obj
else
    TARGET_EXT := ".a"
endif

CC := clang

.PHONY: all
all: build-lib

.PHONY: build-lib
build-lib:
	$(CC) -c -Isource source/c_parser.c -o lib/libc-parser$(TARGET_EXT) -O2

# $(CC) -Isource source/main.c lib/libc-parser.a lib/libtree-sitter$(TARGET_EXT) -o build/parser -O2
# cd tree-sitter/lib/src
# clang -c -I../include *.c -o libtree-sitter.obj