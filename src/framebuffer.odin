package mou

import "core:log"
import gl "vendor:OpenGL"

Framebuffer_Target :: enum u32 {
	Draw = gl.DRAW_FRAMEBUFFER,
	Read = gl.READ_FRAMEBUFFER,
	All  = gl.FRAMEBUFFER,
}

Attachment_Type :: enum u32 {
	Colour0 = gl.COLOR_ATTACHMENT0,
	Colour1 = gl.COLOR_ATTACHMENT1,
	Colour2 = gl.COLOR_ATTACHMENT2,
	Colour3 = gl.COLOR_ATTACHMENT3, // We can go to 31 if need be
	Depth   = gl.DEPTH_ATTACHMENT, // There's also stencil/depth+stencil
}

Framebuffer_Attachment :: struct {
	type: Attachment_Type,
	tex:  ^Texture,
}

Framebuffer :: struct {
	handle:      u32,
	attachments: [dynamic; len(Attachment_Type)]Framebuffer_Attachment,
}

make_framebuffer :: proc(
	attachments: []Framebuffer_Attachment,
	loc := #caller_location,
) -> (
	fbo: Framebuffer,
) {
	when ODIN_DEBUG {
		gl.CreateFramebuffers(1, &fbo.handle, loc = loc)
	} else {
		gl.CreateFramebuffers(1, &fbo.handle)
	}
	if len(attachments) == 0 {return}

	assert(
		len(attachments) <= len(Attachment_Type),
		"more attachments than should be possible, what are you doing?",
		loc = loc,
	)

	used_attachments := make(
		map[Attachment_Type]struct{
			// kinda hacky hashset
		},
		len(Attachment_Type),
		context.temp_allocator,
	)

	for a in attachments {
		if _, used := used_attachments[a.type]; used {
			log.warnf(
				"Duplicate framebuffer attachment {}, only the first one will be used",
				a.type,
				location = loc,
			)
		} else {
			append(&fbo.attachments, a)
			used_attachments[a.type] = {}
		}
	}

	colour_attachments: [len(Attachment_Type)]u32
	colour_attachment_count := 0
	for a in fbo.attachments {
		when ODIN_DEBUG {
			gl.NamedFramebufferTexture(fbo.handle, cast(u32)a.type, a.tex.handle, 0, loc = loc)
		} else {
			gl.NamedFramebufferTexture(fbo.handle, cast(u32)a.type, a.tex.handle, 0)
		}

		if a.type >= .Colour0 && a.type <= .Colour3 {
			colour_attachments[colour_attachment_count] = cast(u32)a.type
			colour_attachment_count += 1
		}
	}

	if colour_attachment_count == 0 {
		when ODIN_DEBUG {
			gl.NamedFramebufferDrawBuffer(fbo.handle, gl.NONE, loc = loc)
			gl.NamedFramebufferReadBuffer(fbo.handle, gl.NONE, loc = loc)
		} else {
			gl.NamedFramebufferDrawBuffer(fbo.handle, gl.NONE)
			gl.NamedFramebufferReadBuffer(fbo.handle, gl.NONE)
		}
	} else if colour_attachment_count == 1 {
		when ODIN_DEBUG {
			gl.NamedFramebufferDrawBuffer(fbo.handle, colour_attachments[0], loc = loc)
			gl.NamedFramebufferReadBuffer(fbo.handle, colour_attachments[0], loc = loc)
		} else {
			gl.NamedFramebufferDrawBuffer(fbo.handle, colour_attachments[0])
			gl.NamedFramebufferReadBuffer(fbo.handle, colour_attachments[0])
		}
	} else {
		when ODIN_DEBUG {
			gl.NamedFramebufferDrawBuffers(
				fbo.handle,
				cast(i32)colour_attachment_count,
				raw_data(colour_attachments[:]),
				loc = loc,
			)
		} else {
			gl.NamedFramebufferDrawBuffers(
				fbo.handle,
				cast(i32)colour_attachment_count,
				raw_data(colour_attachments[:]),
			)
		}
	}

	if gl.CheckNamedFramebufferStatus(fbo.handle, cast(u32)Framebuffer_Target.All) !=
	   gl.FRAMEBUFFER_COMPLETE {
		log.panic("Framebuffer did not complete", location = loc)
	}

	return
}

destroy_framebuffer :: proc(fbo: ^Framebuffer, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.DeleteFramebuffers(1, &fbo.handle, loc = loc)
	} else {
		gl.DeleteFramebuffers(1, &fbo.handle)
	}
	fbo^ = {}
}

bind_framebuffer :: proc(fbo: Framebuffer, target: Framebuffer_Target, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindFramebuffer(cast(u32)target, fbo.handle, loc = loc)
	} else {
		gl.BindFramebuffer(cast(u32)target, fbo.handle)
	}
}

unbind_framebuffer :: proc(target: Framebuffer_Target, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.BindFramebuffer(cast(u32)target, 0, loc = loc)
	} else {
		gl.BindFramebuffer(cast(u32)target, 0)
	}
}

resize_framebuffer :: proc(fbo: ^Framebuffer, width, height: i32, loc := #caller_location) {
	for a in fbo.attachments {
		new_tex := make_texture(
			a.tex.name,
			width,
			height,
			a.tex.format,
			a.tex.wrap,
			a.tex.min_filter,
			a.tex.mag_filter,
			a.tex.levels,
		)

		when ODIN_DEBUG {
			gl.NamedFramebufferTexture(fbo.handle, cast(u32)a.type, new_tex.handle, 0, loc = loc)
		} else {
			gl.NamedFramebufferTexture(fbo.handle, cast(u32)a.type, new_tex.handle, 0)
		}

		if gl.CheckNamedFramebufferStatus(fbo.handle, cast(u32)Framebuffer_Target.All) !=
		   gl.FRAMEBUFFER_COMPLETE {
			log.panic("Framebuffer resize did not complete")
		}

		// NOTE: this'll replace the initial textures, which will be cleaned up in main
		destroy_texture(a.tex)
		a.tex^ = new_tex
	}
}
