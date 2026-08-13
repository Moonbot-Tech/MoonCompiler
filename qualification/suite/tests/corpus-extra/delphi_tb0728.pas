program delphi_tb0728;

{$mode delphi}
{$modeswitch stringordcast}
{$modeswitch inlinevars}
{$warn 6018 off}

const
  CByte = Byte('A');
  CShortint = Shortint('B');
  CWord = Word('HI');
  CSmallint = Smallint('no');
  CDword = DWord('abcd');
  CLongint = Longint('ABCD');
  CCardinal = Cardinal('RIFF');
  CQword = QWord('12345678');
  CInt64 = Int64('abcdefgh');
  CHex = DWord(#$DE#$AD#$BE#$EF);

var
  GDword: DWord = DWord('abcd');
  GQword: QWord = QWord('12345678');

procedure Expect(var Actual; const Expected: array of Byte; Code: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Expected) do
    If PByte(@Actual)[I] <> Expected[I] then
      Halt(Code);
end;

procedure CheckInline;
begin
  var A := DWord('abcd');
  var B: Word := Word('HI');
  Expect(A, [$61, $62, $63, $64], 1);
  Expect(B, [$48, $49], 2);
end;

begin
  var B1: Byte := CByte;
  var B2: Shortint := CShortint;
  var W1: Word := CWord;
  var W2: Smallint := CSmallint;
  var D1: DWord := CDword;
  var D2: Longint := CLongint;
  var D3: Cardinal := CCardinal;
  var Q1: QWord := CQword;
  var Q2: Int64 := CInt64;
  var D4: DWord := CHex;

  Expect(B1, [$41], 10);
  Expect(B2, [$42], 11);
  Expect(W1, [$48, $49], 12);
  Expect(W2, [$6E, $6F], 13);
  Expect(D1, [$61, $62, $63, $64], 14);
  Expect(D2, [$41, $42, $43, $44], 15);
  Expect(D3, [$52, $49, $46, $46], 16);
  Expect(Q1, [$31, $32, $33, $34, $35, $36, $37, $38], 17);
  Expect(Q2, [$61, $62, $63, $64, $65, $66, $67, $68], 18);
  Expect(D4, [$DE, $AD, $BE, $EF], 19);
  Expect(GDword, [$61, $62, $63, $64], 20);
  Expect(GQword, [$31, $32, $33, $34, $35, $36, $37, $38], 21);
  CheckInline;
  WriteLn('DELPHI_TB0728_OK');
end.
