program rtl_api_freetype_contracts;
{$mode delphiunicode}
uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
  SysUtils, Classes, Dynlibs, freetypehdyn;

procedure Check(Value: Boolean; const Msg: string);
begin
  If not Value then
    raise Exception.Create(Msg);
end;

procedure CheckAddresses(Loaded: Boolean);
begin
  Check(Assigned(FT_Done_Face)=Loaded,'FT_Done_Face lifecycle');
  Check(Assigned(FT_Done_FreeType)=Loaded,'FT_Done_FreeType lifecycle');
  Check(Assigned(FT_Get_Char_Index)=Loaded,'FT_Get_Char_Index lifecycle');
  Check(Assigned(FT_Get_Kerning)=Loaded,'FT_Get_Kerning lifecycle');
  Check(Assigned(FT_Init_FreeType)=Loaded,'FT_Init_FreeType lifecycle');
  Check(Assigned(FT_Load_Char)=Loaded,'FT_Load_Char lifecycle');
  Check(Assigned(FT_Load_Glyph)=Loaded,'FT_Load_Glyph lifecycle');
  Check(Assigned(FT_New_Face)=Loaded,'FT_New_Face lifecycle');
  Check(Assigned(FT_Set_Char_Size)=Loaded,'FT_Set_Char_Size lifecycle');
  Check(Assigned(FT_Set_Pixel_Sizes)=Loaded,'FT_Set_Pixel_Sizes lifecycle');
  Check(Assigned(FT_Set_Transform)=Loaded,'FT_Set_Transform lifecycle');
  Check(Assigned(FT_Get_Sfnt_Name_Count)=Loaded,'FT_Get_Sfnt_Name_Count lifecycle');
  Check(Assigned(FT_Get_Sfnt_Name)=Loaded,'FT_Get_Sfnt_Name lifecycle');
  Check(Assigned(FT_Get_Sfnt_Table)=Loaded,'FT_Get_Sfnt_Table lifecycle');
  Check(Assigned(FT_Outline_Decompose)=Loaded,'FT_Outline_Decompose lifecycle');
  Check(Assigned(FT_Library_Version)=Loaded,'FT_Library_Version lifecycle');
  Check(Assigned(FT_Get_Glyph)=Loaded,'FT_Get_Glyph lifecycle');
  Check(Assigned(FT_Glyph_Copy)=Loaded,'FT_Glyph_Copy lifecycle');
  Check(Assigned(FT_Glyph_To_Bitmap)=Loaded,'FT_Glyph_To_Bitmap lifecycle');
  Check(Assigned(FT_Glyph_Transform)=Loaded,'FT_Glyph_Transform lifecycle');
  Check(Assigned(FT_Done_Glyph)=Loaded,'FT_Done_Glyph lifecycle');
  Check(Assigned(FT_Glyph_Get_CBox)=Loaded,'FT_Glyph_Get_CBox lifecycle');
end;

{$IFDEF LINUX}
function LineCallback(const Point: PFT_Vector; Context: Pointer): Integer; cdecl;
begin
  Inc(PInteger(Context)^);
  Result:=0;
end;
function ConicCallback(const Control, Point: PFT_Vector; Context: Pointer): Integer; cdecl;
begin
  Inc(PInteger(Context)^);
  Result:=0;
end;
function CubicCallback(const First, Second, Point: PFT_Vector; Context: Pointer): Integer; cdecl;
begin
  Inc(PInteger(Context)^);
  Result:=0;
end;
{$ENDIF}

type
  TLoaderThread = class(TThread)
    Path: string;
    Passed: Boolean;
    procedure Execute; override;
  end;

procedure TLoaderThread.Execute;
var
  I: Integer;
  Lib: PFT_Library;
begin
  try
    for I:=1 to 30 do
      begin
      Check(InitializeFreetype(Path)>0,'concurrent initialize');
      try
        CheckAddresses(True);
        Check(FT_Init_FreeType(Lib)=0,'concurrent call after publication');
        Check(FT_Done_FreeType(Lib)=0,'concurrent done');
      finally
        ReleaseFreetype;
      end;
      end;
    Passed:=True;
  except
    Passed:=False;
  end;
end;

