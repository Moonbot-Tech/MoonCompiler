program native_blob_bind;
{$mode delphi}{$H+}{$codepage utf8}
uses SysUtils, Classes, DB, SQLDB, IBConnection, MySQL80Conn;

procedure Check(OK: Boolean; const Detail: string);
begin
  if not OK then raise Exception.Create(Detail);
end;

procedure Exercise(Conn: TSQLConnection; MySQL: Boolean);
const
  TextValue = 'Текст café 漢''\';
var
  Tx: TSQLTransaction;
  Q: TSQLQuery;
  Stream: TBytesStream;
  Bytes, Actual, ExpectedText: TBytes;
  N, I, Mode: Integer;
begin
  Tx := TSQLTransaction.Create(nil);
  Q := TSQLQuery.Create(nil);
  try
    ExpectedText := BytesOf(RawByteString(UTF8Encode(TextValue)));
    Tx.Database := Conn;
    Q.Database := Conn;
    Q.Transaction := Tx;
    if not MySQL then
      begin
      Tx.Params.Add('read_committed');
      Tx.Params.Add('rec_version');
      Tx.Params.Add('nowait');
      end;
    Conn.Open;
    if MySQL then Conn.ExecuteDirect('create temporary table blob_probe (b longblob, t longtext)')
    else Conn.ExecuteDirect('create table blob_probe (b blob sub_type binary, t blob sub_type text)');
    Tx.Commit;
    for Mode := 0 to Ord(MySQL) do
      begin
      if MySQL then
        if Mode = 0 then Conn.ExecuteDirect('set session sql_mode = ''''')
        else Conn.ExecuteDirect('set session sql_mode = ''NO_BACKSLASH_ESCAPES''');
      for N in TArray<Integer>.Create(-1, 0, 1, 3, 65535, 65536, 131071) do
        begin
        Conn.ExecuteDirect('delete from blob_probe');
        Q.SQL.Text := 'insert into blob_probe (b,t) values (:b,:t)';
        if N < 0 then
          begin
          Q.ParamByName('b').DataType := ftBlob;
          Q.ParamByName('b').Clear;
          end
        else
          begin
          SetLength(Bytes, N);
          for I := 0 to N - 1 do Bytes[I] := (I * 31 + $41) and $ff;
          Stream := TBytesStream.Create(Bytes);
          try
            Q.ParamByName('b').LoadFromStream(Stream, ftBlob);
          finally
            Stream.Free;
          end;
          end;
        Q.ParamByName('t').AsMemo := TextValue;
        Q.ExecSQL;
        Tx.Commit;
        Q.SQL.Text := 'select b, octet_length(b), t from blob_probe';
        Q.Open;
        Check(not Q.EOF, 'missing row');
        Actual := Q.Fields[2].AsBytes;
        Check((Length(Actual) = Length(ExpectedText)) and
              CompareMem(Pointer(Actual), Pointer(ExpectedText), Length(ExpectedText)), 'stored text bytes');
        Check(Q.Fields[0].IsNull = (N < 0), 'NULL vs empty');
        if N >= 0 then
          begin
          Check(Q.Fields[1].AsInteger = N, 'server byte count');
          Actual := Q.Fields[0].AsBytes;
          Check((Length(Actual) = N) and ((N = 0) or CompareMem(Pointer(Actual), Pointer(Bytes), N)), 'stored bytes');
          end;
        Q.Close;
        end;
      end;
  finally
    Q.Free;
    Tx.Free;
  end;
end;

var
  Conn: TSQLConnection;
  MySQL: Boolean;
begin
  MySQL := ParamStr(1) = 'mysql';
  if MySQL then
    begin
    Conn := TMySQL80Connection.Create(nil);
    Conn.HostName := 'localhost';
    Conn.UserName := 'root';
    Conn.CharSet := 'utf8mb4';
    Conn.DatabaseName := 'mysql';
    end
  else
    begin
    Conn := TIBConnection.Create(nil);
    Conn.DatabaseName := ParamStr(1);
    Conn.UserName := 'SYSDBA';
    Conn.CharSet := 'UTF8';
    end;
  try
    if not MySQL then TIBConnection(Conn).CreateDB;
    Exercise(Conn, MySQL);
    Writeln('NATIVE_BLOB_BIND_PASS ', Conn.ClassName);
  finally
    Conn.Free;
  end;
end.
