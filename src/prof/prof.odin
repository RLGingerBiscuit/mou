package prof

import "core:fmt"
import "core:mem"
import "core:os"
import "core:prof/spall"
import "core:strings"
import "core:sync"
import "core:time"

_ :: fmt
_ :: mem
_ :: os
_ :: spall
_ :: strings
_ :: sync
_ :: time

PROFILING :: #config(PROFILING, false)

when PROFILING {
	Context :: spall.Context
	Buffer :: spall.Buffer
	Prof :: struct {
		ctx:          Context,
		bufs:         map[int]Buffer,
		allocator:    mem.Allocator,
		lock:         sync.RW_Mutex,
		_initialised: bool,
	}
} else {
	Prof :: struct {}
}

@(private)
prof: Prof

when PROFILING {
	// Initialises profiling for the main thread.
	init :: proc(allocator := context.allocator, loc := #caller_location) {
		ensure(!prof._initialised, "prof.init() should only be called once")

		context.allocator = allocator

		prof.bufs = make(map[int]Buffer)

		// Generate timestamped filename
		now_buf: [time.MIN_YYYY_DATE_LEN + time.MIN_HMS_LEN + 1]u8
		now := time.now()
		a := time.to_string_yyyy_mm_dd(now, now_buf[:])
		now_buf[len(a)] = '_'
		_ = time.to_string_hms(now, now_buf[len(a) + 1:])
		now_buf[len(a) + 3] = '-'
		now_buf[len(a) + 6] = '-'
		now_str := cast(string)now_buf[:]

		filename := strings.concatenate({"prof/prof-", now_str, ".spall"}, context.temp_allocator)
		defer delete(filename, context.temp_allocator)

		ok: bool
		prof.ctx, ok = spall.context_create(filename)
		ensure(ok, "could not create profiling context")

		prof._initialised = true
		prof.allocator = allocator

		init_thread(loc = loc)
	}

	// Initialises profiling for threads other than the main thread.
	init_thread :: proc(loc := #caller_location) {
		context.allocator = prof.allocator

		sync.guard(&prof.lock)

		ensure(
			prof._initialised,
			"prof.init_thread() should only be called after prof.init()",
			loc = loc,
		)
		_, exists := prof.bufs[os.current_thread_id()]
		ensure(
			!exists,
			"prof.init_thread() should only be called once per additional thread",
			loc = loc,
		)

		backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)

		buf, ok := spall.buffer_create(backing, u32(os.current_thread_id()))
		ensure(
			ok,
			fmt.tprint("could not create profiling buffer for thread", os.current_thread_id()),
			loc = loc,
		)

		prof.bufs[os.current_thread_id()] = buf
	}

	// Deinitialises profiling for the entire application (including other threads).
	//
	// Should only be called from the main thread.
	deinit :: proc(loc := #caller_location) {
		ensure(prof._initialised, "prof.deinit() should only be called once", loc = loc)

		sync.guard(&prof.lock)

		for _, &buf in prof.bufs {
			data := buf.data
			spall.buffer_destroy(&prof.ctx, &buf)
			delete(data)
		}

		spall.context_destroy(&prof.ctx)

		delete(prof.bufs)

		prof._initialised = false
	}

	// Flushes any pending events to disk.
	//
	// This method is thread-safe.
	flush :: proc(loc := #caller_location) {
		if !prof._initialised {return}
		buf, ok := &prof.bufs[os.current_thread_id()]
		ensure(
			ok,
			"prof.flush() should only be called on a thread after prof.init_thread()",
			loc = loc,
		)
		#force_inline spall.buffer_flush(&prof.ctx, buf)
	}

	// Starts an event with name `name`.
	//
	// This method is thread-safe.
	//
	// **Usage:**
	//
	//	event_begin("event name")
	//	/* ... */
	//	event_end()
	event_begin :: proc(name: string, loc := #caller_location) {
		if !prof._initialised {return}
		buf, ok := &prof.bufs[os.current_thread_id()]
		ensure(
			ok,
			"prof.event_begin() should only be called on a thread after prof.init_thread()",
			loc = loc,
		)
		#force_inline spall._buffer_begin(&prof.ctx, buf, name, location = loc)
	}

	// Ends the latest event to have begun.
	//
	// This method is thread-safe.
	//
	// **Usage:**
	//
	//	event_begin("event name")
	//	/* ... */
	//	event_end()
	event_end :: proc(loc := #caller_location) {
		if !prof._initialised {return}
		buf, ok := &prof.bufs[os.current_thread_id()]
		ensure(
			ok,
			"prof.event_end() should only be called on a thread after prof.init_thread()",
			loc = loc,
		)
		#force_inline spall._buffer_end(&prof.ctx, buf)
	}

	// Starts an event with name `name`, and ends it at the end of the current scope.
	//
	// This procedure always returns `true`, which makes it easy to define a scope
	// for the event by running this procedure inside an `if` statement.
	//
	// This method is thread-safe.
	//
	// **Usage:**
	//
	//	if event("event name") {
	//	/* ... */
	//	} 
	//	 /* Event is automagically ended */
	@(deferred_in = _scoped_event_end)
	event :: proc(name: string, loc := #caller_location) -> bool {
		if !prof._initialised {return true}
		#force_inline event_begin(name, loc = loc)
		return true
	}

	_scoped_event_end :: proc(_: string, loc := #caller_location) {
		#force_inline event_end()
	}

} else {
	init :: proc(allocator := context.allocator, loc := #caller_location) {}
	init_thread :: proc(loc := #caller_location) {}
	deinit :: proc(loc := #caller_location) {}

	flush :: proc(loc := #caller_location) {}
	event_begin :: proc(name: string, loc := #caller_location) {}
	event_end :: proc(loc := #caller_location) {}
	event :: proc(name: string, loc := #caller_location) -> bool {return true}
	_scoped_event_end :: proc(_: bool, loc := #caller_location) {}
}
