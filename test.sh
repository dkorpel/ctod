gcc -c -Isource source/c_parser.c -o lib/libc-parser.a -O2
gcc -Isource source/main.c lib/libc-parser.a lib/libtree-sitter.a -o build/parser -O2