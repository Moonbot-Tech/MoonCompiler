program sdk2410_sqlite;

{$mode delphi}{$H+}{$codepage utf8}

uses {$IF defined(UNIX) and (SIZEOF(Char)=1)}cwstring,{$ENDIF} SysUtils, Classes, DB, SQLDB, SQLite3Conn, SQLite3Dyn, ctypes;

type
  TConnectionProbe = class(TSQLite3Connection)
    procedure Exec(const SQL: string);
    function Strings(const SQL: string): TArrayStringArray;
    procedure Indexes(Defs: TIndexDefs; const TableName: string);
  end;
  TOpen = function(Filename: PAnsiChar; DB: PPSQLite3; Flags: cint; VFS: PAnsiChar): cint; cdecl;
  TKey = function(DB: PSQLite3; Key: Pointer; Len: cint): cint; cdecl;
  TEnable = function(DB: PSQLite3; OnOff: cint): cint; cdecl;
  TLoad = function(DB: PSQLite3; FileName, Entry: PAnsiChar; Error: PPAnsiChar): cint; cdecl;
  TPrepare = function(DB: PSQLite3; SQL: PAnsiChar; Len: cint; Stmt: PPSQLite3_Stmt; Tail: PPAnsiChar): cint; cdecl;

const
  UValue: UnicodeString = 'Привет 中文 '+#$D83D#$DE42;
  UTable: UnicodeString = 'таблица_中文';
  UColumn: UnicodeString = 'имя_中文';
  UIndex: UnicodeString = 'индекс_中文';
  UMissing: UnicodeString = 'нет_такой_таблицы_中文';
  UCollation: UnicodeString = 'сравнение_中文';
  UVFS: UnicodeString = 'файловая_система_中文';
  UKey: UnicodeString = 'ключ'+#0+'中文';
  UExtension: UnicodeString = 'каталог/библиотека_中文.so';
var
  Checks: Integer;
  SavedOpen: TOpen;
  SavedKey: TKey;
  SavedEnable: TEnable;
  SavedLoad: TLoad;
  SavedPrepare: TPrepare;
  ExpectedSQL: UTF8String;
  PrepareCalls: Integer;
  GotFilename, GotVFS, GotKey, GotExtension: RawByteString;
  KeyCalls, ExtensionCalls: Integer;

function Text(const S: UnicodeString): string;
begin
  {$IF SIZEOF(Char)=2}
  Result:=S;
  {$ELSE}
  RawByteString(Result):=UTF8Encode(S);
  SetCodePage(RawByteString(Result),DefaultSystemCodePage,False);
  {$ENDIF}
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Condition then raise Exception.Create('SQLITE_FAIL: '+Name);
end;

function SameBytes(const A,B: RawByteString): Boolean;
begin
  Result:=(Length(A)=Length(B)) and ((Length(A)=0) or CompareMem(Pointer(A),Pointer(B),Length(A)));
end;

function PlatformANSI(const Value: UnicodeString): AnsiString; noinline;
begin
  Result:=Value;
end;

function TableSQL(const Prefix: UnicodeString): UnicodeString; noinline;
begin
  Result:=Prefix+'"'+UTable+'"';
end;

procedure TConnectionProbe.Exec(const SQL: string);
begin
  execsql(SQL);
end;

function TConnectionProbe.Strings(const SQL: string): TArrayStringArray;
begin
  Result:=stringsquery(SQL);
end;

procedure TConnectionProbe.Indexes(Defs: TIndexDefs; const TableName: string);
begin
  UpdateIndexDefs(Defs,TableName);
end;

procedure RawExec(DB: PSQLite3; const SQL: UnicodeString);
var S: UTF8String;
begin
  S:=UTF8Encode(SQL);
  Check(sqlite3_exec(DB,PAnsiChar(S),nil,nil,nil)=SQLITE_OK,'raw UTF-8 control');
end;

