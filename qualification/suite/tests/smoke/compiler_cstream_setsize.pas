program compiler_cstream_setsize;
{$mode objfpc}{$H+}

uses
  cstreams, SysUtils;

var
  Stream: TCFileStream;
  Data: array[0..7] of Byte;
  SeekError: Longint;

begin
  FillChar(Data, SizeOf(Data), 65);
  Stream:=TCFileStream.Create('compiler_cstream_setsize.bin', fmCreate);
  try
    Stream.WriteBuffer(Data, SizeOf(Data));
    Stream.Position:=2;
    Stream.Size:=-1;
    SeekError:=CStreamError;
    If (SeekError=0) or (Stream.Size<>SizeOf(Data)) or (Stream.Position<>2) then
      Halt(1);
    Stream.Size:=4;
    If (CStreamError<>0) or (Stream.Size<>4) then
      Halt(2);
    Stream.Position:=0;
    FillChar(Data, SizeOf(Data), 0);
    Stream.ReadBuffer(Data, 4);
    If (Data[0]<>65) or (Data[3]<>65) then
      Halt(3);
  finally
    Stream.Free;
    DeleteFile('compiler_cstream_setsize.bin');
  end;
  Writeln('COMPILER_CSTREAM_SETSIZE_OK');
end.
