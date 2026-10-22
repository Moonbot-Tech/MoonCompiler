{%MainUnit rcparser.pas}
{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2008 by Giulio Bernardi

    Resource parser includes

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$IFDEF INC_HEADER}

type
  tyinclude = class
  const
    yi_maxlevels = 5;
  var
    stack: array[0..yi_maxlevels] of record
      yyinput           : Text;        (* input and output file *)
      yyline            : AnsiString;      (* current input line *)
      yylineno, yycolno : Integer;     (* current input position *)
      fn                : AnsiString;
      prev_wrap         : yywrap_t;
    end;
    level: integer;
    WorkDir: string;
    SearchPaths: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    class function wrapone(): Boolean; static;
    function push(const incfile: UnicodeString): Boolean;
    function pop(): Boolean;
    function expand(raw: string): UnicodeString;
  end;

var
  yinclude: tyinclude;

{$ELSE}

class function tyinclude.wrapone(): Boolean;
begin
  Result:= yinclude.pop;
end;

function tyinclude.push(const incfile: UnicodeString): Boolean;
begin
  if level > High(stack) then
    raise EParserError.Create('Too many include levels');
  stack[level].yyinput:= yyinput;
  stack[level].yyline:= yyline;
  stack[level].yylineno:= yylineno;
  stack[level].yycolno:= yycolno;
  stack[level].prev_wrap:= yywrap;
  stack[level].fn:= yyfilename;
  inc(level);
  yywrap:= @tyinclude.wrapone;
  AssignFile(yyinput, incfile);
  Reset(yyinput);
  yyfilename:= incfile;
  yyline:= '';
  yylineno:= 0;
  yycolno:= 0;
  {$if declared(ypreproc)}
  ypreproc.newfile(yyfilename);
  {$endif}
  Result:= true;
end;

function tyinclude.pop(): Boolean;
begin
  Close(yyinput);
  Result:= level = 0;
  if not Result then begin
    Dec(level);
    yyinput:= stack[level].yyinput;
    yyline:= stack[level].yyline;
    yylineno:= stack[level].yylineno;
    yycolno:= stack[level].yycolno;
    yywrap:= stack[level].prev_wrap;
    yyfilename:= stack[level].fn;
    {$if declared(ypreproc)}
    ypreproc.newfile(yyfilename);
    {$endif}
  end;
end;

function tyinclude.expand(raw: string): UnicodeString;
var
  i: integer;
  fn, f: UnicodeString;
begin
  widestringmanager.Ansi2UnicodeMoveProc(PAnsiChar(raw), opt_code_page, fn, Length(raw));
  fn:= NormalizeResourcePath(fn);
  if Length(fn) > 2 then begin
    if (fn[1] = '<') and (fn[length(fn)] = '>') then begin
      fn:= copy(fn, 2, Length(fn)-2);
      if CharInSet(fn[1], AllowDirectorySeparators) then
        Delete(fn, 1, 1);
      for i:= 0 to SearchPaths.Count - 1 do begin
        f:= UnicodeString(IncludeTrailingPathDelimiter(SearchPaths[i])) + fn;
        if FileExists(f) then
          Exit(f);
      end;
      raise EParserError.Create('Include file not found on search paths: <'+fn+'>');
    end
    else if (fn[1] = '"') and (fn[length(fn)] = '"') then begin
      fn:= copy(fn, 2, Length(fn)-2);
      if CharInSet(fn[1], AllowDirectorySeparators) then
        Delete(fn, 1, 1);
      f:= UnicodeString(IncludeTrailingPathDelimiter(WorkDir)) + fn;
      if FileExists(f) then
        Exit(f);
      if fn = 'windows.h' then begin
        // treat windows.h as an alias for windres.h
        f:= ConcatPaths([WorkDir, 'windres.h']);
        if FileExists(f) then
          Exit(f);
      end;
      raise EParserError.Create('Include file not found: "'+fn+'"');
    end;
  end;
  raise EParserError.Create('Invalid include directive: "'+fn+'"');
end;

constructor tyinclude.Create;
begin
  inherited Create;
  level:= 0;
  WorkDir:= GetCurrentDir;
  SearchPaths:= TStringList.Create;
end;

destructor tyinclude.Destroy;
begin
  FreeAndNil(SearchPaths);
  inherited;
end;

{$ENDIF}

