{$ifndef ALLPACKAGES}
{$mode objfpc}{$H+}
program fpmake;

uses {$ifdef unix}cthreads,{$endif} fpmkunit;

Var
  P : TPackage;
  T : TTarget;
begin
  With Installer do
    begin
{$endif ALLPACKAGES}

    P:=AddPackage('libpcre');
    P.ShortName:='pcre';
{$ifdef ALLPACKAGES}
    P.Directory:=ADirectory;
{$endif ALLPACKAGES}
    P.Version:='3.3.1';
    P.Author := 'Library: PCRE';
    P.License := 'Library: BSD License, header: LGPL with modification, ';
    P.HomepageURL := 'www.freepascal.org';
    P.Email := '';
    P.Description := 'Headers for the PCRE (Perl Compatible Regular Expressions) library';
    P.NeedLibC:= true;  // true for headers that indirectly link to libc?
    P.OSes :=  [Win64,Linux,darwin];

    P.SourcePath.Add('src');
    P.IncludePath.Add('src');

    T:=P.Targets.AddUnit('libpcre2_8.pp');
      with T.Dependencies do
        begin
          AddInclude('pcreconsts.inc');
        end;
    T:=P.Targets.AddUnit('libpcre2_16.pp');
    T.OSes:=[Win64,Linux];
      with T.Dependencies do
        begin
          AddInclude('pcreconsts.inc');
        end;
    T:=P.Targets.AddUnit('libpcre2_32.pp');
    T.OSes:=[Win64,Linux];
    P.ObjectPath.Add('native/x86_64-win64',[Win64]);
    P.ObjectPath.Add('native/x86_64-linux',[Linux]);
    P.InstallFiles.Add('native/x86_64-win64/libmoonpcre2.a',[Win64],'$(unitinstalldir)');
    P.InstallFiles.Add('native/x86_64-win64/libmoonpcre_os.a',[Win64],'$(unitinstalldir)');
    P.InstallFiles.Add('native/x86_64-linux/libmoonpcre2.a',[Linux],'$(unitinstalldir)');
    T:=P.Targets.AddUnit('moon.internal.pcre2.pp',[Win64,Linux]);
    T.Dependencies.AddInclude('pcreconsts.inc');
    P.ExamplePath.Add('examples');
    P.Targets.AddExampleProgram('tpcre.pp');
    P.NamespaceMap:='namespaces.lst';

{$ifndef ALLPACKAGES}
    Run;
    end;
end.
{$endif ALLPACKAGES}
