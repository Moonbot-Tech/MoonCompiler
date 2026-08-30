program bsearch;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$endif}
{$APPTYPE CONSOLE}{$Q-}{$R-}
uses SysUtils, Math, Generics.Defaults, Generics.Collections;

type
  TItem = record
    Time: Double;
    Tag:  Integer;
  end;

var
  Cmp: IComparer<TItem>;

function Run(const A: array of TItem; const Probe: TItem; Lo, Cnt: Integer): string;
var
  Idx: Integer;
  Found: Boolean;
  Arr: TArray<TItem>;
  I: Integer;
begin
  SetLength(Arr, Length(A));
  for I := 0 to High(A) do Arr[I] := A[I];
  Idx := -1;
  Found := TArray.BinarySearch<TItem>(Arr, Probe, Idx, Cmp, Lo, Cnt);
  Result := Format('found=%s idx=%d', [BoolToStr(Found, True), Idx]);
end;

var
  A: array[0..7] of TItem;
  P: TItem;
  I: Integer;
begin
  Cmp := TDelegatedComparer<TItem>.Create(
    function(const L, R: TItem): Integer
    begin
      { нетранзитивный: близкие считаются равными }
      if Abs(L.Time - R.Time) < 0.5 then Result := 0
      else Result := Sign(L.Time - R.Time);
    end);

  { лента с повторами: несколько записей с одним временем }
  for I := 0 to 7 do
  begin
    A[I].Time := I div 2;      { 0,0,1,1,2,2,3,3 }
    A[I].Tag := I;
  end;

  P.Time := 1; P.Tag := 99;
  WriteLn('поиск 1.0 во всех восьми:   ', Run(A, P, 0, 8));
  P.Time := 0; P.Tag := 99;
  WriteLn('поиск 0.0 во всех восьми:   ', Run(A, P, 0, 8));
  P.Time := 3; P.Tag := 99;
  WriteLn('поиск 3.0 во всех восьми:   ', Run(A, P, 0, 8));
  P.Time := 2.4; P.Tag := 99;
  WriteLn('поиск 2.4 (в допуске к 2):  ', Run(A, P, 0, 8));
  P.Time := 5; P.Tag := 99;
  WriteLn('поиск 5.0 (за краем):       ', Run(A, P, 0, 8));
  P.Time := 1; P.Tag := 99;
  WriteLn('поиск 1.0 в первых четырёх: ', Run(A, P, 0, 4));
end.
