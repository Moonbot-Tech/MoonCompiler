program strutils_surface_semantic;

{$mode delphi}{$H+}

uses
  StrUtils;

const
  Text = 'abcabc';

begin
  if RPosEx('b',Text,6)<>5 then Halt(1);
  if RPosEx('z',Text,1)<>0 then Halt(2);
  if RPosEx('z',Text,Length(Text))<>0 then Halt(3);
  if RPosEx('bc',Text,6)<>5 then Halt(4);
  if RPosEx('bc',Text,-1)<>0 then Halt(5);
  WriteLn('STRUTILS_SURFACE_PASS');
end.
