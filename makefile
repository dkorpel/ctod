
ifeq ($(OS),Windows_NT)
    TARGET_EXT := .obj
else
    TARGET_EXT := ".a"
endif

CC := clang
#CC := "zig cc"

.PHONY: all
all: build-lib

.PHONY: build-lib
build-lib:
	clang -E -Isource -P source/ctod/c_parser.c > source/ctod/c_parser_pre.c
	$(CC) -c -Isource source/ctod/c_parser.c -o lib/libc-parser$(TARGET_EXT) -O2 -fPIC

# $(CC) -Isource source/main.c lib/libc-parser.a lib/libtree-sitter$(TARGET_EXT) -o build/parser -O2
# cd tree-sitter/lib/src
# clang -c -I../include *.c -o libtree-sitter.obj
.PHONY: wasm
wasm:
	ldc2 -i=. -i=std $(COMMON_FLAGS) -Iarsd-webassembly/ -L-allow-undefined -of=$(BUILD_DIR)/$(TARGET_NAME)-wasm -mtriple=wasm32-unknown-unknown-wasm \
	source/mathnum/package.d arsd-webassembly/object.d
