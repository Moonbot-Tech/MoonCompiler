program sdk2410_ini;

{$mode delphi}{$H+}

uses {$IF defined(UNIX) and (SIZEOF(Char)=1)}cwstring,{$ENDIF} SysUtils, Classes, IniFiles;

type
  TVirtualIni = class(TMemIniFile)
    IntegerCalls, StringCalls, LastDefault, Forced: Integer;
    function ReadInteger(const Section, Ident: string; Default: Longint): Longint; override;
    function ReadString(const Section, Ident, Default: string): string; override;
  end;

function TVirtualIni.ReadInteger(const Section, Ident: string; Default: Longint): Longint;
begin
  Inc(IntegerCalls);
  LastDefault:=Default;
  Result:=Forced;
end;

function TVirtualIni.ReadString(const Section, Ident, Default: string): string;
begin
  Inc(StringCalls);
  Result:='bad';
end;

var Checks: Integer;

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Condition then raise Exception.Create('INI_FAIL: '+Name);
end;

procedure Matrix(Ini: TCustomIniFile);
const
  Inputs: array[0..24] of string = ('0','1','2','-1','-42','+2','00','01','10','$0','$10','0x0','0x10',
    ' 2 ','','true','True','false','yes','no','1bad','0bad','2147483648','-2147483649','999999999999999999999');
  Values: array[0..12] of Boolean = (False,True,True,True,True,True,False,True,True,False,True,False,True);
var I: Integer; D: Boolean; Expected: Boolean;
begin
  For D:=False to True do begin
    Check(Ini.ReadBool('missing','missing',D)=D,'missing default');
    For I:=0 to High(Inputs) do begin
      Ini.WriteString('section','key',Inputs[I]);
      If I<=High(Values) then Expected:=Values[I]
      else If I=13 then Expected:=Ini.ReadInteger('section','key',Ord(D))<>0
      else Expected:=D;
      Check(Ini.ReadBool('section','key',D)=Expected,'input '+IntToStr(I)+' default '+IntToStr(Ord(D)));
    end;
    Ini.WriteBool('section','key',D);
    Check(Ini.ReadString('section','key','')=IntToStr(Ord(D)),'WriteBool numeric');
    Check(Ini.ReadBool('section','key',not D)=D,'WriteBool roundtrip');
  end;
  Ini.Options:=Ini.Options+[ifoWriteStringBoolean];
  Ini.WriteBool('section','key',True);
  Check(Ini.ReadString('section','key','')='true','explicit text WriteBool');
  Check(Ini.ReadBool('section','key',False),'explicit text read');
  Ini.WriteString('section','key','FALSE');
  Check(not Ini.ReadBool('section','key',True),'explicit text false');
  Ini.WriteString('section','key','yes');
  Check(Ini.ReadBool('section','key',True),'explicit text invalid default');
  Ini.SetBoolStringValues(True,['yes','да']);
  Ini.SetBoolStringValues(False,['no','нет']);
  Ini.WriteString('section','key','YES');
  Check(Ini.ReadBool('section','key',False),'explicit true list');
  Ini.WriteString('section','key','NO');
  Check(not Ini.ReadBool('section','key',True),'explicit false list');
  Ini.WriteString('section','key','1');
  Check(not Ini.ReadBool('section','key',False),'explicit list overrides numeric');
  Ini.Options:=Ini.Options-[ifoWriteStringBoolean];
  Ini.WriteString('section','key','yes');
  Check(Ini.ReadBool('section','key',False),'explicit list without writer option');
end;

procedure VirtualRoute;
var Ini: TVirtualIni; D: Boolean; I: Integer;
begin
  Ini:=TVirtualIni.Create('');
  try
    For D:=False to True do
      For I:=-1 to 2 do begin
        Ini.Forced:=I;
        Check(Ini.ReadBool('section','key',D)=(I<>0),'virtual integer result');
        Check(Ini.LastDefault=Ord(D),'virtual integer default');
      end;
    Check((Ini.IntegerCalls=8) and (Ini.StringCalls=0),'single virtual integer route');
  finally
    Ini.Free;
  end;
end;

var Ini: TCustomIniFile; F: string;
begin
  try
    F:=ExpandFileName('sdk2410_ini_test.ini');
    Ini:=TIniFile.Create(F);
    try
      Matrix(Ini);
    finally
      Ini.Free;
      DeleteFile(F);
    end;
    Ini:=TMemIniFile.Create('');
    try
      Matrix(Ini);
    finally
      Ini.Free;
    end;
    VirtualRoute;
    Writeln('INI_PASS checks=',Checks);
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
