library moon_freetype_fixture;
{$mode delphi}
{ Independent loader fixture: deliberately does not import the binding under test. }
type
{$IFDEF WIN64}
  CLong = LongInt;
{$ELSE}
  CLong = Int64;
{$ENDIF}
function FT_Init_FreeType(var Lib: Pointer): Integer; cdecl;
begin
  Lib:=Pointer(73);
  Result:=0;
end;
function FT_Done_FreeType(Lib: Pointer): Integer; cdecl;
begin
  Result:=Ord(Lib<>Pointer(73));
end;
function FT_New_Face(Lib: Pointer; Path: PAnsiChar; Index: CLong; var Face: Pointer): Integer; cdecl;
begin
  Result:=Ord((Lib<>Pointer(73)) or (Index<>-1));
  Face:=Pointer(91);
end;
function FT_Done_Face(Face: Pointer): Integer; cdecl;
begin
  Result:=Ord(Face<>Pointer(91));
end;
function FT_Set_Char_Size(Face: Pointer; Width, Height: CLong; X, Y: Cardinal): Integer; cdecl;
begin
  Result:=Ord((Face<>Pointer(91)) or (Width<>-64) or (Height<>-128) or (X<>72) or (Y<>96));
end;
procedure Unused; cdecl;
begin
end;
exports
  FT_Init_FreeType, FT_Done_FreeType, FT_New_Face, FT_Set_Char_Size,
{$IFNDEF MISSING_FREETYPE_EXPORT}
  FT_Done_Face,
{$ENDIF}
  Unused name 'FT_Get_Char_Index', Unused name 'FT_Get_Kerning',
  Unused name 'FT_Load_Char', Unused name 'FT_Load_Glyph',
  Unused name 'FT_Set_Pixel_Sizes', Unused name 'FT_Set_Transform',
  Unused name 'FT_Get_Sfnt_Name_Count', Unused name 'FT_Get_Sfnt_Name',
  Unused name 'FT_Get_Sfnt_Table', Unused name 'FT_Outline_Decompose',
  Unused name 'FT_Library_Version', Unused name 'FT_Get_Glyph',
  Unused name 'FT_Glyph_Copy', Unused name 'FT_Glyph_To_Bitmap',
  Unused name 'FT_Glyph_Transform', Unused name 'FT_Done_Glyph'
{$IFNDEF MISSING_FREETYPE_TAIL}
  , Unused name 'FT_Glyph_Get_CBox'
{$ENDIF}
  ;
begin
end.
