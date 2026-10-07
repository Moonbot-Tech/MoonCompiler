/* Native C counterpart of the Windows Pascal fixture. No Pascal runtime or
   TLS pin may hide physical unload/reload in the FreeType loader test. */
#include <stdint.h>
int FT_Init_FreeType(void **library) { *library = (void *)(uintptr_t)73; return 0; }
int FT_Done_FreeType(void *library) { return library != (void *)(uintptr_t)73; }
int FT_New_Face(void *library, const char *path, long index, void **face) {
    (void)path;
    *face = (void *)(uintptr_t)91;
    return library != (void *)(uintptr_t)73 || index != -1;
}
#ifndef MISSING_FREETYPE_EXPORT
int FT_Done_Face(void *face) { return face != (void *)(uintptr_t)91; }
#endif
int FT_Set_Char_Size(void *face, long width, long height, unsigned x, unsigned y) {
    return face != (void *)(uintptr_t)91 || width != -64 || height != -128 || x != 72 || y != 96;
}
#define UNUSED_ENTRY(name) void name(void) {}
UNUSED_ENTRY(FT_Get_Char_Index)
UNUSED_ENTRY(FT_Get_Kerning)
UNUSED_ENTRY(FT_Load_Char)
UNUSED_ENTRY(FT_Load_Glyph)
UNUSED_ENTRY(FT_Set_Pixel_Sizes)
UNUSED_ENTRY(FT_Set_Transform)
UNUSED_ENTRY(FT_Get_Sfnt_Name_Count)
UNUSED_ENTRY(FT_Get_Sfnt_Name)
UNUSED_ENTRY(FT_Get_Sfnt_Table)
UNUSED_ENTRY(FT_Outline_Decompose)
UNUSED_ENTRY(FT_Library_Version)
UNUSED_ENTRY(FT_Get_Glyph)
UNUSED_ENTRY(FT_Glyph_Copy)
UNUSED_ENTRY(FT_Glyph_To_Bitmap)
UNUSED_ENTRY(FT_Glyph_Transform)
UNUSED_ENTRY(FT_Done_Glyph)
#ifndef MISSING_FREETYPE_TAIL
UNUSED_ENTRY(FT_Glyph_Get_CBox)
#endif
