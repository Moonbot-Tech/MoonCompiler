{ %OPT=-O3 }

program tfieldaddrholder1;

{$mode delphi}
{$H+}{$R-}{$Q-}

type
  TItem = record
    A,B,C: Int64;
  end;
  TItems = array[0..7] of TItem;
  TDetail = record
    Value: Int64;
    Text: AnsiString;
  end;
  THolder = class
    Items: TItems;
    Detail: TDetail;
    function Sum: Int64; noinline;
    function ReplacedSelf: Int64; noinline;
  end;
  PHolder = ^THolder;
  TValue = record
    Holder: THolder;
    Detail: TDetail;
  end;
  TOldObject = object
    Holder: THolder;
    Detail: TDetail;
  end;

var
  First,Second: THolder;
  Escaped: PHolder;

procedure SetValue(var Value: Int64); noinline;
begin
  Value:=37;
end;

procedure SetText(var Text: AnsiString); noinline;
begin
  Text:='managed';
end;

procedure Replace(var Holder: THolder); noinline;
begin
  Holder:=Second;
end;

procedure ReplaceOut(out Holder: THolder); noinline;
begin
  Holder:=Second;
end;

procedure ReplaceEscaped; noinline;
begin
  Escaped^:=Second;
end;

function THolder.Sum: Int64;
var
  I: Integer;
begin
  Result:=0;
  for I:=0 to 7 do
    Result:=Result+Items[I].A+Items[I].B+Items[I].C;
  with Detail do
  begin
    SetValue(Value);
    SetText(Text);
    Result:=Result+Value+Length(Text);
  end;
end;

function ExplicitAddress(Holder: THolder): Int64; noinline;
var
  I: Integer;
begin
  Escaped:=@Holder;
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      ReplaceEscaped;
    Result:=Result+Holder.Items[I].A;
  end;
  Escaped:=nil;
end;

function THolder.ReplacedSelf: Int64;
var
  I: Integer;
begin
  SetValue(Detail.Value);
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      Replace(Self);
    Result:=Result+Items[I].A;
  end;
end;

function FieldAlias(Holder: THolder): Int64; noinline;
var
  P: PInt64;
  I: Integer;
begin
  P:=@Holder.Items[3].A;
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      SetValue(P^);
    Result:=Result+Holder.Items[I].A;
  end;
end;

function VarParameter(var Holder: THolder): Int64; noinline;
var
  I: Integer;
begin
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      Replace(Holder);
    Result:=Result+Holder.Items[I].A;
  end;
  SetValue(Holder.Detail.Value);
end;

function OutParameter(out Holder: THolder): Int64; noinline;
begin
  Holder:=First;
  SetText(Holder.Detail.Text);
  ReplaceOut(Holder);
  Result:=Holder.Items[0].A;
end;

function RecordStorage: Int64; noinline;
var
  Value: TValue;
  I: Integer;
begin
  Value.Holder:=First;
  with Value.Detail do
    SetValue(Value);
  Escaped:=@Value.Holder;
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      ReplaceEscaped;
    Result:=Result+Value.Holder.Items[I].A;
  end;
  Result:=Result+Value.Detail.Value;
  Escaped:=nil;
end;

function OldObjectStorage: Int64; noinline;
var
  Value: TOldObject;
  I: Integer;
begin
  Value.Holder:=First;
  Escaped:=@Value.Holder;
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      ReplaceEscaped;
    Result:=Result+Value.Holder.Items[I].A;
  end;
  Escaped:=nil;
end;

function Captured: Int64; noinline;
var
  Holder: THolder;
  I: Integer;
  procedure Nested;
  begin
    Holder:=Second;
    with Holder do
      with Detail do
        SetText(Text);
  end;
begin
  Holder:=First;
  Result:=0;
  for I:=0 to 7 do
  begin
    if I=3 then
      Nested;
    Result:=Result+Holder.Items[I].A;
  end;
end;

var
  I: Integer;
  Holder: THolder;
begin
  First:=THolder.Create;
  Second:=THolder.Create;
  for I:=0 to 7 do
  begin
    First.Items[I].A:=1;
    First.Items[I].B:=2;
    First.Items[I].C:=3;
    Second.Items[I].A:=10;
  end;
  if First.Sum<>92 then Halt(1);
  if ExplicitAddress(First)<>53 then Halt(2);
  Holder:=First;
  if VarParameter(Holder)<>53 then Halt(3);
  if OutParameter(Holder)<>10 then Halt(4);
  if RecordStorage<>90 then Halt(5);
  if OldObjectStorage<>53 then Halt(6);
  if Captured<>53 then Halt(7);
  if First.ReplacedSelf<>53 then Halt(8);
  if FieldAlias(First)<>44 then Halt(9);
  First.Free;
  Second.Free;
end.
