program rtti_parameter_attributes;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.Rtti, System.TypInfo;

type
  TFieldBindingAttribute = class(TCustomAttribute)
  public
    Name: string;
    constructor Create(const AName: string);
  end;

  {$RTTI EXPLICIT METHODS([vcPublic])}
  [TFieldBindingAttribute('owner')]
  TImportJob = class(TPersistent)
  public
    [TFieldBindingAttribute('handler')]
    procedure Accept([TFieldBindingAttribute('incoming')] const InputValue: string);
  end;
  {$RTTI INHERIT}

constructor TFieldBindingAttribute.Create(const AName: string);
begin
  Name := AName;
end;

procedure TImportJob.Accept(const InputValue: string);
begin
end;

var
  Ctx: TRttiContext;
  Job: TRttiType;
  Handler: TRttiMethod;
  Args: TArray<TRttiParameter>;
  Binding: TArray<TCustomAttribute>;
begin
  Ctx := TRttiContext.Create;
  try
    Job := Ctx.GetType(TImportJob);
    Handler := Job.GetMethod('Accept');
    Args := Handler.GetParameters;
    Writeln('class attrs=', Length(Job.GetAttributes), ' handler attrs=', Length(Handler.GetAttributes),
      ' args=', Length(Args));
    If Length(Args) <> 1 then Halt(1);
    Binding := Args[0].GetAttributes;
    Writeln('parameter name=', Args[0].Name, ' attrs=', Length(Binding));
    If Length(Binding) <> 1 then Halt(1);
    Writeln('binding=', TFieldBindingAttribute(Binding[0]).Name);
    If TFieldBindingAttribute(Binding[0]).Name <> 'incoming' then Halt(1);
  finally
    Ctx.Free;
  end;
end.
