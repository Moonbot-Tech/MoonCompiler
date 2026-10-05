function CookieDomainMatches(const Host, Domain: string): Boolean;
var
  I: Integer;
  IsAddress: Boolean;
begin
  If Host = Domain then
    Exit(True);
  IsAddress := Pos(':', Host) <> 0;
  If not IsAddress then begin
    IsAddress := True;
    for I := 1 to Length(Host) do
      If not (Host[I] in ['0'..'9', '.']) then begin
        IsAddress := False;
        Break;
      end;
  end;
  Result := not IsAddress and (Length(Host) > Length(Domain)) and
    (Copy(Host, Length(Host) - Length(Domain) + 1, MaxInt) = Domain) and
    (Host[Length(Host) - Length(Domain)] = '.');
end;

function CookiePathMatches(const RequestPath, CookiePath: string): Boolean;
begin
  Result := (Copy(RequestPath, 1, Length(CookiePath)) = CookiePath) and
    ((Length(RequestPath) = Length(CookiePath)) or (CookiePath[Length(CookiePath)] = '/') or
     (RequestPath[Length(CookiePath) + 1] = '/'));
end;

class function TCookie.Create(const Data: string; const URI: System.Net.URLClient.TURI): TCookie;
var
  Token, Key, AttrValue, Domain: string;
  Start, Stop, Sep, I: Integer;
  MaxAge: Int64;
  HasMaxAge: Boolean;
