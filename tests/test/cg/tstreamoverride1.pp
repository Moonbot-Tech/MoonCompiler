{ %CPU=x86_64 }
program tstreamoverride1;

{$mode delphiunicode}

uses
  Classes;

type
  TProbeStream = class(TStream)
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

function TProbeStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result:=Count;
end;

begin
end.
