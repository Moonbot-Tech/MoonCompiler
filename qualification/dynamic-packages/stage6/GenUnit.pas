unit GenUnit;

{ A package unit that uses what the RTL package contains:
  - a generic list and a managed record: the inlined System helpers they
    expand into reach InitializeRecord and the RTTIFlattenInitialize table,
    implementation symbols of System the RTL package did not export;
  - a kernel32 routine System also calls (GetCurrentProcessId): its import
    thunk was resolved in the RTL package, which does not export it, and the
    package did not load (STATUS_ENTRYPOINT_NOT_FOUND);
  - Rtti. }

{$mode delphi}

interface

function Describe: string;

implementation

uses
  SysUtils, Classes, Generics.Collections, Rtti;

type
  TItem = class
  public
    Name: string;
    constructor Create(const AName: string);
  end;

  TItemInfo = record
    Name: string;
    Tags: array of string;
  end;

function GetCurrentProcessId: Cardinal; stdcall; external 'kernel32.dll' name 'GetCurrentProcessId';

constructor TItem.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
end;

function Describe: string;
var
  List: TObjectList<TItem>;
  Infos: TList<TItemInfo>;
  Info: TItemInfo;
  Context: TRttiContext;
begin
  List := TObjectList<TItem>.Create;
  Infos := TList<TItemInfo>.Create;
  try
    List.Add(TItem.Create('a'));
    List.Add(TItem.Create('b'));
    Info := Default(TItemInfo);
    Info.Name := 'info';
    SetLength(Info.Tags, 2);
    Infos.Add(Info);
    Context := TRttiContext.Create;
    Result := Format('%d %s %d %s %d', [List.Count, Infos[0].Name, Length(Infos[0].Tags),
      Context.GetType(TItem).Name, Ord(GetCurrentProcessId <> 0)]);
  finally
    Infos.Free;
    List.Free;
  end;
end;

end.