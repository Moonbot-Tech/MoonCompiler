program variant_unicode_system_only;
{$mode delphiunicode}
{ No Variants initialization: the fallback must work with a user manager alone. }
var Original, Custom: TVariantManager;
    V: Variant;
    U: UnicodeString;
    WideCalls, NativeCalls: Integer;
procedure WideReader(var Dest: WideString; const Source: Variant);
begin Inc(WideCalls); Dest:='wide'; end;
procedure NativeReader(var Dest: UnicodeString; const Source: Variant);
begin Inc(NativeCalls); Dest:='native'; end;
procedure OtherReader(var Dest: WideString; const Source: Variant);
begin Inc(WideCalls); Dest:='other'; end;
procedure Check(B: Boolean);
begin if not B then Halt(1); end;
begin
  GetVariantManager(Original);
  Custom:=Original;
  Custom.VarToWStr:=@WideReader;
  SetVariantManager(Custom);
  U:=UnicodeString(V);
  Check((U='wide') and (WideCalls=1));
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
  RegisterVariantUnicodeStringManager(@WideReader,@NativeReader);
  U:=UnicodeString(V);
  Check((U='native') and (NativeCalls=1));
  Custom.VarToWStr:=@OtherReader;
  SetVariantManager(Custom);
  U:=UnicodeString(V);
  Check((U='other') and (NativeCalls=1));
  Custom.VarToWStr:=@WideReader;
  SetVariantManager(Custom);
  U:=UnicodeString(V);
  Check((U='native') and (NativeCalls=2));
  RegisterVariantUnicodeStringManager(nil);
  U:=UnicodeString(V);
  Check((U='wide') and (WideCalls=3));
  {$endif}
  SetVariantManager(Original);
  WriteLn('VARIANT_SYSTEM_ONLY_PASS');
end.
