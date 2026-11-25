{ Rewrite the selected profile through a helper emitted by a separately compiled unit. }

function BreadthSelectRoute(var Selected: Integer): Integer;
begin
  Inc(Selected);
  Result := Integer(OpaqueI(1));
end;

procedure RunBreadthRouteProfileHelper;
var
  Profiles: array[0..1] of TBreadthRouteProfile;
  Original, Current: TBreadthRouteProfile;
  Calls: Integer;
begin
  Profiles[0].Ticket := OpaqueI(-930000000071);
  Profiles[0].Caption := 'neighbor';
  Profiles[1].Ticket := OpaqueI(720000000109);
  Profiles[1].Caption := 'primary' + #0 + #$03BB;
  Original := Profiles[1];
  Calls := 0;

  Current := Profiles[BreadthSelectRoute(Calls)].WithSuffix(UnicodeString('::A'), OpaqueI(-110000000010));
  Check((Calls = 1) and (Current.Ticket = 610000000099) and (Current.Caption = 'primary' + #0 + #$03BB + '::A'),
    'breadth-record-helper-inline-scalar-overload-selects-profile-once');
  Current := Current.WithSuffix(['/', #$D83D + #$DE80], OpaqueI(390000000001));
  Check((Current.Ticket = 1000000000100) and (Current.Caption = 'primary' + #0 + #$03BB + '::A/' + #$D83D + #$DE80),
    'breadth-record-helper-open-array-overload-reads-self-before-managed-return-overwrite');
  Current.Caption[1] := 'P';
  Check((Original.Ticket = 720000000109) and (Original.Caption = 'primary' + #0 + #$03BB)
    and (Profiles[1].Caption = Original.Caption) and (Profiles[0].Caption = 'neighbor')
    and (Profiles[0].Ticket = -930000000071), 'breadth-record-helper-preserves-source-and-neighbor-snapshots');
  Mix(UInt64(Current.Ticket));
end;