begin
  Result := Default(TCookie);
  Result.Domain := LowerCase(URI.Host);
  Result.FHostOnly := True;
  Result.Path := URI.Path;
  I := LastDelimiter('/', Result.Path);
  If (I <= 1) or (Result.Path[1] <> '/') then
    Result.Path := '/'
  else
    SetLength(Result.Path, I - 1);
  Stop := Pos(';', Data);
  If Stop = 0 then
    Stop := Length(Data) + 1;
  Token := Copy(Data, 1, Stop - 1);
  Sep := Pos('=', Token);
  If Sep <= 1 then
    Exit(Default(TCookie));
  Result.Name := Trim(Copy(Token, 1, Sep - 1));
  Result.Value := Trim(Copy(Token, Sep + 1, MaxInt));
  If Result.Name = '' then
    Exit(Default(TCookie));
  for I := 1 to Length(Result.Name) do
    If (Ord(Result.Name[I]) <= 32) or (Ord(Result.Name[I]) >= 127) or
      (Result.Name[I] in ['(', ')', '<', '>', '@', ',', ';', ':', '\', '"', '/', '[', ']', '?', '=', '{', '}']) then
      Exit(Default(TCookie));
  for I := 1 to Length(Result.Value) do
    If (Ord(Result.Value[I]) < 32) or (Ord(Result.Value[I]) = 127) then
      Exit(Default(TCookie));
  HasMaxAge := False;
  MaxAge := 0;
  Start := Stop + 1;
  while Start <= Length(Data) do begin
    Stop := Start;
    while (Stop <= Length(Data)) and (Data[Stop] <> ';') do
      Inc(Stop);
    Token := Trim(Copy(Data, Start, Stop - Start));
    Sep := Pos('=', Token);
    If Sep = 0 then begin
      Key := LowerCase(Token);
      AttrValue := '';
    end else begin
      Key := LowerCase(Trim(Copy(Token, 1, Sep - 1)));
      AttrValue := Trim(Copy(Token, Sep + 1, MaxInt));
    end;
    If Key = 'domain' then begin
      Domain := LowerCase(AttrValue);
      If (Domain <> '') and (Domain[1] = '.') then
        Delete(Domain, 1, 1);
      If (Domain = '') or (Domain[Length(Domain)] = '.') or
        not CookieDomainMatches(LowerCase(URI.Host), Domain) then
        Exit(Default(TCookie));
      { A single DNS label cannot grant a cookie to every host under a TLD. }
      If (Pos('.', Domain) = 0) and (Domain <> LowerCase(URI.Host)) then
        Exit(Default(TCookie));
      Result.Domain := Domain;
      Result.FHostOnly := False;
    end else If Key = 'path' then begin
      If (AttrValue <> '') and (AttrValue[1] = '/') then
        Result.Path := AttrValue;
    end else If Key = 'secure' then
      Result.Secure := True
    else If Key = 'httponly' then
      Result.HttpOnly := True
    else If Key = 'expires' then
      HttpDateToDateTime(StringToUtf8(AttrValue), Result.Expires)
    else If Key = 'max-age' then
      HasMaxAge := TryStrToInt64(AttrValue, MaxAge);
    Start := Stop + 1;
  end;
  If HasMaxAge then begin
    If MaxAge <= 0 then
      Result.Expires := 1
    else If MaxAge > 253402300799 then
      Result.Expires := 2958465
    else begin
      Result.Expires := NowUtc + MaxAge / 86400;
      If Result.Expires > 2958465 then
        Result.Expires := 2958465;
    end;
  end;
  If Result.Secure and not SameText(URI.Scheme, 'https') then
    Exit(Default(TCookie));
  If (Copy(Result.Name, 1, 9) = '__Secure-') and not Result.Secure then
    Exit(Default(TCookie));
  If (Copy(Result.Name, 1, 7) = '__Host-') and
    (not Result.Secure or not Result.FHostOnly or (Result.Path <> '/')) then
    Exit(Default(TCookie));
end;

function TCookie.ToString: string;
begin
  Result := Name + '=' + Value;
end;

function TCookie.GetServerCookie: string;
begin
  Result := ToString;
  If (Domain <> '') and not FHostOnly then
    Result := Result + '; Domain=' + Domain;
  If Path <> '' then
    Result := Result + '; Path=' + Path;
  If Expires <> 0 then
    Result := Result + '; Expires=' + Utf8ToString(DateTimeToHttpDate(Expires));
  If Secure then
    Result := Result + '; Secure';
  If HttpOnly then
    Result := Result + '; HttpOnly';
end;

constructor TCookieManager.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TCookieManager.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TCookieManager.PurgeExpired;
var
  I, N: Integer;
  Time: TDateTime;
begin
  N := 0;
  Time := NowUtc;
  for I := 0 to High(FCookies) do
    If (FCookies[I].Expires = 0) or (FCookies[I].Expires > Time) then begin
      FCookies[N] := FCookies[I];
      Inc(N);
    end;
  SetLength(FCookies, N);
end;

function TCookieManager.Count: Integer;
begin
  FLock.Acquire;
  try
    PurgeExpired;
    Result := Length(FCookies);
  finally
    FLock.Release;
  end;
end;

procedure TCookieManager.AddServerCookie(const ACookieData, ACookieURL: string);
var
  Cookie: TCookie;
  I: Integer;
begin
  Cookie := TCookie.Create(ACookieData, System.Net.URLClient.TURI.Create(ACookieURL));
  If Cookie.Name = '' then
    Exit;
  FLock.Acquire;
  try
    for I := 0 to High(FCookies) do
      If (FCookies[I].Name = Cookie.Name) and (FCookies[I].Domain = Cookie.Domain) and
        (FCookies[I].Path = Cookie.Path) then begin
        If FCookies[I].Secure and not SameText(System.Net.URLClient.TURI.Create(ACookieURL).Scheme, 'https') then
          Exit;
        FCookies[I] := Cookie;
        PurgeExpired;
        Exit;
      end;
    PurgeExpired;
    If (Cookie.Expires <> 0) and (Cookie.Expires <= NowUtc) then
      Exit;
    SetLength(FCookies, Length(FCookies) + 1);
    FCookies[High(FCookies)] := Cookie;
  finally
    FLock.Release;
  end;
end;

function TCookieManager.CookieHeader(const AURL: string): string;
var
  URI: System.Net.URLClient.TURI;
  Host, Path: string;
  Indices: array of Integer;
  I, J, N: Integer;
begin
  URI := System.Net.URLClient.TURI.Create(AURL);
  Host := LowerCase(URI.Host);
  Path := URI.Path;
  If Path = '' then
    Path := '/';
  Result := '';
  FLock.Acquire;
  try
    PurgeExpired;
    SetLength(Indices, Length(FCookies));
    N := 0;
    for I := 0 to High(FCookies) do
      If ((FCookies[I].Domain = Host) or
        (not FCookies[I].FHostOnly and CookieDomainMatches(Host, FCookies[I].Domain))) and
        (not FCookies[I].Secure or SameText(URI.Scheme, 'https')) and CookiePathMatches(Path, FCookies[I].Path) then begin
        J := N;
        while (J > 0) and (Length(FCookies[Indices[J - 1]].Path) < Length(FCookies[I].Path)) do begin
          Indices[J] := Indices[J - 1];
          Dec(J);
        end;
        Indices[J] := I;
        Inc(N);
      end;
    for I := 0 to N - 1 do begin
      If Result <> '' then
        Result := Result + '; ';
      Result := Result + FCookies[Indices[I]].ToString;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TCookieManager.Assign(Source: TCookieManager);
var
  Snapshot: TCookiesArray;
begin
  If Source = Self then
    Exit;
  Snapshot := nil;
  If Source <> nil then begin
    Source.FLock.Acquire;
    try
      Snapshot := Copy(Source.FCookies);
    finally
      Source.FLock.Release;
    end;
  end;
  FLock.Acquire;
  try
    FCookies := Snapshot;
  finally
    FLock.Release;
  end;
end;
