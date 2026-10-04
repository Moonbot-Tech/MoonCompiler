program inline_managed_result_ownership_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils;

type
  TIntArray = array of Integer;

  TStore = class
  public
    Values: TIntArray;
    Text: UnicodeString;
    function GetValues: TIntArray; inline;
    function GetText: UnicodeString; inline;
  end;

var
  GlobalValues, ArrayTrash: TIntArray;
  GlobalText, TextTrash: UnicodeString;
  GlobalAnsi, AnsiTrash: AnsiString;
  GlobalWide, WideTrash: WideString;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('INLINE_MANAGED_OWNERSHIP_FAIL: '+AMessage);
end;

procedure FillValues(var Values: TIntArray; Base: Integer);
var
  I: Integer;
begin
  SetLength(Values,128);
  for I:=0 to High(Values) do
    Values[I]:=Base+I;
end;

function TStore.GetValues: TIntArray;
begin
  Result:=Values;
end;

function TStore.GetText: UnicodeString;
begin
  Result:=Text;
end;

function GetGlobalValues: TIntArray; inline;
begin
  Result:=GlobalValues;
end;

function ForwardValues(const Values: TIntArray): TIntArray; inline;
begin
  Result:=Values;
end;

function GetGlobalText: UnicodeString; inline;
begin
  Result:=GlobalText;
end;

function GetGlobalAnsi: AnsiString; inline;
begin
  Result:=GlobalAnsi;
end;

function GetGlobalWide: WideString; inline;
begin
  Result:=GlobalWide;
end;

procedure ConsumeGlobalValues(const Values: TIntArray); noinline;
begin
  GlobalValues:=nil;
  FillValues(ArrayTrash,-1000);
  Check((Length(Values)=128) and (Values[0]=0) and (Values[127]=127),
    'global dynamic array');
end;

procedure ConsumeForwardedValues(const Values: TIntArray); noinline;
begin
  GlobalValues:=nil;
  FillValues(ArrayTrash,-2000);
  Check((Length(Values)=128) and (Values[0]=100) and (Values[127]=227),
    'forwarded const dynamic array');
end;

procedure ConsumeFieldValues(Store: TStore; const Values: TIntArray); noinline;
begin
  Store.Values:=nil;
  FillValues(ArrayTrash,-3000);
  Check((Length(Values)=128) and (Values[0]=200) and (Values[127]=327),
    'field dynamic array');
end;

procedure ConsumeGlobalText(const Text: UnicodeString); noinline;
begin
  GlobalText:='';
  TextTrash:=StringOfChar('Z',128);
  Check(Text=StringOfChar('U',128),'UnicodeString');
end;

procedure ConsumeGlobalAnsi(const Text: AnsiString); noinline;
begin
  GlobalAnsi:='';
  AnsiTrash:=AnsiString(StringOfChar('Z',128));
  Check(Text=AnsiString(StringOfChar('A',128)),'AnsiString');
end;

procedure ConsumeGlobalWide(const Text: WideString); noinline;
begin
  GlobalWide:='';
  WideTrash:=WideString(StringOfChar('Z',128));
  Check(Text=WideString(StringOfChar('W',128)),'WideString');
end;

procedure ConsumeFieldText(Store: TStore; const Text: UnicodeString); noinline;
begin
  Store.Text:='';
  TextTrash:=StringOfChar('Z',128);
  Check(Text=StringOfChar('F',128),'field UnicodeString');
end;

var
  Store: TStore;
begin
  FillValues(GlobalValues,0);
  ConsumeGlobalValues(GetGlobalValues);

  FillValues(GlobalValues,100);
  ConsumeForwardedValues(ForwardValues(GlobalValues));

  Store:=TStore.Create;
  try
    FillValues(Store.Values,200);
    ConsumeFieldValues(Store,Store.GetValues);
    Store.Text:=StringOfChar('F',128);
    ConsumeFieldText(Store,Store.GetText);
  finally
    Store.Free;
  end;

  GlobalText:=StringOfChar('U',128);
  ConsumeGlobalText(GetGlobalText);
  GlobalAnsi:=AnsiString(StringOfChar('A',128));
  ConsumeGlobalAnsi(GetGlobalAnsi);
  GlobalWide:=WideString(StringOfChar('W',128));
  ConsumeGlobalWide(GetGlobalWide);
  WriteLn('INLINE_MANAGED_RESULT_OWNERSHIP_SEMANTIC_PASS');
end.
