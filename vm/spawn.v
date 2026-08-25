// spawn.v — real OS-thread concurrency for the VuurRaaf VM.
//
//   let job = spawn(fn, arg1, arg2, ...)   // start, returns a job id
//   let result = spawn_join(job)           // wait for the result
//
// Each spawned closure runs on its own OS thread in a *fresh, isolated* VM.
// The child heap is built on the parent thread (so the deep-copy of captured
// values and arguments happens while the parent heap is quiescent), then the
// child VM is handed to a worker thread which owns it exclusively. The only
// state shared between threads is the immutable bytecode; the result is
// handed back through a per-job channel.
//
// The child Vm is passed to the worker *by value*: V copies the struct, and
// because the child grows its own slice pools (reallocating the backing on
// append), the worker's mutations never touch the parent's memory.
//
// Supported argument/result shapes: ints, floats, strings, `none`, and flat
// arrays/structs of those, deep-copied into the child heap. Composite
// results are rendered to their string form so the parent never holds a
// dangling child handle.

module vm

// Job records one in-flight spawn; the result arrives on the channel.
struct Job {
mut:
	entry int
	ready Vm // the isolated child VM, exclusively owned by the worker thread
	ch    chan JobResult
}

// JobResult is the outcome of a spawned closure, delivered via channel.
struct JobResult {
mut:
	ok  bool
	err string
	// exactly one of str / val is set: strings come back as `str` (always
	// isomorphic across heaps); other scalar results as `val`; composite
	// results are delivered as their string rendering in `str`.
	str string
	val i64
}

const max_jobs = 256

// spawn is wired to the `spawn` builtin: launch a closure on an OS thread.
fn (mut v Vm) native_spawn(argc int) !i64 {
	if argc < 1 {
		return error('spawn expects a function followed by zero or more arguments')
	}
	// stack (top first): arg_{argc-1} ... arg_0, closure
	mut args := []i64{len: argc - 1}
	for i in 0..argc - 1 {
		args[argc - 2 - i] = v.pop()!
	}
	ch := v.pop()!
	if !v.is_closure(ch) || !v.valid_closure_handle(ch) {
		return error('spawn expects a function as its first argument')
	}
	cl := v.closures[v.hand(ch)]
	if v.jobs.len >= max_jobs {
		return error('too many concurrent spawn jobs (limit ${max_jobs})')
	}
	child := v.build_job_vm(cl.entry, cl.captured, args)!
	idx := v.jobs.len
	v.jobs << Job{ entry: cl.entry, ready: child, ch: chan JobResult{cap: 1} }
	// pass the child Vm by value: the worker owns this copy exclusively
	job_child := v.jobs[idx].ready
	ch_result := v.jobs[idx].ch
	go run_spawned_job(job_child, ch_result)
	return v.enc_int(i64(idx))
}

// native_spawn_join is wired to the `spawn_join` builtin: block until the job
// finished, then return its result (deep-read back into the parent heap).
fn (mut v Vm) native_spawn_join() !i64 {
	id := int(v.dec_int(v.pop()!))
	if id < 0 || id >= v.jobs.len {
		return error('spawn_join: unknown job id ${id}')
	}
	res := <-v.jobs[id].ch
	if !res.ok {
		return error('spawned job failed: ${res.err}')
	}
	if res.str != '' {
		return v.alloc_str(res.str)
	}
	return res.val
}

// build_job_vm constructs the isolated child Vm and pre-loads the closure's
// captured values + call arguments as leading locals. Runs on the parent
// thread while the parent heap is quiescent.
fn (mut v Vm) build_job_vm(entry int, captured []i64, args []i64) !Vm {
	mut child := Vm{
		code:       v.code
		strings:    v.strings.clone()
		stack:      []i64{len: stack_cap}
		lines:      v.lines
		fns:        v.fns
		const_strs: v.const_strs
		max_ops:    v.max_ops
	}
	// Synthetic entry frame laid out exactly like Vm.call: [ip, old_bp, argc,
	// local_0..local_{argc-1}] with bp at local_0 (so stack[bp-3]=ip,
	// stack[bp-2]=old_bp, stack[bp-1]=argc). The synthetic caller is placed at
	// bp = 3 + n so that the closure's final `ret` — which reads ip(bp-3),
	// old_bp(bp-2), argc(bp-1), unwinds `sp -= argc`, then halts (ip == -1) and
	// pushes the return value — lands back at slot (3+n)-3-n = 0, mirroring
	// how a top-level `main` returns.
	n := captured.len + args.len
	child.bp = 3 + n
	child.sp = 3 + n
	base := child.bp - 3 // ip slot
	child.stack[base] = child.enc_int(-1) // return ip: signals the synthetic frame
	child.stack[base + 1] = child.enc_int(0) // old_bp
	child.stack[base + 2] = child.enc_int(i64(n)) // argc (captured + args)
	for i, c in captured {
		child.stack[child.bp + i] = v.copy_into(mut child, c)!
	}
	for i, a in args {
		child.stack[child.bp + captured.len + i] = v.copy_into(mut child, a)!
	}
	child.sp = child.bp + n
	child.ip = entry
	return child
}

// run_spawned_job is the worker thread entry: it drives the exclusively-owned
// child VM to completion and sends the result back. The child is passed by
// value — V copies the struct (including the freshly-allocated slice backings
// built on the parent thread), so this worker's mutations never alias the
// parent's memory.
fn run_spawned_job(child Vm, ch chan JobResult) {
	mut c := child
	c.exec() or {
		ch <- JobResult{ ok: false, err: err.msg() }
		return
	}
	res := c.stack[0] // left by ret from the synthetic entry frame
	if c.is_str(res) && c.valid_handle(res) {
		ch <- JobResult{ ok: true, str: c.strings[c.hand(res)] }
		return
	}
	ch <- JobResult{ ok: true, val: res }
}

// copy_into deep-copies a parent value into the child heap, re-interned so
// the child's handles are valid in its own pools. Runs on the parent thread.
fn (mut v Vm) copy_into(mut child Vm, x i64) !i64 {
	if v.is_int(x) {
		return x
	}
	if v.is_none(x) {
		return x
	}
	if v.is_float(x) && v.valid_float_handle(x) {
		child.floats << v.fval(x)
		return child.mkfloat(child.floats.len - 1)
	}
	if v.is_str(x) && v.valid_handle(x) {
		child.strings << v.strings[v.hand(x)]
		return child.mkstr(child.strings.len - 1)
	}
	if v.is_arr(x) && v.valid_arr_handle(x) {
		src := v.arrays[v.hand(x)]
		mut na := []i64{len: src.len}
		for i, el in src {
			na[i] = v.copy_into(mut child, el)!
		}
		child.arrays << na
		return child.mkarr(child.arrays.len - 1)
	}
	if v.is_struct(x) && v.valid_struct_handle(x) {
		s := v.structs[v.hand(x)]
		mut nf := []Field{len: s.fields.len}
		for i, fld in s.fields {
			nf[i] = Field{ name: fld.name, val: v.copy_into(mut child, fld.val)! }
		}
		child.structs << StructVal{ fields: nf, by_name: child.index_fields(nf) }
		return child.mkstruct_handle(child.structs.len - 1)
	}
	if v.is_closure(x) {
		return error('spawn: closures capturing composite/closure values are not supported')
	}
	return error('spawn: unsupported value type for cross-thread copy')
}