program stream_adapter_copy_semantic;
{$ifdef FPC}{$mode delphi}{$endif}
{$apptype console}
uses Classes, SysUtils, {$ifdef FPC}Types{$else}Winapi.ActiveX{$endif};
type
  TChunked = class(TMemoryStream)
    RefuseRead: Boolean;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;
{$ifdef FPC}
  TTestSink = class(TStreamAdapter)
  public
    Limit: DWord;
    Status: HResult;
    Calls: Integer;
    FailOnCall, PartialErrorCall: Integer;
    function Write(pv: Pointer; cb: DWord; pcbWritten: PDWord): HResult; override; stdcall;
  end;
{$endif}
function TChunked.Read(var Buffer; Count: Longint): Longint;
begin
  if RefuseRead then raise EReadError.Create('read refused');
  if Count>17 then Count:=17;
  Result:=inherited Read(Buffer,Count);
end;
procedure Check(OK: Boolean; const Detail: string);
begin
  if not OK then begin WriteLn('FAIL ',Detail); Halt(1) end;
end;
{$ifdef FPC}
function TTestSink.Write(pv: Pointer; cb: DWord; pcbWritten: PDWord): HResult;
begin
  Inc(Calls);
  if Calls=FailOnCall then raise EWriteError.Create('write refused');
  if Calls=PartialErrorCall then begin
    inherited Write(pv,2,pcbWritten);
    Exit(STG_E_MEDIUMFULL);
  end;
  if Status<0 then begin
    pcbWritten^:=0;
    Exit(Status);
  end;
  if cb>Limit then cb:=Limit;
  Result:=inherited Write(pv,cb,pcbWritten);
  if Result=0 then Result:=Status;
end;
{$endif}
var
  Input, Output: TMemoryStream;
  S,D: IStream;
  Bytes: array[0..3076] of Byte;
  R,W: UInt64;
  Status: HResult;
  I: Integer;
{$ifdef FPC}
  Sink: TTestSink;
{$endif}
begin
  Input:=TChunked.Create;
  Output:=TMemoryStream.Create;
  try
    for I:=0 to High(Bytes) do Bytes[I]:=Byte((I*37+11) and 255);
    Input.WriteBuffer(Bytes,SizeOf(Bytes));
    Input.Position:=0;
    S:=TStreamAdapter.Create(Input);
    D:=TStreamAdapter.Create(Output);
    Status:=S.CopyTo(D,0,R,W);
    Check((Status=0) and (R=0) and (W=0) and (Input.Position=0),'zero request');
    Status:=S.CopyTo(D,5,R,W);
    Check((Status=0) and (R=5) and (W=5) and (Output.Size=5),'bounded copy');
    Status:=S.CopyTo(D,High(UInt64),R,W);
    Check((Status=0) and (R=SizeOf(Bytes)-5) and (W=R) and (Output.Size=SizeOf(Bytes)),'copy remainder at EOF');
    Check(CompareMem(Output.Memory,@Bytes[0],SizeOf(Bytes)),'identical bytes');
    Status:=S.CopyTo(D,1,R,W);
    Check((Status=0) and (W=0) and (R=0),'empty source');
{$ifdef FPC}
    Input.Position:=0;
    Output.Size:=0;
    Output.Position:=0;
    Sink:=TTestSink.Create(Output);
    Sink.Limit:=3;
    D:=Sink;
    Status:=S.CopyTo(D,20,R,W);
    Check((Status=0) and (Sink.Calls>1) and (W=20) and (R=20) and (Output.Size=20) and
      CompareMem(Output.Memory,@Bytes[0],20),'partial writes retain tail');
    Sink.Limit:=0;
    Check(S.CopyTo(D,1,R,W)=STG_E_MEDIUMFULL,'writer made no progress');
    Sink.Status:=STG_E_REVERTED;
    Check(S.CopyTo(D,1,R,W)=STG_E_REVERTED,'destination HRESULT propagated');
    Check(S.CopyTo(nil,1,R,W)=STG_E_INVALIDPOINTER,'missing destination');
    Check(S.CopyTo(nil,0,R,W)=0,'zero request has no destination access');
    Sink.Status:=0;
    Sink.Limit:=5;
    Check(S.CopyTo(D,5,PUInt64(nil)^,PUInt64(nil)^)=0,'optional count pointers');
    Sink.PartialErrorCall:=Sink.Calls+1;
    Check((S.CopyTo(D,8,R,W)=STG_E_MEDIUMFULL) and (R=8) and (W=2),'partial failure on first write');
    Sink.Limit:=3;
    Sink.PartialErrorCall:=Sink.Calls+2;
    Check((S.CopyTo(D,8,R,W)=STG_E_MEDIUMFULL) and (R=8) and (W=5),'partial failure on second write');
    Sink.Status:=S_FALSE;
    Check((S.CopyTo(D,7,R,W)=S_OK) and (R=7) and (W=7),'successful partial writes normalize status');
    Check(S.CopyTo(D,4,R,W)=S_OK,'successful full write normalizes status');
    Sink.FailOnCall:=Sink.Calls+2;
    Sink.Limit:=3;
    Check((S.CopyTo(D,7,R,W)=E_UNEXPECTED) and (R=7) and (W=3),'exception after three written bytes');
    Sink.FailOnCall:=Sink.Calls+1;
    Check(S.CopyTo(D,1,R,W)=E_UNEXPECTED,'write exception is reported through HRESULT');
{$endif}
    TChunked(Input).RefuseRead:=True;
    Check(S.CopyTo(D,1,R,W)=HResult($8000FFFF),'read exception is reported through HRESULT');
  finally
    S:=nil; D:=nil;
    Output.Free; Input.Free;
  end;
  WriteLn('STREAM_ADAPTER_COPY_PASS');
end.
