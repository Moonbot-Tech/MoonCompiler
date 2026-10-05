{ HTTP Basic challenges, RFC 7617. Other schemes are returned to the caller
  as a 401 response; declaring their enum does not implement their protocol. }
function BasicAuthorization(const UserName, Password: string): string;
var
  Ch: Char;
begin
  If Pos(':', UserName) <> 0 then
    raise ENetHTTPClientException.Create('A Basic authentication user name cannot contain a colon');
  for Ch in UserName + Password do
    If (Ord(Ch) < 32) or (Ord(Ch) = 127) then
      raise ENetHTTPClientException.Create('Basic authentication credentials contain a control character');
  Result := 'Basic ' + TNetEncoding.Base64String.Encode(UserName + ':' + Password);
end;

function BasicChallengeRealm(const Headers: TNetHeaders; out Realm: string): Boolean;
var
  Header: TNetHeader;
  Text, Scheme, Name, Value: string;
  P, Start: Integer;
  HasRealm, Closed: Boolean;
begin
  Result := False;
  Realm := '';
  for Header in Headers do begin
    If not SameText(Header.Name, 'WWW-Authenticate') then
      Continue;
    Text := Header.Value;
    Scheme := '';
    HasRealm := False;
    P := 1;
    while P <= Length(Text) do begin
      while (P <= Length(Text)) and (Text[P] in [' ', #9, ',']) do
        Inc(P);
      Start := P;
      while (P <= Length(Text)) and not (Text[P] in [' ', #9, ',', '=']) do
        Inc(P);
      Name := Copy(Text, Start, P - Start);
      If Name = '' then
        Break;
      while (P <= Length(Text)) and (Text[P] in [' ', #9]) do
        Inc(P);
      If (P > Length(Text)) or (Text[P] <> '=') then begin
        If SameText(Scheme, 'Basic') and HasRealm then
          Exit(True);
        Scheme := Name;
        HasRealm := False;
        Continue;
      end;
      Inc(P);
      while (P <= Length(Text)) and (Text[P] in [' ', #9]) do
        Inc(P);
      Value := '';
      If (P <= Length(Text)) and (Text[P] = '"') then begin
        Inc(P);
        Closed := False;
        while P <= Length(Text) do begin
          If Text[P] = '"' then begin
            Inc(P);
            Closed := True;
            Break;
          end;
          If Text[P] = '\' then begin
            Inc(P);
            If P > Length(Text) then
              Break;
          end;
          Value := Value + Text[P];
          Inc(P);
        end;
        If not Closed then
          Break;
      end else begin
        Start := P;
        while (P <= Length(Text)) and not (Text[P] in [' ', #9, ',']) do
          Inc(P);
        Value := Copy(Text, Start, P - Start);
      end;
      If SameText(Scheme, 'Basic') and SameText(Name, 'realm') then begin
        Realm := Value;
        HasRealm := True;
      end;
    end;
    If SameText(Scheme, 'Basic') and HasRealm then
      Exit(True);
  end;
end;
