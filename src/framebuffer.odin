package mou

import sa "core:container/small_array"
import "core:log"
import "core:os"
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
	attachments: sa.Small_Array(len(Attachment_Type), Framebuffer_Attachment),
}

make_framebuffer :: proc(
	attachments: []Framebuffer_Attachment,
	loc := #caller_location,
) -> (
	fbo: Framebuffer,
) {
	when ODIN_DEBUG {
		gl.GenFramebuffers(1, &fbo.handle, loc = loc)
	} else {
		gl.GenFramebuffers(1, &fbo.handle)
	}
	if len(attachments) == 0 {return}

	bind_framebuffer(fbo, .All)
	defer unbind_framebuffer(.All)

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
			assert(sa.append(&fbo.attachments, a))
			used_attachments[a.type] = {}
		}
	}

	for a in sa.slice(&fbo.attachments) {
		when ODIN_DEBUG {
			gl.FramebufferTexture2D(
				cast(u32)Framebuffer_Target.All,
				cast(u32)a.type,
				gl.TEXTURE_2D,
				a.tex.handle,
				0,
				loc = loc,
			)
		} else {
			gl.FramebufferTexture2D(
				cast(u32)Framebuffer_Target.All,
				cast(u32)a.type,
				gl.TEXTURE_2D,
				a.tex.handle,
				0,
			)
		}
	}

	if gl.CheckFramebufferStatus(cast(u32)Framebuffer_Target.All) != gl.FRAMEBUFFER_COMPLETE {
		log.fatal("Framebuffer did not complete", location = loc)
		os.exit(1)
	}

	return
}

destroy_framebuffer :: proc(fbo: ^Framebuffer, loc := #caller_location) {
	when ODIN_DEBUG {
		gl.DeleteFramebuffers(1, &fbo.handle, loc = loc)
	} else {
		gl.DeleteFramebuffers(1, &fbo.handle)
	}
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
	for a in sa.slice(&fbo.attachments) {
		new_tex := make_texture(
			a.tex.name,
			width,
			height,
			a.tex.format,
			a.tex.wrap,
			a.tex.min_filter,
			a.tex.mag_filter,
			a.tex.mipmap,
		)

		bind_framebuffer(fbo^, .All)
		defer unbind_framebuffer(.All)

		when ODIN_DEBUG {
			gl.FramebufferTexture2D(
				cast(u32)Framebuffer_Target.All,
				cast(u32)a.type,
				gl.TEXTURE_2D,
				new_tex.handle,
				0,
				loc = loc,
			)
		} else {
			gl.FramebufferTexture2D(
				cast(u32)Framebuffer_Target.All,
				cast(u32)a.type,
				gl.TEXTURE_2D,
				new_tex.handle,
				0,
			)
		}

		if gl.CheckFramebufferStatus(cast(u32)Framebuffer_Target.All) != gl.FRAMEBUFFER_COMPLETE {
			log.fatal("Framebuffer resize did not complete")
			os.exit(1)
		}

		// NOTE: this'll replace the initial textures, which will be cleaned up in main
		destroy_texture(a.tex)
		a.tex^ = new_tex
	}
}
