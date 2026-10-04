program ttupleoperandonce1;

{$mode delphi}
{$modeswitch tuples}

uses
  SysUtils;

type
  TPair = (Integer,Integer);
  TManagedPair = (UnicodeString,Integer);

var
  LeftCalls,RightCalls: Integer;
  LeftA,LeftB,RightA,RightB: Integer;
  BoolValue,Raised: Boolean;

function NextLeft: TPair; noinline;
begin
  Inc(LeftCalls);
  Result:=(LeftA,LeftB);
end;

function NextRight: TPair; noinline;
begin
  Inc(RightCalls);
  Result:=(RightA,RightB);
end;

function NextManagedLeft: TManagedPair; noinline;
begin
  Inc(LeftCalls);
  Result:=('same',10);
end;

function NextManagedRight: TManagedPair; noinline;
begin
  Inc(RightCalls);
  Result:=('same',10);
end;

function BoomLeft: TPair; noinline;
begin
  Inc(LeftCalls);
  raise Exception.Create('tuple operand');
end;

procedure Reset(ALeftA,ALeftB,ARightA,ARightB: Integer);
begin
  LeftCalls:=0;
  RightCalls:=0;
  LeftA:=ALeftA;
  LeftB:=ALeftB;
  RightA:=ARightA;
  RightB:=ARightB;
end;

procedure Check(Code: Integer);
begin
  if (LeftCalls<>1) or (RightCalls<>1) then
    Halt(Code);
end;

begin
  Reset(10,20,10,20);
  BoolValue:=NextLeft=NextRight;
  Check(1);
  if not BoolValue then Halt(2);

  Reset(10,20,10,21);
  BoolValue:=NextLeft<>NextRight;
  Check(3);
  if not BoolValue then Halt(4);

  Reset(10,20,10,21);
  BoolValue:=NextLeft<NextRight;
  Check(5);
  if not BoolValue then Halt(6);

  Reset(10,20,10,20);
  BoolValue:=NextLeft<=NextRight;
  Check(7);
  if not BoolValue then Halt(8);

  Reset(11,0,10,99);
  BoolValue:=NextLeft>NextRight;
  Check(9);
  if not BoolValue then Halt(10);

  Reset(10,20,10,20);
  BoolValue:=NextLeft>=NextRight;
  Check(11);
  if not BoolValue then Halt(12);

  LeftCalls:=0;
  RightCalls:=0;
  BoolValue:=NextManagedLeft=NextManagedRight;
  Check(13);
  if not BoolValue then Halt(14);

  LeftCalls:=0;
  RightCalls:=0;
  Raised:=False;
  try
    BoolValue:=BoomLeft=NextRight;
  except
    on Exception do
      Raised:=True;
  end;
  if not Raised or (LeftCalls<>1) or (RightCalls<>0) then
    Halt(15);
end.
