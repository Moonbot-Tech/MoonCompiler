program reader_fixup_registration_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses
{$IFDEF UNIX}cthreads,{$ENDIF}
  System.Classes, System.SysUtils;
type
  TReceiver = class(TComponent)
  private
    FRef: TComponent;
  published
    property Ref: TComponent read FRef write FRef;
  end;
  TWorker = class(TThread)
  public
    ErrorText: string;
    procedure Execute; override;
  end;
  TQuery = class(TThread)
  public
    ErrorText: string;
    procedure Execute; override;
  end;
var
  Workers: array[0..3] of TWorker;
  Query: TQuery;
  StopQueries: LongInt;

procedure TWorker.Execute;
var
  I: Integer;
  Receiver: TReceiver;
  Text: TStringStream;
  Binary: TMemoryStream;
  Reader: TReader;
  Names: TStringList;
begin
  try
    Text := TStringStream.Create('object Receiver: TReceiver' + sLineBreak + 'Ref = Later.Child' + sLineBreak + 'end');
    Binary := TMemoryStream.Create;
    Names := TStringList.Create;
    try
      ObjectTextToBinary(Text, Binary);
      For I := 1 to 2000 do begin
        Receiver := TReceiver.Create(nil);
        try
          Binary.Position := 0;
          Reader := TReader.Create(Binary, 4096);
          try
            Reader.ReadRootComponent(Receiver);
          finally
            Reader.Free;
          end;
          Names.Clear;
          GetFixupReferenceNames(Receiver, Names);
          If Names.CommaText <> 'Later' then
            raise Exception.Create('live receiver reference lost');
        finally
          Receiver.Free;
        end;
      end;
    finally
      Names.Free;
      Binary.Free;
      Text.Free;
    end;
  except
    on E: Exception do
      ErrorText := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TQuery.Execute;
var
  Names: TStringList;
begin
  try
    Names := TStringList.Create;
    try
      While InterlockedCompareExchange(StopQueries, 0, 0) = 0 do begin
        GlobalFixupReferences;
        Names.Clear;
        GetFixupReferenceNames(nil, Names);
      end;
    finally
      Names.Free;
    end;
  except
    on E: Exception do
      ErrorText := E.ClassName + ': ' + E.Message;
  end;
end;

var
  I: Integer;
  Names: TStringList;
begin
  try
    Query := TQuery.Create(True);
    For I := Low(Workers) to High(Workers) do
      Workers[I] := TWorker.Create(True);
    Query.Start;
    For I := Low(Workers) to High(Workers) do
      Workers[I].Start;
    For I := Low(Workers) to High(Workers) do
      Workers[I].WaitFor;
    InterlockedExchange(StopQueries, 1);
    Query.WaitFor;
    If Query.ErrorText <> '' then
      raise Exception.Create('query ' + Query.ErrorText);
    Query.Free;
    For I := Low(Workers) to High(Workers) do begin
      If Workers[I].ErrorText <> '' then
        raise Exception.Create('worker ' + Workers[I].ErrorText);
      Workers[I].Free;
    end;
    Names := TStringList.Create;
    try
      GetFixupReferenceNames(nil, Names);
      If Names.Count <> 0 then
        raise Exception.Create('dead receivers remain');
    finally
      Names.Free;
    end;
    WriteLn('READER_FIXUP_REGISTRATION_PASS');
  except
    on E: Exception do begin
      WriteLn('FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.