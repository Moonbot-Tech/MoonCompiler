program rtl_api_sorted_find_contracts;
{$mode delphiunicode}{$R-}{$Q-}
uses SysUtils, Classes;
type
  TReverse = class(TStringList)
  public
    Calls: Integer;
    function DoCompareText(const S1, S2: UnicodeString): PtrInt; override;
  end;
function TReverse.DoCompareText(const S1, S2: UnicodeString): PtrInt;
begin
  Inc(Calls);
  Result := -inherited DoCompareText(S1, S2);
end;
var L: TStringList;
    J, N, K, Index, Expected: Integer;
    Sensitive, Locale, Reverse, Hit: Boolean;
    S: UnicodeString;
    Checks: Integer;
function Compare(const A, B: UnicodeString): Integer;
begin
  If Sensitive then
    If Locale then
      Result := AnsiCompareStr(A, B)
    else
      Result := CompareStr(A, B)
  else If Locale then
    Result := AnsiCompareText(A, B)
  else
    Result := CompareText(A, B);
  If Reverse then
    Result := -Result;
end;
begin
  Checks := 0;
  for K := 0 to 7 do
  begin
    Sensitive := K and 1 <> 0;
    Locale := K and 2 <> 0;
    Reverse := K and 4 <> 0;
    If Reverse then
      L := TReverse.Create
    else
      L := TStringList.Create;
    try
      L.CaseSensitive := Sensitive;
      L.UseLocale := Locale;
      L.Sorted := True;
      L.Duplicates := dupAccept;
      for N := 0 to 64 do
      begin
        If N > 0 then
        begin
          L.Add(Format('field%.4d', [N div 3]));
          L.Add(Format('FIELD%.4d', [N div 3]));
        end;
        for J := 0 to 32 do
        begin
          If J and 1 = 0 then
            S := Format('field%.4d', [J div 2])
          else
            S := Format('FIELD%.4d', [J div 2]);
          Expected := 0;
          while (Expected < L.Count) and (Compare(L[Expected], S) < 0) do
            Inc(Expected);
          Hit := (Expected < L.Count) and (Compare(L[Expected], S) = 0);
          If L.Find(S, Index) <> Hit then
            Halt(1);
          If Index <> Expected then
            Halt(2);
          Inc(Checks);
        end;
      end;
      If Reverse and (TReverse(L).Calls = 0) then
        Halt(3);
      L.Sorted := False;
      try
        L.Find('field0001', Index);
        Halt(4);
      except
        on E: EListError do ;
      end;
    finally
      L.Free;
    end;
  end;
  If Checks <> 17160 then
    Halt(5);
  Writeln('RTL_API_SORTED_FIND_CONTRACTS_OK');
end.
