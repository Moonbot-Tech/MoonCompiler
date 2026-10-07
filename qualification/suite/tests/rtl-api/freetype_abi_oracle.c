/* FreeType's public C headers independently validate the Pascal ABI witnesses. */
#include <stddef.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include <stdio.h>

_Static_assert(sizeof(FT_Long) == 8, "Linux LP64 long");
_Static_assert(sizeof(FT_F26Dot6) == 8, "26.6 value is a C long");
_Static_assert(sizeof(FT_Bitmap) == 40, "bitmap size");
_Static_assert(offsetof(FT_Bitmap, pixel_mode) == 26, "bitmap pixel_mode");
_Static_assert(sizeof(FT_Bitmap_Size) == 32, "bitmap strike size");
_Static_assert(FT_ENCODING_UNICODE == 0x756E6963, "numeric encoding tag");
_Static_assert(sizeof(((FT_GlyphSlot)0)->control_len) == 8, "control data length");
_Static_assert(offsetof(FT_GlyphSlotRec, other) == 288, "glyph slot trailing fields");
_Static_assert(sizeof(FT_GlyphSlotRec) == 304, "complete glyph slot");
int main(void) {
    puts("FREETYPE_C_ABI_OK");
    return 0;
}
