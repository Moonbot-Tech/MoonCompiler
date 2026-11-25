{ Roll back a temporary settings edit, select a new checkpoint, or commit the active values. }

type
  TBreadthRecallSettings = class(TPersistent)
  public
    Ticket: Int64;
    Caption: UnicodeString;
    procedure Assign(Source: TPersistent); override;
  end;

procedure TBreadthRecallSettings.Assign(Source: TPersistent);
begin
  If Source is TBreadthRecallSettings then begin
    Ticket := TBreadthRecallSettings(Source).Ticket;
    Caption := TBreadthRecallSettings(Source).Caption;
  end else
    inherited Assign(Source);
end;

procedure RunBreadthSettingsRecall;
var
  Active: TBreadthRecallSettings;
  Checkpoint: TRecall;
  Cancelled: Boolean;
begin
  Active := TBreadthRecallSettings.Create;
  try
    Active.Ticket := OpaqueI(580000000013);
    Active.Caption := 'base' + #0 + #$03BB;
    Cancelled := False;
    try
      Checkpoint := TRecall.Create(TBreadthRecallSettings.Create, Active);
      try
        Active.Ticket := -17;
        Active.Caption[1] := 'B';
        raise EAbort.Create('cancel preview');
      finally
        FreeAndNil(Checkpoint);
      end;
    except
      on E: EAbort do Cancelled := E.Message = 'cancel preview';
    end;
    Check(Cancelled and (Active.Ticket = 580000000013) and (Active.Caption = 'base' + #0 + #$03BB),
      'breadth-recall-restores-managed-settings-during-exception-unwind');

    Checkpoint := TRecall.Create(TBreadthRecallSettings.Create, Active);
    try
      Check(Checkpoint.Reference = Active, 'breadth-recall-exposes-the-active-settings-owner');
      Active.Ticket := OpaqueI(-680000000021);
      Active.Caption := 'staged';
      Checkpoint.Store;
      Active.Ticket := 23;
      Active.Caption := 'preview';
    finally
      FreeAndNil(Checkpoint);
    end;
    Check((Active.Ticket = -680000000021) and (Active.Caption = 'staged'),
      'breadth-recall-store-replaces-the-rollback-checkpoint');

    Checkpoint := TRecall.Create(TBreadthRecallSettings.Create, Active);
    try
      Active.Ticket := OpaqueI(870000000019);
      Active.Caption := 'committed' + #$20AC;
      Checkpoint.Forget;
      Check(Checkpoint.Reference = nil, 'breadth-recall-forget-detaches-the-active-settings');
    finally
      FreeAndNil(Checkpoint);
    end;
    Check((Active.Ticket = 870000000019) and (Active.Caption = 'committed' + #$20AC),
      'breadth-recall-forgotten-checkpoint-keeps-committed-settings');
    Mix(UInt64(Active.Ticket));
  finally
    FreeAndNil(Active);
  end;
end;
