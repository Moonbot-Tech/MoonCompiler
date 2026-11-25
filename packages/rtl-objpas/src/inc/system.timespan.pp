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
var
  I, Last: SizeInt;
  Part, HoursPart, MinutesPart, Scale: Cardinal;
  Seconds, Fraction, Limit, Ticks: QWord;
  Negative: Boolean;

  function ReadDecimal(out Number: Cardinal): Boolean;
  var
    Start: SizeInt;
    Digit: Cardinal;
  begin
    Start := I;
    Number := 0;
    while (I <= Last) and (S[I] in ['0'..'9']) do
    begin
      Digit := Ord(S[I]) - Ord('0');
      if Number > (High(Cardinal) - Digit) div 10 then Exit(False);
      Number := Number * 10 + Digit;
      Inc(I);
    end;
    Result := I <> Start;
  end;

  function Consume(C: Char): Boolean; inline;
  begin
    Result := (I <= Last) and (S[I] = C);
    if Result then Inc(I);
  end;

begin
  Value.FTicks := 0;
  I := 1;
  Last := Length(S);
  while (I <= Last) and (S[I] in [' ', #9]) do Inc(I);
  while (I <= Last) and (S[Last] in [' ', #9]) do Dec(Last);
  Negative := Consume('-');
  if not ReadDecimal(Part) then Exit(False);
  Fraction := 0;
  if I > Last then
    Seconds := QWord(Part) * 86400
  else
  begin
    Seconds := 0;
    HoursPart := Part;
    if Consume('.') then
    begin
      Seconds := QWord(Part) * 86400;
      if not ReadDecimal(HoursPart) then Exit(False);
    end;
    if not Consume(':') or not ReadDecimal(MinutesPart) then Exit(False);
    Inc(Seconds, QWord(HoursPart) * 3600 + QWord(MinutesPart) * 60);
    if Consume(':') then
    begin
      { Older Moon files may use more than 23 hours or 59 minutes/seconds. }
      if I > Last then Exit(False);
      if S[I] <> '.' then
      begin
        if not ReadDecimal(Part) then Exit(False);
        Inc(Seconds, Part);
      end;
      if Consume('.') then
      begin
        if Last - I + 1 > 7 then Exit(False);
        Scale := TicksPerSecond;
        while I <= Last do
        begin
          if not (S[I] in ['0'..'9']) then Exit(False);
          Scale := Scale div 10;
          Inc(Fraction, (Ord(S[I]) - Ord('0')) * Scale);
          Inc(I);
        end;
      end;
    end
    else if (HoursPart > 23) or (MinutesPart > 59) then
      Exit(False);
  end;
  if I <= Last then Exit(False);
  Limit := QWord(High(Int64)) + Ord(Negative);
  if Seconds > (Limit - Fraction) div TicksPerSecond then Exit(False);
  Ticks := Seconds * TicksPerSecond + Fraction;
  if Negative and (Ticks <> 0) then
    Value.FTicks := -Int64(Ticks - 1) - 1
  else
    Value.FTicks := Int64(Ticks);
  Result := True;
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