var
  Good, Incomplete, MissingTail: string;
  Lib: PFT_Library;
  Face: PFT_Face;
  Bitmap: FT_Bitmap;
  Slot: TFT_GlyphSlot;
  Threads: array[0..7] of TLoaderThread;
  I: Integer;
{$IFDEF LINUX}
  OutlineFuncs: FT_Outline_Funcs;
  Segments: Integer;
{$ENDIF}
begin
  Good:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'moon-freetype-good.'+SharedSuffix;
  Incomplete:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'moon-freetype-incomplete.'+SharedSuffix;
  MissingTail:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'moon-freetype-tail.'+SharedSuffix;
  CheckAddresses(False);
  Check(TryInitializeFreetype(Good+'.missing')=0,'missing library');
  CheckAddresses(False);
  Check(TryInitializeFreetype(Incomplete)=0,'incomplete library rejected');
  CheckAddresses(False);
  Check(TryInitializeFreetype(MissingTail)=0,'late missing export rejected');
  CheckAddresses(False);
  ReleaseFreetype;
  for I:=1 to 2 do
    begin
    Check(InitializeFreetype(Good)=1,'load/reload');
    CheckAddresses(True);
    Check(InitializeFreetype(Good)=2,'second owner');
    Check(TryInitializeFreetype(Incomplete)=0,'cannot switch live library');
    ReleaseFreetype;
    CheckAddresses(True);
    Check(FT_Init_FreeType(Lib)=0,'create library');
    Check(FT_New_Face(Lib,'fixture',-1,Face)=0,'signed C long face index');
    Check(FT_Set_Char_Size(Face,-64,-128,72,96)=0,'signed C long char sizes');
    Check(FT_Done_Face(Face)=0,'destroy face');
    Check(FT_Done_FreeType(Lib)=0,'destroy library');
    ReleaseFreetype;
    CheckAddresses(False);
    end;
  for I:=0 to High(Threads) do
    begin
    Threads[I]:=TLoaderThread.Create(True);
    Threads[I].Path:=Good;
    end;
  try
    for I:=0 to High(Threads) do
      Threads[I].Start;
    for I:=0 to High(Threads) do
      begin
      Threads[I].WaitFor;
      Check(Threads[I].Passed,'concurrent loader lifetime');
      end;
  finally
    for I:=0 to High(Threads) do
      Threads[I].Free;
  end;
  CheckAddresses(False);
  Check(SizeOf(FT_F26Dot6)=SizeOf(FT_Long),'C long metric width');
  Check((SizeOf(FT_Bitmap)=40) and (NativeUInt(@Bitmap.pixel_mode)-NativeUInt(@Bitmap)=26),'bitmap C layout');
  Check(FT_ENCODING_UNICODE=$756E6963,'encoding tag byte order');
{$IFDEF LINUX}
  Check(SizeOf(FT_Bitmap_Size)=32,'LP64 bitmap strike size');
  Check((SizeOf(Slot)=304) and (NativeUInt(@Slot.other)-NativeUInt(@Slot)=288),'LP64 glyph slot layout');
  Check(InitializeFreetype('libfreetype.so.6')=1,'system FreeType');
  try
    CheckAddresses(True);
    Check(FT_Init_FreeType(Lib)=0,'real create library');
    try
      Check(FT_New_Face(Lib,'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',0,Face)=0,'real create face');
      try
        Check(FT_IS_SCALABLE(Face) and (Face^.num_glyphs>0),'real face fields');
        Check(FT_Set_Pixel_Sizes(Face,0,20)=0,'real font size');
        Check(FT_Load_Char(Face,Ord('A'),FT_LOAD_RENDER)=0,'real render glyph');
        Check((Face^.glyph^.bitmap.num_grays=256) and (Face^.glyph^.bitmap.width>0),'real bitmap fields');
        OutlineFuncs:=Default(FT_Outline_Funcs);
        OutlineFuncs.move_to:=LineCallback;
        OutlineFuncs.line_to:=LineCallback;
        OutlineFuncs.conic_to:=ConicCallback;
        OutlineFuncs.cubic_to:=CubicCallback;
        Segments:=0;
        Check(FT_Outline_Decompose(@Face^.glyph^.outline,@OutlineFuncs,@Segments)=0,'C outline callbacks');
        Check(Segments>0,'outline callbacks executed');
      finally
        Check(FT_Done_Face(Face)=0,'real destroy face');
      end;
    finally
      Check(FT_Done_FreeType(Lib)=0,'real destroy library');
    end;
  finally
    ReleaseFreetype;
  end;
  CheckAddresses(False);
{$ELSE}
  Check(SizeOf(FT_Bitmap_Size)=16,'LLP64 bitmap strike size');
{$ENDIF}
  Writeln('RTL_API_FREETYPE_CONTRACTS_OK');
end.
