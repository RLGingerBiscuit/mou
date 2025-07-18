package mou

import "base:intrinsics"
import "core:log"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"

GL_MAJOR :: 3
GL_MINOR :: 3
GLFW_PROFILE :: glfw.OPENGL_CORE_PROFILE

Window :: struct {
	handle:       glfw.WindowHandle,
	title:        string,
	size:         [2]i32,
	flags:        bit_set[enum u8 {
		Visible,
		UI,
		Minimised,
	};u8],
	// Input
	cursor:       [2]f64,
	prev_cursor:  [2]f64,
	scroll:       [2]f64,
	prev_scroll:  [2]f64,
	buttons:      [i32(Mouse_Button.Last)]Action,
	prev_buttons: [i32(Mouse_Button.Last)]Action,
	keys:         [i32(Key.Last)]Action,
	prev_keys:    [i32(Key.Last)]Action,
}

init_window :: proc(
	state: ^State,
	title: string,
	size: [2]i32,
	vsync := true,
	visible: bool = true,
) -> (
	ok: bool,
) {
	WINDOW := &state.window

	log.debug("Creating GLFW window")

	WINDOW.title = title
	title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
	defer delete(title_cstr, context.temp_allocator)

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, GLFW_PROFILE)
	glfw.WindowHint(glfw.VISIBLE, b32(visible))
	when ODIN_OS == .Darwin {
		glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)
	}

	WINDOW.handle = glfw.CreateWindow(size.x, size.y, title_cstr, nil, nil)
	if WINDOW.handle == nil {
		desc, code := glfw.GetError()
		log.fatalf("Error creating GLFW window ({}): {}", code, desc)
		return
	}

	glfw.MakeContextCurrent(WINDOW.handle)
	if vsync {
		glfw.SwapInterval(1)
	} else {
		glfw.SwapInterval(0)
	}

	gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)

	WINDOW.flags = visible ? {.Visible} : {}
	resize_window(state, size.x, size.y)

	glfw.SetWindowUserPointer(WINDOW.handle, state)
	glfw.SetFramebufferSizeCallback(WINDOW.handle, _window_framebuffer_size_callback)
	glfw.SetCursorPosCallback(WINDOW.handle, _window_cursor_pos_callback)
	glfw.SetKeyCallback(WINDOW.handle, _window_key_callback)
	glfw.SetMouseButtonCallback(WINDOW.handle, _window_mouse_button_callback)
	glfw.SetScrollCallback(WINDOW.handle, _window_scroll_callback)

	ok = true
	return
}

destroy_window :: proc(wnd: ^Window) {
	log.debug("Destroying GLFW window")
	glfw.DestroyWindow(wnd.handle)
}

window_aspect_ratio :: proc(wnd: Window) -> f32 {
	return cast(f32)wnd.size.x / cast(f32)wnd.size.y
}

