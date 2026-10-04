{ %OPT=-O3 }
program tmoonwithobjectcapture1;
{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}

type
  TProc = reference to procedure;
  TBase = class
    Value: Integer;
    procedure Add(N: Integer);
  end;
  TItem = class(TBase)
    Text: UnicodeString;
    constructor Create(N: Integer);
    function Identity: TItem;
  end;
  TSource = class
    Item: TItem;
    function GetItem: TItem;
    property Current: TItem read GetItem;
  end;
var
  Owner, Alternate: TItem;
  Calls, Seen: Integer;
  ReadBack, Change: TProc;

procedure TBase.Add(N: Integer);
begin
  Inc(Value, N);
end;

constructor TItem.Create(N: Integer);
begin
  inherited Create;
  Value := N;
  Text := 'item';
end;

function TItem.Identity: TItem;
begin
  Result := Self;
end;

function MakeItem: TItem;
begin
  Inc(Calls);
  Result := Owner;
end;

function TSource.GetItem: TItem;
begin
  Inc(Calls);
  Result := Item;
end;

procedure CaptureFunction;
begin
  with MakeItem do
    begin
      Change := procedure begin Add(7); end;
      ReadBack := procedure begin Seen := Value + Length(Text); end;
    end;
end;

procedure CaptureProperty;
var Source: TSource;
begin
  Source := TSource.Create;
  Source.Item := Owner;
  try
    with Source.Current do
      begin
        ReadBack := procedure begin Seen := Value; end;
        { Replacing the producer must not retarget an already evaluated with. }
        Source.Item := Alternate;
      end;
  finally
    Source.Free;
  end;
end;

procedure CaptureConstructor;
begin
  with TItem.Create(40) do
    begin
      { Explicit object ownership is separate from closure ownership. }
      Owner := Identity;
      ReadBack := procedure begin Seen := Value; end;
    end;
end;

var A: array[0..1] of TItem;
function Index: Integer;
begin
  Inc(Calls);
  Result := 1;
end;

procedure CaptureElement;
begin
  with A[Index] do
    begin
      ReadBack := procedure begin Seen := Value; end;
      A[1] := Alternate;
    end;
end;

begin
  Owner := TItem.Create(10);
  Alternate := TItem.Create(90);
  try
    CaptureFunction;
    if Calls <> 1 then Halt(1);
    Change();
    ReadBack();
    if (Seen <> 21) or (Owner.Value <> 17) or (Calls <> 1) then Halt(2);
    CaptureProperty;
    ReadBack();
    if (Seen <> 17) or (Calls <> 2) then Halt(3);
    A[1] := Owner;
    CaptureElement;
    ReadBack();
    if (Seen <> 17) or (Calls <> 3) then Halt(4);
    ReadBack := nil;
    Change := nil;
  finally
    Owner.Free;
    Alternate.Free;
  end;
  CaptureConstructor;
  try
    ReadBack();
    if Seen <> 40 then Halt(5);
    ReadBack := nil;
  finally
    Owner.Free;
  end;
  Writeln('ok');
end.
