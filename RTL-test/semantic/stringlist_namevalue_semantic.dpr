program stringlist_namevalue_semantic;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils,
  Classes
  {$else FPC}
  System.SysUtils,
  System.Classes
  {$endif FPC};

type
  TFirstCharStringList = class(TStringList)
  protected
    {$ifdef FPC}
    function DoCompareText(const S1, S2: string): NativeInt; override;
    {$else FPC}
    function CompareStrings(const S1, S2: string): Integer; override;
    {$endif FPC}
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create('STRINGLIST_NAMEVALUE_FAIL: ' + MessageText);
end;

{$ifdef FPC}
function TFirstCharStringList.DoCompareText(const S1,
  S2: string): NativeInt;
{$else FPC}
function TFirstCharStringList.CompareStrings(const S1,
  S2: string): Integer;
{$endif FPC}
begin
  If (S1 <> '') and (S2 <> '') then
    Result := Ord(S1[1]) - Ord(S2[1])
  else
    Result := Length(S1) - Length(S2);
end;

procedure CheckPlain;
var
  EmbeddedValue: string;
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Add('alpha=first');
    List.Add('alphabet=longer');
    List.Add('empty=');
    List.Add('=nameless');
    List.Add('plain');
    List.Add('a=b=embedded');
    List.Add(UnicodeString(#$0411#$0435#$0442#$0430) + '=unicode');

    Check(List.Values['alpha'] = 'first', 'plain value');
    Check(List.Values['alphabet'] = 'longer', 'prefix collision');
    Check(List.Values['missing'] = '', 'missing name');
    Check(List.Values['empty'] = '', 'empty value');
    Check(List.Values[''] = 'nameless', 'empty name');
    Check(List.IndexOfName('plain') = -1, 'missing separator');
    EmbeddedValue := List.Values['a=b'];
    Check(EmbeddedValue = 'embedded', 'separator inside name: index=' +
      IntToStr(List.IndexOfName('a=b')) + ' value=' + EmbeddedValue);

    List.CaseSensitive := False;
    Check(List.Values['ALPHA'] = 'first', 'ASCII insensitive');
    Check(List.Values[UnicodeString(#$0431#$0435#$0442#$0430)] = 'unicode',
      'Unicode insensitive');
    List.CaseSensitive := True;
    Check(List.IndexOfName('ALPHA') = -1, 'ASCII sensitive');
    Check(List.IndexOfName(UnicodeString(#$0431#$0435#$0442#$0430)) = -1,
      'Unicode sensitive');

    List.UseLocale := False;
    List.CaseSensitive := False;
    Check(List.Values['ALPHA'] = 'first', 'ordinal ASCII insensitive');
    Check(List.IndexOfName(UnicodeString(#$0431#$0435#$0442#$0430)) = -1,
      'ordinal comparison only folds ASCII');
    List.CaseSensitive := True;
    Check(List.IndexOfName('ALPHA') = -1, 'ordinal ASCII sensitive');

    List.NameValueSeparator := ':';
    List.Add('colon:value');
    Check(List.Values['colon'] = 'value', 'custom separator');
  finally
    List.Free;
  end;
end;

procedure CheckSorted;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    List.Add('gamma=3');
    List.Add('alpha=1');
    List.Add('beta=2');
    Check(List.Values['alpha'] = '1', 'sorted first');
    Check(List.Values['beta'] = '2', 'sorted middle');
    Check(List.Values['gamma'] = '3', 'sorted last');
  finally
    List.Free;
  end;
end;

procedure CheckInheritedComparison;
var
  List: TFirstCharStringList;
begin
  List := TFirstCharStringList.Create;
  try
    List.Add('apple=value');
    Check(List.IndexOfName('anchor') = 0, 'overridden comparison');
  finally
    List.Free;
  end;
end;

begin
  CheckPlain;
  CheckSorted;
  CheckInheritedComparison;
  WriteLn('STRINGLIST_NAMEVALUE_SEMANTIC_OK');
end.