update_window :: proc(wnd: ^Window) {
	if window_get_key(wnd^, .Tab) == .Press && window_get_prev_key(wnd^, .Tab) != .Press {
		wnd.flags ~= {.UI}
		if .UI in wnd.flags {
			log.debug("Opening UI")
			glfw.SetInputMode(wnd.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
		} else {
			log.debug("Closing UI")
			glfw.SetInputMode(wnd.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
		}
		window_center_cursor(wnd)
	}

	wnd.prev_cursor = wnd.cursor
	wnd.prev_scroll = wnd.scroll
	wnd.prev_keys = wnd.keys
	wnd.prev_buttons = wnd.buttons

	wnd.scroll = {}
}

window_should_close :: proc(wnd: Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(wnd.handle)
}

set_window_should_close :: proc(wnd: Window, close: bool) {
	glfw.SetWindowShouldClose(wnd.handle, b32(close))
}

window_swap_buffers :: proc(wnd: Window) {
	glfw.SwapBuffers(wnd.handle)
}

window_center_cursor :: proc(wnd: ^Window) {
	centre := [2]f64{cast(f64)wnd.size.x / 2, cast(f64)wnd.size.y / 2}
	glfw.SetCursorPos(wnd.handle, centre.x, centre.y)
	wnd.cursor = centre
}

resize_window :: proc(state: ^State, width, height: i32) {
	wnd := &state.window
	if width == 0 || height == 0 {
		wnd.flags |= {.Minimised}
		return
	}
	wnd.flags &~= {.Minimised}
	assert(width > 0, "window width must be > 0")
	assert(height > 0, "window height must be > 0")
	wnd.size = {width, height}
	gl.Viewport(0, 0, width, height)
	log.debugf("Window '{}' resized to {}x{}", wnd.title, width, height)
	resize_framebuffer(&state.fbo, width, height)
}

show_window :: proc(wnd: ^Window) {
	wnd.flags |= {.Visible}
	glfw.ShowWindow(wnd.handle)
	gl.Viewport(0, 0, wnd.size.x, wnd.size.y)
}
hide_window :: proc(wnd: ^Window) {
	wnd.flags &~= {.Visible}
	glfw.HideWindow(wnd.handle)
}

window_get_key :: proc(wnd: Window, key: Key) -> Action {
	return wnd.keys[key]
}
window_get_prev_key :: proc(wnd: Window, key: Key) -> Action {
	return wnd.prev_keys[key]
}

window_get_button :: proc(wnd: Window, button: Mouse_Button) -> Action {
	return wnd.buttons[button]
}
window_get_prev_button :: proc(wnd: Window, button: Mouse_Button) -> Action {
	return wnd.prev_buttons[button]
}

_window_cursor_pos_callback :: proc "c" (handle: glfw.WindowHandle, x, y: f64) {
	ptr := glfw.GetWindowUserPointer(handle)
	state := cast(^State)ptr
	wnd := &state.window
	wnd.cursor = {x, y}
}

_window_framebuffer_size_callback :: proc "c" (handle: glfw.WindowHandle, width, height: i32) {
	context = default_context()
	ptr := glfw.GetWindowUserPointer(handle)
	state := cast(^State)ptr
	resize_window(state, width, height)
}

_window_key_callback :: proc "c" (
	handle: glfw.WindowHandle,
	ikey, _scancode, iaction, _mods: i32,
) {
	if ikey == -1 {return}
	ptr := glfw.GetWindowUserPointer(handle)
	state := cast(^State)ptr
	wnd := &state.window
	key := cast(Key)ikey
	action := cast(Action)iaction
	if action == .Repeat {action = .Press}
	wnd.keys[key] = action
}

_window_mouse_button_callback :: proc "c" (
	handle: glfw.WindowHandle,
	ibutton, iaction, _mods: i32,
) {
	ptr := glfw.GetWindowUserPointer(handle)
	state := cast(^State)ptr
	wnd := &state.window
	button := cast(Mouse_Button)ibutton
	action := cast(Action)iaction
	wnd.buttons[button] = action
}

_window_scroll_callback :: proc "c" (handle: glfw.WindowHandle, xoffset, yoffset: f64) {
	ptr := glfw.GetWindowUserPointer(handle)
	state := cast(^State)ptr
	wnd := &state.window
	wnd.scroll = {xoffset, yoffset}
}

Action :: enum u8 {
	Release = 0,
	Press   = 1,
	Repeat  = 2,
}
Key :: enum i32 {
	/* The unknown key */
	Unknown       = glfw.KEY_UNKNOWN,

	/** Printable keys **/

	/* Named printable keys */
	Space         = glfw.KEY_SPACE,
	Apostrophe    = glfw.KEY_APOSTROPHE, /* ' */
	Comma         = glfw.KEY_COMMA, /* , */
	Minus         = glfw.KEY_MINUS, /* - */
	Period        = glfw.KEY_PERIOD, /* . */
	Slash         = glfw.KEY_SLASH, /* / */
	Semicolon     = glfw.KEY_SEMICOLON, /* ; */
	Equal         = glfw.KEY_EQUAL, /*  */
	Left_Bracket  = glfw.KEY_LEFT_BRACKET, /* [ */
	Backslash     = glfw.KEY_BACKSLASH, /* \ */
	Right_Bracket = glfw.KEY_RIGHT_BRACKET, /* ] */
	Grave_Accent  = glfw.KEY_GRAVE_ACCENT, /* ` */
	World_1       = glfw.KEY_WORLD_1, /* non-US #1 */
	World_2       = glfw.KEY_WORLD_2, /* non-US #2 */

	/* Alphanumeric characters */
	D0            = glfw.KEY_0,
	D1            = glfw.KEY_1,
	D2            = glfw.KEY_2,
	D3            = glfw.KEY_3,
	D4            = glfw.KEY_4,
	D5            = glfw.KEY_5,
	D6            = glfw.KEY_6,
	D7            = glfw.KEY_7,
	D8            = glfw.KEY_8,
	D9            = glfw.KEY_9,
	A             = glfw.KEY_A,
	B             = glfw.KEY_B,
	C             = glfw.KEY_C,
	D             = glfw.KEY_D,
	E             = glfw.KEY_E,
	F             = glfw.KEY_F,
	G             = glfw.KEY_G,
	H             = glfw.KEY_H,
	I             = glfw.KEY_I,
	J             = glfw.KEY_J,
	K             = glfw.KEY_K,
	L             = glfw.KEY_L,
	M             = glfw.KEY_M,
	N             = glfw.KEY_N,
	O             = glfw.KEY_O,
	P             = glfw.KEY_P,
	Q             = glfw.KEY_Q,
	R             = glfw.KEY_R,
	S             = glfw.KEY_S,
	T             = glfw.KEY_T,
	U             = glfw.KEY_U,
	V             = glfw.KEY_V,
	W             = glfw.KEY_W,
	X             = glfw.KEY_X,
	Y             = glfw.KEY_Y,
	Z             = glfw.KEY_Z,


	/** Function keys **/

	/* Named non-printable keys */
	Escape        = glfw.KEY_ESCAPE,
	Enter         = glfw.KEY_ENTER,
	Tab           = glfw.KEY_TAB,
	Backspace     = glfw.KEY_BACKSPACE,
	Insert        = glfw.KEY_INSERT,
	Delete        = glfw.KEY_DELETE,
	Right         = glfw.KEY_RIGHT,
	Left          = glfw.KEY_LEFT,
	Down          = glfw.KEY_DOWN,
	Up            = glfw.KEY_UP,
	Page_Up       = glfw.KEY_PAGE_UP,
	Page_Down     = glfw.KEY_PAGE_DOWN,
	Home          = glfw.KEY_HOME,
	End           = glfw.KEY_END,
	Caps_Lock     = glfw.KEY_CAPS_LOCK,
	Scroll_Lock   = glfw.KEY_SCROLL_LOCK,
	Num_Lock      = glfw.KEY_NUM_LOCK,
	Print_Screen  = glfw.KEY_PRINT_SCREEN,
	Pause         = glfw.KEY_PAUSE,

	/* Function keys */
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10           = glfw.KEY_F10,
	F11           = glfw.KEY_F11,
	F12           = glfw.KEY_F12,
	F13           = glfw.KEY_F13,
	F14           = glfw.KEY_F14,
	F15           = glfw.KEY_F15,
	F16           = glfw.KEY_F16,
	F17           = glfw.KEY_F17,
	F18           = glfw.KEY_F18,
	F19           = glfw.KEY_F19,
	F20           = glfw.KEY_F20,
	F21           = glfw.KEY_F21,
	F22           = glfw.KEY_F22,
	F23           = glfw.KEY_F23,
	F24           = glfw.KEY_F24,
	F25           = glfw.KEY_F25,

	/* Keypad numbers */
	KP_0          = glfw.KEY_KP_0,
	KP_1          = glfw.KEY_KP_1,
	KP_2          = glfw.KEY_KP_2,
	KP_3          = glfw.KEY_KP_3,
	KP_4          = glfw.KEY_KP_4,
	KP_5          = glfw.KEY_KP_5,
	KP_6          = glfw.KEY_KP_6,
	KP_7          = glfw.KEY_KP_7,
	KP_8          = glfw.KEY_KP_8,
	KP_9          = glfw.KEY_KP_9,

	/* Keypad named function keys */
	KP_Decimal    = glfw.KEY_KP_DECIMAL,
	KP_Divide     = glfw.KEY_KP_DIVIDE,
	KP_Multiply   = glfw.KEY_KP_MULTIPLY,
	KP_Subtract   = glfw.KEY_KP_SUBTRACT,
	KP_Add        = glfw.KEY_KP_ADD,
	KP_Enter      = glfw.KEY_KP_ENTER,
	KP_Equal      = glfw.KEY_KP_EQUAL,

	/* Modifier keys */
	Left_Shift    = glfw.KEY_LEFT_SHIFT,
	Left_Control  = glfw.KEY_LEFT_CONTROL,
	Left_Alt      = glfw.KEY_LEFT_ALT,
	Left_Super    = glfw.KEY_LEFT_SUPER,
	Right_Shift   = glfw.KEY_RIGHT_SHIFT,
	Right_Control = glfw.KEY_RIGHT_CONTROL,
	Right_Alt     = glfw.KEY_RIGHT_ALT,
	Right_Super   = glfw.KEY_RIGHT_SUPER,
	Menu          = glfw.KEY_MENU,
	Last          = glfw.KEY_LAST,
}

Mouse_Button :: enum i32 {
	Left   = glfw.MOUSE_BUTTON_LEFT,
	Middle = glfw.MOUSE_BUTTON_MIDDLE,
	Right  = glfw.MOUSE_BUTTON_RIGHT,
	Last   = glfw.MOUSE_BUTTON_LAST,
}
