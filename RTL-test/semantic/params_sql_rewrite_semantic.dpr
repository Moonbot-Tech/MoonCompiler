program params_sql_rewrite_semantic;

uses SysUtils, {$ifdef FPC}DB{$else}Data.DB{$endif};

const
  Source = 'select :X, ''don''''t bind :Q'', :missing, ?, :x';
  Expected = 'select ?, ''don''''t bind :Q'', ?, ?, ?';

{$ifdef FPC}
type
  TObservedParams = class(TParams)
  public
    Calls: Integer;
    function DoParseSQL(const SQL: string; Options: TSQLParseOptions; ParameterStyle: TParamStyle;
      out ParamBinding: TParamBinding; MacroChar: Char; out ReplaceString: string): string; override;
  end;

function TObservedParams.DoParseSQL(const SQL: string; Options: TSQLParseOptions; ParameterStyle: TParamStyle;
  out ParamBinding: TParamBinding; MacroChar: Char; out ReplaceString: string): string;
begin
  Inc(Calls);
  Result:=inherited;
end;
{$endif}

var
  P: {$ifdef FPC}TObservedParams{$else}TParams{$endif};
  Prior: TParam;
{$ifdef FPC}
  Binding: TParamBinding;
{$endif}
begin
  P:={$ifdef FPC}TObservedParams{$else}TParams{$endif}.Create(nil);
  try
    if (P.ParseSQL(Source,False)<>Expected) or (P.Count<>0) then Halt(1);
    Prior:=P.CreateParam(ftInteger,'X',ptInput);
    Prior.AsInteger:=42;
    if (P.ParseSQL(Source,False)<>Expected) or (P.Count<>1) or (P[0]<>Prior) or (Prior.AsInteger<>42) then Halt(2);
{$ifdef FPC}
    if P.Calls<>2 then Halt(3);
    if P.ParseSQL('select :x,:X,:y',True)<>'select ?,?,?' then Halt(4);
    if (P.Count<>2) or (P[0].Name<>'x') or (P[0].ParamType<>ptInput) then Halt(5);
    if P.ParseSQL('select :y,:X,:x',False,True,True,psPostgreSQL,Binding)<>'select $2,$1,$1' then Halt(6);
    if (Length(Binding)<>3) or (Binding[0]<>1) or (Binding[1]<>0) or (Binding[2]<>0) then Halt(7);
    try
      P.ParseSQL('select :missing',False,True,True,psInterbase,Binding);
      Halt(8);
    except
      on EDatabaseError do ;
    end;
{$endif}
  finally
    P.Free;
  end;
  WriteLn('PARAMS_SQL_REWRITE_OK');
end.
