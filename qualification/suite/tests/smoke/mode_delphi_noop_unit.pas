unit mode_delphi_noop_unit;

{ Indy's IdCompilerDefines.inc and mORMot's mormot.defines.inc repeat the
  mode the product driver already selected.  Under the product profile
  (-Mdelphi -Municodestrings ... and MOONCOMPILER_UNICODE_DEFAULT) this
  directive must change nothing: String stays UnicodeString and the driver's
  additional mode switches - inline variables here - stay in force.  Compiled
  from another start mode the same directive still switches to Delphi, so the
  inline variable below is then a syntax error (the gate's negative control). }
{$MODE Delphi}

interface

function CharSize: Integer;
function PCharIsWide(P: PChar): Boolean;
function InlineVarSum(A, B: Integer): Integer;
function Defines: string;
function Passthrough(const S: string): string;

implementation

function CharSize: Integer;
var
  S: string;
begin
  S := 'x';
  Result := SizeOf(S[1]);
end;

function PCharIsWide(P: PChar): Boolean;
begin
  Result := SizeOf(P^) = 2;
end;

function InlineVarSum(A, B: Integer): Integer;
begin
  var Sum := A + B;
  Result := Sum;
end;

function Defines: string;
begin
  Result := '';
  {$IFDEF FPC_UNICODESTRINGS} Result := Result + ' FPC_UNICODESTRINGS'; {$ENDIF}
  {$IFDEF UNICODE} Result := Result + ' UNICODE'; {$ENDIF}
end;

function Passthrough(const S: string): string;
begin
  Result := S;
end;

end.
