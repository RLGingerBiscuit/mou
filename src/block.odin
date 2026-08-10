package mou

import glm "core:math/linalg/glsl"

TRANSPARENT_LEAVES :: true

Block_Face :: enum {
	Neg_X,
	Pos_X,
	Neg_Y,
	Pos_Y,
	Neg_Z,
	Pos_Z,
}
Block_Face_Mask :: bit_set[Block_Face]

Block_Diag :: enum {
	NNN,
	NNZ,
	NNP,
	NZN,
	NZP,
	NPN,
	NPZ,
	NPP,
	ZNN,
	ZNP,
	ZPN,
	ZPP,
	PNN,
	PNZ,
	PNP,
	PZN,
	PZP,
	PPN,
	PPZ,
	PPP,
}
Block_Diag_Mask :: bit_set[Block_Diag]

Block_ID :: enum u8 {
	Air,
	Stone,
	Dirt,
	Grass,
	Water,
	Glass,
	Log,
	Leaves,
	Planks,
}

Block :: struct {
	id: Block_ID,
}

block_is_opaque :: proc(block: Block) -> bool {
	switch block.id {
	case .Air, .Glass, .Water:
		return false
	case .Stone, .Grass, .Dirt, .Log, .Planks:
		return true
	case .Leaves:
		return !TRANSPARENT_LEAVES
	}
	unreachable()
}

block_culls_self :: proc(block: Block) -> bool {
	switch block.id {
	case .Air:
		return false
	case .Stone, .Grass, .Dirt, .Glass, .Water, .Log, .Leaves, .Planks:
		return true
	case:
		unreachable()
	}
}

// Every block texture gets its own layer in the block texture array, so the enum value *is* the layer index.
Block_Texture :: enum u32 {
	Dirt,
	Glass,
	Grass_Side,
	Grass_Top,
	Leaves,
	Leaves_Transparent,
	Log_Side,
	Log_Top,
	Planks,
	Stone,
	Water,
}

// odinfmt:disable
@(rodata)
BLOCK_TEXTURE_ASSET_NAMES := [Block_Texture]string {
	.Dirt               = "dirt.png",
	.Glass              = "glass.png",
	.Grass_Side         = "grass_side.png",
	.Grass_Top          = "grass_top.png",
	.Leaves             = "leaves.png",
	.Leaves_Transparent = "leaves_transparent.png",
	.Log_Side           = "log_side.png",
	.Log_Top            = "log_top.png",
	.Planks             = "planks.png",
	.Stone              = "stone.png",
	.Water              = "water.png",
}
// odinfmt:enable

block_texture :: proc(block: Block, face: Block_Face) -> Block_Texture {
	switch block.id {
	case .Stone:
		return .Stone

	case .Grass:
		#partial switch face {
		case .Neg_Y:
			return .Dirt
		case .Pos_Y:
			return .Grass_Top
		case:
			return .Grass_Side
		}

	case .Dirt:
		return .Dirt

	case .Glass:
		return .Glass

	case .Water:
		return .Water

	case .Log:
		return face == .Pos_Y ? .Log_Top : .Log_Side

	case .Leaves:
		return TRANSPARENT_LEAVES ? .Leaves_Transparent : .Leaves

	case .Planks:
		return .Planks

	case .Air:
		fallthrough

	case:
		unreachable()
	}
}

block_pos_centre :: proc(block_pos: Block_Pos) -> glm.vec3 {
	return block_pos_to_world_pos(block_pos) + 0.5
}
