program rtl_api_release231_contracts;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$codepage utf8}{$ENDIF}
uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
  SysUtils, Classes, IOUtils
{$IFDEF LINUX}
  , BaseUnix, Posix.Unistd, Posix.Fcntl, Posix.Stdio
{$ENDIF}
  ;

procedure Check(Value: Boolean; const Msg: string);
begin
  If not Value then
    raise Exception.Create(Msg);
end;

type
  TCall = procedure;
  TCallWithArguments = procedure(A,B,C,D,E,F,G,H: NativeInt); cdecl;
  TTrackedObject = class(TInterfacedObject)
    destructor Destroy; override;
  end;
  TFaultThread = class(TThread)
    Passed: Boolean;
    procedure Execute; override;
  end;
{$IFDEF LINUX}
  TFifoWriter = class(TThread)
    Path: UTF8String;
    Passed: Boolean;
    procedure Execute; override;
  end;
{$ENDIF}

var
  Destroyed: Integer;

destructor TTrackedObject.Destroy;
begin
  InterlockedIncrement(Destroyed);
  inherited Destroy;
end;

procedure CallAddress(Address: Pointer); {$IFDEF FPC}noinline;{$ENDIF}
var
  Call: TCall;
begin
  Call:=TCall(Address);
  Call();
end;

procedure ReadAddress(Address: Pointer); {$IFDEF FPC}noinline;{$ENDIF}
var
  Value: Integer;
begin
  Value:=PInteger(Address)^;
  Check(Value=73,'unexpected accessible fault address');
end;

procedure CallWithOwnedLocal(Address: Pointer); {$IFDEF FPC}noinline;{$ENDIF}
var
  Ref: IInterface;
  Call: TCallWithArguments;
begin
  Ref:=TTrackedObject.Create;
  Call:=TCallWithArguments(Address);
  Call(1,2,3,4,5,6,7,8);
  Check(Assigned(Ref),'owned local');
end;

procedure CheckFaults;
var
  I, Finalized, Caught, BeforeDestroyed: Integer;
  Keep: string;
  NonExecutable: Pointer;
begin
  Caught:=0;
  Finalized:=0;
  Keep:='managed value across unwind';
  for I:=0 to 3 do
    try
      try
        If I<2 then
          CallAddress(Pointer(NativeUInt(I)))
        else
          ReadAddress(Pointer(NativeUInt(I-2)));
        Check(False,'fault returned normally');
      finally
        Inc(Finalized);
        Check(Keep='managed value across unwind','managed local after fault');
      end;
    except
      on E: EAccessViolation do
        Inc(Caught);
    end;
  Check((Caught=4) and (Finalized=4),'invalid call/data faults and finally');
  try
    try
      CallAddress(nil);
    except
      on E: EAccessViolation do
        raise;
    end;
  except
    on E: EAccessViolation do
      Inc(Caught);
  end;
  Check(Caught=5,'reraise after invalid call');
  BeforeDestroyed:=Destroyed;
  try
    CallWithOwnedLocal(nil);
  except
    on E: EAccessViolation do
      Inc(Caught);
  end;
  Check((Caught=6) and (Destroyed=BeforeDestroyed+1),'stack arguments and managed cleanup');
  GetMem(NonExecutable,32);
  try
    FillChar(NonExecutable^,32,0);
    try
      CallAddress(NonExecutable);
    except
      on E: EAccessViolation do
        Inc(Caught);
    end;
  finally
    FreeMem(NonExecutable);
  end;
  Check(Caught=7,'non-executable call target');
end;

procedure TFaultThread.Execute;
begin
  try
    CheckFaults;
    Passed:=True;
  except
    Passed:=False;
  end;
end;

{$IFDEF LINUX}
procedure TFifoWriter.Execute;
var
  FD, I: Integer;
  Block: array[0..4095] of Byte;
begin
  FillChar(Block,SizeOf(Block),$A5);
  FD:=__open(PAnsiChar(Path),O_WRONLY);
  If FD<0 then
    Exit;
  try
    for I:=1 to 20 do
      If __write(FD,@Block,SizeOf(Block))<>SizeOf(Block) then
        Exit;
    Passed:=True;
  finally
    __close(FD);
  end;
end;

procedure CheckPosixAndPseudoFiles(const FileName: string);
var
  Bytes: TBytes;
  TextFile: Text;
  WordValue: string;
  Path, Renamed, Fifo: UTF8String;
  Writer: TFifoWriter;
  I: Integer;
