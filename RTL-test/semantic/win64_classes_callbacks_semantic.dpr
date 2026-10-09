program win64_classes_callbacks_semantic;
{%TARGET=win64}
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.Math, Winapi.Windows;
type
  TReceiver = class
    Calls: Integer;
    Bias: NativeInt;
    procedure Receive(var Msg: TMessage);
  end;
var
  A, B: TReceiver;
  P, Q: Pointer;
  W: HWND;
  I: Integer;
  FreeBytes, TotalBytes: TLargeInteger;
  X: Double;
procedure TReceiver.Receive(var Msg: TMessage);
begin
  If Msg.Msg = WM_USER + 17 then begin
    Inc(Calls);
    If (Msg.WParam <> WPARAM($123456789)) or (Msg.LParam <> LPARAM(-1234567890123)) then
      raise Exception.Create('Truncated message arguments');
    Msg.Result := LRESULT($123456789AB) + Bias;
  end;
end;
begin
  SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX);
  A := TReceiver.Create;
  B := TReceiver.Create;
  try
    B.Bias := 7;
    P := MakeObjectInstance(A.Receive);
    Q := MakeObjectInstance(B.Receive);
    try
      If CallWindowProcW(P, 0, WM_USER + 17, $123456789, -1234567890123) <> $123456789AB then
        raise Exception.Create('First callback result');
      If CallWindowProcW(Q, 0, WM_USER + 17, $123456789, -1234567890123) <> $123456789B2 then
        raise Exception.Create('Second callback instance');
    finally
      FreeObjectInstance(Q);
      FreeObjectInstance(P);
    end;
    for I := 1 to 32 do begin
      W := AllocateHWnd(A.Receive);
      try
        If not IsWindow(W) then
          raise Exception.Create('Hidden window missing');
        If SendMessageW(W, WM_USER + 17, $123456789, -1234567890123) <> $123456789AB then
          raise Exception.Create('Hidden window callback');
      finally
        DeallocateHWnd(W);
      end;
      If IsWindow(W) then
        raise Exception.Create('Hidden window leaked');
    end;
    If (A.Calls <> 33) or (B.Calls <> 1) then
      raise Exception.Create('Callback identity/count');
    X := 123.45;
    If (Max(0, X) <> X) or (Min(X, 500) <> X) then
      raise Exception.Create('Windows unit shadows Math');
    If not Assigned(SysUtils.GetDiskFreeSpaceEx) or
       not SysUtils.GetDiskFreeSpaceEx(PChar(GetCurrentDir), FreeBytes, TotalBytes, nil) or
       (TotalBytes <= 0) or (FreeBytes < 0) then
      raise Exception.Create('Unicode disk-space API');
  finally
    B.Free;
    A.Free;
  end;
  WriteLn('WIN64_CLASSES_CALLBACKS_PASS');
end.
