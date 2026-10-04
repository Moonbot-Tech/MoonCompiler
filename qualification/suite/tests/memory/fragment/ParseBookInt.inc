function ParseBookInt(const data: PDocVariantData; var oBook: TOrdersGlass): Boolean;
var
  i, k: Integer;
  item: TOrderGlass;
  row: PDocVariantData;
begin
  result := false;
  k := 0;
  SetLength(oBook, 0);
  for i := 0 to data^.Count - 1 do begin
    if _SafeArray(data^.Values[i], row) and (row^.Count >= 2) then begin
      item.Rate := row^.Values[0];
      item.Quantity := row^.Values[1];
      if item.Quantity <> 0 then begin
        if k >= Length(oBook) then
          SetLength(oBook, k + 20);
        oBook[k] := item;
        inc(k);
      end;
    end;
  end;
  SetLength(oBook, k);
  result := true;
end;
