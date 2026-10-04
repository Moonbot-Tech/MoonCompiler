unit uforunrollppu1;

{$mode delphi}
{$inline on}

interface

function PureExplicit: Integer; inline;
function PureAuto: Integer;
function HandlerExplicit: Integer; inline;
function ContinuationExplicit: Integer; inline;

implementation

uses
  SysUtils;

procedure RaiseAt(const Value: Integer); noinline;
begin
  if Value=2 then
    raise Exception.Create('loop counter observation');
end;

function PureExplicit: Integer; inline;
var
  Index: Integer;
begin
  Result:=0;
  for Index:=1 to 3 do
    Inc(Result,Index);
end;

function PureAuto: Integer;
var
  Index: Integer;
begin
  Result:=0;
  for Index:=1 to 3 do
    Inc(Result,Index);
end;

function HandlerExplicit: Integer; inline;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Result:=Index;
  end;
end;

function ContinuationExplicit: Integer; inline;
var
  Index: Integer;
  Raised: Boolean;
begin
  Index:=77;
  Raised:=False;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    Raised:=True;
  end;
  if Raised then
    Result:=Index
  else
    Result:=-1;
end;

end.
