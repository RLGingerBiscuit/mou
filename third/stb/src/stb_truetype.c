#define STB_TRUETYPE_IMPLEMENTATION
// NOTE: The reason this is included here is to ensure that
// the correct struct layouts are used, although
// this also means that stbrp also needs to be linked to.
// Which is why this has been split from Odin's vendor libs.
#include "stb_rect_pack.h"
#include "stb_truetype.h"
