program zip;

{$APPTYPE CONSOLE}

{ Write a ZIP archive and read it back with the Delphi TZipFile surface.
  System.Zip is compiled over mORMot (from the mormot directory next to
  toolchain), so this is also the shortest check that the toolchain sees a
  MoonORMot of the version its runtime units require. }

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Zip;

const
  Text = 'MoonCompiler zip example';

begin
  var Path := TPath.Combine(TPath.GetTempPath, 'mooncompiler-example.zip');
  var Archive := TZipFile.Create;
  try
    Archive.Open(Path, zmWrite);
    var Data := TStringStream.Create(Text, TEncoding.UTF8);
    try
      Archive.Add(Data, 'readme.txt', zcDeflate);
      Data.Position := 0;
      Archive.Add(Data, 'copy/readme.txt', zcStored);
    finally
      Data.Free;
    end;
    Archive.Close;

    Archive.Open(Path, zmRead);
    for var Name in Archive.FileNames do begin
      var Bytes: TBytes;
      Archive.Read(Name, Bytes);
      Writeln(Name, ': ', Length(Bytes), ' bytes');
    end;
    var Back: TBytes;
    Archive.Read('readme.txt', Back);
    If TEncoding.UTF8.GetString(Back) = Text then
      Writeln('ZIP_EXAMPLE_OK')
    else
      Writeln('ZIP_EXAMPLE_MISMATCH');
    Archive.Close;
  finally
    Archive.Free;
    DeleteFile(Path);
  end;
end.
