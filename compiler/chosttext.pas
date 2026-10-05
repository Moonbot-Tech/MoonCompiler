{
    Copyright (c) 2026 by MoonCompiler contributors

    Host text boundaries for the compiler and its command-line frontend.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, see <https://www.gnu.org/licenses/>.
}
unit chosttext;

{$mode objfpc}{$H+}

interface

var
  SourceSystemCodePage: TSystemCodePage;

function HostEnvironmentVariable(const Name: AnsiString): AnsiString;
function HostOptionsCodePage(const FileName: AnsiString): TSystemCodePage;
procedure ReadHostOptionsLine(var F: Text; out Line: AnsiString; var CodePage: TSystemCodePage; FirstLine: Boolean);

implementation

uses SysUtils;

function HostEnvironmentVariable(const Name: AnsiString): AnsiString;
begin
{$ifdef windows}
  Result:=AnsiString(SysUtils.GetEnvironmentVariable(UnicodeString(Name)));
{$else}
  Result:=SysUtils.GetEnvironmentVariable(Name);
{$endif}
end;

function HostOptionsCodePage(const FileName: AnsiString): TSystemCodePage;
begin
  if SameText(ExtractFileExt(FileName),'.mooncompiler') then
    Result:=CP_UTF8
  else
    Result:=SourceSystemCodePage;
end;

procedure ReadHostOptionsLine(var F: Text; out Line: AnsiString; var CodePage: TSystemCodePage; FirstLine: Boolean);
{$ifdef windows}
var
  Bytes: RawByteString;
{$endif}
begin
{$ifdef windows}
  { Read bytes before choosing their encoding: legacy configs use the host
    source code page, project files use UTF-8, and a BOM overrides either. }
  SetTextCodePage(F,CP_NONE);
  ReadLn(F,Bytes);
  if FirstLine and (Copy(Bytes,1,3)=#$EF#$BB#$BF) then
    begin
      Delete(Bytes,1,3);
      CodePage:=CP_UTF8;
    end;
  SetCodePage(Bytes,CodePage,false);
  Line:=Bytes;
{$else}
  ReadLn(F,Line);
{$endif}
end;

initialization
  { Windows file and process names use UTF-8 internally. Pascal source and
    byte character semantics retain the original host ANSI code page. }
  SourceSystemCodePage:=DefaultSystemCodePage;
{$ifdef windows}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
{$endif}
end.
