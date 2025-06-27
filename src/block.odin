package mou

Block_Face_Bit :: enum u8 {
	Neg_X,
	Pos_X,
	Neg_Y,
	Pos_Y,
	Neg_Z,
	Pos_Z,
}
Block_Face_Mask :: bit_set[Block_Face_Bit;u8]

Block_ID :: enum u8 {
	Air,
	Stone,
	Grass,
	Dirt,
	Glass,
	Water,
}

Block :: struct {
	id: Block_ID,
}

block_is_opaque :: proc(block: Block) -> bool {
	switch block.id {
	case .Air, .Glass, .Water:
		return false
	case .Stone, .Grass, .Dirt:
		return true
	}
	unreachable()
}

block_culls_self :: proc(block: Block) -> bool {
	switch block.id {
	case .Air:
		return false
	case .Stone, .Grass, .Dirt, .Glass, .Water:
		return true
	case:
		unreachable()
	}
}

block_asset_name :: proc(block: Block, face: Block_Face_Bit) -> string {
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

	// TODO: animated water somehow
	case .Water:
		#partial switch face {
		case .Neg_Y:
			return "water_still.png"
		case .Pos_Y:
			return "water_still.png"
		case:
			return "water_flow.png"
		}

	case .Air:
		fallthrough

	case:
		unreachable()
	}
}
