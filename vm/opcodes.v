// opcodes.v — bytecode opcodes for the VuurRaaf VM.
//
// Keep in sync with the compiler and assembler.
module vm

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
const op_shas = u8(40) // has(map, "key") -> 1 if key exists, 0 otherwise
const op_sdel = u8(41) // delete(map, "key") -> removes the key
const op_slen = u8(42) // slen(struct) -> number of fields
const op_skeys = u8(43) // skeys(struct) -> array of field name strings