function RawScalar(DB: PSQLite3; const SQL: UnicodeString): RawByteString;
var S: UTF8String; Stmt: PSQLite3_Stmt; P: PAnsiChar; N: Integer;
begin
  S:=UTF8Encode(SQL);
  Check(sqlite3_prepare(DB,PAnsiChar(S),Length(S),@Stmt,nil)=SQLITE_OK,'raw prepare control: '+Text(UTF8Decode(sqlite3_errmsg(DB)))+' SQL='+Text(SQL));
  try
    Check(sqlite3_step(Stmt)=SQLITE_ROW,'raw result exists');
    P:=sqlite3_column_text(Stmt,0);
    N:=sqlite3_column_bytes(Stmt,0);
    SetString(Result,P,N);
  finally
    sqlite3_finalize(Stmt);
  end;
end;

function OpenHook(Filename: PAnsiChar; DB: PPSQLite3; Flags: cint; VFS: PAnsiChar): cint; cdecl;
begin
  SetString(GotFilename,Filename,StrLen(Filename));
  If VFS=nil then GotVFS:='' else SetString(GotVFS,VFS,StrLen(VFS));
  Result:=SavedOpen(Filename,DB,Flags,nil);
end;

function KeyHook(DB: PSQLite3; Key: Pointer; Len: cint): cint; cdecl;
begin
  Inc(KeyCalls);
  SetString(GotKey,PAnsiChar(Key),Len);
  Result:=SQLITE_OK;
end;

function EnableHook(DB: PSQLite3; OnOff: cint): cint; cdecl;
begin
  Check(OnOff=1,'enable extension flag');
  Result:=SQLITE_OK;
end;

function LoadHook(DB: PSQLite3; FileName, Entry: PAnsiChar; Error: PPAnsiChar): cint; cdecl;
begin
  Inc(ExtensionCalls);
  SetString(GotExtension,FileName,StrLen(FileName));
  Check(Entry=nil,'default extension entry');
  Result:=SQLITE_OK;
end;

