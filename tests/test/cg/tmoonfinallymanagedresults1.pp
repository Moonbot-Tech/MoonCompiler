{ %OPT=-O3 -OoAUTOINLINE }
program tmoonfinallymanagedresults1;

{$ifdef FPC}{$mode delphiunicode}{$endif}
{$inline on}

uses SysUtils;

type
  IToken = interface
    function Value: Integer;
  end;
  TToken = class(TInterfacedObject, IToken)
    constructor Create;
    destructor Destroy; override;
    function Value: Integer;
  end;
  TBundle = record
    Text: UnicodeString;
    Token: IToken;
  end;
  TTokens = array of IToken;
  TBuffer = class
    function Bytes: UTF8String; inline;
    function Wide: UnicodeString; inline;
    function Narrow: AnsiString; inline;
    property Text: AnsiString read Narrow;
  end;

var
  Created, Destroyed, Visits: Integer;

constructor TToken.Create;
begin
  inherited Create;
  Inc(Created);
end;

destructor TToken.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TToken.Value: Integer;
begin
  Result := 37;
end;

function TBuffer.Bytes: UTF8String;
begin
  SetLength(Result, 3);
  Result[1] := 'a';
  Result[2] := 'b';
  Result[3] := 'c';
end;

function TBuffer.Wide: UnicodeString;
begin
  Result := UTF8Decode(Bytes);
end;

function TBuffer.Narrow: AnsiString;
begin
  Result := Wide;
end;

function ConvertInFinally: AnsiString;
var
  Buffer: TBuffer;
begin
  Buffer := TBuffer.Create;
  try
    Inc(Visits);
  finally
    Result := Buffer.Text;
    Buffer.Free;
  end;
end;

function MakeText: UnicodeString; inline;
begin
  SetLength(Result, 3);
  Result[1] := 'a';
  Result[2] := WideChar($03a9);
  Result[3] := 'z';
end;

function MakeWide: WideString; inline;
begin
  Result := MakeText;
end;

function MakeToken: IToken; inline;
begin
  Result := TToken.Create;
end;

function MakeBundle: TBundle; inline;
begin
  Result.Text := MakeText;
  Result.Token := MakeToken;
end;

function MakeTokens: TTokens; inline;
begin
  SetLength(Result, 2);
  Result[0] := MakeToken;
  Result[1] := MakeToken;
end;

procedure CheckText(const S: UnicodeString);
begin
  if (Length(S) <> 3) or (S[1] <> 'a') or (Ord(S[2]) <> $03a9) or (S[3] <> 'z') then
    Halt(1);
end;

procedure CheckWide(const S: WideString);
begin
  if (Length(S) <> 3) or (Ord(S[2]) <> $03a9) then
    Halt(2);
end;

procedure CheckToken(const V: IToken);
begin
  if (V = nil) or (V.Value <> 37) then
    Halt(3);
end;

procedure CheckBundle(const V: TBundle; Fail: Boolean);
begin
  CheckText(V.Text);
  CheckToken(V.Token);
  if Fail then
    raise Exception.Create('consumer');
end;

procedure CheckTokens(const V: TTokens);
begin
  if Length(V) <> 2 then
    Halt(4);
  CheckToken(V[0]);
  CheckToken(V[1]);
end;

{ No declared managed locals: only inline expansion can introduce them.
  Exercise return, Exit, unwinding and an exception in the consumer itself. }
procedure Probe(Mode: Integer);
begin
  try
    Inc(Visits);
    if Mode = 1 then
      Exit;
    if Mode = 2 then
      raise Exception.Create('body');
  finally
    CheckText(MakeText);
    CheckWide(MakeWide);
    CheckToken(MakeToken);
    CheckTokens(MakeTokens);
    try
      CheckBundle(MakeBundle, Mode = 3);
    finally
      Inc(Visits);
      CheckToken(MakeToken);
    end;
  end;
end;

{ The presence of an unrelated managed local must not change correctness. }
procedure WithExistingCleanup(Mode: Integer);
var
  Hold: IToken;
begin
  Hold := MakeToken;
  try
    Probe(Mode);
  finally
    CheckToken(Hold);
  end;
end;

var
  Mode, Round, Caught: Integer;
begin
  if ConvertInFinally <> 'abc' then
    Halt(5);
  for Round := 0 to 1 do
    for Mode := 0 to 3 do
      begin
        Caught := 0;
        try
          if Round = 0 then
            Probe(Mode)
          else
            WithExistingCleanup(Mode);
        except
          on E: Exception do
            begin
              if ((Mode = 2) and (E.Message <> 'body')) or
                 ((Mode = 3) and (E.Message <> 'consumer')) then
                Halt(6);
              Inc(Caught);
            end;
        end;
        if Caught <> Ord(Mode >= 2) then
          Halt(7);
        { Check after the whole caller has left; temporary release inside an
          expression may legally be delayed until the caller's epilogue. }
        if Created <> Destroyed then
          Halt(8);
      end;
  if (Created <> 44) or (Visits <> 17) then
    Halt(9);
  Writeln('ok');
end.
