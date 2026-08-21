program widen;

{ Где именно теряется беззнаковость Word: в сведениях о типе, по которым RTL
  выбирает сравниватель, или в самом расширении Word до Integer. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, TypInfo, Generics.Defaults;

{ Тело один в один как в RTL: Generics.Defaults, TCompare.UInt16. }
function LikeRtl(const ALeft, ARight: UInt16): Integer;
begin
  Result := System.Integer(ALeft) - System.Integer(ARight);
end;

var
  W: Word;
  A, B: UInt16;
  Wide: Integer;
begin
  WriteLn('--- type data for Word');
  WriteLn('ordtype = ', Ord(GetTypeData(TypeInfo(Word))^.OrdType),
          '   (otUByte=1 otSWord=2 otUWord=3 otSLong=4 otULong=5, otSByte=0)');
  WriteLn('min     = ', GetTypeData(TypeInfo(Word))^.MinValue);
  WriteLn('max     = ', GetTypeData(TypeInfo(Word))^.MaxValue);
  WriteLn('kind    = ', Ord(PTypeInfo(TypeInfo(Word))^.Kind));

  WriteLn('--- widening Word to Integer');
  W := 65535;
  Wide := Integer(W);
  WriteLn('Integer(W) where W=65535        = ', Wide);
  WriteLn('System.Integer(W)               = ', System.Integer(W));
  W := 40000;
  WriteLn('Integer(W) where W=40000        = ', Integer(W));
  W := 32768;
  WriteLn('Integer(W) where W=32768        = ', Integer(W));

  WriteLn('--- the RTL body, compiled here');
  A := 65535;
  B := 1;
  WriteLn('LikeRtl(65535, 1)               = ', LikeRtl(A, B));
  A := 40000;
  WriteLn('LikeRtl(40000, 1)               = ', LikeRtl(A, B));

  WriteLn('--- what the RTL actually returns');
  WriteLn('TComparer<Word>.Compare(65535,1)= ',
          TComparer<Word>.Default.Compare(65535, 1));
  WriteLn('done');
end.
