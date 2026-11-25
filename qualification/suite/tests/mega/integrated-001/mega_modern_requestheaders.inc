{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A request uses a copy of saved headers and keeps repeated fields only through Append. }

procedure RunBreadthRequestHeaders;
var
  Settings: TStringList;
  Saved, Request: TURLHeaders;
  Appended: TNetHeaders;
begin
  Settings := TStringList.Create;
  try
    Settings.Add('Accept-Language=en');
    Settings.Add('X-View=grid');
    Saved := TURLHeaders.Create;
    try
      Request := TURLHeaders.Create;
      try
        Saved.Assign(Settings);
        Check((Saved.Count = 2) and (Saved['accept-language'] = 'en') and (Saved['X-VIEW'] = 'grid'),
          'breadth-request-headers-imports-name-value-profiles-case-insensitively');
        Request.Assign(Saved);
        Request['ACCEPT-LANGUAGE'] := 'de, en';
        Check((Request.Count = 2) and (Request['Accept-Language'] = 'de, en') and (Saved['Accept-Language'] = 'en'),
          'breadth-request-headers-change-does-not-mutate-saved-profile');

        Appended := [TNetHeader.Create('X-Note', 'first'), TNetHeader.Create('x-note', 'second')];
        Request.Append(Appended);
        Check((Request.Count = 4) and (Request.Values[2] = 'first') and (Request.Values[3] = 'second'),
          'breadth-request-headers-append-preserves-explicit-repeated-fields');
        Request.Delete('X-NOTE');
        Check((Request.Count = 2) and (Request.FindItem('x-note') < 0) and (Request['x-view'] = 'grid'),
          'breadth-request-headers-delete-case-insensitively-removes-all-repeated-fields');
        Mix(UInt64(Request.Count));
      finally
        Request.Free;
      end;
    finally
      Saved.Free;
    end;
  finally
    Settings.Free;
  end;
end;
{$endif}
