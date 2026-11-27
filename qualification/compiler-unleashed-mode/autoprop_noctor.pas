program autoprop_noctor;

{ Auto-property initializers of a class that declares no constructor. The
  compiler gives it an inherited constructor to run them in, but took the
  constructors of the direct parent only: TPersistent declares none, so
  TGroup.Create (TObject.Create, two levels up) left Width at 0. }
{$mode unleashed}

uses
  Classes;

type
  TGroup = class(TPersistent)
  published
    property Width: Integer = 800;
    property Name: string = 'group';
  end;

  TOwner = class(TPersistent)
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Group: TGroup; readonly;
  end;

constructor TOwner.Create;
begin
  inherited Create;
  FGroup := TGroup.Create;
end;

destructor TOwner.Destroy;
begin
  FGroup.Free;
  inherited Destroy;
end;

var
  G: TGroup;
  O: TOwner;
begin
  G := TGroup.Create;
  O := TOwner.Create;
  WriteLn(G.Width, ' ', G.Name, ' ', O.Group.Width);
  O.Free;
  G.Free;
end.