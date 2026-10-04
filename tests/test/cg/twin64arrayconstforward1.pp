{ %CPU=x86_64 }
program twin64arrayconstforward1;

{$mode objfpc}

uses
  SysUtils;

{$ifdef WIN64}
type
  TFormatter = class
    function AddObject(const S: string; AObject: TObject): Integer; overload;
    function AddObject(const Fmt: string; Args: array of const; AObject: TObject): Integer; overload;
    function AddConst(const Fmt: string; const Args: array of const): Integer;
  end;

function TFormatter.AddObject(const S: string; AObject: TObject): Integer;
begin
  Result:=StrToInt(S)+Ord(Assigned(AObject));
end;

function TFormatter.AddObject(const Fmt: string; Args: array of const; AObject: TObject): Integer;
begin
  Result:=AddObject(Format(Fmt,Args),AObject);
end;

function TFormatter.AddConst(const Fmt: string; const Args: array of const): Integer;
begin
  Result:=AddObject(Format(Fmt,Args),nil);
end;

var
  Formatter: TFormatter;

begin
  Formatter:=TFormatter.Create;
  try
    if Formatter.AddObject('%d',[42],nil)<>42 then
      Halt(1);
    if Formatter.AddObject('%d',[42],Formatter)<>43 then
      Halt(2);
    if Formatter.AddConst('%d',[73])<>73 then
      Halt(3);
  finally
    Formatter.Free;
  end;
end.
{$else WIN64}
begin
end.
{$endif WIN64}
