program database_blob_stream_semantic;

{$mode delphi}{$H+}
uses SysUtils, Classes, Variants, DB, BufDataset, SQLDB, SQLite3Conn, SQLite3Dyn, MSSQLConn, MySQL80Conn;

type
  TInputStream = class(TMemoryStream)
  public
    RefuseRead: Boolean;
    function Read(var Buffer; Count: Longint): Longint; override;
  end;

  TSqlServer = class(TMSSQLConnection);
  TMySQL = class(TMySQL80Connection);

function TInputStream.Read(var Buffer; Count: Longint): Longint;
begin
  if RefuseRead then Exit(0);
  Result := inherited Read(Buffer, Count);
end;

procedure Check(OK: Boolean; const Detail: string);
begin
  if not OK then raise Exception.Create(Detail);
end;

procedure CheckBytes(const Bytes, Expected: TBytes);
begin
  Check(Length(Bytes) = Length(Expected), 'wrong byte count');
  if Length(Bytes) > 0 then Check(CompareMem(Pointer(Bytes), Pointer(Expected), Length(Bytes)), 'wrong bytes');
end;

procedure CheckParameter;
var
  Params, SavedParams: TParams;
  Param: TParam;
  Stream: TInputStream;
  Bytes, Buffer: TBytes;
  Snapshot: Variant;
  BlobType: TFieldType;
  N, I: Integer;
begin
  Params := TParams.Create(nil);
  SavedParams := TParams.Create(nil);
  Stream := TInputStream.Create;
  try
    Param := Params.CreateParam(ftBlob, 'blob', ptInput);
    for BlobType in [ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftOraBlob] do
      for N in TArray<Integer>.Create(0, 1, 3, 63, 64, 65, 256, 65536) do
        begin
        SetLength(Bytes, N);
        for I := 0 to N - 1 do Bytes[I] := (I * 31 + $41) and $ff;
        Stream.Size := 0;
        if N > 0 then Stream.WriteBuffer(Bytes[0], N);
        Param.LoadFromStream(Stream, BlobType);
        Check((Stream.Position = N) and Param.Bound and not Param.IsNull and (Param.DataType = BlobType), 'state');
        Check(VarType(Param.Value) = (varArray or varByte), 'binary Variant');
        Check(Param.GetDataSize = N, 'GetDataSize');
        CheckBytes(Param.AsBlob, Bytes);
        SetLength(Buffer, N + 2);
        FillChar(Buffer[0], N + 2, $aa);
        Param.GetData(@Buffer[1]);
        Check((Buffer[0] = $aa) and (Buffer[N + 1] = $aa), 'GetData guards');
        SavedParams.Assign(Params);
        Check(SavedParams.IsEqual(Params), 'equal binary values');
        if N = 0 then Continue;
        Check(CompareMem(@Buffer[1], Pointer(Bytes), N), 'GetData payload');
        Snapshot := Param.Value;
        Bytes[0] := Bytes[0] xor $ff;
        Stream.Position := 0;
        Stream.WriteBuffer(Bytes[0], N);
        Param.LoadFromStream(Stream, BlobType);
        Check(not SavedParams.IsEqual(Params), 'unequal binary values');
        Check((Integer(Snapshot[0]) = $41) and (SavedParams[0].AsBytes[0] = $41), 'previous value changed');
        Buffer := Param.AsBytes;
        Buffer[0] := 0;
        CheckBytes(Param.AsBytes, Bytes);
        Stream.RefuseRead := True;
        try
          try
            Param.LoadFromStream(Stream, ftBlob);
            raise Exception.Create('missing EReadError');
          except
            on EReadError do Check((Param.DataType = BlobType) and Param.Bound, 'failed read changed metadata');
          end;
        finally
          Stream.RefuseRead := False;
        end;
        CheckBytes(Param.AsBytes, Bytes);
        end;
    Snapshot := VarArrayCreate([4, 6], varByte);
    Snapshot[4] := $41;
    Snapshot[5] := 0;
    Snapshot[6] := $ff;
    Param.DataType := ftBlob;
    Param.Value := Snapshot;
    CheckBytes(Param.AsBytes, TBytes.Create($41, 0, $ff));
    Check(Param.GetDataSize = 3, 'nonzero lower bound');
    Param.Value := AnsiString('old');
    Check((VarType(Param.Value) = varString) and (Param.AsString = 'old'), 'explicit string Variant');
    Param.Clear;
    Check(Param.IsNull, 'NULL');
  finally
    Stream.Free;
    SavedParams.Free;
    Params.Free;
  end;
