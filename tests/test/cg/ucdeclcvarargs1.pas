unit ucdeclcvarargs1;

{$mode objfpc}

interface

type
  TSprintf = function(Buffer,Fmt: PAnsiChar; const Args: array of const): LongInt; cdecl;

{$ifdef windows}
function CPrintf(Buffer,Fmt: PAnsiChar; const Args: array of const): LongInt; cdecl;
  external 'msvcrt.dll' name 'sprintf';
{$else}
{$linklib c}
function CPrintf(Buffer,Fmt: PAnsiChar; const Args: array of const): LongInt; cdecl;
  external name 'sprintf';
{$endif}

function GetCPrintf: TSprintf;
function CFirst(const Values: array of Integer): Integer; cdecl;

implementation

function GetCPrintf: TSprintf;
begin
  Result:=@CPrintf;
end;

function CFirst(const Values: array of Integer): Integer; cdecl;
begin
  Result:=Values[0];
end;

end.
