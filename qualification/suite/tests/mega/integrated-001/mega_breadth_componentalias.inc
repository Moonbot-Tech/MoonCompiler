{ A saved form migrates from its former class name to the canonical registration. }

type
  TBreadthCurrentRoute = class(TComponent)
  private
    FQuota: Int64;
    FCaption: UnicodeString;
  published
    property Quota: Int64 read FQuota write FQuota;
    property Caption: UnicodeString read FCaption write FCaption;
  end;

procedure RunBreadthComponentAlias;
const
  LegacyName = 'TBreadthRetiredRoute';
  Frame: AnsiString = 'object MigratedRoute: TBreadthRetiredRoute'#10 +
    '  Quota = 730000000031'#10 +
    '  Caption = ''prior route'''#10 +
    'end'#10;
var
  Source, Binary: TMemoryStream;
  Loaded, Reopened: TBreadthCurrentRoute;
begin
  Source := TMemoryStream.Create;
  Binary := nil;
  Loaded := nil;
  Reopened := nil;
  RegisterClass(TBreadthCurrentRoute);
  try
    RegisterClassAlias(TBreadthCurrentRoute, LegacyName);
    Check(GetClass(LegacyName) = TBreadthCurrentRoute, 'breadth-component-alias-finds-renamed-class');
    Binary := TMemoryStream.Create;
    Source.WriteBuffer(Frame[1], Length(Frame));
    Source.Position := 0;
    ObjectTextToBinary(Source, Binary);
    Binary.Position := 0;
    Loaded := Binary.ReadComponent(nil) as TBreadthCurrentRoute;
    Check((Loaded.Name = 'MigratedRoute') and (Loaded.Quota = 730000000031) and (Loaded.Caption = 'prior route'),
      'breadth-component-alias-loads-old-form-into-new-class');

    Loaded.Quota := OpaqueI(-810000000047);
    Loaded.Caption := 'saved ' + #$03BB;
    Binary.Clear;
    Binary.WriteComponent(Loaded);
    UnRegisterClass(TBreadthCurrentRoute);
    RegisterClass(TBreadthCurrentRoute);
    Check(GetClass(LegacyName) = nil, 'breadth-component-alias-unregister-removes-former-name');
    Binary.Position := 0;
    Reopened := Binary.ReadComponent(nil) as TBreadthCurrentRoute;
    Check((Reopened.Name = 'MigratedRoute') and (Reopened.Quota = -810000000047) and (Reopened.Caption = 'saved ' + #$03BB),
      'breadth-component-alias-export-reopens-with-only-canonical-name');
    Mix(UInt64(Reopened.Quota));
  finally
    UnRegisterClass(TBreadthCurrentRoute);
    FreeAndNil(Reopened);
    FreeAndNil(Loaded);
    FreeAndNil(Binary);
    FreeAndNil(Source);
  end;
end;