begin
  { These must still denote System routines with Posix units last in uses. }
  AssignFile(TextFile,FileName);
  Rewrite(TextFile);
  Write(TextFile,'pascal');
  Close(TextFile);
  Reset(TextFile);
  Read(TextFile,WordValue);
  Close(TextFile);
  Check(WordValue='pascal','Pascal I/O is not hidden by POSIX imports');
  Path:=UTF8Encode(FileName);
  Renamed:=Path+'.renamed';
  Check(__rename(PAnsiChar(Path),PAnsiChar(Renamed))=0,'POSIX rename');
  Check(__rename(PAnsiChar(Renamed),PAnsiChar(Path))=0,'POSIX rename back');
  Check(__open('/moon-nonexistent-rtl-api-file',O_RDONLY)=-1,'POSIX open two arguments');
  Check(__close(-1)=-1,'POSIX close invalid descriptor');
  Bytes:=TFile.ReadAllBytes('/proc/self/status');
  Check((Length(Bytes)>0) and (Pos('Name:',TEncoding.UTF8.GetString(Bytes))>0),'procfs byte stream');
  Check(Pos('Name:',TFile.ReadAllText('/proc/self/status'))>0,'procfs text stream');
  Check(Length(TFile.ReadAllLines('/proc/self/status'))>0,'procfs line stream');
  Check(Length(TFile.ReadAllBytes('/dev/null'))=0,'zero-sized device');
  try
    TFile.ReadAllBytes('/proc/self/mem');
    Check(False,'failed read must not become an empty result');
  except
    on E: EReadError do ;
  end;
  Fifo:=Path+'.fifo';
  Check(fpMkFifo(PAnsiChar(Fifo),&600)=0,'create FIFO');
  Writer:=TFifoWriter.Create(True);
  try
    Writer.Path:=Fifo;
    Writer.Start;
    Bytes:=TFile.ReadAllBytes(string(Fifo));
    Writer.WaitFor;
    Check(Writer.Passed and (Length(Bytes)=81920),'nonseekable multi-chunk input');
    for I:=0 to High(Bytes) do
      Check(Bytes[I]=$A5,'FIFO bytes preserved');
  finally
    Writer.Free;
    DeleteFile(string(Fifo));
  end;
end;
{$ENDIF}

procedure CheckFileReplacement(const Path: string);
var
  Source, Backup: string;
{$IFDEF MSWINDOWS}
  Locked: TFileStream;
{$ENDIF}
  I: Integer;
  Raised: Boolean;
begin
  Source:=Path+'.'+#$4E2D+'.source';
  Backup:=Path+'.'+#$0416+'.backup';
  try
    for I:=0 to 3 do
      begin
      TFile.WriteAllText(Source,'new');
      TFile.WriteAllText(Path,'old');
      If Odd(I) then
        TFile.WriteAllText(Backup,'stale backup')
      else
        DeleteFile(Backup);
{$IFDEF MSWINDOWS}
      If I>=2 then
        TFile.Replace(Source,Path,Backup,I=3)
      else
{$ENDIF}
        TFile.Replace(Source,Path,Backup);
      Check(not FileExists(Source),'replacement consumes source');
      Check(TFile.ReadAllText(Path)='new','replacement publishes new contents');
      Check(TFile.ReadAllText(Backup)='old','replacement backs up original contents');
      end;
    Raised:=False;
    try
      TFile.Replace(Source,Path,Backup);
    except
      on E: EFileNotFoundException do Raised:=True;
    end;
    Check(Raised and (TFile.ReadAllText(Path)='new'),'missing source raises without altering destination');
    TFile.WriteAllText(Source,'next');
    Raised:=False;
    try
      TFile.Replace(Source,Path+'.missing',Backup);
    except
      on E: EFileNotFoundException do Raised:=True;
    end;
    Check(Raised and FileExists(Source),'missing destination leaves source');
    Raised:=False;
    try
      TFile.Replace(Source,Path,'');
    except
      on E: EInOutArgumentException do Raised:=True;
    end;
    Check(Raised and FileExists(Source),'empty backup is invalid');
    Raised:=False;
    try
      TFile.Replace(Source,Path,Path+'.missing'+PathDelim+'backup');
    except
      on E: EDirectoryNotFoundException do Raised:=True;
    end;
    Check(Raised and (TFile.ReadAllText(Path)='new'),'backup failure preserves destination');
    Raised:=False;
    try
      TFile.Copy(Source,Path);
    except
      on E: EInOutError do Raised:=True;
    end;
    Check(Raised and (TFile.ReadAllText(Path)='new'),'copy must not silently ignore existing destination');
    TFile.Copy(Source,Path,True);
    Check((TFile.ReadAllText(Path)='next') and FileExists(Source),'copy overwrite preserves source');
{$IFDEF MSWINDOWS}
    Locked:=TFileStream.Create(Path,fmOpenRead or fmShareExclusive);
    try
      Raised:=False;
      try
        TFile.Replace(Source,Path,Backup);
      except
        on E: EInOutError do Raised:=True;
      end;
      Check(Raised,'native replacement failure raises a file I/O exception');
    finally
      Locked.Free;
    end;
    Check((TFile.ReadAllText(Path)='next') and FileExists(Source),'sharing failure preserves both files');
{$ENDIF}
{$IFDEF LINUX}
    DeleteFile(Backup);
    Check(fpLink(PAnsiChar(UTF8Encode(Source)),PAnsiChar(UTF8Encode(Backup)))=0,'create hard-link alias');
    Raised:=False;
    try
      TFile.Replace(Source,Path,Backup);
    except
      on E: EInOutError do Raised:=True;
    end;
    Check(Raised and (TFile.ReadAllText(Source)='next'),'backup cannot alias replacement source');
    DeleteFile(Backup);
    Check(fpSymLink(PAnsiChar(UTF8Encode(Path)),PAnsiChar(UTF8Encode(Backup)))=0,'create symlink alias');
    Raised:=False;
    try
      TFile.Replace(Source,Path,Backup);
    except
      on E: EInOutError do Raised:=True;
    end;
    Check(Raised and (TFile.ReadAllText(Path)='next'),'backup cannot alias destination');
    Raised:=False;
    try
      TFile.Copy('/proc/self/mem',Path,True);
    except
      on E: EReadError do Raised:=True;
    end;
    Check(Raised,'copy surfaces a read error');
{$ENDIF}
  finally
    DeleteFile(Source);
    DeleteFile(Backup);
  end;
