program lab_004_o3_byte_record_cast;

{$mode delphi}

type
  TTestRecord = record
    W1, W2, W3, W4: Word;
  end;

var
  ErrorCount: LongInt;
  W1, W2: Word;
  B1, B2: Byte;
  TestRecord: TTestRecord;

procedure Error(Position: LongInt);
begin
  Writeln('Error at position ', Position);
  Inc(ErrorCount);
end;

function GetRecord: TTestRecord;
begin
  Result := TestRecord;
end;

begin
  ErrorCount := 0;
  B1 := $57;
  W1 := $2D57;
  B2 := $E3;
  W2 := $ABE3;
  If Byte(W1) <> B1 then
    Error(1);
  If Byte(W2) <> B2 then
    Error(2);
  TestRecord.W1 := W1;
  If Byte(TestRecord.W1) <> B1 then
    Error(3);
  If TestRecord.W1 = B1 then
    Error(4);
  If Byte(GetRecord.W1) <> B1 then
    Error(5);
  If GetRecord.W1 <> W1 then
    Error(6);
  TestRecord.W1 := $1234;
  TestRecord.W2 := W2;
  TestRecord.W3 := W1;
  If Byte(TestRecord.W2) <> B2 then
    Error(7);
  If TestRecord.W2 = B2 then
    Error(8);
  If Byte(GetRecord.W2) <> B2 then
    Error(9);
  If GetRecord.W2 <> W2 then
    Error(10);
  If Byte(TestRecord.W3) <> B1 then
    Error(11);
  If TestRecord.W3 = B1 then
    Error(12);
  If Byte(GetRecord.W3) <> B1 then
    Error(13);
  If GetRecord.W3 <> W1 then
    Error(14);
  If ErrorCount <> 0 then
    Halt(ErrorCount);
end.
