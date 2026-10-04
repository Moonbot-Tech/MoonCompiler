unit Moon.Diagnostics.Zip;

{$mode delphiunicode}{$H+}

interface

uses SysUtils;

{ The caller owns the exclusively created output handle. }
procedure WriteDiagnosticZip(const FileName: string; Handle: THandle);

{$ifdef MOON_DIAGNOSTICS_TEST}
var
  DiagnosticTestZipWrite: function(Handle: THandle; const Buffer; Count: LongInt): LongInt;
{$endif}

implementation

uses Classes, mormot.core.zip, MoonORMot.Need
  {$ifdef LINUX}, BaseUnix{$endif};

type
  TDiagnosticZipStream = class(TStream)
  private
    FHandle: THandle;
    FPosition, FSize: Int64;
    FFailed: Boolean;
  public
    constructor Create(AHandle: THandle);
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    property Failed: Boolean read FFailed;
  end;

constructor TDiagnosticZipStream.Create(AHandle: THandle);
begin
  inherited Create;
  FHandle := AHandle;
end;

function TDiagnosticZipStream.Write(const Buffer; Count: LongInt): LongInt;
var
  Offset, Written: LongInt;
begin
  Result := Count;
  If Count <= 0 then Exit;
  Offset := 0;
  while not FFailed and (Offset < Count) do begin
    {$ifdef MOON_DIAGNOSTICS_TEST}
    If Assigned(DiagnosticTestZipWrite) then
      Written := DiagnosticTestZipWrite(FHandle, PByte(@Buffer)[Offset], Count - Offset)
    else
    {$endif}
      Written := FileWrite(FHandle, PByte(@Buffer)[Offset], Count - Offset);
    {$ifdef LINUX}
    If (Written < 0) and (FpGetErrno = ESysEINTR) then Continue;
    {$endif}
    If (Written <= 0) or (Written > Count - Offset) then
      FFailed := True
    else
      Inc(Offset, Written);
  end;
  Inc(FPosition, Count);
  If FPosition > FSize then FSize := FPosition;
end;

function TDiagnosticZipStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target, Actual: Int64;
begin
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPosition + Offset;
    soEnd: Target := FSize + Offset;
  end;
  If Target < 0 then FFailed := True;
  If not FFailed then begin
    Actual := FileSeek(FHandle, Target, fsFromBeginning);
    If Actual < 0 then
      FFailed := True
    else
      Target := Actual;
  end;
  If Target >= 0 then FPosition := Target;
  Result := FPosition;
end;

procedure WriteDiagnosticZip(const FileName: string; Handle: THandle);
var
  Source: TFileStream;
  Output: TDiagnosticZipStream;
  Entry: TStream;
  Zip: TZipWrite;
begin
  Source := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Output := TDiagnosticZipStream.Create(Handle);
    try
      Zip := TZipWrite.Create(Output);
      try
        Zip.ForceZip64 := True;
        { The stream overload does not load the whole report into memory. }
        Entry := Zip.AddDeflatedStream('report.txt');
        try
          Entry.CopyFrom(Source, Source.Size);
        finally
          Entry.Free;
        end;
      finally
        Zip.Free;
      end;
      { mORMot flushes from destructors. Keep an output failure latched until
        all ZIP objects are gone, then raise once so nested cleanup cannot spin. }
      If Output.Failed then raise EWriteError.Create('Diagnostic ZIP write failed');
    finally
      Output.Free;
    end;
  finally
    Source.Free;
  end;
end;
end.
