program case_stream_bool;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$Z1}
uses SysUtils, Classes;
type
  TMethod = (m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, m16, m17, m18, m19, m20, m21, m22, m23, m24, m25, m26, m27, m28, m29, m30, m31, m32, m33, m34, m35, m36);
  TRequest = class
    Method: TMethod;
    function Dispatch: Integer;
  end;
function TRequest.Dispatch: Integer;
begin
  case Method of
    m0: Result := 0;
    m1: Result := 1;
    m2: Result := 2;
    m3: Result := 3;
    m4: Result := 4;
    m5: Result := 5;
    m6: Result := 6;
    m7: Result := 7;
    m8: Result := 8;
    m9: Result := 9;
    m10: Result := 10;
    m11: Result := 11;
    m12: Result := 12;
    m13: Result := 13;
    m14: Result := 14;
    m15: Result := 15;
    m16: Result := 16;
    m17: Result := 17;
    m18: Result := 18;
    m19: Result := 19;
    m20: Result := 20;
    m21: Result := 21;
    m22: Result := 22;
    m23: Result := 23;
    m24: Result := 24;
    m25: Result := 25;
    m26: Result := 26;
    m27: Result := 27;
    m28: Result := 28;
    m29: Result := 29;
    m30: Result := 30;
    m31: Result := 31;
    m32: Result := 32;
    m33: Result := 33;
    m34: Result := 34;
    m35: Result := 35;
    m36: Result := 36;
  else
    Result := -1;
  end;
end;
{$INLINE ON}
function CheckBoolean(B: Boolean): Integer; inline;
begin
  Result := -77;
  case B of
    False: Result := 7;
    True: Result := 9;
  end;
end;
function CheckByteBool(B: ByteBool): Integer; inline;
begin
  Result := -77;
  case B of
    False: Result := 7;
    True: Result := 9;
  end;
end;
function CheckWordBool(B: WordBool): Integer; inline;
begin
  Result := -77;
  case B of
    False: Result := 7;
    True: Result := 9;
  end;
end;
function CheckLongBool(B: LongBool): Integer; inline;
begin
  Result := -77;
  case B of
    False: Result := 7;
    True: Result := 9;
  end;
end;
var
  Stream: TMemoryStream;
  Request: TRequest;
  I, Expected: Integer;
  Raw: Byte;
begin
  Stream := TMemoryStream.Create;
  Request := TRequest.Create;
  try
    for I := 0 to 255 do begin
      Raw := I;
      Stream.Position := 0;
      Stream.WriteBuffer(Raw, SizeOf(Raw));
      Stream.Position := 0;
      Stream.ReadBuffer(Request.Method, SizeOf(Request.Method));
      If I <= 36 then Expected := I else Expected := -1;
      If Request.Dispatch <> Expected then raise Exception.CreateFmt('Stream dispatch %d', [I]);
    end;
  finally
    Request.Free;
    Stream.Free;
  end;
  If (CheckBoolean(False) <> 7) or (CheckBoolean(True) <> 9) then Halt(2);
  If (CheckByteBool(False) <> 7) or (CheckByteBool(True) <> 9) then Halt(2);
  If (CheckWordBool(False) <> 7) or (CheckWordBool(True) <> 9) then Halt(2);
  If (CheckLongBool(False) <> 7) or (CheckLongBool(True) <> 9) then Halt(2);
  If CheckByteBool(ByteBool(2)) <> 9 then Halt(3);
  If CheckWordBool(WordBool(2)) <> 9 then Halt(3);
  If CheckLongBool(LongBool(2)) <> 9 then Halt(3);
  Writeln('CASE_STREAM_BOOL_PASS');
end.