end;

procedure CheckFieldAndFile;
var
  Params: TParams;
  Param: TParam;
  DataSet: TBufDataset;
  Bytes: TBytes;
  FileName: string;
  Stream: TFileStream;
begin
  FileName := GetTempFileName;
  Params := TParams.Create(nil);
  DataSet := TBufDataset.Create(nil);
  try
    Bytes := TBytes.Create($41, 0, $ff);
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
    Param := Params.CreateParam(ftBlob, 'p', ptInput);
    Param.LoadFromFile(FileName, ftBlob);
    DataSet.FieldDefs.Add('payload', ftBlob);
    DataSet.FieldDefs.Add('limited', ftVarBytes, 3);
    DataSet.CreateDataset;
    DataSet.Append;
    Param.AssignToField(DataSet.Fields[0]);
    CheckBytes(DataSet.Fields[0].AsBytes, Bytes);
    Param.Assign(DataSet.Fields[0]);
    CheckBytes(Param.AsBytes, Bytes);
    Param.AssignFromField(DataSet.Fields[0]);
    CheckBytes(Param.AsBytes, Bytes);
    Param.DataType := ftBytes;
    CheckBytes(Param.AsBytes, Bytes);
    Param.DataType := ftVarBytes;
    CheckBytes(Param.AsBytes, Bytes);
    Param.AsBlob := TBytes.Create(1, 0, 2, 3, 4);
    Param.AssignToField(DataSet.Fields[1]);
    CheckBytes(DataSet.Fields[1].AsBytes, TBytes.Create(1, 0, 2));
    Param.Clear;
    Param.AssignToField(DataSet.Fields[0]);
    Check(DataSet.Fields[0].IsNull, 'NULL field');
  finally
    DataSet.Free;
    Params.Free;
    DeleteFile(FileName);
  end;
end;

procedure CheckDrivers;
var
  Connection: TSQLite3Connection;
  Transaction: TSQLTransaction;
  Query: TSQLQuery;
  MSSQL: TSqlServer;
  MySQL: TMySQL;
  Stream: TBytesStream;
  Param: TParam;
  Bytes: TBytes;
  Hex: string;
  N, I: Integer;
begin
  {$ifdef MSWINDOWS}SQLiteDefaultLibrary := 'winsqlite3.dll';{$else}SQLiteDefaultLibrary := 'libsqlite3.so.0';{$endif}
  Connection := TSQLite3Connection.Create(nil);
  Transaction := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  MSSQL := TSqlServer.Create(nil);
  MySQL := TMySQL.Create(nil);
  try
    Connection.DatabaseName := ':memory:';
    Transaction.Database := Connection;
    Query.Database := Connection;
    Query.Transaction := Transaction;
    Query.SQL.Text := 'select typeof(:p) as kind, hex(:p) as payload';
    for N in TArray<Integer>.Create(0, 1, 3, 256) do
      begin
      SetLength(Bytes, N);
      Hex := '';
      for I := 0 to N - 1 do
        begin
        Bytes[I] := (I * 31 + $41) and $ff;
        Hex := Hex + IntToHex(Bytes[I], 2);
        end;
      Param := Query.Params.ParamByName('p');
      Stream := TBytesStream.Create(Bytes);
      try
        Param.LoadFromStream(Stream, ftBlob);
      finally
        Stream.Free;
      end;
      Query.Open;
      Check((Query.Fields[0].AsString = 'blob') and (Query.Fields[1].AsString = Hex), 'SQLite bind');
      Check(MSSQL.GetAsSQLText(Param) = '0x' + Hex, 'SQL Server literal');
      Check(MySQL.GetAsSQLText(Param) = 'X''' + Hex + '''', 'MySQL binary literal');
      Query.Close;
      end;
    Param.AsBlob := BytesOf(AnsiString('printable payload'));
    Check(MySQL.GetAsSQLText(Param) = '_binary''printable payload''', 'MySQL printable literal');
  finally
    MySQL.Free;
    MSSQL.Free;
    Query.Free;
    Transaction.Free;
    Connection.Free;
  end;
end;

begin
  CheckParameter;
  CheckFieldAndFile;
  CheckDrivers;
  WriteLn('DATABASE_BLOB_STREAM_PASS');
end.