function PrepareHook(DB: PSQLite3; SQL: PAnsiChar; Len: cint; Stmt: PPSQLite3_Stmt; Tail: PPAnsiChar): cint; cdecl;
var Actual: RawByteString;
begin
  Inc(PrepareCalls);
  Check(Len=Length(ExpectedSQL)+1,'prepare length includes terminator');
  SetString(Actual,SQL,Length(ExpectedSQL));
  Check(SameBytes(Actual,ExpectedSQL),'prepare UTF-8 exact bytes');
  Check(SQL[Length(ExpectedSQL)]=#0,'prepare buffer terminated');
  Result:=SavedPrepare(DB,SQL,Len,Stmt,Tail);
end;

procedure PrepareBoundaries(C: TConnectionProbe);
var I: Integer; SQL: UnicodeString;
begin
  SavedPrepare:=sqlite3_prepare;
  try
    sqlite3_prepare:=PrepareHook;
    For I:=0 to 3 do begin
      case I of
        0: SQL:='create table prep_short(i)';
        1: SQL:='create table "подготовка_中文"("данные" varchar(100))';
        2: SQL:='create table prep_first(i); create table prep_second(i)';
        3: SQL:='create table prep_nul(i);'+#0+'create table prep_after_nul(i)';
      end;
      ExpectedSQL:=UTF8Encode(SQL);
      C.ExecuteDirect(Text(SQL));
    end;
  finally
    sqlite3_prepare:=SavedPrepare;
  end;
  Check(PrepareCalls=4,'prepare all controls reached');
  Check(RawScalar(C.Handle,'select count(*) from sqlite_master where name in (''prep_short'',''prep_first'',''prep_nul'',''подготовка_中文'')')='4','prepared SQL first statement effects');
  Check(RawScalar(C.Handle,'select count(*) from sqlite_master where name in (''prep_second'',''prep_after_nul'')')='0','SQL tail and embedded NUL unchanged');
end;

procedure Data(C: TConnectionProbe; T: TSQLTransaction);
var Q: TSQLQuery; B: TBytes; Defs: TIndexDefs; Rows: TArrayStringArray; L: TStringList; Actual: RawByteString; SQL: UnicodeString;
begin
  SQL:=TableSQL('create table ');
  SQL:=SQL+'("'+UColumn+'" varchar(100), w nvarchar(100), m text, b blob)';
  C.ExecuteDirect(Text(SQL));
  Q:=TSQLQuery.Create(nil);
  Defs:=TIndexDefs.Create(nil);
  L:=TStringList.Create;
  try
    Q.Database:=C;
    Q.Transaction:=T;
    SQL:=TableSQL('insert into ');
    Q.SQL.Text:=Text(SQL+' values(:text,:wide,:memo,:blob)');
    {$IF SIZEOF(Char)=2}
    Q.Params[0].AsString:=Text(UValue);
    {$ELSE}
    Q.Params[0].AsUTF8String:=UTF8Encode(UValue);
    {$ENDIF}
    Q.Params[1].AsWideString:=UValue;
    {$IF SIZEOF(Char)=2}
    Q.Params[2].AsMemo:=Text(UValue);
    {$ELSE}
    Q.Params[2].AsUTF8String:=UTF8Encode(UValue);
    Q.Params[2].DataType:=ftMemo;
    {$ENDIF}
    B:=TBytes.Create($00,$80,$FF,$01,$00,$42,$7F);
    Q.Params[3].AsBlob:=B;
    Q.ExecSQL;
    Actual:=RawScalar(C.Handle,TableSQL('select hex(b) from '));
    Check(Actual='0080FF0100427F','odd binary exact bytes: '+string(Actual));
    Check(SameBytes(RawScalar(C.Handle,TableSQL('select * from ')),UTF8Encode(UValue)),'UTF-8 parameter stored');
    Check(SameBytes(RawScalar(C.Handle,TableSQL('select w from ')),UTF8Encode(UValue)),'UTF-16 parameter stored');
    Q.Close;
    Q.SQL.Text:=Text(TableSQL('select * from '));
    Q.Open;
    {$IF SIZEOF(Char)=2}
    Check(Q.Fields[0].FieldName=Text(UColumn),'Unicode column name');
    {$ELSE}
    Check(SameBytes(Q.Fields[0].FieldName,UTF8Encode(UColumn)),'UTF-8 column name bytes');
    {$ENDIF}
    {$IF SIZEOF(Char)=2}
    Check(Q.Fields[0].AsWideString=UValue,'UTF-8 field decoded');
    {$ELSE}
    Check(Q.Fields[0].AsUTF8String=UTF8Encode(UValue),'UTF-8 field bytes');
    {$ENDIF}
    Check(Q.Fields[1].AsWideString=UValue,'wide field decoded');
    Check(Q.Fields[2].AsWideString=UValue,'memo field decoded');
    Check(Length(Q.Fields[3].AsBytes)=Length(B),'blob field length');
    Check(CompareMem(@Q.Fields[3].AsBytes[0],@B[0],Length(B)),'blob field bytes');
    Q.Close;
    SQL:='create index "';
    SQL:=SQL+UIndex+'" on "'+UTable+'"("'+UColumn+'")';
    C.Exec(Text(SQL));
    SQL:='"';
    C.Indexes(Defs,Text(SQL+UTable+'"'));
    Check(Defs.Count=1,'metadata index count');
    {$IF SIZEOF(Char)=2}
    Check((Defs[0].Name=Text(UIndex)) and (Defs[0].Fields=Text(UColumn)),'metadata index names');
    {$ELSE}
    Check(SameBytes(Defs[0].Name,UTF8Encode(UIndex)) and SameBytes(Defs[0].Fields,UTF8Encode(UColumn)),'metadata UTF-8 index bytes');
    {$ENDIF}
    C.GetFieldNames(Text(UTable),L);
    {$IF SIZEOF(Char)=2}
    Check((L.Count=4) and (L[0]=Text(UColumn)),'schema field names');
    {$ELSE}
    Check((L.Count=4) and SameBytes(L[0],PlatformANSI(UColumn)),'schema ANSI profile field names');
    {$ENDIF}
    SQL:='select "';
    SQL:=SQL+UColumn+'",NULL,'''' from "'+UTable+'"';
    Rows:=C.Strings(Text(SQL));
    {$IF SIZEOF(Char)=2}
    Check((Length(Rows)=1) and (Rows[0][0]=Text(UValue)),'callback Unicode value');
    {$ELSE}
    Check((Length(Rows)=1) and SameBytes(Rows[0][0],UTF8Encode(UValue)),'callback UTF-8 value bytes');
    {$ENDIF}
    Check((Rows[0][1]='') and (Rows[0][2]=''),'callback nil and empty strings');
    T.Commit;
    T.StartTransaction;
    SQL:=TableSQL('insert into ');
    C.Exec(Text(SQL+'(b) values(x''00'')'));
    T.Rollback;
    Check(RawScalar(C.Handle,TableSQL('select count(*) from '))='1','transaction commit rollback');
  finally
    L.Free;
    Defs.Free;
    Q.Free;
  end;
end;

procedure BindBoundaries(C: TConnectionProbe; T: TSQLTransaction);
var Q: TSQLQuery; I: Integer; Actual: RawByteString;
begin
  RawExec(C.Handle,'create table bounds(t text,w text,b blob)');
  Q:=TSQLQuery.Create(nil);
  try
    Q.Database:=C;
    Q.Transaction:=T;
    Q.SQL.Text:='insert into bounds values(:t,:w,:b)';
    For I:=0 to 2 do begin
      If I=0 then begin
        Q.Params[0].AsString:='';
        Q.Params[1].AsWideString:='';
        Q.Params[2].AsBlob:=nil;
      end else If I=1 then begin
        Q.Params[0].AsString:='A'+#0+'B';
        Q.Params[1].AsWideString:='A'+#0+'B';
        Q.Params[2].AsBlob:=TBytes.Create(0,1,0,255,128);
      end else begin
        Q.Params[0].Clear;
        Q.Params[1].Clear;
        Q.Params[2].Clear;
      end;
      Q.ExecSQL;
    end;
    Actual:=RawScalar(C.Handle,'select typeof(t)||'',''||typeof(w)||'',''||typeof(b) from bounds where rowid=1');
    Check(Actual='text,text,blob','empty differs from NULL: '+string(Actual));
    Check(RawScalar(C.Handle,'select hex(t)||'',''||hex(w)||'',''||hex(b) from bounds where rowid=2')='410042,410042,000100FF80','embedded NUL byte lengths');
    Check(RawScalar(C.Handle,'select typeof(t)||'',''||typeof(w)||'',''||typeof(b) from bounds where rowid=3')='null,null,null','NULL stays NULL');
  finally
    Q.Free;
  end;
end;

procedure Errors(C: TConnectionProbe);
var Raised: Boolean; SQL: UnicodeString;
begin
  Raised:=False;
  try
    SQL:='select * from "';
    C.ExecuteDirect(Text(SQL+UMissing+'"'));
  except
    on E: ESQLDatabaseError do begin
      Raised:=True;
      Check(Pos(Text(UMissing),E.Message)>0,'prepare UTF-8 error decoded');
    end;
  end;
  Check(Raised,'prepare failure reached');
  Raised:=False;
  try
    SQL:='select * from "';
    C.Exec(Text(SQL+UMissing+'"'));
  except
    on E: EDatabaseError do begin
      Raised:=True;
      Check(Pos(Text(UMissing),E.Message)>0,'exec UTF-8 error decoded');
    end;
  end;
  Check(Raised,'exec failure reached');
  Raised:=False;
  try
    SQL:='select * from "';
    C.ExecuteDirect(Text(SQL+UMissing+'%s"'));
  except
    on E: ESQLDatabaseError do begin
      Raised:=True;
      Check((E.ErrorCode=SQLITE_ERROR) and (Pos(Text(UMissing)+'%s',E.Message)>0),'literal percent preserved in native error');
    end;
  end;
  Check(Raised,'percent identifier failure reached');
end;

procedure Collation(C: TConnectionProbe);
var SQL: UnicodeString;
begin
  C.CreateCollation(Text(UCollation),0);
  SQL:='select case when ''a'' < ''b'' collate "';
  Check(RawScalar(C.Handle,SQL+UCollation+'" then ''yes'' else ''no'' end')='yes','Unicode collation registered and invoked');
end;

procedure Hooks;
var C: TConnectionProbe;
begin
  SavedOpen:=sqlite3_open_v2;
  SavedKey:=sqlite3_key;
  SavedEnable:=sqlite3_enable_load_extension;
  SavedLoad:=sqlite3_load_extension;
  C:=TConnectionProbe.Create(nil);
  try
    sqlite3_open_v2:=OpenHook;
    sqlite3_key:=KeyHook;
    sqlite3_enable_load_extension:=EnableHook;
    sqlite3_load_extension:=LoadHook;
    C.DatabaseName:=':memory:';
    C.VFS:=Text(UVFS);
    C.Password:=Text(UKey);
    C.Open;
    Check(SameBytes(GotVFS,UTF8Encode(UVFS)),'VFS UTF-8 bytes');
    Check((KeyCalls=1) and SameBytes(GotKey,UTF8Encode(UKey)),'key byte length includes NUL');
    C.LoadExtension(Text(UExtension));
    Check((ExtensionCalls=1) and SameBytes(GotExtension,UTF8Encode(UExtension)),'extension UTF-8 filename');
  finally
    C.Free;
    sqlite3_open_v2:=SavedOpen;
    sqlite3_key:=SavedKey;
    sqlite3_enable_load_extension:=SavedEnable;
    sqlite3_load_extension:=SavedLoad;
  end;
end;

procedure FileNames;
var C: TConnectionProbe; F: string;
begin
  F:=ExpandFileName('sdk2410_'+Text(UValue)+'.sqlite');
  C:=TConnectionProbe.Create(nil);
  try
    C.DatabaseName:=F;
    C.CreateDB;
    Check(FileExists(F),'CreateDB Unicode filename');
    C.Open;
    RawExec(C.Handle,'create table file_ok(i)');
    C.Close;
    C.OpenFlags:=[sofReadOnly];
    C.Open;
    Check(RawScalar(C.Handle,'select count(*) from file_ok')='0','reopen UTF-8 filename');
    C.Close;
    C.DropDB;
    Check(not FileExists(F),'DropDB Unicode filename');
  finally
    C.Free;
    DeleteFile(F);
  end;
end;

var C: TConnectionProbe; T: TSQLTransaction; Group: string;
begin
  try
    {$IFDEF MSWINDOWS}SQLiteDefaultLibrary:='winsqlite3.dll';{$ELSE}SQLiteDefaultLibrary:='libsqlite3.so.0';{$ENDIF}
    InitializeSQLite;
    try
      C:=TConnectionProbe.Create(nil);
      T:=TSQLTransaction.Create(nil);
      try
        T.Database:=C;
        T.Options:=[];
        C.DatabaseName:=':memory:';
        C.Open;
        RawExec(C.Handle,'create table raw_control(i integer)');
        Group:=ParamStr(1);
        If (Group='') or (Group='data') then Data(C,T);
        If (Group='') or (Group='bind') then BindBoundaries(C,T);
        If (Group='') or (Group='errors') then Errors(C);
        If (Group='') or (Group='collation') then Collation(C);
        If (Group='') or (Group='prepare') then PrepareBoundaries(C);
        If (Group='') or (Group='hooks') then Hooks;
        {$IF SIZEOF(Char)=2}
        If (Group='') or (Group='files') then FileNames;
        {$ENDIF}
        Check(Checks>3,'fixture ran');
        Writeln('SQLITE_PASS checks=',Checks);
      finally
        T.Free;
        C.Free;
      end;
    finally
      ReleaseSQLite;
    end;
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
