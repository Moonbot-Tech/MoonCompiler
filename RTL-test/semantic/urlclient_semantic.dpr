program urlclient_semantic;

{$mode delphi}{$H+}

{ System.Net.URLClient (planning contract 3.1): the header collection is
  checked against its stated semantics (first match wins, case-insensitive
  names, Delete removes every match and chains), the request and certificate
  records and the exception hierarchy. }

uses
  SysUtils,
  Classes,
  System.Net.URLClient;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

procedure Headers;
var
  H, H2: TURLHeaders;
  P: TNameValuePair;
  L: TStringList;
  I: Integer;
begin
  P := TNameValuePair.Create('Accept', 'text/html');
  Check((P.Name = 'Accept') and (P.Value = 'text/html'), 'TNameValuePair.Create');
  H := TURLHeaders.Create;
  H2 := TURLHeaders.Create;
  try
    Check(H.Value['X'] = '', 'absent header reads empty');
    Check(H.FindItem('X') = -1, 'FindItem of an absent header');
    Check(Length(H.Headers) = 0, 'no headers');
    H.Value['Content-Type'] := 'text/plain';
    H['Accept'] := 'text/html';
    Check(Length(H.Headers) = 2, 'two headers');
    Check(H['CONTENT-TYPE'] = 'text/plain', 'name case ignored');
    Check(H.FindItem('accept') = 1, 'FindItem position');
    H['content-type'] := 'application/json';
    Check((Length(H.Headers) = 2) and (H.Headers[0].Name = 'Content-Type') and (H.Headers[0].Value = 'application/json'),
      'writing replaces the first match and keeps its spelling');
    H2.Assign(H);
    Check((Length(H2.Headers) = 2) and (H2['Accept'] = 'text/html'), 'Assign copies');
    H2['Accept'] := 'changed';
    Check(H['Accept'] = 'text/html', 'Assign made an independent copy');
    Check(H.Delete('accept').Delete('nothing') = H, 'Delete chains and returns the collection');
    Check((Length(H.Headers) = 1) and (H['Accept'] = ''), 'Delete removed the header');
    Check(H2.Clear = H2, 'Clear chains');
    Check((Length(H2.Headers) = 0) and (H2.Count = 0), 'Clear empties');
    H2.Add('a', 'b');
    H2.Assign(nil);            { the TNetHeaders overload: an empty array }
    Check(H2.Count = 0, 'Assign(nil) takes the array overload and clears');
    try
      H2.Assign(TPersistent(nil));
      Check(False, 'Assign of a nil TPersistent must raise as TPersistent does');
    except
      on EConvertError do ;
    end;
    { the Delphi surface beyond Value[]: Add appends even a repeated name,
      Count/Names/Values by index, the enumerator, ToString, Append, Delete(index) }
    H2.Add('Set-Cookie', 'a=1').Add(TNetHeader.Create('Set-Cookie', 'b=2'));
    Check((H2.Count = 2) and (H2['set-cookie'] = 'a=1') and (H2.Names[1] = 'Set-Cookie') and (H2.Values[1] = 'b=2'),
      'Add appends, Value reads the first, Names/Values by index');
    H2['Set-Cookie'] := 'c=3';
    Check((H2.Count = 2) and (H2.Values[0] = 'c=3') and (H2.Values[1] = 'b=2'), 'writing Value replaces the first only');
    Check(H2.ToString = 'Set-Cookie: c=3'#13#10'Set-Cookie: b=2'#13#10, 'ToString lines');
    H2.Delete(0);
    Check((H2.Count = 1) and (H2.Values[0] = 'b=2'), 'Delete(index)');
    try
      H2.Delete(5);
      Check(False, 'Delete of a bad index must raise');
    except
      on EListError do ;
    end;
    try
      H2.Names[-1];
      Check(False, 'Names[-1] must raise');
    except
      on EListError do ;
    end;
    H2.Append(H).Append(TNetHeaders.Create(TNetHeader.Create('X', 'y')));
    Check(H2.Count = 3, 'Append of a collection and of an array');
    I := 0;
    for P in H2 do
      Inc(I);
    Check(I = 3, 'for-in enumerates every header');
    H2.Delete('set-cookie');
    Check((H2.Count = 2) and (H2.FindItem('Set-Cookie') = -1), 'Delete(name) removes all of them');
    L := TStringList.Create;
    try
      L.Add('Accept=text/*');
      L.Add('X-Trace=1');
      H2.Assign(L);
      Check((H2.Count = 2) and (H2['Accept'] = 'text/*') and (H2['x-trace'] = '1'), 'Assign from name=value strings');
    finally
      L.Free;
    end;
  finally
    H.Free;
    H2.Free;
  end;
end;

procedure Requests;
var
  R: TURLRequest;
  C: TCertificate;
begin
  R := TURLRequest.Create('https://example.com/x?y=1', 'POST');
  try
    Check((R.URL.ToString = 'https://example.com/x?y=1') and (R.MethodString = 'POST'), 'TURLRequest fields');
  finally
    R.Free;
  end;
  C := Default(TCertificate);
  Check((C.Subject = '') and (C.Expiry = 0), 'TCertificate default');
  Check(ENetURIClientException.InheritsFrom(ENetException) and ENetURIRequestException.InheritsFrom(ENetException) and
        ENetURIResponseException.InheritsFrom(ENetException) and ENetURIException.InheritsFrom(ENetException) and
        ENetException.InheritsFrom(Exception), 'exception hierarchy');
end;

begin
  Failures := 0;
  Headers;
  Requests;
  If Failures <> 0 then
    Halt(1);
  WriteLn('URLCLIENT_PASS');
end.
