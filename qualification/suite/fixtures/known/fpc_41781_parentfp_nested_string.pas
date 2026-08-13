program fpc_advanced_bug;

{$mode objfpc}{$H+}
{$PACKRECORDS 4} // Enforces alignment to match complex frameworks like MSEgui

uses
  SysUtils;

type
  TFileNameTy = UnicodeString;
  TFileNameArTy = array of TFileNameTy;

  // Mirroring the exact projectoptions structure
  TSubOptions = record
    MakeCommand: TFileNameTy;
    TargetFile: TFileNameTy;
    TargPref: TFileNameTy;
    MainFile: TFileNameTy;
    UnitDirs: TFileNameArTy;
    UnitDirsOn: array of Integer;
    ReversePathOrder: Boolean;
    UnitPref, IncPref, LibPref, ObjPref: TFileNameTy;
    MakeOptions: array of TFileNameTy;
    MakeOptionsOn: array of Integer;
  end;

  TProjectOptions = record
    K: TSubOptions;
  end;

  TTExp = record
    OptAfterMainFileMask: Integer;
  end;

  TCommandLineBuilder = class
  private
    FOptions: TProjectOptions;
    FTExp: TTExp;
  public
    constructor Create;
    function BuildMakeCommandLine(const ATag: Integer): TFileNameTy;
  end;

constructor TCommandLineBuilder.Create;
var
  I: Integer;
begin
  // Replicating a realistic IDE multi-path structural setup
  FOptions.K.MakeCommand := 'fpc -O3';
  FOptions.K.TargetFile := 'output_binary.exe';
  FOptions.K.TargPref := '-o';
  FOptions.K.MainFile := 'myprog.pas';
  FOptions.K.ReversePathOrder := False;
  FOptions.K.UnitPref := '-Fu';
  FOptions.K.IncPref := '-Fi';
  
  FTExp.OptAfterMainFileMask := $400;

  SetLength(FOptions.K.UnitDirs, 12);
  SetLength(FOptions.K.UnitDirsOn, 12);
  for I := 0 to 11 do
  begin
    FOptions.K.UnitDirs[I] := 'C:\MseLibraries\Path_Subdir_Layout_For_Testing\' + IntToStr(I);
    FOptions.K.UnitDirsOn[I] := $10000 or $20000; // Triggers internal branch evaluations
  end;

  SetLength(FOptions.K.MakeOptions, 2);
  SetLength(FOptions.K.MakeOptionsOn, 2);
  FOptions.K.MakeOptions[0] := '-gl'; FOptions.K.MakeOptionsOn[0] := $1;
  FOptions.K.MakeOptions[1] := '-Xg'; FOptions.K.MakeOptionsOn[1] := $400;
end;

function TCommandLineBuilder.BuildMakeCommandLine(const ATag: Integer): TFileNameTy;
// THE CRITICAL ELEMENT: A nested function reading/writing PARENT stack frames
 function NormalizeName(const AName: TFileNameTy): TFileNameTy;
 begin
   // Passing custom string operations inside a nested scope enforces the hidden parentfp register 
   Result := UpperCase(Trim(AName));
 end;

var
 Int1, Int2, Step: Integer;
 Str1, Str2, Str3: TFileNameTy;
begin
 // The complex multi-variable nested loop context window
 with FOptions, K, FTExp do begin
  if MakeCommand = '' then begin
   Result := '';
   Exit;
  end;

  Str3 := '"' + MakeCommand + '"';
  Str1 := Str3;
  
  if (TargetFile <> '') and (TargPref <> '') then begin
   Str1 := Str1 + ' ' + TargPref + NormalizeName(TargetFile);
  end;
  
  Int2 := High(UnitDirs);
  Int1 := High(UnitDirsOn);
  if Int1 < Int2 then Int2 := Int1;

  if not ReversePathOrder then begin
   Int1 := Int2; Int2 := -1; Step := -1;
  end else begin
   Int1 := 0; Int2 := Int2 + 1; Step := 1;
  end;
  
  // High-density optimization block where register exhaustion occurs
  while Int1 <> Int2 do begin
   if (ATag and UnitDirsOn[Int1] <> 0) and (UnitDirs[Int1] <> '') then begin
    Str2 := NormalizeName(UnitDirs[Int1]);
    if UnitDirsOn[Int1] and $10000 <> 0 then Str1 := Str1 + ' ' + UnitPref + Str2;
    if UnitDirsOn[Int1] and $20000 <> 0 then Str1 := Str1 + ' ' + IncPref + Str2;
   end;
   Inc(Int1, Step);
  end;
  
  for Int1 := 0 to High(MakeOptions) do begin
   if MakeOptionsOn[Int1] and OptAfterMainFileMask = 0 then begin
    if (ATag and MakeOptionsOn[Int1] <> 0) and (MakeOptions[Int1] <> '') then begin
     Str1 := Str1 + ' ' + MakeOptions[Int1];
    end;
   end;
  end;
  
  Str1 := Str1 + ' ' + NormalizeName(MainFile);
  
  for Int1 := 0 to High(MakeOptions) do begin
    if MakeOptionsOn[Int1] and OptAfterMainFileMask <> 0 then begin
      if (ATag and MakeOptionsOn[Int1] <> 0) and (MakeOptions[Int1] <> '') then begin
        Str1 := Str1 + ' ' + MakeOptions[Int1];
      end;
    end;
  end;
 end;
 Result := Str1;
end;

var
 Builder: TCommandLineBuilder;
 Command: TFileNameTy;
begin
  Writeln('Building Demo Environment...');
  Builder := TCommandLineBuilder.Create;
  try
    Writeln('Invoking string parser loop...');
    Command := Builder.BuildMakeCommandLine($F000F);
    Writeln('Success: ', Command);
  finally
    Builder.Free;
  end;
end.
