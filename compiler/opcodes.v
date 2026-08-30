// opcodes.v — bytecode opcodes and native-builtin IDs for VuurRaaf.
//
// This is the single source of truth for opcode and builtin IDs. The VM
// (vm/opcodes.v) re-exports these constants, so the compiler, VM, and
// assembler can never drift apart.
module compiler

pub const op_halt = u8(0)
pub const op_push_i = u8(1)
pub const op_push_s = u8(2)
pub const op_load = u8(3)
pub const op_store = u8(4)
pub const op_pop = u8(5)
pub const op_dup = u8(6)
pub const op_add = u8(7)
pub const op_sub = u8(8)
pub const op_mul = u8(9)
pub const op_div = u8(10)
pub const op_mod = u8(11)
pub const op_neg = u8(12)
pub const op_eq = u8(13)
pub const op_ne = u8(14)
pub const op_lt = u8(15)
pub const op_le = u8(16)
pub const op_gt = u8(17)
pub const op_ge = u8(18)
pub const op_and = u8(19)
pub const op_or = u8(20)
pub const op_not = u8(21)
pub const op_jmp = u8(22)
pub const op_jz = u8(23)
pub const op_jnz = u8(24)
pub const op_call = u8(25)
pub const op_ret = u8(26)
pub const op_retv = u8(27)
pub const op_print = u8(28)
pub const op_println = u8(29)
pub const op_assert = u8(30)
pub const op_enter = u8(31)
pub const op_mkarray = u8(32)
pub const op_aget = u8(33)
pub const op_aset = u8(34)
pub const op_alen = u8(35)
pub const op_apush = u8(36)
pub const op_mkstruct = u8(37)
pub const op_sget = u8(38)
pub const op_sset = u8(39)
pub const op_shas = u8(40)
pub const op_sdel = u8(41)
pub const op_slen = u8(42)
pub const op_skeys = u8(43)
pub const op_slice = u8(44)
pub const op_push_f = u8(45)
pub const op_native = u8(46)
pub const op_and_b = u8(47)
pub const op_or_b = u8(48)
pub const op_xor = u8(49)
pub const op_shl = u8(50)
pub const op_shr = u8(51)
pub const op_not_b = u8(52)
pub const op_try = u8(53)
pub const op_throw = u8(54)
pub const op_catch_done = u8(55)
pub const op_closure = u8(56)
pub const op_call_closure = u8(57)
pub const op_argc = u8(58) // push the current frame's arg count
pub const op_load_dyn = u8(59) // pop idx, push stack[bp + idx]
pub const op_varargs = u8(60) // <named:i64> <dst:i64> — collect args[named..argc-1] into an array at local dst
pub const op_str_method = u8(61) // <name:str> <argc:i64> — call a string method (s.len(), s.contains(x), ...)
pub const op_push_none = u8(62) // push the `none` sentinel
pub const op_in = u8(63) // membership: x in col -> 0 or 1

// native builtin ids (keep in sync with vm/opcodes.v)
pub const native_abs = 100
pub const native_min = 101
pub const native_max = 102
pub const native_pow = 103
pub const native_sqrt = 104
pub const native_floor = 105
pub const native_ceil = 106
pub const native_round = 107
pub const native_rand = 108
pub const native_rand_int = 109
pub const native_int = 110
pub const native_str = 111
pub const native_float = 112
pub const native_type = 113
pub const native_split = 114
pub const native_join = 115
pub const native_contains = 116
pub const native_starts_with = 117
pub const native_ends_with = 118
pub const native_trim = 119
pub const native_lower = 120
pub const native_upper = 121
pub const native_pop = 122
pub const native_insert = 123
pub const native_remove = 124
pub const native_sort = 125
pub const native_clone = 126
pub const native_reverse = 127
pub const native_index_of = 128
pub const native_args = 129
pub const native_getenv = 130
pub const native_setenv = 131
pub const native_exit = 132
pub const native_time = 133
pub const native_sleep = 134
pub const native_read_file = 135
pub const native_write_file = 136
pub const native_eprint = 137

// build-module builtins (.vrmm) — available to `vr make` scripts and to any
// program that wants to drive the toolchain
pub const native_build_compile = 138
pub const native_build_assemble = 139
pub const native_build_link = 140
pub const native_build_run = 141
pub const native_build_test = 142
pub const native_build_bench = 143
pub const native_build_clean = 144
pub const native_build_exec = 145
pub const native_build_exec_status = 146
pub const native_build_exists = 147
pub const native_build_mkdir = 148
pub const native_build_rm = 149
pub const native_build_copy = 150
pub const native_build_glob = 151
pub const native_build_ls = 152
pub const native_build_base = 153
pub const native_build_dir = 154
pub const native_build_join = 155
pub const native_build_root = 156

// stdlib builtins (JSON + string formatting)
pub const native_json_encode = 157
pub const native_json_decode = 158
pub const native_format = 159
pub const native_replace = 160
pub const native_split_lines = 161
pub const native_pad = 162
pub const native_pad_left = 163
pub const native_repeat = 164
pub const native_build_is_dir = 165
pub const native_cwd = 166
pub const native_json_pretty = 167

// HTTP client builtins
pub const native_http_get = 168
pub const native_http_post = 169

// date/time builtins
pub const native_now = 170
pub const native_time_ms = 171
pub const native_format_time = 172
pub const native_parse_time = 173

// regex builtins
pub const native_regex_match = 174
pub const native_regex_find_all = 175
pub const native_regex_replace = 176
pub const native_regex_split = 177

// crypto/encoding builtins
pub const native_base64_encode = 178
pub const native_base64_decode = 179
pub const native_sha256 = 180
pub const native_md5 = 181
pub const native_csv_parse = 182

// extended HTTP + filesystem/process builtins
pub const native_http_req = 183
pub const native_path_ext = 184
pub const native_path_abs = 185
pub const native_path_rel = 186
pub const native_exec_full = 187
pub const native_weekday = 188

// string builder (efficient repeated concatenation)
pub const native_sb_new = 189
pub const native_sb_add = 190
pub const native_sb_str = 191
pub const native_sb_len = 192

// concurrency: spawn/join threads
pub const native_spawn = 193
pub const native_spawn_join = 194

// interactive input: read a line from stdin
pub const native_read_line = 195
pub const native_input = 196

// getopt-style flag parsing over args()
pub const native_flag_val = 197
pub const native_flag_has = 198
pub const native_flag_positional = 199

// structured reflection + sequence helper
pub const native_type_info = 200
pub const native_range = 201
