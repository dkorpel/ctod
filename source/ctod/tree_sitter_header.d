/**
Previously: extern(C) bindings to the tree-sitter C library.

The tree-sitter runtime and the C grammar are now implemented in D
(ctod.treesitter and ctod.c_grammar), so this module just re-exports the D API
under the original module name that the rest of ctod imports.
*/
module ctod.tree_sitter_header;

public import ctod.treesitter;

alias cstring = const(char)*;
