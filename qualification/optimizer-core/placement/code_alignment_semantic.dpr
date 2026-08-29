program code_alignment_semantic;

{$mode unleashed}
{$Q-}
{$R-}
{$ifdef CODEALIGN_64}
  {$CODEALIGN PROC=64,LOOP=64,JUMP=64}
{$endif}

function HotLeaf(Value: QWord): QWord; noinline;
begin
  Result := (Value * 17 + 3) xor (Value shr 2);
end;

function NaturalLoop(Count: Integer): QWord; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < Count do begin
    Result := Result + HotLeaf(I);
    Inc(I);
  end;
end;

function ExplicitLabelLoop(Count: Integer): QWord; noinline;
label
  Again;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  If Count <= 0 then
    Exit;
Again:
  Result := Result + HotLeaf(I);
  Inc(I);
  If I < Count then
    goto Again;
end;

var
  Digest: QWord;
begin
  Digest := NaturalLoop(200) + ExplicitLabelLoop(200);
  If Digest <> 677800 then
    Halt(1);
  WriteLn('CODEALIGN:PASS:', Digest);
end.
