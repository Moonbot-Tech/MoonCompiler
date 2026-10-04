program ansistring_compare_semantic;

{ The AnsiString compare helpers (fpc_ansistr_compare / _compare_equal,
  x86-64 fast paths in front of the generic routines): the sign of the
  ordering and the zero of the equality must agree with a byte-by-byte
  reference for every length and mismatch position around the eight-byte
  chunks, the last-chunk overlap and the 64-byte switch to CompareByte;
  nil and shared pointers; strings whose raw code pages differ take the
  generic (translating) path and still answer like a converted compare. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils;

var
  Failures: Integer = 0;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
  begin
    Inc(Failures);
    If Failures <= 20 then
      WriteLn('FAIL ', MessageText);
  end;
end;

function Sign(V: Integer): Integer;
begin
  If V < 0 then Result := -1 else If V > 0 then Result := 1 else Result := 0;
end;

{ the reference: byte order, then length }
function RefCompare(const A, B: UTF8String): Integer;
var
  I, N: Integer;
begin
  N := Length(A);
  If Length(B) < N then N := Length(B);
  for I := 1 to N do
    If A[I] <> B[I] then
      Exit(Sign(Ord(A[I]) - Ord(B[I])));
  Result := Sign(Length(A) - Length(B));
end;

function CmpSign(const A, B: UTF8String): Integer;
begin
  If A < B then Result := -1 else If A > B then Result := 1 else Result := 0;
end;

function Fill(Len: Integer; Seed: Integer): UTF8String;
var
  I: Integer;
begin
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := AnsiChar(Ord('a') + ((I * 7 + Seed) mod 23));
end;

procedure CheckPair(const A, B: UTF8String; const What: string);
var
  R: Integer;
begin
  R := RefCompare(A, B);
  Check(CmpSign(A, B) = R, What + ': order ' + IntToStr(CmpSign(A, B)) + ' expected ' + IntToStr(R));
  Check(CmpSign(B, A) = -R, What + ': reverse order');
  Check((A = B) = (R = 0), What + ': equality');
  Check((B = A) = (R = 0), What + ': reverse equality');
  Check((A <> B) = (R <> 0), What + ': inequality');
end;

procedure Lengths;
var
  Len, Pos: Integer;
  A, B, C: UTF8String;
begin
  for Len := 0 to 140 do
  begin
    A := Fill(Len, 1);
    B := Fill(Len, 1);
    UniqueString(B);
    CheckPair(A, B, 'equal len ' + IntToStr(Len));
    If Len > 0 then
    begin
      C := A + 'z';
      CheckPair(A, C, 'prefix len ' + IntToStr(Len));
      for Pos := 1 to Len do
      begin
        B := A;
        UniqueString(B);
        B[Pos] := AnsiChar(Ord(B[Pos]) xor $40);
        CheckPair(A, B, 'mismatch len ' + IntToStr(Len) + ' at ' + IntToStr(Pos));
      end;
    end;
  end;
end;

procedure Pointers;
var
  A, B, E: UTF8String;
begin
  E := '';
  A := Fill(12, 3);
  B := A;
  Check(A = B, 'shared pointer equal');
  Check(not (A < B) and not (A > B), 'shared pointer order');
  Check(E = '', 'nil = nil');
  Check(not (E < E), 'nil < nil');
  Check(E < A, 'nil < string');
  Check(A > E, 'string > nil');
  Check(not (A < E), 'string < nil');
  Check(E <> A, 'nil <> string');
  Check(A <> E, 'string <> nil');
  Check(not (E = A), 'nil = string');
end;

procedure CodePages;
var
  U, V, W: UTF8String;
begin
  { a string whose dynamic code page differs from the other's takes the
    generic (converting) path; with ASCII content every conversion is
    the identity, so the answers must be the plain byte answers on any
    system code page }
  U := Fill(12, 5);
  V := U;
  UniqueString(V);
  SetCodePage(RawByteString(V), 1251, False);
  Check(StringCodePage(V) = 1251, 'cp1251 set');
  Check(V = U, 'cp1251 = utf8 (same bytes)');
  Check(not (V < U) and not (V > U), 'cp1251 vs utf8 order (same bytes)');
  W := U + 'z';
  SetCodePage(RawByteString(W), 1251, False);
  Check(U < W, 'cp1251 vs utf8 order (prefix)');
  Check(W > U, 'cp1251 vs utf8 reverse order (prefix)');
  Check(W <> U, 'cp1251 <> utf8 (prefix)');
  { a placeholder code page (CP_ACP) translates to the default one }
  V := U;
  UniqueString(V);
  SetCodePage(RawByteString(V), 0, False);
  Check(StringCodePage(V) = 0, 'placeholder page set');
  Check(V = U, 'placeholder page equal');
  V[3] := AnsiChar(Ord(V[3]) + 1);
  Check(U < V, 'placeholder page order');
  Check(V <> U, 'placeholder page inequality');
end;

begin
  Lengths;
  Pointers;
  CodePages;
  If Failures > 0 then
  begin
    WriteLn('ANSISTRING_COMPARE_FAIL ', Failures);
    Halt(1);
  end;
  WriteLn('ANSISTRING_COMPARE_OK');
end.
