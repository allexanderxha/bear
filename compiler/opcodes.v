// opcodes.v — bytecode opcodes for the VuurRaaf compiler.
//
// Keep in sync with vm/vm.v and assembler/assembler.v.
module compiler

const op_halt = u8(0)
const op_push_i = u8(1)
const op_push_s = u8(2)
const op_load = u8(3)
const op_store = u8(4)
const op_pop = u8(5)
const op_dup = u8(6)
const op_add = u8(7)
const op_sub = u8(8)
const op_mul = u8(9)
const op_div = u8(10)
const op_mod = u8(11)
const op_neg = u8(12)
const op_eq = u8(13)
const op_ne = u8(14)
const op_lt = u8(15)
const op_le = u8(16)
const op_gt = u8(17)
const op_ge = u8(18)
const op_and = u8(19)
const op_or = u8(20)
const op_not = u8(21)
const op_jmp = u8(22)
const op_jz = u8(23)
const op_jnz = u8(24)
const op_call = u8(25)
const op_ret = u8(26)
const op_retv = u8(27)
const op_print = u8(28)
const op_println = u8(29)
const op_assert = u8(30)
const op_enter = u8(31)
const op_mkarray = u8(32)
const op_aget = u8(33)
const op_aset = u8(34)
const op_alen = u8(35)
const op_apush = u8(36)
const op_mkstruct = u8(37)
const op_sget = u8(38)
const op_sset = u8(39)
const op_shas = u8(40)
const op_sdel = u8(41)
const op_slen = u8(42)
const op_skeys = u8(43)
const op_slice = u8(44)
const op_push_f = u8(45)
const op_native = u8(46)
const op_and_b = u8(47)
const op_or_b = u8(48)
const op_xor = u8(49)
const op_shl = u8(50)
const op_shr = u8(51)
const op_not_b = u8(52)
const op_try = u8(53)
const op_throw = u8(54)
const op_catch_done = u8(55)
const op_closure = u8(56)
const op_call_closure = u8(57)
const op_argc = u8(58) // push the current frame's arg count
const op_load_dyn = u8(59) // pop idx, push stack[bp + idx]
const op_varargs = u8(60) // <named:i64> <dst:i64> — collect args[named..argc-1] into an array at local dst
const op_str_method = u8(61) // <name:str> <argc:i64> — call a string method (s.len(), s.contains(x), ...)
const op_push_none = u8(62) // push the `none` sentinel

// native builtin ids (keep in sync with vm/opcodes.v)
const native_abs = 100
const native_min = 101
const native_max = 102
const native_pow = 103
const native_sqrt = 104
const native_floor = 105
const native_ceil = 106
const native_round = 107
const native_rand = 108
const native_rand_int = 109
const native_int = 110
const native_str = 111
const native_float = 112
const native_type = 113
const native_split = 114
const native_join = 115
const native_contains = 116
const native_starts_with = 117
const native_ends_with = 118
const native_trim = 119
const native_lower = 120
const native_upper = 121
const native_pop = 122
const native_insert = 123
const native_remove = 124
const native_sort = 125
const native_clone = 126
const native_reverse = 127
const native_index_of = 128
const native_args = 129
const native_getenv = 130
const native_setenv = 131
const native_exit = 132
const native_time = 133
const native_sleep = 134
const native_read_file = 135
const native_write_file = 136
const native_eprint = 137

// build-module builtins (.vrmm) — available to `vr make` scripts and to any
// program that wants to drive the toolchain
const native_build_compile = 138
const native_build_assemble = 139
const native_build_link = 140
const native_build_run = 141
const native_build_test = 142
const native_build_bench = 143
const native_build_clean = 144
const native_build_exec = 145
const native_build_exec_status = 146
const native_build_exists = 147
const native_build_mkdir = 148
const native_build_rm = 149
const native_build_copy = 150
const native_build_glob = 151
const native_build_ls = 152
const native_build_base = 153
const native_build_dir = 154
const native_build_join = 155
const native_build_root = 156

// stdlib builtins (JSON + string formatting)
const native_json_encode = 157
const native_json_decode = 158
const native_format = 159
const native_replace = 160
const native_split_lines = 161
const native_pad = 162
const native_pad_left = 163
const native_repeat = 164
const native_build_is_dir = 165
const native_cwd = 166
const native_json_pretty = 167

// HTTP client builtins
const native_http_get = 168
const native_http_post = 169

// date/time builtins
const native_now = 170
const native_time_ms = 171
const native_format_time = 172
const native_parse_time = 173

// regex builtins
const native_regex_match = 174
const native_regex_find_all = 175
const native_regex_replace = 176
const native_regex_split = 177

// crypto/encoding builtins
const native_base64_encode = 178
const native_base64_decode = 179
const native_sha256 = 180
const native_md5 = 181
const native_csv_parse = 182

// extended HTTP + filesystem/process builtins
const native_http_req = 183
const native_path_ext = 184
const native_path_abs = 185
const native_path_rel = 186
const native_exec_full = 187
const native_weekday = 188
