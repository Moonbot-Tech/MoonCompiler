program tracker_so_04;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

type
  ITracked = interface ['{84F55ED3-E50D-442E-87F7-35C9E769EAAA}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TTrackedArray = array of ITracked;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure ExerciseList;
var List: TList<TTrackedArray>; OldValue, NewValue: TTrackedArray;
begin
  List := TList<TTrackedArray>.Create;
  try
    OldValue := TTrackedArray.Create(TTracked.Create); List.Add(OldValue); OldValue := nil;
    NewValue := TTrackedArray.Create(TTracked.Create); List[0] := NewValue; NewValue := nil;
    Check(TTracked.Alive = 1, 'replacement-release');
  finally List.Free; end;
end;

procedure Run;
begin
ExerciseList; Check(TTracked.Alive = 0, 'final-release');
end;

begin
  try
    Run;
    WriteLn('PASS SO-04');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-04: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