end;

var
  Path: string;
  Bytes, Actual: TBytes;
  Sizes: array[0..5] of Integer = (0,1,16383,16384,16385,70001);
  I, N: Integer;
  Worker: TFaultThread;
begin
  CheckFaults;
  Worker:=TFaultThread.Create(True);
  try
    Worker.Start;
    Worker.WaitFor;
    Check(Worker.Passed,'thread fault recovery');
  finally
    Worker.Free;
  end;
  Path:=GetTempFileName;
  try
    CheckFileReplacement(Path);
    for N in Sizes do
      begin
      SetLength(Bytes,N);
      for I:=0 to N-1 do
        Bytes[I]:=Byte(I mod 251);
      TFile.WriteAllBytes(Path,Bytes);
      Actual:=TFile.ReadAllBytes(Path);
      Check(Length(Actual)=N,'regular file length');
      If N>0 then
        Check(CompareMem(@Actual[0],@Bytes[0],N),'regular file content');
      end;
    TFile.WriteAllText(Path,'Hello Ж中',TEncoding.UTF8);
    Actual:=TFile.ReadAllBytes(Path);
    Check((Actual[0]=$EF) and (Actual[1]=$BB) and (Actual[2]=$BF),'explicit UTF-8 preamble');
    Check(TFile.ReadAllText(Path)='Hello Ж中','UTF-8 BOM round trip');
    TFile.WriteAllText(Path,'Hello Ж中',TEncoding.Unicode);
    Actual:=TFile.ReadAllBytes(Path);
    Check((Actual[0]=$FF) and (Actual[1]=$FE),'explicit UTF-16 preamble');
    Check(TFile.ReadAllText(Path)='Hello Ж中','UTF-16 BOM round trip');
    TFile.WriteAllText(Path,'Ж',TEncoding.Unicode);
    TFile.AppendAllText(Path,'中');
    Actual:=TFile.ReadAllBytes(Path);
    Check((Length(Actual)=6) and (Actual[4]=$2D) and (Actual[5]=$4E),'append detects UTF-16 LE');
    Check(TFile.ReadAllText(Path)='Ж中','UTF-16 LE append round trip');
    TFile.WriteAllText(Path,'Ж',TEncoding.BigEndianUnicode);
    TFile.AppendAllText(Path,'中');
    Actual:=TFile.ReadAllBytes(Path);
    Check((Length(Actual)=6) and (Actual[4]=$4E) and (Actual[5]=$2D),'append detects UTF-16 BE');
    Check(TFile.ReadAllText(Path)='Ж中','UTF-16 BE append round trip');
    TFile.WriteAllText(Path,'',TEncoding.Unicode);
    Check(Length(TFile.ReadAllBytes(Path))=2,'empty encoded file preserves preamble');
    TFile.WriteAllText(Path,'Ж');
    TFile.AppendAllText(Path,'Ж');
    Actual:=TFile.ReadAllBytes(Path);
    Check((Length(Actual)=4) and (Actual[0]=$D0) and (Actual[1]=$96) and
      (Actual[2]=$D0) and (Actual[3]=$96),'default write and append are UTF-8 without BOM');
    TFile.WriteAllLines(Path,['Hello','Ж中']);
    Actual:=TFile.ReadAllBytes(Path);
    Check(Actual[0]=Ord('H'),'default lines omit BOM');
    Check(TFile.ReadAllLines(Path)[1]='Ж中','UTF-8 line round trip');
    TFile.WriteAllLines(Path,[],TEncoding.Unicode);
    Check(Length(TFile.ReadAllBytes(Path))=2,'empty explicit lines preserve BOM');
    try
      TFile.WriteAllText(Path,'invalid',nil);
      Check(False,'nil encoding accepted');
    except
      on E: EInOutArgumentException do ;
    end;
    try
      TFile.ReadAllText(Path,nil);
      Check(False,'nil read encoding accepted');
    except
      on E: EInOutArgumentException do ;
    end;
    try
      TFile.ReadAllLines(Path,nil);
      Check(False,'nil lines encoding accepted');
    except
      on E: EInOutArgumentException do ;
    end;
{$IFDEF LINUX}
    CheckPosixAndPseudoFiles(Path);
{$ENDIF}
  finally
    DeleteFile(Path);
  end;
  Writeln('RTL_API_RELEASE231_CONTRACTS_OK');
end.
