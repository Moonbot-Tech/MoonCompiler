program inline_const_string_char_reassign_fail;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  {$ifdef FPC}SysUtils{$else}System.SysUtils{$endif};

begin
  const Value=String(IntToStr(12));
  Value[1]:='9';
end.
