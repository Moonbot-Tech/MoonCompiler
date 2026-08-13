unit omni_mode_delphi_transition;

{$ifdef FPC}
  {$mode delphi}
{$endif}

interface

function DelphiModeDefinesMatchTypes: Boolean;

implementation

{$ifdef FPC}
const
  HasFpcUnicodeStrings =
{$ifdef FPC_UNICODESTRINGS}
    True;
{$else}
    False;
{$endif}
  HasUnicode =
{$ifdef UNICODE}
    True;
{$else}
    False;
{$endif}
{$endif}

function DelphiModeDefinesMatchTypes: Boolean;
begin
{$ifdef FPC}
  Result := (SizeOf(Char) = 1) and (SizeOf(PChar^) = 1) and
    (SizeOf(String('x')[1]) = 1) and
    not HasFpcUnicodeStrings and not HasUnicode;
{$else}
  Result := True;
{$endif}
end;

end.
