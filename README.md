# C to D code converter

There's already dpp and dstep for translating C headers to D.
This tool attempts to translate C source code to D.

### Why?
Dub is unable to compile C projects.
What if I want to use a C library for my D project, such as GLFW?
You could include a pre-compiled `glfw.dll` and `libglfw.so` in the git repository, and use a dynamic loader like bindbc-glfw.
This is a bit clumsy.
`sourceFiles `

But what if I want to translate source files
- sometimes, dstep gives an error

Instead of using libclang (the LLVM C parser api) it uses the tree-sitter parser for C.
tree-sitter is a parser generator with a focus on incremental parsing and error recovery, useful for IDE tools.
The latter property is also useful for this tool: if you want, you can convert broken C code to similarly broken D code.


To get familiar with how tree-sitter parses C code and how it names its nodes, try out the playground:
https://tree-sitter.github.io/tree-sitter/playground

```
dub -- ../test/cute_time.c
```

### Todo
- #undef
- wchar_t => import core.stdc.stddef: wchar_t;
- #define can be alias, not only enum
- number literals such as 1.f => 1.0f
- passing function pointers or static arrays to functions
- don't always use [] initializers
- convert arrays in functions to static arrays instead of pointers

??
__declspec(dllexport) == export
__stdcall == extern(System)

### C Language fields

0. (null)
1. alternative
2. argument
3. arguments
4. body
5. condition
6. consequence
7. declarator
8. designator
9. directive
10. field
11. function
12. index
13. initializer
14. label
15. left
16. name
17. operator
18. parameters
19. path
20. right
21. size
22. type
23. update

### C Language symbols
 0. end
 1. identifier
 2. #include
 3. "\n"
 4. #define
 5. (
 6. ...
 7. ,
 8. )
 9. #if
10. #endif
11. #ifdef
12. #ifndef
13. #else
14. #elif
15. preproc_directive
16. preproc_arg
17. (
18. defined
19. !
20. ~
21. -
22. +
23. *
24. /
25. %
26. ||
27. &&
28. |
29. ^
30. &
31. ==
32. !=
33. >
34. >=
35. <=
36. <
37. <<
38. >>
39. ;
40. typedef
41. extern
42. __attribute__
43. __declspec
44. __based
45. __cdecl
46. __clrcall
47. __stdcall
48. __fastcall
49. __thiscall
50. __vectorcall
51. ms_restrict_modifier
52. ms_unsigned_ptr_modifier
53. ms_signed_ptr_modifier
54. _unaligned
55. __unaligned
56. {
57. }
58. [
59. ]
60. =
61. static
62. auto
63. register
64. inline
65. const
66. volatile
67. restrict
68. _Atomic
69. signed
70. unsigned
71. long
72. short
73. primitive_type
74. enum
75. struct
76. union
77. :
78. if
79. else
80. switch
81. case
82. default
83. while
84. do
85. for
86. return
87. break
88. continue
89. goto
90. ?
91. *=
92. /=
93. %=
94. +=
95. -=
96. <<=
97. >>=
98. &=
99. ^=
100. |=
101. --
102. ++
103. sizeof
104. .
105. ->
106. number_literal
107. L'
108. u'
109. U'
110. u8'
111. '
112. char_literal_token1
113. L"
114. u"
115. U"
116. u8"
117. "
118. string_literal_token1
119. escape_sequence
120. system_lib_string
121. true
122. false
123. null
124. comment
125. translation_unit
126. preproc_include
127. preproc_def
128. preproc_function_def
129. preproc_params
130. preproc_call
131. preproc_if
132. preproc_ifdef
133. preproc_else
134. preproc_elif
135. preproc_if
136. preproc_ifdef
137. preproc_else
138. preproc_elif
139. _preproc_expression
140. parenthesized_expression
141. preproc_defined
142. unary_expression
143. call_expression
144. argument_list
145. binary_expression
146. function_definition
147. declaration
148. type_definition
149. _declaration_specifiers
150. linkage_specification
151. attribute_specifier
152. ms_declspec_modifier
153. ms_based_modifier
154. ms_call_modifier
155. ms_unaligned_ptr_modifier
156. ms_pointer_modifier
157. declaration_list
158. _declarator
159. _field_declarator
160. _type_declarator
161. _abstract_declarator
162. parenthesized_declarator
163. parenthesized_declarator
164. parenthesized_declarator
165. abstract_parenthesized_declarator
166. pointer_declarator
167. pointer_declarator
168. pointer_declarator
169. abstract_pointer_declarator
170. function_declarator
171. function_declarator
172. function_declarator
173. abstract_function_declarator
174. array_declarator
175. array_declarator
176. array_declarator
177. abstract_array_declarator
178. init_declarator
179. compound_statement
180. storage_class_specifier
181. type_qualifier
182. _type_specifier
183. sized_type_specifier
184. enum_specifier
185. enumerator_list
186. struct_specifier
187. union_specifier
188. field_declaration_list
189. _field_declaration_list_item
190. field_declaration
191. bitfield_clause
192. enumerator
193. parameter_list
194. parameter_declaration
195. labeled_statement
196. expression_statement
197. if_statement
198. switch_statement
199. case_statement
200. while_statement
201. do_statement
202. for_statement
203. return_statement
204. break_statement
205. continue_statement
206. goto_statement
207. _expression
208. comma_expression
209. conditional_expression
210. assignment_expression
211. pointer_expression
212. unary_expression
213. binary_expression
214. update_expression
215. cast_expression
216. type_descriptor
217. sizeof_expression
218. subscript_expression
219. call_expression
220. argument_list
221. field_expression
222. compound_literal_expression
223. parenthesized_expression
224. initializer_list
225. initializer_pair
226. subscript_designator
227. field_designator
228. char_literal
229. concatenated_string
230. string_literal
231. _empty_declaration
232. macro_type_specifier
233. translation_unit_repeat1
234. preproc_params_repeat1
235. preproc_if_in_field_declaration_list_repeat1
236. preproc_argument_list_repeat1
237. declaration_repeat1
238. type_definition_repeat1
239. type_definition_repeat2
240. _declaration_specifiers_repeat1
241. pointer_declarator_repeat1
242. function_declarator_repeat1
243. sized_type_specifier_repeat1
244. enumerator_list_repeat1
245. field_declaration_repeat1
246. parameter_list_repeat1
247. case_statement_repeat1
248. argument_list_repeat1
249. initializer_list_repeat1
250. initializer_pair_repeat1
251. concatenated_string_repeat1
252. string_literal_repeat1
253. field_identifier
254. statement_identifier
255. type_identifier