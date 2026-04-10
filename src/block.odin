package mou

import glm "core:math/linalg/glsl"

TRANSPARENT_LEAVES :: false

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

block_asset_name :: proc(block: Block, face: Block_Face) -> string {
	switch block.id {
	case .Stone:
		return "stone.png"

	case .Grass:
		#partial switch face {
		case .Neg_Y:
			return "dirt.png"
		case .Pos_Y:
			return "grass_top.png"
		case:
			return "grass_side.png"
		}

	case .Dirt:
		return "dirt.png"

	case .Glass:
		return "glass.png"

	case .Water:
		return "water.png"

	case .Log:
		return face == .Pos_Y ? "log_top.png" : "log_side.png"

	case .Leaves:
		return TRANSPARENT_LEAVES ? "leaves_transparent.png" : "leaves.png"

	case .Planks:
		return "planks.png"

	case .Air:
		fallthrough

	case:
		unreachable()
	}
}

block_pos_centre :: proc(block_pos: Block_Pos) -> glm.vec3 {
	return block_pos_to_world_pos(block_pos) + 0.5
}
