{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2022 by Marco van de Voort
        member of the Free Pascal development team.

    Delphi compatibility unit that emulates the C# timespan record

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit system.timespan;

{$mode Delphi}

interface

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.Classes, System.SysUtils;
{$ELSE FPC_DOTTEDUNITS}
uses
  Classes, SysUtils;
{$ENDIF FPC_DOTTEDUNITS}

Type
    TTimeSpan = record
  private
    FTicks: Int64;
  strict private
    function GetDays: Integer;
    function GetHours: Integer;
    function GetMinutes: Integer;
    function GetSeconds: Integer;
    function GetMilliseconds: Integer;
    function GetTotalDays: Double;
    function GetTotalHours: Double;
    function GetTotalMinutes: Double;
    function GetTotalSeconds: Double;
    function GetTotalMilliseconds: Double;
    class function GetScaledInterval(Value: Double; Scale: Integer): TTimeSpan; static;
    class constructor Create;
  strict private class var
    FMinValue: TTimeSpan;
    FMaxValue: TTimeSpan;
    FZero: TTimeSpan;
  strict private const
    MillisecondsPerTick = 0.0001;
    SecondsPerTick = 1e-07;
    MinutesPerTick = 1.6666666666666667E-09;
    HoursPerTick = 2.7777777777777777E-11;
    DaysPerTick = 1.1574074074074074E-12;
    MillisPerSecond = 1000;
    MillisPerMinute = 60 * MillisPerSecond;
    MillisPerHour = 60 * MillisPerMinute;
    MillisPerDay = 24 * MillisPerHour;
    MaxSeconds = 922337203685;
    MinSeconds = -922337203685;
    MaxMilliseconds = 922337203685477;
    MinMilliseconds = -922337203685477;
  public const
    TicksPerMillisecond = 10000;
    TicksPerSecond = 1000 * Int64(TicksPerMillisecond);
    TicksPerMinute = 60 * Int64(TicksPerSecond);
    TicksPerHour = 60 * Int64(TicksPerMinute);
    TicksPerDay = 24 * TIcksPerHour;
  public
    constructor Create(ATicks: Int64); overload;
    constructor Create(Hours, Minutes, Seconds: Integer); overload;
    constructor Create(Days, Hours, Minutes, Seconds: Integer); overload;
    constructor Create(Days, Hours, Minutes, Seconds, Milliseconds: Integer); overload;
    function Add(const TS: TTimeSpan): TTimeSpan; overload;
    function Duration: TTimeSpan;
    function Negate: TTimeSpan;
    function Subtract(const TS: TTimeSpan): TTimeSpan; overload;
    function ToString: string;

    class function FromDays(Value: Double): TTimeSpan; static;
    class function FromHours(Value: Double): TTimeSpan; static;
    class function FromMinutes(Value: Double): TTimeSpan; static;
    class function FromSeconds(Value: Double): TTimeSpan; static;
    class function FromMilliseconds(Value: Double): TTimeSpan; static;
    class function FromTicks(Value: Int64): TTimeSpan; static;
    class function Subtract(const D1, D2: TDateTime): TTimeSpan; overload; static;
    class function Parse(const S: string): TTimeSpan; static;
    class function TryParse(const S: string; out Value: TTimeSpan): Boolean; static;
    class operator Add(const Left, Right: TTimeSpan): TTimeSpan;
    class operator Add(const Left: TTimeSpan; Right: TDateTime): TDateTime;
    class operator Add(const Left: TDateTime; Right: TTimeSpan): TDateTime;
    class operator Subtract(const Left, Right: TTimeSpan): TTimeSpan;
    class operator Subtract(const Left: TDateTime; Right: TTimeSpan): TDateTime;
    class operator Equal(const Left, Right: TTimeSpan): Boolean;
    class operator NotEqual(const Left, Right: TTimeSpan): Boolean;
    class operator GreaterThan(const Left, Right: TTimeSpan): Boolean;
    class operator GreaterThanOrEqual(const Left, Right: TTimeSpan): Boolean;
    class operator LessThan(const Left, Right: TTimeSpan): Boolean;
    class operator LessThanOrEqual(const Left, Right: TTimeSpan): Boolean;
    class operator Negative(const Value: TTimeSpan): TTimeSpan;
    class operator Positive(const Value: TTimeSpan): TTimeSpan;
    class operator Implicit(const Value: TTimeSpan): string;
    class operator Explicit(const Value: TTimeSpan): string;
    property Ticks: Int64 read FTicks;
    property Days: Integer read GetDays;
    property Hours: Integer read GetHours;
    property Minutes: Integer read GetMinutes;
    property Seconds: Integer read GetSeconds;
    property Milliseconds: Integer read GetMilliseconds;
    property TotalDays: Double read GetTotalDays;
    property TotalHours: Double read GetTotalHours;
    property TotalMinutes: Double read GetTotalMinutes;
    property TotalSeconds: Double read GetTotalSeconds;
    property TotalMilliseconds: Double read GetTotalMilliseconds;
    class property MinValue: TTimeSpan read FMinValue;
    class property MaxValue: TTimeSpan read FMaxValue;
    class property Zero: TTimeSpan read FZero;
  end;

implementation

{$IFDEF FPC_DOTTEDUNITS}
Uses System.Math;
{$ELSE FPC_DOTTEDUNITS}
Uses Math;
{$ENDIF FPC_DOTTEDUNITS}

// Embacadero documentation is poor, I used MS' http://www1.cs.columbia.edu/~lok/csharp/refdocs/System/types/TimeSpan.html
// mscorlib's docs seems to be not locale dependent, while C# docs mention "culture".
// for now, I left it non locale dependent.

{ TTimeSpan }

function TTimeSpan.GetDays: Integer;
begin
  result:=FTicks div TicksPerDay;
end;

function TTimeSpan.GetHours: Integer;
begin
  result:=(FTicks div TicksPerHour) mod HoursPerDay;
end;

function TTimeSpan.GetMinutes: Integer;
begin
  result:=(FTicks div TicksPerMinute) mod MinsPerHour;
end;

function TTimeSpan.GetSeconds: Integer;
begin
  result:=(FTicks div TicksPerSecond) mod SecsPerMin;
end;

function TTimeSpan.GetMilliseconds: Integer;
begin
  result:=(FTicks div TicksPerMillisecond) mod MillisPerSecond;
end;

function TTimeSpan.GetTotalDays: Double;
begin
  result:=FTicks/TicksPerDay;
end;

function TTimeSpan.GetTotalHours: Double;
begin
  result:=FTicks/TicksPerHour;
end;

function TTimeSpan.GetTotalMinutes: Double;
begin
  result:=FTicks/TicksPerMinute;
end;

function TTimeSpan.GetTotalSeconds: Double;
begin
  result:=FTicks/TicksPerSecond;
end;

function TTimeSpan.GetTotalMilliseconds: Double;
begin
  result:=FTicks/TicksPerMillisecond;
end;

class function TTimeSpan.GetScaledInterval(Value: Double; Scale: Integer
  ): TTimeSpan;
begin //
  result.FTicks:=round(value*scale);
end;

class constructor TTimeSpan.Create;
begin
  FMinValue.FTicks:= -9223372036854775808;
  FMaxValue.FTicks:= $7FFFFFFFFFFFFFFF;
  fzero.fticks:=0;
end;

constructor TTimeSpan.Create(ATicks: Int64);
begin
 FTicks:=ATicks;
end;

constructor TTimeSpan.Create(Hours, Minutes, Seconds: Integer);
begin
 fticks:=seconds*TicksPerSecond+minutes*TicksPerMinute+hours*TicksPerHour;
end;

constructor TTimeSpan.Create(Days, Hours, Minutes, Seconds: Integer);
begin
 fticks:=seconds*TicksPerSecond+minutes*TicksPerMinute+hours*TicksPerHour+days*TicksPerDay;
end;

constructor TTimeSpan.Create(Days, Hours, Minutes, Seconds,
  Milliseconds: Integer);
begin
 fticks:=milliseconds*TicksPerMillisecond+seconds*TicksPerSecond+minutes*TicksPerMinute+hours*TicksPerHour+days*TicksPerDay;

end;

function TTimeSpan.Add(const TS: TTimeSpan): TTimeSpan;
begin
 result.fticks:=fticks+ts.FTicks;
end;

function TTimeSpan.Duration: TTimeSpan;
begin
 result.fticks:=abs(fticks);
end;

function TTimeSpan.Negate: TTimeSpan;
begin
 result.fticks:=-fticks;
end;

function TTimeSpan.Subtract(const TS: TTimeSpan): TTimeSpan;
begin
  result.fticks:=fticks-ts.FTicks;
end;

function TTimeSpan.ToString: string;
var
  DaysPart, HoursPart, MinutesPart, SecondsPart, Fraction: Integer;
  Remainder: Int64;
begin
  DaysPart := Abs(FTicks div TicksPerDay);
  Remainder := Abs(FTicks mod TicksPerDay);
  HoursPart := Remainder div TicksPerHour;
  MinutesPart := Remainder div TicksPerMinute mod 60;
  SecondsPart := Remainder div TicksPerSecond mod 60;
  Fraction := Remainder mod TicksPerSecond;
  Result := Format('%.2d:%.2d:%.2d', [HoursPart, MinutesPart, SecondsPart]);
  if Fraction <> 0 then
    Result := Result + Format('.%.7d', [Fraction]);
  if DaysPart <> 0 then
    Result := IntToStr(DaysPart) + '.' + Result;
  if FTicks < 0 then
    Result := '-' + Result;
end;

class function TTimeSpan.FromDays(Value: Double): TTimeSpan;
begin
  result.fticks:=round(value*TicksPerDay);
end;

class function TTimeSpan.FromHours(Value: Double): TTimeSpan;
begin
  result.fticks:=round(value*TicksPerHour);
end;

class function TTimeSpan.FromMinutes(Value: Double): TTimeSpan;
begin
  result.fticks:=round(value*TicksPerMinute);
end;

class function TTimeSpan.FromSeconds(Value: Double): TTimeSpan;
begin
  result.fticks:=round(value*TicksPerSecond);
end;

class function TTimeSpan.FromMilliseconds(Value: Double): TTimeSpan;
begin
  result.fticks:=round(value*TicksPerMillisecond);
end;

class function TTimeSpan.FromTicks(Value: Int64): TTimeSpan;
begin
 result.fticks:=value;
end;

class function TTimeSpan.Subtract(const D1, D2: TDateTime): TTimeSpan;
begin
  result.fticks:=round((d1-d2)*TicksPerDay);
end;

class function TTimeSpan.Parse(const S: string): TTimeSpan;
begin
  {if not}   tryparse(s,result);  {then}
   {some default ? }
end;

class function TTimeSpan.TryParse(const S: string; out Value: TTimeSpan
  ): Boolean;
var i,len,k,v2 : integer;
    v : longint;
    sgn : boolean;
    seconds, fraction, ticks: Int64;
begin
  value.fticks:=0;
  seconds:=0;
  fraction:=0;
  i:=1; len:=length(s);
  while (i<=len) and (s[i]=' ') do // skip spaces.
   inc(i);
  sgn:=(i<=len) and (s[i]='-');
  if sgn then
    inc(i);
  k:=pos('.',s,i);
  v:=pos(':',s,i);
  if k>v then        // difference dot for days[.]hrs vs dot for sec[.]millisecs
                     // If : is earlier, there is no days dot.
    k:=0;
  if k<>0 then
    begin
      if not trystrtoint(copy (s,i,k-i),v) then
        exit(false);
       seconds:=Int64(v)*86400;
       i:=k+1;
    end;
  k:=pos(':',s,i);
  if k=0 then     // hr part mandatory.
    exit(false);
  if not trystrtoint(copy (s,i,k-i),v) then
    exit(false);
  seconds:=seconds+Int64(v)*3600;
  i:=k+1;
  k:=pos(':',s,i);
  if k=0 then     // min part mandatory.
    exit(false);
  if not trystrtoint(copy (s,i,k-i),v) then
    exit(false);
   seconds:=seconds+Int64(v)*60;
  i:=k+1;
  k:=pos('.',s,i);
  if k=0 then     // sec part mandatory, but the dot at the end not.
    begin
      k:=pos(' ',s,i); // there could be trailing whitespace.
      if k=0 then
        k:=len+1;     // simulate hypothetical point after end of string
    end;
  if not trystrtoint(copy (s,i,k-i),v) then
    exit(false);
  Inc(seconds,v);
  if (k<=len) and (s[k]='.') then
  begin
    i:=k+1;
    k:=i;
    while (k<=len) and (s[k]>='0') and (s[k]<='9') do
      Inc(k);
    if k-i>7 then
      Exit(False);
    if k>i then
    begin
      if not TryStrToInt(Copy(s,i,k-i),v) then
        Exit(False);
      fraction:=v;
      for v2:=k-i to 6 do
        fraction:=fraction*10;
    end;
  end;
  while (k<=len) and (s[k]=' ') do
    Inc(k);
  if k<=len then
    Exit(False);
  if sgn then
  begin
    seconds:=-seconds;
    fraction:=-fraction;
  end;
  if (seconds<Low(Int64) div TicksPerSecond) or (seconds>High(Int64) div TicksPerSecond) then
    Exit(False);
  ticks:=seconds*TicksPerSecond;
  if ((fraction<0) and (ticks<Low(Int64)-fraction)) or
     ((fraction>0) and (ticks>High(Int64)-fraction)) then
    Exit(False);
  value.fticks:=ticks+fraction;
  Result:=True;
end;

class operator TTimeSpan.Add(const Left, Right: TTimeSpan): TTimeSpan;
begin
 result.fticks:=left.fticks+right.fticks;
end;

class operator TTimeSpan.Add(const Left: TTimeSpan; Right: TDateTime
  ): TDateTime;
begin
 result:=left.fticks/ticksperday+right;
end;

class operator TTimeSpan.Add(const Left: TDateTime; Right: TTimeSpan
  ): TDateTime;
begin
  result:=left+right.fticks/TicksPerDay;
end;

class operator TTimeSpan.Subtract(const Left, Right: TTimeSpan): TTimeSpan;
begin
  result.FTicks:=left.FTicks-right.fticks;
end;

class operator TTimeSpan.Subtract(const Left: TDateTime; Right: TTimeSpan
  ): TDateTime;
begin
  result:=left-right.fticks/TicksPerDay;
end;

class operator TTimeSpan.Equal(const Left, Right: TTimeSpan): Boolean;
begin
  result:=left.fticks=right.fticks;
end;

class operator TTimeSpan.NotEqual(const Left, Right: TTimeSpan): Boolean;
begin
  result:=left.fticks<>right.fticks;
end;

class operator TTimeSpan.GreaterThan(const Left, Right: TTimeSpan): Boolean;
begin
  result:=left.fticks>right.fticks;
end;

class operator TTimeSpan.GreaterThanOrEqual(const Left, Right: TTimeSpan
  ): Boolean;
begin
  result:=left.fticks>=right.fticks;
end;

class operator TTimeSpan.LessThan(const Left, Right: TTimeSpan): Boolean;
begin
  result:=left.fticks<right.fticks;
end;

class operator TTimeSpan.LessThanOrEqual(const Left, Right: TTimeSpan): Boolean;
begin
  result:=left.fticks<=right.fticks;
end;

class operator TTimeSpan.Negative(const Value: TTimeSpan): TTimeSpan;
begin
  result.fticks:=-value.fticks;
end;

class operator TTimeSpan.Positive(const Value: TTimeSpan): TTimeSpan;
begin
  result.fticks:=value.fticks; // abs ?
end;

class operator TTimeSpan.Implicit(const Value: TTimeSpan): string;
begin
  result:=value.tostring;
end;

class operator TTimeSpan.Explicit(const Value: TTimeSpan): string;
begin
  result:=value.tostring;
end;

end.

