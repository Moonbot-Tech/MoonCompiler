unit uwin64aggregateabidelphi1;

{$mode unleashed}

interface

type
  TRec1 = packed record B0: Byte; end;
  TRec2 = packed record B: array[0..1] of Byte; end;
  TRec4 = packed record B: array[0..3] of Byte; end;
  TRec8 = packed record Bits: QWord; end;
  TRec16 = packed record First,Second: QWord; end;
  TRead8 = function(const Value: TRec8): QWord;
  TReader = class
    function Read8(const Value: TRec8): QWord; noinline;
  end;

function Read1(const Value: TRec1): QWord; noinline;
function Read2(const Value: TRec2): QWord; noinline;
function Read4(const Value: TRec4): QWord; noinline;
function Read8(const Value: TRec8): QWord; noinline;
function Read16(const Value: TRec16): QWord; noinline;
function GetRead8: TRead8; noinline;
function Make8(Value: QWord): TRec8; noinline;

implementation

function Read1(const Value: TRec1): QWord;
begin
  Result:=Value.B0;
end;

function Read2(const Value: TRec2): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function Read4(const Value: TRec4): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;

function Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function Read16(const Value: TRec16): QWord;
begin
  Result:=Value.First;
end;

function GetRead8: TRead8;
begin
  Result:=@Read8;
end;

function Make8(Value: QWord): TRec8;
begin
  Result.Bits:=Value;
end;

function TReader.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

end.
