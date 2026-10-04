{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2005 by Florian Klaempfl
    member of the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{-------------------------------------------------------------------------
 Using functions from AMath/DAMath libraries, which are covered by the
 following license:

 (C) Copyright 2009-2013 Wolfgang Ehrhardt

 This software is provided 'as-is', without any express or implied warranty.
 In no event will the authors be held liable for any damages arising from
 the use of this software.

 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:

 1. The origin of this software must not be misrepresented; you must not
    claim that you wrote the original software. If you use this software in
    a product, an acknowledgment in the product documentation would be
    appreciated but is not required.

 2. Altered source versions must be plainly marked as such, and must not be
    misrepresented as being the original software.

 3. This notice may not be removed or altered from any source distribution.
----------------------------------------------------------------------------}
{
  This unit is an equivalent to the Delphi Math unit
  (with some improvements)

  What's to do:
    o some statistical functions
    o optimizations
}

{$MODE objfpc}
{$IFDEF CPUWASM32}
{$inline off}
{$ELSE}
{$inline on}
{$ENDIF}
{$GOTO on}
{$IFNDEF FPC_DOTTEDUNITS}
unit Math;
{$ENDIF FPC_DOTTEDUNITS}
interface


{$ifndef FPUNONE}
{$IFDEF FPC_DOTTEDUNITS}
    uses
       System.SysUtils, System.Types;
{$ELSE FPC_DOTTEDUNITS}
    uses
       sysutils, types;
{$ENDIF FPC_DOTTEDUNITS}

{$IFDEF FPDOC_MATH}
Type
  Float = MaxFloatType;

Const
  MinFloat = 0;
  MaxFloat = 0;
{$ENDIF}

    { Ranges of the IEEE floating point types, including denormals }
{$ifdef FPC_HAS_TYPE_SINGLE}
    const
      { values according to
        https://en.wikipedia.org/wiki/Single-precision_floating-point_format#Single-precision_examples
      }
      MinSingle    =  1.1754943508e-38;
      MaxSingle    =  3.4028234664e+38;
{$endif FPC_HAS_TYPE_SINGLE}
{$ifdef FPC_HAS_TYPE_DOUBLE}
    const
      { values according to
        https://en.wikipedia.org/wiki/Double-precision_floating-point_format#Double-precision_examples
      }
      MinDouble    =  2.2250738585072014e-308;
      MaxDouble    =  1.7976931348623157e+308;
{$endif FPC_HAS_TYPE_DOUBLE}
{$ifdef FPC_HAS_TYPE_EXTENDED}
    const
      MinExtended  =  3.36210314311209350626e-4932;
      MaxExtended  =  1.18973149535723176502e+4932;

{$endif FPC_HAS_TYPE_EXTENDED}
{$ifdef FPC_HAS_TYPE_COMP}
    const
      MinComp      = -9.223372036854775807e+18;
      MaxComp      =  9.223372036854775807e+18;
{$endif FPC_HAS_TYPE_COMP}

       { the original delphi functions use extended as argument, }
       { but I would prefer double, because 8 bytes is a very    }
       { natural size for the processor                          }
       { WARNING : changing float type will                      }
       { break all assembler code  PM                            }
{$if defined(FPC_HAS_TYPE_FLOAT128)}
      type
         Float = Float128;

      const
         MinFloat = MinFloat128;
         MaxFloat = MaxFloat128;
{$elseif defined(FPC_HAS_TYPE_EXTENDED)}
      type
         Float = extended;

      const
         MinFloat = MinExtended;
         MaxFloat = MaxExtended;
{$elseif defined(FPC_HAS_TYPE_DOUBLE)}
      type
         Float = double;

      const
         MinFloat = MinDouble;
         MaxFloat = MaxDouble;
{$elseif defined(FPC_HAS_TYPE_SINGLE)}
      type
         Float = single;

      const
         MinFloat = MinSingle;
         MaxFloat = MaxSingle;
{$else}
        {$fatal At least one floating point type must be supported}
{$endif}

    type
       PFloat = ^Float;
       PInteger = ObjPas.PInteger;

       TPaymentTime = (ptEndOfPeriod,ptStartOfPeriod);

       EInvalidArgument = class(ematherror);

{$IFDEF FPC_DOTTEDUNITS}
       TValueRelationship = System.Types.TValueRelationship;
{$ELSE FPC_DOTTEDUNITS}
       TValueRelationship = types.TValueRelationship;
{$ENDIF FPC_DOTTEDUNITS}

    const
{$IFDEF FPC_DOTTEDUNITS}
       EqualsValue = System.Types.EqualsValue;
       LessThanValue = System.Types.LessThanValue;
       GreaterThanValue = System.Types.GreaterThanValue;
{$ELSE FPC_DOTTEDUNITS}
       EqualsValue = types.EqualsValue;
       LessThanValue = types.LessThanValue;
       GreaterThanValue = types.GreaterThanValue;
{$ENDIF FPC_DOTTEDUNITS}


{$push}
{$R-}
{$Q-}
       NaN = 0.0/0.0;
       Infinity = 1.0/0.0;
       NegInfinity = -1.0/0.0;
{$pop}


{$IFDEF FPDOC_MATH}

// This must be after the above defines.

{$DEFINE FPC_HAS_TYPE_SINGLE}
{$DEFINE FPC_HAS_TYPE_DOUBLE}
{$DEFINE FPC_HAS_TYPE_EXTENDED}
{$DEFINE FPC_HAS_TYPE_COMP}
{$ENDIF}

{ Min/max determination }
function MinIntValue(const Data: array of Integer): Integer;
function MaxIntValue(const Data: array of Integer): Integer;

{ Extra, not present in Delphi, but used frequently  }
function Min(a, b: Integer): Integer;inline; overload;
function Max(a, b: Integer): Integer;inline; overload;
{ this causes more trouble than it solves
function Min(a, b: Cardinal): Cardinal; overload;
function Max(a, b: Cardinal): Cardinal; overload;
}
function Min(a, b: Int64): Int64;inline; overload;
function Max(a, b: Int64): Int64;inline; overload;
function Min(a, b: QWord): QWord;inline; overload;
function Max(a, b: QWord): QWord;inline; overload;
{$ifdef FPC_HAS_TYPE_SINGLE}
function Min(a, b: Single): Single;inline; overload;
function Max(a, b: Single): Single;inline; overload;
{$endif FPC_HAS_TYPE_SINGLE}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function Min(a, b: Double): Double;inline; overload;
function Max(a, b: Double): Double;inline; overload;
{$endif FPC_HAS_TYPE_DOUBLE}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function Min(a, b: Extended): Extended;inline; overload;
function Max(a, b: Extended): Extended;inline; overload;
{$endif FPC_HAS_TYPE_EXTENDED}

function InRange(const AValue, AMin, AMax: Integer): Boolean;inline; overload;
function InRange(const AValue, AMin, AMax: Int64): Boolean;inline; overload;
{$ifdef FPC_HAS_TYPE_DOUBLE}
function InRange(const AValue, AMin, AMax: Double): Boolean;inline;  overload;
{$endif FPC_HAS_TYPE_DOUBLE}

function EnsureRange(const AValue, AMin, AMax: Integer): Integer;inline;  overload;
function EnsureRange(const AValue, AMin, AMax: Int64): Int64;inline;  overload;
{$ifdef FPC_HAS_TYPE_DOUBLE}
function EnsureRange(const AValue, AMin, AMax: Double): Double;inline;  overload;
{$endif FPC_HAS_TYPE_DOUBLE}


procedure DivMod(Dividend: LongInt; Divisor: Word;  var Result, Remainder: Word);
procedure DivMod(Dividend: LongInt; Divisor: Word; var Result, Remainder: SmallInt);
procedure DivMod(Dividend: DWord; Divisor: DWord; var Result, Remainder: DWord);
procedure DivMod(Dividend: QWord; Divisor: QWord; var Result, Remainder: QWord);
procedure DivMod(Dividend: LongInt; Divisor: LongInt; var Result, Remainder: LongInt);

{ Floating point modulo}
{$ifdef FPC_HAS_TYPE_SINGLE}
function FMod(const a, b: Single): Single;inline;overload;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function FMod(const a, b: Double): Double;inline;overload;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function FMod(const a, b: Extended): Extended;inline;overload;
{$endif FPC_HAS_TYPE_EXTENDED}

operator mod(const a,b:float) c:float;inline;

// Sign functions
Type
  TValueSign = -1..1;

const
  NegativeValue = Low(TValueSign);
  ZeroValue = 0;
  PositiveValue = High(TValueSign);

function Sign(const AValue: Integer): TValueSign;inline; overload;
function Sign(const AValue: Int64): TValueSign;inline; overload;
{$ifdef FPC_HAS_TYPE_SINGLE}
function Sign(const AValue: Single): TValueSign;inline; overload;
{$endif}
function Sign(const AValue: Double): TValueSign;inline; overload;
{$ifdef FPC_HAS_TYPE_EXTENDED}
function Sign(const AValue: Extended): TValueSign;inline; overload;
{$endif}

function IsZero(const A: Single; Epsilon: Single): Boolean; overload;
function IsZero(const A: Single): Boolean;inline; overload;
{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsZero(const A: Double; Epsilon: Double): Boolean; overload;
function IsZero(const A: Double): Boolean;inline; overload;
{$endif FPC_HAS_TYPE_DOUBLE}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsZero(const A: Extended; Epsilon: Extended): Boolean; overload;
function IsZero(const A: Extended): Boolean;inline; overload;
{$endif FPC_HAS_TYPE_EXTENDED}

function IsNan(const d : Single): Boolean; overload;
{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsNan(const d : Double): Boolean; overload;
{$endif FPC_HAS_TYPE_DOUBLE}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsNan(const d : Extended): Boolean; overload;
{$endif FPC_HAS_TYPE_EXTENDED}

function IsInfinite(const d : Single): Boolean; overload;
{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsInfinite(const d : Double): Boolean; overload;
{$endif FPC_HAS_TYPE_DOUBLE}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsInfinite(const d : Extended): Boolean; overload;
{$endif FPC_HAS_TYPE_EXTENDED}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function SameValue(const A, B: Extended): Boolean;inline; overload;
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function SameValue(const A, B: Double): Boolean;inline; overload;
{$endif}
function SameValue(const A, B: Single): Boolean;inline; overload;
{$ifdef FPC_HAS_TYPE_EXTENDED}
function SameValue(const A, B: Extended; Epsilon: Extended): Boolean; overload;
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function SameValue(const A, B: Double; Epsilon: Double): Boolean; overload;
{$endif}
function SameValue(const A, B: Single; Epsilon: Single): Boolean; overload;

type
  TRoundToRange = -37..37;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function RoundTo(const AVAlue: Extended; const Digits: TRoundToRange): Extended;
{$endif}
{$ifdef FPC_HAS_TYPE_SINGLE}
function RoundTo(const AValue: Single; const Digits: TRoundToRange): Single;
{$endif}
{$ifdef FPC_HAS_TYPE_SINGLE}
function SimpleRoundTo(const AValue: Single; const Digits: TRoundToRange = -2): Single;
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function SimpleRoundTo(const AValue: Double; const Digits: TRoundToRange = -2): Double;
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function SimpleRoundTo(const AValue: Extended; const Digits: TRoundToRange = -2): Extended;
{$endif}


{ angle conversion }

function DegToRad(deg : float) : float;inline;
function RadToDeg(rad : float) : float;inline;
function GradToRad(grad : float) : float;inline;
function RadToGrad(rad : float) : float;inline;
function DegToGrad(deg : float) : float;inline;
function GradToDeg(grad : float) : float;inline;
{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToDeg(const Cycles: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToDeg(const Cycles: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToDeg(const Cycles: Extended): Extended;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_SINGLE}
function DegToCycle(const Degrees: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function DegToCycle(const Degrees: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function DegToCycle(const Degrees: Extended): Extended;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToGrad(const Cycles: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToGrad(const Cycles: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToGrad(const Cycles: Extended): Extended;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_SINGLE}
function GradToCycle(const Grads: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function GradToCycle(const Grads: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function GradToCycle(const Grads: Extended): Extended;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToRad(const Cycles: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToRad(const Cycles: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToRad(const Cycles: Extended): Extended;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_SINGLE}
function RadToCycle(const Rads: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function RadToCycle(const Rads: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function RadToCycle(const Rads: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
Function DegNormalize(deg : single) : single; inline;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
Function DegNormalize(deg : double) : double; inline;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
Function DegNormalize(deg : extended) : extended; inline;
{$ENDIF}

{ trigonometric functions }

function Tan(x : float) : float;
function Cotan(x : float) : float;
function Cot(x : float) : float; inline;
{$ifdef FPC_HAS_TYPE_SINGLE}
procedure SinCos(theta : single;out sinus,cosinus : single);
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
procedure SinCos(theta : double;out sinus,cosinus : double);
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure SinCos(theta : extended;out sinus,cosinus : extended);
{$endif}


function Secant(x : float) : float; inline;
function Cosecant(x : float) : float; inline;
function Sec(x : float) : float; inline;
function Csc(x : float) : float; inline;

{ inverse functions }

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCos(x : Single) : Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCos(x : Double) : Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCos(x : Extended) : Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcSin(x : Single) : Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcSin(x : Double) : Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcSin(x : Extended) : Extended;
{$ENDIF}

{ calculates arctan(y/x) and returns an angle in the correct quadrant }
function ArcTan2(y,x : float) : float;

{ hyperbolic functions }

{$ifdef FPC_HAS_TYPE_SINGLE}
function cosh(x : Single) : Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function cosh(x : Double) : Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function cosh(x : Extended) : Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function sinh(x : Single) : Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function sinh(x : Double) : Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function sinh(x : Extended) : Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function tanh(x : Single) : Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function tanh(x : Double) : Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function tanh(x : Extended) : Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function SecH(const X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function SecH(const X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function SecH(const X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CscH(const X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CscH(const X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CscH(const X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CotH(const X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CotH(const X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CotH(const X: Extended): Extended;
{$ENDIF}

{ area functions }

{ delphi names: }
function ArcCosH(x : float) : float;inline;
function ArcSinH(x : float) : float;inline;
function ArcTanH(x : float) : float;inline;
{ IMHO the function should be called as follows (FK) }
function ArCosH(x : float) : float;
function ArSinH(x : float) : float;
function ArTanH(x : float) : float;

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcSec(X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcSec(X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcSec(X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCsc(X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCsc(X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCsc(X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCot(X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCot(X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCot(X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcSecH(X : Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcSecH(X : Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcSecH(X : Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCscH(X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCscH(X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCscH(X: Extended): Extended;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCotH(X: Single): Single;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCotH(X: Double): Double;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCotH(X: Extended): Extended;
{$ENDIF}

{ triangle functions }

{ returns the length of the hypotenuse of a right triangle }
{ if x and y are the other sides                           }
function Hypot(x,y : float) : float;

{ logarithm functions }

function Log10(x : float) : float;
function Log2(x : float) : float;
function LogN(n,x : float) : float;

{ returns natural logarithm of x+1, accurate for x values near zero }
function LnXP1(x : float) : float;
{ Return exp(x)-1, accurate even for x near 0 }
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ExpM1(x : double) : double;
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ExpM1(x : extended) : extended;
{$endif}

{ exponential functions }

function Power(base,exponent : float) : float;
{ base^exponent }
function IntPower(base : float;exponent : longint) : float;

operator ** (base,exponent : float) e: float; inline;
operator ** (base,exponent : int64) res: int64;

{ number converting }

{ rounds x towards positive infinity }
function Ceil(x : float) : Integer;
function Ceil64(x: float): Int64;
{ rounds x towards negative infinity }
function Floor(x : float) : Integer;
function Floor64(x: float): Int64;

{ misc. functions }

{$ifdef FPC_HAS_TYPE_SINGLE}
{ splits x into mantissa and exponent (to base 2) }
procedure Frexp(X: single; out Mantissa: single; out Exponent: integer);
{ returns x*(2^p) }
function Ldexp(X: single; p: Integer) : single;
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
procedure Frexp(X: double; out Mantissa: double; out Exponent: integer);
function Ldexp(X: double; p: Integer) : double;
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure Frexp(X: extended; out Mantissa: extended; out Exponent: integer);
function Ldexp(X: extended; p: Integer) : extended;
{$endif}

{ statistical functions }

{$ifdef FPC_HAS_TYPE_SINGLE}
function Mean(const data : array of Single) : float;
function Sum(const data : array of Single) : float;inline;
function Mean(const data : PSingle; Const N : longint) : float;
function Sum(const data : PSingle; Const N : Longint) : float;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function Mean(const data : array of double) : float;inline;
function Sum(const data : array of double) : float;inline;
function Mean(const data : PDouble; Const N : longint) : float;
function Sum(const data : PDouble; Const N : Longint) : float;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function Mean(const data : array of Extended) : float;
function Sum(const data : array of Extended) : float;inline;
function Mean(const data : PExtended; Const N : longint) : float;
function Sum(const data : PExtended; Const N : Longint) : float;
{$endif FPC_HAS_TYPE_EXTENDED}

function SumInt(const data : PInt64;Const N : longint) : Int64;
function SumInt(const data : array of Int64) : Int64;inline;
function Mean(const data : PInt64; const N : Longint):Float;
function Mean(const data: array of Int64):Float;
function SumInt(const data : PInteger; Const N : longint) : Int64;
function SumInt(const data : array of Integer) : Int64;inline;
function Mean(const data : PInteger; const N : Longint):Float;
function Mean(const data: array of Integer):Float;


{$ifdef FPC_HAS_TYPE_SINGLE}
function SumOfSquares(const data : array of Single) : float;inline;
function SumOfSquares(const data : PSingle; Const N : Integer) : float;
{ calculates the sum and the sum of squares of data }
procedure SumsAndSquares(const data : array of Single;
  var sum,sumofsquares : float);inline;
procedure SumsAndSquares(const data : PSingle; Const N : Integer;
  var sum,sumofsquares : float);
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function SumOfSquares(const data : array of double) : float;inline;
function SumOfSquares(const data : PDouble; Const N : Integer) : float;
{ calculates the sum and the sum of squares of data }
procedure SumsAndSquares(const data : array of Double;
  var sum,sumofsquares : float);inline;
procedure SumsAndSquares(const data : PDouble; Const N : Integer;
  var sum,sumofsquares : float);
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function SumOfSquares(const data : array of Extended) : float;inline;
function SumOfSquares(const data : PExtended; Const N : Integer) : float;
{ calculates the sum and the sum of squares of data }
procedure SumsAndSquares(const data : array of Extended;
  var sum,sumofsquares : float);inline;
procedure SumsAndSquares(const data : PExtended; Const N : Integer;
  var sum,sumofsquares : float);
{$endif FPC_HAS_TYPE_EXTENDED}

{$ifdef FPC_HAS_TYPE_SINGLE}
function MinValue(const data : array of Single) : Single;inline;
function MinValue(const data : PSingle; Const N : Integer) : Single;
function MaxValue(const data : array of Single) : Single;inline;
function MaxValue(const data : PSingle; Const N : Integer) : Single;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function MinValue(const data : array of Double) : Double;inline;
function MinValue(const data : PDouble; Const N : Integer) : Double;
function MaxValue(const data : array of Double) : Double;inline;
function MaxValue(const data : PDouble; Const N : Integer) : Double;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function MinValue(const data : array of Extended) : Extended;inline;
function MinValue(const data : PExtended; Const N : Integer) : Extended;
function MaxValue(const data : array of Extended) : Extended;inline;
function MaxValue(const data : PExtended; Const N : Integer) : Extended;
{$endif FPC_HAS_TYPE_EXTENDED}

function MinValue(const data : array of integer) : Integer;inline;
function MinValue(const Data : PInteger; Const N : Integer): Integer;

function MaxValue(const data : array of integer) : Integer;inline;
function MaxValue(const data : PInteger; Const N : Integer) : Integer;

{ returns random values with gaussian distribution }
function RandG(mean,stddev : float) : float;

function RandomRange(const aFrom, aTo: Integer): Integer;
function RandomRange(const aFrom, aTo: Int64): Int64;

{$ifdef FPC_HAS_TYPE_SINGLE}
{ calculates the standard deviation }
function StdDev(const data : array of Single) : float;inline;
function StdDev(const data : PSingle; Const N : Integer) : float;
{ calculates the mean and stddev }
procedure MeanAndStdDev(const data : array of Single;
  var mean,stddev : float);inline;
procedure MeanAndStdDev(const data : PSingle;
  Const N : Longint;var mean,stddev : float);
function Variance(const data : array of Single) : float;inline;
function TotalVariance(const data : array of Single) : float;inline;
function Variance(const data : PSingle; Const N : Integer) : float;
function TotalVariance(const data : PSingle; Const N : Integer) : float;

{ Population (aka uncorrected) variance and standard deviation }
function PopnStdDev(const data : array of Single) : float;inline;
function PopnStdDev(const data : PSingle; Const N : Integer) : float;
function PopnVariance(const data : PSingle; Const N : Integer) : float;
function PopnVariance(const data : array of Single) : float;inline;
procedure MomentSkewKurtosis(const data : array of Single;
  out m1,m2,m3,m4,skew,kurtosis : float);inline;
procedure MomentSkewKurtosis(const data : PSingle; Const N : Integer;
  out m1,m2,m3,m4,skew,kurtosis : float);

{ geometrical function }

{ returns the euclidean L2 norm }
function Norm(const data : array of Single) : float;inline;
function Norm(const data : PSingle; Const N : Integer) : float;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
{ calculates the standard deviation }
function StdDev(const data : array of Double) : float;inline;
function StdDev(const data : PDouble; Const N : Integer) : float;
{ calculates the mean and stddev }
procedure MeanAndStdDev(const data : array of Double;
  var mean,stddev : float);inline;
procedure MeanAndStdDev(const data : PDouble;
  Const N : Longint;var mean,stddev : float);
function Variance(const data : array of Double) : float;inline;
function TotalVariance(const data : array of Double) : float;inline;
function Variance(const data : PDouble; Const N : Integer) : float;
function TotalVariance(const data : PDouble; Const N : Integer) : float;

{ Population (aka uncorrected) variance and standard deviation }
function PopnStdDev(const data : array of Double) : float;inline;
function PopnStdDev(const data : PDouble; Const N : Integer) : float;
function PopnVariance(const data : PDouble; Const N : Integer) : float;
function PopnVariance(const data : array of Double) : float;inline;
procedure MomentSkewKurtosis(const data : array of Double;
  out m1,m2,m3,m4,skew,kurtosis : float);inline;
procedure MomentSkewKurtosis(const data : PDouble; Const N : Integer;
  out m1,m2,m3,m4,skew,kurtosis : float);

{ geometrical function }

{ returns the euclidean L2 norm }
function Norm(const data : array of double) : float;inline;
function Norm(const data : PDouble; Const N : Integer) : float;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
{ calculates the standard deviation }
function StdDev(const data : array of Extended) : float;inline;
function StdDev(const data : PExtended; Const N : Integer) : float;
{ calculates the mean and stddev }
procedure MeanAndStdDev(const data : array of Extended;
  var mean,stddev : float);inline;
procedure MeanAndStdDev(const data : PExtended;
  Const N : Longint;var mean,stddev : float);
function Variance(const data : array of Extended) : float;inline;
function TotalVariance(const data : array of Extended) : float;inline;
function Variance(const data : PExtended; Const N : Integer) : float;
function TotalVariance(const data : PExtended; Const N : Integer) : float;

{ Population (aka uncorrected) variance and standard deviation }
function PopnStdDev(const data : array of Extended) : float;inline;
function PopnStdDev(const data : PExtended; Const N : Integer) : float;
function PopnVariance(const data : PExtended; Const N : Integer) : float;
function PopnVariance(const data : array of Extended) : float;inline;
procedure MomentSkewKurtosis(const data : array of Extended;
  out m1,m2,m3,m4,skew,kurtosis : float);inline;
procedure MomentSkewKurtosis(const data : PExtended; Const N : Integer;
  out m1,m2,m3,m4,skew,kurtosis : float);

{ geometrical function }

{ returns the euclidean L2 norm }
function Norm(const data : array of Extended) : float;inline;
function Norm(const data : PExtended; Const N : Integer) : float;
{$endif FPC_HAS_TYPE_EXTENDED}

{ Financial functions }

function FutureValue(ARate: Float; NPeriods: Integer;
  APayment, APresentValue: Float; APaymentTime: TPaymentTime): Float;

function InterestRate(NPeriods: Integer; APayment, APresentValue, AFutureValue: Float;
  APaymentTime: TPaymentTime): Float;

function NumberOfPeriods(ARate, APayment, APresentValue, AFutureValue: Float;
  APaymentTime: TPaymentTime): Float;

function Payment(ARate: Float; NPeriods: Integer;
  APresentValue, AFutureValue: Float; APaymentTime: TPaymentTime): Float;

function PresentValue(ARate: Float; NPeriods: Integer;
  APayment, AFutureValue: Float; APaymentTime: TPaymentTime): Float;

{ Misc functions }

function IfThen(val:boolean;const iftrue:integer; const iffalse:integer= 0) :integer; inline; overload;
function IfThen(val:boolean;const iftrue:int64  ; const iffalse:int64 = 0)  :int64;   inline; overload;
function IfThen(val:boolean;const iftrue:double ; const iffalse:double =0.0):double;  inline; overload;

function CompareValue ( const A, B  : Integer) : TValueRelationship; inline;
function CompareValue ( const A, B  : Int64) : TValueRelationship; inline;
function CompareValue ( const A, B  : QWord) : TValueRelationship; inline;

{$ifdef FPC_HAS_TYPE_SINGLE}
function CompareValue ( const A, B : Single; delta : Single = 0.0 ) : TValueRelationship; inline;
{$endif}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CompareValue ( const A, B : Double; delta : Double = 0.0) : TValueRelationship; inline;
{$endif}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CompareValue ( const A, B : Extended; delta : Extended = 0.0 ) : TValueRelationship; inline;
{$endif}

function RandomFrom(const AValues: array of Double): Double; overload;
function RandomFrom(const AValues: array of Integer): Integer; overload;
function RandomFrom(const AValues: array of Int64): Int64; overload;
{$if FPC_FULLVERSION >=30101}
generic function RandomFrom<T>(const AValues:array of T):T;
{$endif}

{ cpu specific stuff }

type
  TFPURoundingMode = system.TFPURoundingMode;
  TFPUPrecisionMode = system.TFPUPrecisionMode;
  TFPUException = system.TFPUException;
  TFPUExceptionMask = system.TFPUExceptionMask;

function GetRoundMode: TFPURoundingMode;
function SetRoundMode(const RoundMode: TFPURoundingMode): TFPURoundingMode;
function GetPrecisionMode: TFPUPrecisionMode;
function SetPrecisionMode(const Precision: TFPUPrecisionMode): TFPUPrecisionMode;
function GetExceptionMask: TFPUExceptionMask;
function SetExceptionMask(const Mask: TFPUExceptionMask): TFPUExceptionMask;
procedure ClearExceptions(RaisePending: Boolean =true);


implementation

function copysign(x,y: float): float; forward;    { returns abs(x)*sign(y) }

{ include cpu specific stuff }
{$i mathu.inc}

ResourceString
  SMathError = 'Math Error : %s';
  SInvalidArgument = 'Invalid argument';

Procedure DoMathError(Const S : String);
begin
  Raise EMathError.CreateFmt(SMathError,[S]);
end;

Procedure InvalidArgument;

begin
  Raise EInvalidArgument.Create(SInvalidArgument);
end;


function Sign(const AValue: Integer): TValueSign;inline;

begin
  result:=TValueSign(
    SarLongint(AValue,sizeof(AValue)*8-1) or            { gives -1 for negative values, 0 otherwise }
    (longint(-AValue) shr (sizeof(AValue)*8-1))         { gives 1 for positive values, 0 otherwise }
  );
end;

function Sign(const AValue: Int64): TValueSign;inline;

begin
{$ifdef cpu64}
  result:=TValueSign(
    SarInt64(AValue,sizeof(AValue)*8-1) or
    (-AValue shr (sizeof(AValue)*8-1))
  );
{$else cpu64}
  If Avalue<0 then
    Result:=NegativeValue
  else If Avalue>0 then
    Result:=PositiveValue
  else
    Result:=ZeroValue;
{$endif}
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function Sign(const AValue: Single): TValueSign;inline;

begin
  Result:=ord(AValue>0.0)-ord(AValue<0.0);
end;
{$endif}


function Sign(const AValue: Double): TValueSign;inline;

begin
  Result:=ord(AValue>0.0)-ord(AValue<0.0);
end;

{$ifdef FPC_HAS_TYPE_EXTENDED}
function Sign(const AValue: Extended): TValueSign;inline;

begin
  Result:=ord(AValue>0.0)-ord(AValue<0.0);
end;
{$endif}

function degtorad(deg : float) : float;inline;
  begin
     degtorad:=deg*(pi/180.0);
  end;

function radtodeg(rad : float) : float;inline;
  begin
     radtodeg:=rad*(180.0/pi);
  end;

function gradtorad(grad : float) : float;inline;
  begin
     gradtorad:=grad*(pi/200.0);
  end;

function radtograd(rad : float) : float;inline;
  begin
     radtograd:=rad*(200.0/pi);
  end;

function degtograd(deg : float) : float;inline;
  begin
     degtograd:=deg*(200.0/180.0);
  end;

function gradtodeg(grad : float) : float;inline;
  begin
     gradtodeg:=grad*(180.0/200.0);
  end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToDeg(const Cycles: Single): Single;
begin
  CycleToDeg:=Cycles*360.0;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToDeg(const Cycles: Double): Double;
begin
  CycleToDeg:=Cycles*360.0;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToDeg(const Cycles: Extended): Extended;
begin
  CycleToDeg:=Cycles*360.0;
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function DegToCycle(const Degrees: Single): Single;
begin
  DegToCycle:=Degrees*(1/360.0);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function DegToCycle(const Degrees: Double): Double;
begin
  DegToCycle:=Degrees*(1/360.0);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function DegToCycle(const Degrees: Extended): Extended;
begin
  DegToCycle:=Degrees*(1/360.0);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToGrad(const Cycles: Single): Single;
begin
  CycleToGrad:=Cycles*400.0;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToGrad(const Cycles: Double): Double;
begin
  CycleToGrad:=Cycles*400.0;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToGrad(const Cycles: Extended): Extended;
begin
  CycleToGrad:=Cycles*400.0;
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function GradToCycle(const Grads: Single): Single;
begin
  GradToCycle:=Grads*(1/400.0);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function GradToCycle(const Grads: Double): Double;
begin
  GradToCycle:=Grads*(1/400.0);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function GradToCycle(const Grads: Extended): Extended;
begin
  GradToCycle:=Grads*(1/400.0);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CycleToRad(const Cycles: Single): Single;
begin
  CycleToRad:=Cycles*2*pi;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function CycleToRad(const Cycles: Double): Double;
begin
  CycleToRad:=Cycles*2*pi;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function CycleToRad(const Cycles: Extended): Extended;
begin
  CycleToRad:=Cycles*2*pi;
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function RadToCycle(const Rads: Single): Single;
begin
  RadToCycle:=Rads*(1/(2*pi));
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function RadToCycle(const Rads: Double): Double;
begin
  RadToCycle:=Rads*(1/(2*pi));
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function RadToCycle(const Rads: Extended): Extended;
begin
  RadToCycle:=Rads*(1/(2*pi));
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
Function DegNormalize(deg : single) : single;

begin
  Result:=Deg-Int(Deg/360)*360;
  If Result<0 then Result:=Result+360;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
Function DegNormalize(deg : double) : double; inline;

begin
  Result:=Deg-Int(Deg/360)*360;
  If (Result<0) then Result:=Result+360;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
Function DegNormalize(deg : extended) : extended; inline;

begin
  Result:=Deg-Int(Deg/360)*360;
  If Result<0 then Result:=Result+360;
end;
{$ENDIF}

{$ifndef FPC_MATH_HAS_TAN}
function tan(x : float) : float;
  var
    _sin,_cos : float;
  begin
    sincos(x,_sin,_cos);
    tan:=_sin/_cos;
  end;
{$endif FPC_MATH_HAS_TAN}


{$ifndef FPC_MATH_HAS_COTAN}
function cotan(x : float) : float;
  var
    _sin,_cos : float;
  begin
    sincos(x,_sin,_cos);
    cotan:=_cos/_sin;
  end;
{$endif FPC_MATH_HAS_COTAN}

function cot(x : float) : float; inline;
begin
  cot := cotan(x);
end;


{$ifndef FPC_MATH_HAS_SINCOS}
{$ifdef FPC_HAS_TYPE_SINGLE}
procedure sincos(theta : single;out sinus,cosinus : single);
  begin
    sinus:=sin(theta);
    cosinus:=cos(theta);
  end;
{$endif}


{$ifdef FPC_HAS_TYPE_DOUBLE}
procedure sincos(theta : double;out sinus,cosinus : double);
  begin
    sinus:=sin(theta);
    cosinus:=cos(theta);
  end;
{$endif}


{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure sincos(theta : extended;out sinus,cosinus : extended);
  begin
    sinus:=sin(theta);
    cosinus:=cos(theta);
  end;
{$endif}
{$endif FPC_MATH_HAS_SINCOS}


function secant(x : float) : float; inline;
begin
  secant := 1 / cos(x);
end;


function cosecant(x : float) : float; inline;
begin
  cosecant := 1 / sin(x);
end;


function sec(x : float) : float; inline;
begin
  sec := secant(x);
end;


function csc(x : float) : float; inline;
begin
  csc := cosecant(x);
end;


{ arcsin and arccos functions from AMath library (C) Copyright 2009-2013 Wolfgang Ehrhardt }
{$ifdef FPC_HAS_TYPE_SINGLE}
function arcsin(x : Single) : Single;
begin
  arcsin:=arctan2(x,sqrt((1.0-x)*(1.0+x)));
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function arcsin(x : Double) : Double;
begin
  arcsin:=arctan2(x,sqrt((1.0-x)*(1.0+x)));
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function arcsin(x : Extended) : Extended;
begin
  arcsin:=arctan2(x,sqrt((1.0-x)*(1.0+x)));
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_SINGLE}
function Arccos(x : Single) : Single;
begin
  arccos:=arctan2(sqrt((1.0-x)*(1.0+x)),x);
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function Arccos(x : Double) : Double;
begin
  arccos:=arctan2(sqrt((1.0-x)*(1.0+x)),x);
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function Arccos(x : Extended) : Extended;
begin
  arccos:=arctan2(sqrt((1.0-x)*(1.0+x)),x);
end;
{$ENDIF}


{$ifndef FPC_MATH_HAS_ARCTAN2}
function arctan2(y,x : float) : float;
  begin
    if x=0 then
      begin
        if y=0 then
          result:=0.0
        else if y>0 then
          result:=pi/2
        else
          result:=-pi/2;
      end
    else
      begin
        result:=ArcTan(y/x);
        if x<0 then
          if y<0 then
            result:=result-pi
          else
            result:=result+pi;
      end;
  end;
{$endif FPC_MATH_HAS_ARCTAN2}

const
  huge_single: single = 1e30;
  huge_double: double = 1e300;

{$ifdef FPC_HAS_TYPE_SINGLE}
function cosh(x : Single) : Single;
  var
     temp : ValReal;
  begin
     if (x>8.94159862326326216608E+0001) or (x<-8.94159862326326216608E+0001) then
{$push}
{$checkfpuexceptions on}
       exit(huge_single*huge_single);
{$pop}
    temp:=exp(x);
{$push}
{$safefpuexceptions on}
     cosh:=0.5*(temp+1.0/temp);
{$pop}
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function cosh(x : Double) : Double;
  var
     temp : ValReal;
  begin
     if (x>7.10475860073943942030E+0002) or (x<-7.10475860073943942030E+0002) then
{$push}
{$checkfpuexceptions on}
       exit(huge_double*huge_double);
{$pop}
     temp:=exp(x);
{$push}
{$safefpuexceptions on}
     cosh:=0.5*(temp+1.0/temp);
{$pop}
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function cosh(x : Extended) : Extended;
  var
     temp : ValReal;
  begin
     temp:=exp(x);
     cosh:=0.5*(temp+1.0/temp);
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_SINGLE}
function sinh(x : Single) : Single;
  var
     temp : ValReal;
  begin
     if x>8.94159862326326216608E+0001 then
{$push}
{$checkfpuexceptions on}
       exit(huge_single*huge_single);
{$pop}
     if x<-8.94159862326326216608E+0001 then
{$push}
{$checkfpuexceptions on}
       exit(-(huge_single*huge_single));
{$pop}
     temp:=exp(x);
     { gives better behavior around zero, and in particular ensures that sinh(-0.0)=-0.0 }
     if temp=1 then
       exit(x);
{$push}
{$safefpuexceptions on}
     sinh:=0.5*(temp-1.0/temp);
{$pop}
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function sinh(x : Double) : Double;
  var
     temp : ValReal;
  begin
     if x>7.10475860073943942030E+0002 then
{$push}
{$checkfpuexceptions on}
       exit(huge_double*huge_double);
{$pop}
     if x<-7.10475860073943942030E+0002 then
{$push}
{$checkfpuexceptions on}
       exit(-(huge_double*huge_double));
{$pop}
     temp:=exp(x);
     if temp=1 then
       exit(x);
{$push}
{$safefpuexceptions on}
     sinh:=0.5*(temp-1.0/temp);
{$pop}
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function sinh(x : Extended) : Extended;
  var
     temp : ValReal;
  begin
     temp:=exp(x);
     if temp=1 then
       exit(x);
     sinh:=0.5*(temp-1.0/temp);
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_SINGLE}
function tanh(x : Single) : Single;
  var
    tmp:ValReal;
  begin
    if abs(x)>10 then
      begin
        result:=sign(x);
        exit;
      end;

    if x < 0 then
      begin
        tmp:=exp(2*x);
        if tmp=1 then
          exit(x);
{$push}
{$safefpuexceptions on}
        result:=(tmp-1)/(1+tmp)
{$pop}
      end
    else
      begin
        tmp:=exp(-2*x);
        if tmp=1 then
          exit(x);
{$push}
{$safefpuexceptions on}
        result:=(1-tmp)/(1+tmp)
{$pop}
      end;
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function tanh(x : Double) : Double;
  var
    tmp:ValReal;
  begin
    if abs(x)>20 then
      begin
        result:=sign(x);
        exit;
      end;

    if x < 0 then
      begin
        tmp:=exp(2*x);
        if tmp=1 then
          exit(x);
{$push}
{$safefpuexceptions on}
        result:=(tmp-1)/(1+tmp)
{$pop}
      end
    else
      begin
        tmp:=exp(-2*x);
        if tmp=1 then
          exit(x);
{$push}
{$safefpuexceptions on}
        result:=(1-tmp)/(1+tmp)
{$pop}
    end;
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function tanh(x : Extended) : Extended;
  var
    tmp:Extended;
  begin
    if abs(x)>25 then
      begin
        result:=sign(x);
        exit;
      end;

    if x < 0 then
      begin
        tmp:=exp(2*x);
        if tmp=1 then
          exit(x);
        result:=(tmp-1)/(1+tmp)
      end
    else
      begin
        tmp:=exp(-2*x);
        if tmp=1 then
          exit(x);
        result:=(1-tmp)/(1+tmp)
      end;
  end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_SINGLE}
function SecH(const X: Single): Single;
var
  Ex: ValReal;
begin
  //https://en.wikipedia.org/wiki/Hyperbolic_functions#Definitions
  //SecH = 2 / (e^X + e^-X)
  Ex:=Exp(X);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
  SecH:=2/(Ex+1/Ex);
{$pop}
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function SecH(const X: Double): Double;
var
  Ex: ValReal;
begin
  Ex:=Exp(X);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
  SecH:=2/(Ex+1/Ex);
{$pop}
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function SecH(const X: Extended): Extended;
var
  Ex: ValReal;
begin
  Ex:=Exp(X);
  SecH:=2/(Ex+1/Ex);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CscH(const X: Single): Single;
var
  Ex: ValReal;
begin
  //CscH = 2 / (e^X - e^-X)
  Ex:=Exp(X);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
  CscH:=2/(Ex-1/Ex);
{$pop}
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function CscH(const X: Double): Double;
var
  Ex: ValReal;
begin
  Ex:=Exp(X);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
  CscH:=2/(Ex-1/Ex);
{$pop}
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function CscH(const X: Extended): Extended;
var
  Ex: ValReal;
begin
  Ex:=Exp(X);
  CscH:=2/(Ex-1/Ex);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function CotH(const X: Single): Single;
var
  e2: ValReal;
begin
  if x < 0 then begin
    e2:=exp(2*x);
    if e2=1 then
      exit(1/x);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
    result:=(1+e2)/(e2-1)
{$pop}
  end
  else begin
    e2:=exp(-2*x);
    if e2=1 then
      exit(1/x);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
    result:=(1+e2)/(1-e2)
{$pop}
  end;
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function CotH(const X: Double): Double;
var
  e2: ValReal;
begin
  if x < 0 then begin
    e2:=exp(2*x);
    if e2=1 then
      exit(1/x);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
    result:=(1+e2)/(e2-1)
{$pop}
  end
  else begin
    e2:=exp(-2*x);
    if e2=1 then
      exit(1/x);
{$push}
{$checkfpuexceptions on}
{$safefpuexceptions on}
    result:=(1+e2)/(1-e2)
{$pop}
  end;
end;
{$ENDIF}


{$ifdef FPC_HAS_TYPE_EXTENDED}
function CotH(const X: Extended): Extended;
var
  e2: ValReal;
begin
  if x < 0 then begin
    e2:=exp(2*x);
    if e2=1 then
      exit(1/x);
    result:=(1+e2)/(e2-1)
  end
  else begin
    e2:=exp(-2*x);
    if e2=1 then
      exit(1/x);
    result:=(1+e2)/(1-e2)
  end;
end;
{$ENDIF}

function arccosh(x : float) : float; inline;
  begin
     arccosh:=arcosh(x);
  end;

function arcsinh(x : float) : float;inline;
  begin
     arcsinh:=arsinh(x);
  end;

function arctanh(x : float) : float;inline;
  begin
     arctanh:=artanh(x);
  end;

function arcosh(x : float) : float;
  begin
    if x>sqrt(MaxFloat)*0.5 then
      arcosh:=ln(x)+ln(2.0)
    else
      { This form keeps the subtraction accurate near one. }
      arcosh:=lnxp1((x-1.0)+sqrt((x-1.0)*(x+1.0)));
  end;

function arsinh(x : float) : float;
  var
    a,z: float;
  begin
    a:=abs(x);
    if a>sqrt(MaxFloat)*0.5 then
      z:=ln(a)+ln(2.0)
    else
      z:=lnxp1(a+(a/(hypot(1.0,a)+1.0))*a);
    { copysign ensures that arsinh(-Inf)=-Inf and arsinh(-0.0)=-0.0 }
    arsinh:=copysign(z,x);
  end;

function artanh(x : float) : float;
  begin
    artanh:=(lnxp1(x)-lnxp1(-x))*0.5;
  end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcSec(X: Single): Single;
begin
  ArcSec:=ArcCos(1/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcSec(X: Double): Double;
begin
  ArcSec:=ArcCos(1/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcSec(X: Extended): Extended;
begin
  ArcSec:=ArcCos(1/X);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCsc(X: Single): Single;
begin
  ArcCsc:=ArcSin(1/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCsc(X: Double): Double;
begin
  ArcCsc:=ArcSin(1/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCsc(X: Extended): Extended;
begin
  ArcCsc:=ArcSin(1/X);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCot(X: Single): Single;
begin
  if x=0 then
    ArcCot:=0.5*pi
  else
    ArcCot:=ArcTan(1/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCot(X: Double): Double;
begin
  begin
    if x=0 then
      ArcCot:=0.5*pi
    else
      ArcCot:=ArcTan(1/X);
  end;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCot(X: Extended): Extended;
begin
  begin
    if x=0 then
      ArcCot:=0.5*pi
    else
      ArcCot:=ArcTan(1/X);
  end;
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcSecH(X : Single): Single;
begin
  ArcSecH:=lnxp1(sqrt((1.0-X)*(1.0+X)))-ln(X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcSecH(X : Double): Double;
begin
  ArcSecH:=lnxp1(sqrt((1.0-X)*(1.0+X)))-ln(X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcSecH(X : Extended): Extended;
begin
  ArcSecH:=lnxp1(sqrt((1.0-X)*(1.0+X)))-ln(X);
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCscH(X: Single): Single;
var
  R: Float;
begin
  if (X<>0.0) and (abs(X)<=1.0/MaxSingle) then
    ArcCscH:=CopySign(ln(2.0)-ln(abs(X)),X)
  else
    begin
      R:=1.0/X;
      ArcCscH:=arsinh(R);
    end;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCscH(X: Double): Double;
var
  R: Float;
begin
  if (X<>0.0) and (abs(X)<=1.0/MaxDouble) then
    ArcCscH:=CopySign(ln(2.0)-ln(abs(X)),X)
  else
    begin
      R:=1.0/X;
      ArcCscH:=arsinh(R);
    end;
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCscH(X: Extended): Extended;
var
  R: Float;
begin
  if (X<>0.0) and (abs(X)<=1.0/MaxExtended) then
    ArcCscH:=CopySign(ln(2.0)-ln(abs(X)),X)
  else
    begin
      R:=1.0/X;
      ArcCscH:=arsinh(R);
    end;
end;
{$ENDIF}

{$ifdef FPC_HAS_TYPE_SINGLE}
function ArcCotH(X: Single): Single;
begin
  ArcCotH:=artanh(1.0/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function ArcCotH(X: Double): Double;
begin
  ArcCotH:=artanh(1.0/X);
end;
{$ENDIF}
{$ifdef FPC_HAS_TYPE_EXTENDED}
function ArcCotH(X: Extended): Extended;
begin
  ArcCotH:=artanh(1.0/X);
end;
{$ENDIF}

{ hypot function from AMath library (C) Copyright 2009-2013 Wolfgang Ehrhardt }
function hypot(x,y : float) : float;
  begin
    x:=abs(x);
    y:=abs(y);
    if IsInfinite(x) or IsInfinite(y) then
      hypot:=Infinity
    else if IsNan(x) then
      hypot:=x
    else if IsNan(y) then
      hypot:=y
    else if (x>y) then
      hypot:=x*sqrt(1.0+sqr(y/x))
    else if (x>0.0) then
      hypot:=y*sqrt(1.0+sqr(x/y))
    else
      hypot:=y;
  end;

function log10(x : float) : float;
  begin
    log10:=ln(x)*0.43429448190325182765;  { 1/ln(10) }
  end;

{$ifndef FPC_MATH_HAS_LOG2}
function log2(x : float) : float;
  begin
    log2:=ln(x)*1.4426950408889634079;    { 1/ln(2) }
  end;
{$endif FPC_MATH_HAS_LOG2}

function logn(n,x : float) : float;
  begin
     logn:=ln(x)/ln(n);
  end;

{ lnxp1 function from AMath library (C) Copyright 2009-2013 Wolfgang Ehrhardt }
function lnxp1(x : float) : float;
  var
    y: float;
  begin
    if (x>=4.0) then
      lnxp1:=ln(1.0+x)
    else
      begin
        y:=1.0+x;
        if (y=1.0) then
          lnxp1:=x
        else
          begin
            lnxp1:=ln(y);     { lnxp1(-1) = ln(0) = -Inf }
            if y>0.0 then
              lnxp1:=lnxp1+(x-(y-1.0))/y;
          end;
      end;
  end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
{ Ref: Boost, expm1.hpp }
function PolyEval(x: double; const a: array of double): double;
var
  i : sizeint;
begin
  result:=a[High(a)];
  for i:=High(a)-1 downto 0 do result:=result*x+a[i];
end;

function ExpM1(x : double) : double;
const
  P: array[0..5] of double = (
    -2.8127670288085937500E-2,
    +5.1278186299064532072E-1,
    -6.3100290693501981387E-2,
    +1.1638457975729295593E-2,
    -5.2143390687520998431E-4,
    +2.1491399776965686808E-5);
  Q: array[0..5] of double = (
    +1.0000000000000000000,
    -4.5442309511354755935E-1,
    +9.0850389570911710413E-2,
    -1.0088963629815501238E-2,
    +6.3003407478692265934E-4,
    -1.7976570003654402936E-5);
var
  a : double;
begin
  a:=abs(x);
  if a>0.5 then
    result:=exp(x)-1.0
  else if a<3e-16 then
    result:=x
  else
    result:=x*double(0.10281276702880859e1)+x*(PolyEval(x,P)/PolyEval(x,Q));
end;
{$endif}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function PolyEval(x: extended; const a: array of extended): extended;
var
  i : sizeint;
begin
  result:=a[High(a)];
  for i:=High(a)-1 downto 0 do result:=result*x+a[i];
end;

function ExpM1(x : extended) : extended;
const
  P: array[0..9] of extended = (
    -0.28127670288085937499999999999999999854e-1,
    +0.51278156911210477556524452177540792214e0,
    -0.63263178520747096729500254678819588223e-1,
    +0.14703285606874250425508446801230572252e-1,
    -0.8675686051689527802425310407898459386e-3,
    +0.88126359618291165384647080266133492399e-4,
    -0.25963087867706310844432390015463138953e-5,
    +0.14226691087800461778631773363204081194e-6,
    -0.15995603306536496772374181066765665596e-8,
    +0.45261820069007790520447958280473183582e-10);
  Q: array[0..10] of extended = (
    +1,
    -0.45441264709074310514348137469214538853e0,
    +0.96827131936192217313133611655555298106e-1,
    -0.12745248725908178612540554584374876219e-1,
    +0.11473613871583259821612766907781095472e-2,
    -0.73704168477258911962046591907690764416e-4,
    +0.34087499397791555759285503797256103259e-5,
    -0.11114024704296196166272091230695179724e-6,
    +0.23987051614110848595909588343223896577e-8,
    -0.29477341859111589208776402638429026517e-10,
    +0.13222065991022301420255904060628100924e-12);
var
  a : extended;
begin
  a:=abs(x);
  if a>0.5 then
    result:=exp(x)-1
  else if a<2e-19 then
    result:=x
  else
    result:=x*extended(0.10281276702880859375e1)+x*(PolyEval(x,P)/PolyEval(x,Q));
end;
{$endif}


function power(base,exponent : float) : float;
  begin
    if Exponent=0.0 then
      result:=1.0
    else if (base=0.0) and (exponent>0.0) then
      result:=0.0
    else if (frac(exponent)=0.0) and (abs(exponent)<=maxint) then
      result:=intpower(base,trunc(exponent))
    else
      result:=exp(exponent * ln (base));
  end;


function intpower(base : float;exponent : longint) : float;
  var
    magnitude: cardinal;
  begin
    if exponent<0 then
      begin
        base:=1.0/base;
        magnitude:=cardinal(-int64(exponent));
      end
    else
      magnitude:=cardinal(exponent);
    intpower:=1.0;
    while magnitude<>0 do
      begin
        if magnitude and 1<>0 then
          intpower:=intpower*base;
        magnitude:=magnitude shr 1;
        if magnitude<>0 then
          base:=sqr(base);
      end;
  end;


operator ** (base,exponent : float) e: float; inline;
  begin
    e:=power(base,exponent);
  end;


operator ** (base,exponent : int64) res: int64;
begin
  if exponent<0 then
    begin
      if base<=0 then
        raise EInvalidArgument.Create('Non-positive base with negative exponent in **');
      if base=1 then
        res:=1
      else
        res:=0;
      exit;
    end;
  res:=1;
  while exponent<>0 do
    begin
      if exponent and 1<>0 then
        res:=res*base;
      exponent:=exponent shr 1;
      base:=base*base;
    end;
end;


function ceil(x : float) : integer;
  begin
    Result:=Trunc(x)+ord(Frac(x)>0);
  end;


function ceil64(x: float): Int64;
  begin
    Result:=Trunc(x)+ord(Frac(x)>0);
  end;


function floor(x : float) : integer;
  begin
    Result:=Trunc(x)-ord(Frac(x)<0);
  end;


function floor64(x: float): Int64;
  begin
    Result:=Trunc(x)-ord(Frac(x)<0);
  end;


{ Divide an unsigned significand by 2**Shift and round the final result to
  nearest, ties to even.  Shift is proven to be in 1..63 by the caller;
  binary80 handles its distinct Shift=64 boundary before calling here. }
function RoundedShiftRightToEven(M: QWord; Shift: Integer): QWord; inline;
var
  Half, Remainder: QWord;
begin
  Result:=M shr Shift;
  Half:=QWord(1) shl (Shift-1);
  Remainder:=M and ((QWord(1) shl Shift)-1);
  if (Remainder>Half) or ((Remainder=Half) and Odd(Result)) then
    Inc(Result);
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
procedure Frexp(X: single; out Mantissa: single; out Exponent: integer);
  var
    M: uint32;
    E, ExtraE: int32;
  begin
    Mantissa := X;
    E := TSingleRec(X).Exp;
    if (E > 0) and (E < 2 * TSingleRec.Bias + 1) then
    begin
      // Normal.
      TSingleRec(Mantissa).Exp := TSingleRec.Bias - 1;
      Exponent := E - (TSingleRec.Bias - 1);
      exit;
    end;
    if E = 0 then
    begin
      M := TSingleRec(X).Frac;
      if M <> 0 then
      begin
        // Subnormal.
        ExtraE := 23 - BsrDWord(M);
        TSingleRec(Mantissa).Frac := M shl ExtraE; // "and (1 shl 23 - 1)" required to remove starting 1, but .SetFrac already does it.
        TSingleRec(Mantissa).Exp  := TSingleRec.Bias - 1;
        Exponent := -TSingleRec.Bias + 2 - ExtraE;
        exit;
      end;
    end;
    // ±0, ±Inf, NaN.
    Exponent := 0;
  end;


function Ldexp(X: single; p: integer): single;
var
  Bits, SignBits: DWord;
  M: QWord;
  E, ExtraE, Unbiased, Shift: Integer;
begin
  Bits:=TSingleRec(X).Data;
  SignBits:=Bits and $80000000;
  E:=(Bits shr 23) and $ff;
  M:=Bits and $7fffff;
  if E=0 then
    begin
      if M=0 then
        exit(X);
      ExtraE:=23-BsrDWord(DWord(M));
      M:=M shl ExtraE;
      Unbiased:=1-TSingleRec.Bias-ExtraE;
    end
  else
    begin
      if E=$ff then
        exit(X);
      M:=M or QWord(1) shl 23;
      Unbiased:=E-TSingleRec.Bias;
    end;

  if p>TSingleRec.Bias-Unbiased then
    begin
      TSingleRec(Result).Data:=SignBits or $7f800000;
      exit;
    end;
  if p<1-TSingleRec.Bias-24-Unbiased then
    begin
      TSingleRec(Result).Data:=SignBits;
      exit;
    end;
  Inc(Unbiased,p);
  if Unbiased>=1-TSingleRec.Bias then
    TSingleRec(Result).Data:=SignBits or (DWord(Unbiased+TSingleRec.Bias) shl 23) or
      DWord(M and $7fffff)
  else
    begin
      Shift:=1-TSingleRec.Bias-Unbiased;
      M:=RoundedShiftRightToEven(M,Shift);
      if M=QWord(1) shl 23 then
        TSingleRec(Result).Data:=SignBits or $00800000
      else
        TSingleRec(Result).Data:=SignBits or DWord(M);
    end;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_DOUBLE}
procedure Frexp(X: double; out Mantissa: double; out Exponent: integer);
  var
    M: uint64;
    E, ExtraE: int32;
  begin
    Mantissa := X;
    E := TDoubleRec(X).Exp;
    if (E > 0) and (E < 2 * TDoubleRec.Bias + 1) then
    begin
      // Normal.
      TDoubleRec(Mantissa).Exp := TDoubleRec.Bias - 1;
      Exponent := E - (TDoubleRec.Bias - 1);
      exit;
    end;
    if E = 0 then
    begin
      M := TDoubleRec(X).Frac;
      if M <> 0 then
      begin
        // Subnormal.
        ExtraE := 52 - BsrQWord(M);
        TDoubleRec(Mantissa).Frac := M shl ExtraE; // "and (1 shl 52 - 1)" required to remove starting 1, but .SetFrac already does it.
        TDoubleRec(Mantissa).Exp  := TDoubleRec.Bias - 1;
        Exponent := -TDoubleRec.Bias + 2 - ExtraE;
        exit;
      end;
    end;
    // ±0, ±Inf, NaN.
    Exponent := 0;
  end;

function Ldexp(X: double; p: integer): double;
var
  Bits, SignBits, M: QWord;
  E, ExtraE, Unbiased, Shift: Integer;
begin
  Bits:=TDoubleRec(X).Data;
  SignBits:=Bits and QWord($8000000000000000);
  E:=Integer((Bits shr 52) and $7ff);
  M:=Bits and QWord($000fffffffffffff);
  if E=0 then
    begin
      if M=0 then
        exit(X);
      ExtraE:=52-BsrQWord(M);
      M:=M shl ExtraE;
      Unbiased:=1-TDoubleRec.Bias-ExtraE;
    end
  else
    begin
      if E=$7ff then
        exit(X);
      M:=M or QWord(1) shl 52;
      Unbiased:=E-TDoubleRec.Bias;
    end;

  if p>TDoubleRec.Bias-Unbiased then
    begin
      TDoubleRec(Result).Data:=SignBits or QWord($7ff0000000000000);
      exit;
    end;
  if p<1-TDoubleRec.Bias-53-Unbiased then
    begin
      TDoubleRec(Result).Data:=SignBits;
      exit;
    end;
  Inc(Unbiased,p);
  if Unbiased>=1-TDoubleRec.Bias then
    TDoubleRec(Result).Data:=SignBits or (QWord(Unbiased+TDoubleRec.Bias) shl 52) or
      (M and QWord($000fffffffffffff))
  else
    begin
      Shift:=1-TDoubleRec.Bias-Unbiased;
      M:=RoundedShiftRightToEven(M,Shift);
      if M=QWord(1) shl 52 then
        TDoubleRec(Result).Data:=SignBits or QWord($0010000000000000)
      else
        TDoubleRec(Result).Data:=SignBits or M;
    end;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure Frexp(X: extended; out Mantissa: extended; out Exponent: integer);
  var
    M: uint64;
    E, ExtraE: int32;
  begin
    Mantissa := X;
    E := TExtended80Rec(X).Exp;
    if (E > 0) and (E < 2 * TExtended80Rec.Bias + 1) then
    begin
      // Normal.
      TExtended80Rec(Mantissa).Exp := TExtended80Rec.Bias - 1;
      Exponent := E - (TExtended80Rec.Bias - 1);
      exit;
    end;
    if E = 0 then
    begin
      M := TExtended80Rec(X).Frac;
      if M <> 0 then
      begin
        // Subnormal. Extended has explicit starting 1.
        ExtraE := 63 - BsrQWord(M);
        TExtended80Rec(Mantissa).Frac := M shl ExtraE;
        TExtended80Rec(Mantissa).Exp  := TExtended80Rec.Bias - 1;
        Exponent := -TExtended80Rec.Bias + 2 - ExtraE;
        exit;
      end;
    end;
    // ±0, ±Inf, NaN.
    Exponent := 0;
  end;

function Ldexp(X: extended; p: integer): extended;
var
  Input, Output: TExtended80Rec;
  M: QWord;
  SignBits: Word;
  E, ExtraE, Unbiased, Shift: Integer;
begin
  Input.Value:=X;
  SignBits:=Input._Exp and $8000;
  E:=Input._Exp and $7fff;
  M:=Input.Frac;
  if E=0 then
    begin
      if M=0 then
        exit(X);
      ExtraE:=63-BsrQWord(M);
      M:=M shl ExtraE;
      Unbiased:=1-TExtended80Rec.Bias-ExtraE;
    end
  else
    begin
      if E=$7fff then
        exit(X);
      Unbiased:=E-TExtended80Rec.Bias;
    end;

  if p>TExtended80Rec.Bias-Unbiased then
    begin
      Output._Exp:=SignBits or $7fff;
      Output.Frac:=QWord(1) shl 63;
      exit(Output.Value);
    end;
  if p<1-TExtended80Rec.Bias-64-Unbiased then
    begin
      Output._Exp:=SignBits;
      Output.Frac:=0;
      exit(Output.Value);
    end;
  Inc(Unbiased,p);
  if Unbiased>=1-TExtended80Rec.Bias then
    begin
      Output._Exp:=SignBits or Word(Unbiased+TExtended80Rec.Bias);
      Output.Frac:=M;
    end
  else
    begin
      Shift:=1-TExtended80Rec.Bias-Unbiased;
      if Shift=64 then
        begin
          if M>QWord($8000000000000000) then
            M:=1
          else
            M:=0;
        end
      else
        M:=RoundedShiftRightToEven(M,Shift);
      Output._Exp:=SignBits or Word(M shr 63);
      Output.Frac:=M;
    end;
  Result:=Output.Value;
end;
{$endif}

const
  { Cutoff for https://en.wikipedia.org/wiki/Pairwise_summation; sums of at least this many elements are split in two halves. }
  RecursiveSumThreshold=12;

{$ifdef FPC_HAS_TYPE_SINGLE}
function mean(const data : array of Single) : float;

  begin
     Result:=Mean(PSingle(@data[0]),High(Data)+1);
  end;

function mean(const data : PSingle; Const N : longint) : float;
  begin
     mean:=sum(Data,N);
     mean:=mean/N;
  end;

function sum(const data : array of Single) : float;inline;
  begin
     Result:=Sum(PSingle(@Data[0]),High(Data)+1);
  end;

function sum(const data : PSingle;Const N : longint) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sum(data,longword(N) div 2)+sum(data+longword(N) div 2,N-longword(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+data[i];
      end;
  end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function mean(const data : array of Double) : float; inline;
  begin
     Result:=Mean(PDouble(@data[0]),High(Data)+1);
  end;

function mean(const data : PDouble; Const N : longint) : float;
  begin
     mean:=sum(Data,N);
     mean:=mean/N;
  end;

function sum(const data : array of Double) : float; inline;
  begin
     Result:=Sum(PDouble(@Data[0]),High(Data)+1);
  end;

function sum(const data : PDouble;Const N : longint) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sum(data,longword(N) div 2)+sum(data+longword(N) div 2,N-longword(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+data[i];
      end;
  end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function mean(const data : array of Extended) : float;
  begin
     Result:=Mean(PExtended(@data[0]),High(Data)+1);
  end;

function mean(const data : PExtended; Const N : longint) : float;
  begin
     mean:=sum(Data,N);
     mean:=mean/N;
  end;

function sum(const data : array of Extended) : float; inline;
  begin
     Result:=Sum(PExtended(@Data[0]),High(Data)+1);
  end;

function sum(const data : PExtended;Const N : longint) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sum(data,longword(N) div 2)+sum(data+longword(N) div 2,N-longword(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+data[i];
      end;
  end;
{$endif FPC_HAS_TYPE_EXTENDED}

function sumInt(const data : PInt64;Const N : longint) : Int64;
  var
     i : SizeInt;
  begin
     sumInt:=0;
     for i:=0 to N-1 do
       sumInt:=sumInt+data[i];
  end;

function sumInt(const data : array of Int64) : Int64; inline;
  begin
     Result:=SumInt(PInt64(@Data[0]),High(Data)+1);
  end;

function mean(const data : PInt64; const N : Longint):Float;
  begin
     mean:=sumInt(Data,N);
     mean:=mean/N;
  end;

function mean(const data: array of Int64):Float;
  begin
     mean:=mean(PInt64(@data[0]),High(Data)+1);
  end;

function sumInt(const data : PInteger; Const N : longint) : Int64;
var
   i : SizeInt;
  begin
     sumInt:=0;
     for i:=0 to N-1 do
       sumInt:=sumInt+data[i];
  end;

function sumInt(const data : array of Integer) : Int64;inline;
  begin
     Result:=sumInt(PInteger(@Data[0]),High(Data)+1);
  end;

function mean(const data : PInteger; const N : Longint):Float;
  begin
     mean:=sumInt(Data,N);
     mean:=mean/N;
  end;

function mean(const data: array of Integer):Float;
  begin
     mean:=mean(PInteger(@data[0]),High(Data)+1);
  end;

{$ifdef FPC_HAS_TYPE_SINGLE}
 function sumofsquares(const data : array of Single) : float; inline;
 begin
   Result:=sumofsquares(PSingle(@data[0]),High(Data)+1);
 end;

 function sumofsquares(const data : PSingle; Const N : Integer) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sumofsquares(data,cardinal(N) div 2)+sumofsquares(data+cardinal(N) div 2,N-cardinal(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+sqr(data[i]);
      end;
  end;

procedure sumsandsquares(const data : array of Single;
  var sum,sumofsquares : float); inline;
begin
  sumsandsquares (PSingle(@Data[0]),High(Data)+1,Sum,sumofsquares);
end;

procedure sumsandsquares(const data : PSingle; Const N : Integer;
  var sum,sumofsquares : float);
  var
     i : SizeInt;
     temp,tsum,tsumofsquares,sum0,sumofsquares0,sum1,sumofsquares1 : float;
  begin
    if N>=RecursiveSumThreshold then
      begin
        sumsandsquares(data,cardinal(N) div 2,sum0,sumofsquares0);
        sumsandsquares(data+cardinal(N) div 2,N-cardinal(N) div 2,sum1,sumofsquares1);
        sum:=sum0+sum1;
        sumofsquares:=sumofsquares0+sumofsquares1;
      end
    else
      begin
        tsum:=0;
        tsumofsquares:=0;
        for i:=0 to N-1 do
          begin
            temp:=data[i];
            tsum:=tsum+temp;
            tsumofsquares:=tsumofsquares+sqr(temp);
          end;
        sum:=tsum;
        sumofsquares:=tsumofsquares;
      end;
  end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
 function sumofsquares(const data : array of Double) : float; inline;
 begin
   Result:=sumofsquares(PDouble(@data[0]),High(Data)+1);
 end;

 function sumofsquares(const data : PDouble; Const N : Integer) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sumofsquares(data,cardinal(N) div 2)+sumofsquares(data+cardinal(N) div 2,N-cardinal(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+sqr(data[i]);
      end;
  end;

procedure sumsandsquares(const data : array of Double;
  var sum,sumofsquares : float); inline;
begin
  sumsandsquares (PDouble(@Data[0]),High(Data)+1,Sum,sumofsquares);
end;

procedure sumsandsquares(const data : PDouble; Const N : Integer;
  var sum,sumofsquares : float);
  var
     i : SizeInt;
     temp,tsum,tsumofsquares,sum0,sumofsquares0,sum1,sumofsquares1 : float;
  begin
    if N>=RecursiveSumThreshold then
      begin
        sumsandsquares(data,cardinal(N) div 2,sum0,sumofsquares0);
        sumsandsquares(data+cardinal(N) div 2,N-cardinal(N) div 2,sum1,sumofsquares1);
        sum:=sum0+sum1;
        sumofsquares:=sumofsquares0+sumofsquares1;
      end
    else
      begin
        tsum:=0;
        tsumofsquares:=0;
        for i:=0 to N-1 do
          begin
            temp:=data[i];
            tsum:=tsum+temp;
            tsumofsquares:=tsumofsquares+sqr(temp);
          end;
        sum:=tsum;
        sumofsquares:=tsumofsquares;
      end;
  end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
 function sumofsquares(const data : array of Extended) : float; inline;
 begin
   Result:=sumofsquares(PExtended(@data[0]),High(Data)+1);
 end;

 function sumofsquares(const data : PExtended; Const N : Integer) : float;
  var
     i : SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=sumofsquares(data,cardinal(N) div 2)+sumofsquares(data+cardinal(N) div 2,N-cardinal(N) div 2)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+sqr(data[i]);
      end;
  end;

procedure sumsandsquares(const data : array of Extended;
  var sum,sumofsquares : float); inline;
begin
  sumsandsquares (PExtended(@Data[0]),High(Data)+1,Sum,sumofsquares);
end;

procedure sumsandsquares(const data : PExtended; Const N : Integer;
  var sum,sumofsquares : float);
  var
     i : SizeInt;
     temp,tsum,tsumofsquares,sum0,sumofsquares0,sum1,sumofsquares1 : float;
  begin
    if N>=RecursiveSumThreshold then
      begin
        sumsandsquares(data,cardinal(N) div 2,sum0,sumofsquares0);
        sumsandsquares(data+cardinal(N) div 2,N-cardinal(N) div 2,sum1,sumofsquares1);
        sum:=sum0+sum1;
        sumofsquares:=sumofsquares0+sumofsquares1;
      end
    else
      begin
        tsum:=0;
        tsumofsquares:=0;
        for i:=0 to N-1 do
          begin
            temp:=data[i];
            tsum:=tsum+temp;
            tsumofsquares:=tsumofsquares+sqr(temp);
          end;
        sum:=tsum;
        sumofsquares:=tsumofsquares;
      end;
  end;
{$endif FPC_HAS_TYPE_EXTENDED}

function randg(mean,stddev : float) : float;
  Var U1,S2 : Float;
  begin
     repeat
       u1:= 2*random-1;
       S2:=Sqr(U1)+sqr(2*random-1);
     until s2<1;
     randg:=Sqrt(-2*ln(S2)/S2)*u1*stddev+Mean;
  end;


function RandomRange(const aFrom, aTo: Integer): Integer;
begin
  Result:=Random(Abs(aFrom-aTo))+Min(aTo,AFrom);
end;


function RandomBelowQWord(Bound: QWord): QWord;
var
  LowProduct, Threshold: QWord;
  RandomValue: QWord;
begin
  repeat
    RandomValue:=(QWord(Random(Int64(QWord(1) shl 32))) shl 32) or
      QWord(Random(Int64(QWord(1) shl 32)));
    LowProduct:=UMul64x64_128(RandomValue,Bound,Result);
    if LowProduct<Bound then
      begin
        Threshold:=QWord(-Bound) mod Bound;
        if LowProduct<Threshold then
          Continue;
      end;
    Exit;
  until False;
end;


function RandomRange(const aFrom, aTo: Int64): Int64;
var
  Lower, Upper: Int64;
  Span: QWord;
begin
  Lower:=Min(aFrom,aTo);
  Upper:=Max(aFrom,aTo);
  Span:=QWord(Upper)-QWord(Lower);
  if Span=0 then
    Exit(Lower);
  if Span<=QWord(High(Int64)) then
    Result:=Random(Int64(Span))+Lower
  else
    Result:=Int64(QWord(Lower)+RandomBelowQWord(Span));
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
procedure MeanAndTotalVariance
  (const data: PSingle; N: LongInt; var mu, variance: float);

  function CalcVariance(data: PSingle; N: SizeInt; mu: float): float;
  var
    i: SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=CalcVariance(data,SizeUint(N) div 2,mu)+CalcVariance(data+SizeUint(N) div 2,N-SizeUint(N) div 2,mu)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+Sqr(data[i]-mu);
      end;
  end;

begin
  mu := Mean( data, N );
  variance := CalcVariance( data, N, mu );
end;

function stddev(const data : array of Single) : float; inline;
begin
  Result:=Stddev(PSingle(@Data[0]),High(Data)+1);
end;

function stddev(const data : PSingle; Const N : Integer) : float;
  begin
     StdDev:=Sqrt(Variance(Data,N));
  end;

procedure meanandstddev(const data : array of Single;
  var mean,stddev : float); inline;
begin
  Meanandstddev(PSingle(@Data[0]),High(Data)+1,Mean,stddev);
end;

procedure meanandstddev
( const data:   PSingle;
  const N:      Longint;
  var   mean,
        stdDev: Float
);
var totalVariance: float;
begin
  MeanAndTotalVariance( data, N, mean, totalVariance );
  if N < 2 then stdDev := 0
  else stdDev := Sqrt( totalVariance / ( N - 1 ) );
end;

function variance(const data : array of Single) : float; inline;
  begin
     Variance:=Variance(PSingle(@Data[0]),High(Data)+1);
  end;

function variance(const data : PSingle; Const N : Integer) : float;
  begin
     If N=1 then
       Result:=0
     else
       Result:=TotalVariance(Data,N)/(N-1);
  end;

function totalvariance(const data : array of Single) : float; inline;
begin
  Result:=TotalVariance(PSingle(@Data[0]),High(Data)+1);
end;

function totalvariance(const data : PSingle; const N : Integer) : float;
var mu: float;
begin
  MeanAndTotalVariance( data, N, mu, result );
end;

function popnstddev(const data : array of Single) : float;
  begin
     PopnStdDev:=Sqrt(PopnVariance(PSingle(@Data[0]),High(Data)+1));
  end;

function popnstddev(const data : PSingle; Const N : Integer) : float;
  begin
     PopnStdDev:=Sqrt(PopnVariance(Data,N));
  end;

function popnvariance(const data : array of Single) : float; inline;

begin
  popnvariance:=popnvariance(PSingle(@data[0]),high(Data)+1);
end;

function popnvariance(const data : PSingle; Const N : Integer) : float;

  begin
     PopnVariance:=TotalVariance(Data,N)/N;
  end;

procedure momentskewkurtosis(const data : array of single;
  out m1,m2,m3,m4,skew,kurtosis : float); inline;
begin
  momentskewkurtosis(PSingle(@Data[0]),High(Data)+1,m1,m2,m3,m4,skew,kurtosis);
end;

type
  TMoments2to4 = array[2 .. 4] of float;

procedure momentskewkurtosis(
  const data: pSingle;
  Const N: integer;
  out m1: float;
  out m2: float;
  out m3: float;
  out m4: float;
  out skew: float;
  out kurtosis: float
);

  procedure CalcDevSums2to4(data: PSingle; N: SizeInt; m1: float; out m2to4: TMoments2to4);
  var
    tm2, tm3, tm4, dev, dev2: float;
    i: SizeInt;
    m2to4Part0, m2to4Part1: TMoments2to4;
  begin
    if N >= RecursiveSumThreshold then
      begin
        CalcDevSums2to4(data, SizeUint(N) div 2, m1, m2to4Part0);
        CalcDevSums2to4(data + SizeUint(N) div 2, N - SizeUint(N) div 2, m1, m2to4Part1);
        for i := Low(TMoments2to4) to High(TMoments2to4) do
          m2to4[i] := m2to4Part0[i] + m2to4Part1[i];
      end
    else
      begin
        tm2 := 0;
        tm3 := 0;
        tm4 := 0;
        for i := 0 to N - 1 do
          begin
            dev := data[i] - m1;
            dev2 := sqr(dev);
            tm2 := tm2 + dev2;
            tm3 := tm3 + dev2 * dev;
            tm4 := tm4 + sqr(dev2);
          end;
        m2to4[2] := tm2;
        m2to4[3] := tm3;
        m2to4[4] := tm4;
      end;
  end;

var
  reciprocalN: float;
  m2to4: TMoments2to4;
begin
  m1 := 0;
  reciprocalN := 1/N;
  m1 := reciprocalN * sum(data, N);
  CalcDevSums2to4(data, N, m1, m2to4);
  m2 := reciprocalN * m2to4[2];
  m3 := reciprocalN * m2to4[3];
  m4 := reciprocalN * m2to4[4];
  skew := m3 / (sqrt(m2)*m2);
  kurtosis := m4 / (m2 * m2);
end;

function norm(const data : array of Single) : float; inline;
  begin
     norm:=Norm(PSingle(@data[0]),High(Data)+1);
  end;

function norm(const data : PSingle; Const N : Integer) : float;
  var
    i: SizeInt;
  begin
     if FloatExceptionsUnmasked([exOverflow,exUnderflow]) then
       exit(NormUnmaskedSingle(Data,N));
     norm:=sumofsquares(data,N);
     if (norm=0.0) or IsInfinite(norm) or IsNan(norm) or (norm<MinSingle) then
       begin
         norm:=0;
         for i:=0 to N-1 do
           norm:=hypot(norm,data[i]);
       end
     else
       norm:=sqrt(norm);
  end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
procedure MeanAndTotalVariance
  (const data: PDouble; N: LongInt; var mu, variance: float);

  function CalcVariance(data: PDouble; N: SizeInt; mu: float): float;
  var
    i: SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=CalcVariance(data,SizeUint(N) div 2,mu)+CalcVariance(data+SizeUint(N) div 2,N-SizeUint(N) div 2,mu)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+Sqr(data[i]-mu);
      end;
  end;

begin
  mu := Mean( data, N );
  variance := CalcVariance( data, N, mu );
end;

function stddev(const data : array of Double) : float; inline;
begin
  Result:=Stddev(PDouble(@Data[0]),High(Data)+1)
end;

function stddev(const data : PDouble; Const N : Integer) : float;
  begin
     StdDev:=Sqrt(Variance(Data,N));
  end;

procedure meanandstddev(const data : array of Double;
  var mean,stddev : float);

begin
  Meanandstddev(PDouble(@Data[0]),High(Data)+1,Mean,stddev);
end;

procedure meanandstddev
( const data:   PDouble;
  const N:      Longint;
  var   mean,
        stdDev: Float
);
var totalVariance: float;
begin
  MeanAndTotalVariance( data, N, mean, totalVariance );
  if N < 2 then stdDev := 0
  else stdDev := Sqrt( totalVariance / ( N - 1 ) );
end;

function variance(const data : array of Double) : float; inline;
  begin
     Variance:=Variance(PDouble(@Data[0]),High(Data)+1);
  end;

function variance(const data : PDouble; Const N : Integer) : float;

  begin
     If N=1 then
       Result:=0
     else
       Result:=TotalVariance(Data,N)/(N-1);
  end;

function totalvariance(const data : array of Double) : float; inline;
begin
  Result:=TotalVariance(PDouble(@Data[0]),High(Data)+1);
end;

function totalvariance(const data : PDouble; const N : Integer) : float;
var mu: float;
begin
  MeanAndTotalVariance( data, N, mu, result );
end;

function popnstddev(const data : array of Double) : float;

  begin
     PopnStdDev:=Sqrt(PopnVariance(PDouble(@Data[0]),High(Data)+1));
  end;

function popnstddev(const data : PDouble; Const N : Integer) : float;

  begin
     PopnStdDev:=Sqrt(PopnVariance(Data,N));
  end;

function popnvariance(const data : array of Double) : float; inline;

begin
  popnvariance:=popnvariance(PDouble(@data[0]),high(Data)+1);
end;

function popnvariance(const data : PDouble; Const N : Integer) : float;

  begin
     PopnVariance:=TotalVariance(Data,N)/N;
  end;

procedure momentskewkurtosis(const data : array of Double;
  out m1,m2,m3,m4,skew,kurtosis : float);
begin
  momentskewkurtosis(PDouble(@Data[0]),High(Data)+1,m1,m2,m3,m4,skew,kurtosis);
end;

procedure momentskewkurtosis(
  const data: pdouble;
  Const N: integer;
  out m1: float;
  out m2: float;
  out m3: float;
  out m4: float;
  out skew: float;
  out kurtosis: float
);

  procedure CalcDevSums2to4(data: PDouble; N: SizeInt; m1: float; out m2to4: TMoments2to4);
  var
    tm2, tm3, tm4, dev, dev2: float;
    i: SizeInt;
    m2to4Part0, m2to4Part1: TMoments2to4;
  begin
    if N >= RecursiveSumThreshold then
      begin
        CalcDevSums2to4(data, SizeUint(N) div 2, m1, m2to4Part0);
        CalcDevSums2to4(data + SizeUint(N) div 2, N - SizeUint(N) div 2, m1, m2to4Part1);
        for i := Low(TMoments2to4) to High(TMoments2to4) do
          m2to4[i] := m2to4Part0[i] + m2to4Part1[i];
      end
    else
      begin
        tm2 := 0;
        tm3 := 0;
        tm4 := 0;
        for i := 0 to N - 1 do
          begin
            dev := data[i] - m1;
            dev2 := sqr(dev);
            tm2 := tm2 + dev2;
            tm3 := tm3 + dev2 * dev;
            tm4 := tm4 + sqr(dev2);
          end;
        m2to4[2] := tm2;
        m2to4[3] := tm3;
        m2to4[4] := tm4;
      end;
  end;

var
  reciprocalN: float;
  m2to4: TMoments2to4;
begin
  m1 := 0;
  reciprocalN := 1/N;
  m1 := reciprocalN * sum(data, N);
  CalcDevSums2to4(data, N, m1, m2to4);
  m2 := reciprocalN * m2to4[2];
  m3 := reciprocalN * m2to4[3];
  m4 := reciprocalN * m2to4[4];
  skew := m3 / (sqrt(m2)*m2);
  kurtosis := m4 / (m2 * m2);
end;


function norm(const data : array of Double) : float; inline;
  begin
     norm:=Norm(PDouble(@data[0]),High(Data)+1);
  end;

function norm(const data : PDouble; Const N : Integer) : float;
  var
    i: SizeInt;
  begin
     if FloatExceptionsUnmasked([exOverflow,exUnderflow]) then
       exit(NormUnmaskedDouble(Data,N));
     norm:=sumofsquares(data,N);
     if (norm=0.0) or IsInfinite(norm) or IsNan(norm) or (norm<MinDouble) then
       begin
         norm:=0;
         for i:=0 to N-1 do
           norm:=hypot(norm,data[i]);
       end
     else
       norm:=sqrt(norm);
  end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
procedure MeanAndTotalVariance
  (const data: PExtended; N: LongInt; var mu, variance: float);

  function CalcVariance(data: PExtended; N: SizeInt; mu: float): float;
  var
    i: SizeInt;
  begin
    if N>=RecursiveSumThreshold then
      result:=CalcVariance(data,SizeUint(N) div 2,mu)+CalcVariance(data+SizeUint(N) div 2,N-SizeUint(N) div 2,mu)
    else
      begin
        result:=0;
        for i:=0 to N-1 do
          result:=result+Sqr(data[i]-mu);
      end;
  end;

begin
  mu := Mean( data, N );
  variance := CalcVariance( data, N, mu );
end;

function stddev(const data : array of Extended) : float; inline;
begin
  Result:=Stddev(PExtended(@Data[0]),High(Data)+1)
end;

function stddev(const data : PExtended; Const N : Integer) : float;
  begin
     StdDev:=Sqrt(Variance(Data,N));
  end;

procedure meanandstddev(const data : array of Extended;
  var mean,stddev : float); inline;
begin
  Meanandstddev(PExtended(@Data[0]),High(Data)+1,Mean,stddev);
end;

procedure meanandstddev
( const data:   PExtended;
  const N:      Longint;
  var   mean,
        stdDev: Float
);
var totalVariance: float;
begin
  MeanAndTotalVariance( data, N, mean, totalVariance );
  if N < 2 then stdDev := 0
  else stdDev := Sqrt( totalVariance / ( N - 1 ) );
end;

function variance(const data : array of Extended) : float; inline;
  begin
     Variance:=Variance(PExtended(@Data[0]),High(Data)+1);
  end;

function variance(const data : PExtended; Const N : Integer) : float;

  begin
     If N=1 then
       Result:=0
     else
       Result:=TotalVariance(Data,N)/(N-1);
  end;

function totalvariance(const data : array of Extended) : float; inline;
begin
  Result:=TotalVariance(PExtended(@Data[0]),High(Data)+1);
end;

function totalvariance(const data : PExtended;Const N : Integer) : float;
var mu: float;
begin
  MeanAndTotalVariance( data, N, mu, result );
end;

function popnstddev(const data : array of Extended) : float;

  begin
     PopnStdDev:=Sqrt(PopnVariance(PExtended(@Data[0]),High(Data)+1));
  end;

function popnstddev(const data : PExtended; Const N : Integer) : float;

  begin
     PopnStdDev:=Sqrt(PopnVariance(Data,N));
  end;

function popnvariance(const data : array of Extended) : float; inline;
begin
  popnvariance:=popnvariance(PExtended(@data[0]),high(Data)+1);
end;

function popnvariance(const data : PExtended; Const N : Integer) : float;

  begin
     PopnVariance:=TotalVariance(Data,N)/N;
  end;

procedure momentskewkurtosis(const data : array of Extended;
  out m1,m2,m3,m4,skew,kurtosis : float); inline;
begin
  momentskewkurtosis(PExtended(@Data[0]),High(Data)+1,m1,m2,m3,m4,skew,kurtosis);
end;

procedure momentskewkurtosis(
  const data: pExtended;
  Const N: Integer;
  out m1: float;
  out m2: float;
  out m3: float;
  out m4: float;
  out skew: float;
  out kurtosis: float
);

  procedure CalcDevSums2to4(data: PExtended; N: SizeInt; m1: float; out m2to4: TMoments2to4);
  var
    tm2, tm3, tm4, dev, dev2: float;
    i: SizeInt;
    m2to4Part0, m2to4Part1: TMoments2to4;
  begin
    if N >= RecursiveSumThreshold then
      begin
        CalcDevSums2to4(data, SizeUint(N) div 2, m1, m2to4Part0);
        CalcDevSums2to4(data + SizeUint(N) div 2, N - SizeUint(N) div 2, m1, m2to4Part1);
        for i := Low(TMoments2to4) to High(TMoments2to4) do
          m2to4[i] := m2to4Part0[i] + m2to4Part1[i];
      end
    else
      begin
        tm2 := 0;
        tm3 := 0;
        tm4 := 0;
        for i := 0 to N - 1 do
          begin
            dev := data[i] - m1;
            dev2 := sqr(dev);
            tm2 := tm2 + dev2;
            tm3 := tm3 + dev2 * dev;
            tm4 := tm4 + sqr(dev2);
          end;
        m2to4[2] := tm2;
        m2to4[3] := tm3;
        m2to4[4] := tm4;
      end;
  end;

var
  reciprocalN: float;
  m2to4: TMoments2to4;
begin
  m1 := 0;
  reciprocalN := 1/N;
  m1 := reciprocalN * sum(data, N);
  CalcDevSums2to4(data, N, m1, m2to4);
  m2 := reciprocalN * m2to4[2];
  m3 := reciprocalN * m2to4[3];
  m4 := reciprocalN * m2to4[4];
  skew := m3 / (sqrt(m2)*m2);
  kurtosis := m4 / (m2 * m2);
end;

function norm(const data : array of Extended) : float; inline;
  begin
     norm:=Norm(PExtended(@data[0]),High(Data)+1);
  end;

function norm(const data : PExtended; Const N : Integer) : float;
  var
    i: SizeInt;
  begin
     if FloatExceptionsUnmasked([exOverflow,exUnderflow]) then
       exit(NormUnmaskedExtended(Data,N));
     norm:=sumofsquares(data,N);
     if (norm=0.0) or IsInfinite(norm) or IsNan(norm) or (norm<MinExtended) then
       begin
         norm:=0;
         for i:=0 to N-1 do
           norm:=hypot(norm,data[i]);
       end
     else
       norm:=sqrt(norm);
  end;
{$endif FPC_HAS_TYPE_EXTENDED}


function MinIntValue(const Data: array of Integer): Integer;
var
  I: SizeInt;
begin
  Result := Data[Low(Data)];
  For I := Succ(Low(Data)) To High(Data) Do
    If Data[I] < Result Then Result := Data[I];
end;

function MaxIntValue(const Data: array of Integer): Integer;
var
  I: SizeInt;
begin
  Result := Data[Low(Data)];
  For I := Succ(Low(Data)) To High(Data) Do
    If Data[I] > Result Then Result := Data[I];
end;

function MinValue(const Data: array of Integer): Integer; inline;
begin
  Result:=MinValue(Pinteger(@Data[0]),High(Data)+1)
end;

function MinValue(const Data: PInteger; Const N : Integer): Integer;
var
  I: SizeInt;
begin
  Result := Data[0];
  For I := 1 To N-1 do
    If Data[I] < Result Then Result := Data[I];
end;

function MaxValue(const Data: array of Integer): Integer; inline;
begin
  Result:=MaxValue(PInteger(@Data[0]),High(Data)+1)
end;

function maxvalue(const data : PInteger; Const N : Integer) : Integer;
var
   i : SizeInt;
begin
   { get an initial value }
   maxvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]>maxvalue then
       maxvalue:=data[i];
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function minvalue(const data : array of Single) : Single; inline;
begin
   Result:=minvalue(PSingle(@data[0]),High(Data)+1);
end;

function minvalue(const data : PSingle; Const N : Integer) : Single;
var
   i : SizeInt;
begin
   { get an initial value }
   minvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]<minvalue then
       minvalue:=data[i];
end;


function maxvalue(const data : array of Single) : Single; inline;
begin
   Result:=maxvalue(PSingle(@data[0]),High(Data)+1);
end;

function maxvalue(const data : PSingle; Const N : Integer) : Single;
var
   i : SizeInt;
begin
   { get an initial value }
   maxvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]>maxvalue then
       maxvalue:=data[i];
end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function minvalue(const data : array of Double) : Double; inline;
begin
   Result:=minvalue(PDouble(@data[0]),High(Data)+1);
end;

function minvalue(const data : PDouble; Const N : Integer) : Double;
var
   i : SizeInt;
begin
   { get an initial value }
   minvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]<minvalue then
       minvalue:=data[i];
end;


function maxvalue(const data : array of Double) : Double; inline;
begin
   Result:=maxvalue(PDouble(@data[0]),High(Data)+1);
end;

function maxvalue(const data : PDouble; Const N : Integer) : Double;
var
   i : SizeInt;
begin
   { get an initial value }
   maxvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]>maxvalue then
       maxvalue:=data[i];
end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function minvalue(const data : array of Extended) : Extended; inline;
begin
   Result:=minvalue(PExtended(@data[0]),High(Data)+1);
end;

function minvalue(const data : PExtended; Const N : Integer) : Extended;
var
   i : SizeInt;
begin
   { get an initial value }
   minvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]<minvalue then
       minvalue:=data[i];
end;


function maxvalue(const data : array of Extended) : Extended; inline;
begin
   Result:=maxvalue(PExtended(@data[0]),High(Data)+1);
end;

function maxvalue(const data : PExtended; Const N : Integer) : Extended;
var
   i : SizeInt;
begin
   { get an initial value }
   maxvalue:=data[0];
   for i:=1 to N-1 do
     if data[i]>maxvalue then
       maxvalue:=data[i];
end;
{$endif FPC_HAS_TYPE_EXTENDED}


function Min(a, b: Integer): Integer;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Integer): Integer;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;

{
function Min(a, b: Cardinal): Cardinal;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Cardinal): Cardinal;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;
}

function Min(a, b: Int64): Int64;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Int64): Int64;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;

function Min(a, b: QWord): QWord; inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: QWord): Qword;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function Min(a, b: Single): Single;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Single): Single;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function Min(a, b: Double): Double;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Double): Double;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function Min(a, b: Extended): Extended;inline;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Extended): Extended;inline;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;
{$endif FPC_HAS_TYPE_EXTENDED}

function InRange(const AValue, AMin, AMax: Integer): Boolean;inline;

begin
  Result:=(AValue>=AMin) and (AValue<=AMax);
end;

function InRange(const AValue, AMin, AMax: Int64): Boolean;inline;
begin
  Result:=(AValue>=AMin) and (AValue<=AMax);
end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function InRange(const AValue, AMin, AMax: Double): Boolean;inline;

begin
  Result:=(AValue>=AMin) and (AValue<=AMax);
end;
{$endif FPC_HAS_TYPE_DOUBLE}

function EnsureRange(const AValue, AMin, AMax: Integer): Integer;inline;

begin
  Result:=AValue;
  If Result<AMin then
    Result:=AMin;
  if Result>AMax then
    Result:=AMax;
end;

function EnsureRange(const AValue, AMin, AMax: Int64): Int64;inline;

begin
  Result:=AValue;
  If Result<AMin then
    Result:=AMin;
  if Result>AMax then
    Result:=AMax;
end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function EnsureRange(const AValue, AMin, AMax: Double): Double;inline;

begin
  Result:=AValue;
  If Result<AMin then
    Result:=AMin;
  if Result>AMax then
    Result:=AMax;
end;
{$endif FPC_HAS_TYPE_DOUBLE}

Const
  EZeroResolution = Extended(1E-16);
  DZeroResolution = Double(1E-12);
  SZeroResolution = Single(1E-4);


function IsZero(const A: Single; Epsilon: Single): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=SZeroResolution;
  Result:=Abs(A)<=Epsilon;
end;

function IsZero(const A: Single): Boolean;inline;

begin
  Result:=IsZero(A,single(SZeroResolution));
end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsZero(const A: Double; Epsilon: Double): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=DZeroResolution;
  Result:=Abs(A)<=Epsilon;
end;

function IsZero(const A: Double): Boolean;inline;

begin
  Result:=IsZero(A,DZeroResolution);
end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsZero(const A: Extended; Epsilon: Extended): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=EZeroResolution;
  Result:=Abs(A)<=Epsilon;
end;

function IsZero(const A: Extended): Boolean;inline;

begin
  Result:=IsZero(A,EZeroResolution);
end;
{$endif FPC_HAS_TYPE_EXTENDED}


type
  TSplitDouble = packed record
    cards: Array[0..1] of cardinal;
  end;

  TSplitExtended = packed record
    cards: Array[0..1] of cardinal;
    w: word;
  end;

function IsNan(const d : Single): Boolean; overload;
  begin
    result:=(longword(d) and $7fffffff)>$7f800000;
  end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsNan(const d : Double): Boolean;
  var
    fraczero, expMaximal: boolean;
  begin
{$if defined(FPC_BIG_ENDIAN) or defined(FPC_DOUBLE_HILO_SWAPPED)}
    expMaximal := ((TSplitDouble(d).cards[0] shr 20) and $7ff) = 2047;
    fraczero:= (TSplitDouble(d).cards[0] and $fffff = 0) and
                (TSplitDouble(d).cards[1] = 0);
{$else FPC_BIG_ENDIAN}
    expMaximal := ((TSplitDouble(d).cards[1] shr 20) and $7ff) = 2047;
    fraczero := (TSplitDouble(d).cards[1] and $fffff = 0) and
                (TSplitDouble(d).cards[0] = 0);
{$endif FPC_BIG_ENDIAN}
    Result:=expMaximal and not(fraczero);
  end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsNan(const d : Extended): Boolean; overload;
  var
    fraczero, expMaximal: boolean;
  begin
{$ifdef FPC_BIG_ENDIAN}
  {$error no support for big endian extended type yet}
{$else FPC_BIG_ENDIAN}
    expMaximal := (TSplitExtended(d).w and $7fff) = 32767;
    fraczero := (TSplitExtended(d).cards[0] = 0) and
                    ((TSplitExtended(d).cards[1] and $7fffffff) = 0);
{$endif FPC_BIG_ENDIAN}
    Result:=expMaximal and not(fraczero);
  end;
{$endif FPC_HAS_TYPE_EXTENDED}

function IsInfinite(const d : Single): Boolean; overload;
  begin
    result:=(longword(d) and $7fffffff)=$7f800000;
  end;

{$ifdef FPC_HAS_TYPE_DOUBLE}
function IsInfinite(const d : Double): Boolean; overload;
  var
    fraczero, expMaximal: boolean;
  begin
{$if defined(FPC_BIG_ENDIAN) or defined(FPC_DOUBLE_HILO_SWAPPED)}
    expMaximal := ((TSplitDouble(d).cards[0] shr 20) and $7ff) = 2047;
    fraczero:= (TSplitDouble(d).cards[0] and $fffff = 0) and
                (TSplitDouble(d).cards[1] = 0);
{$else FPC_BIG_ENDIAN}
    expMaximal := ((TSplitDouble(d).cards[1] shr 20) and $7ff) = 2047;
    fraczero := (TSplitDouble(d).cards[1] and $fffff = 0) and
                (TSplitDouble(d).cards[0] = 0);
{$endif FPC_BIG_ENDIAN}
    Result:=expMaximal and fraczero;
  end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function IsInfinite(const d : Extended): Boolean; overload;
  var
    fraczero, expMaximal: boolean;
  begin
{$ifdef FPC_BIG_ENDIAN}
  {$error no support for big endian extended type yet}
{$else FPC_BIG_ENDIAN}
    expMaximal := (TSplitExtended(d).w and $7fff) = 32767;
    fraczero := (TSplitExtended(d).cards[0] = 0) and
                    ((TSplitExtended(d).cards[1] and $7fffffff) = 0);
{$endif FPC_BIG_ENDIAN}
    Result:=expMaximal and fraczero;
  end;
{$endif FPC_HAS_TYPE_EXTENDED}

function copysign(x,y: float): float;
begin
{$if defined(FPC_HAS_TYPE_FLOAT128)}
  {$error copysign not yet implemented for float128}
{$elseif defined(FPC_HAS_TYPE_EXTENDED)}
  TSplitExtended(x).w:=(TSplitExtended(x).w and $7fff) or (TSplitExtended(y).w and $8000);
{$elseif defined(FPC_HAS_TYPE_DOUBLE)}
  {$if defined(FPC_BIG_ENDIAN) or defined(FPC_DOUBLE_HILO_SWAPPED)}
  TSplitDouble(x).cards[0]:=(TSplitDouble(x).cards[0] and $7fffffff) or (TSplitDouble(y).cards[0] and longword($80000000));
  {$else}
  TSplitDouble(x).cards[1]:=(TSplitDouble(x).cards[1] and $7fffffff) or (TSplitDouble(y).cards[1] and longword($80000000));
  {$endif}
{$else}
  longword(x):=longword(x and $7fffffff) or (longword(y) and longword($80000000));
{$endif}
  result:=x;
end;

{$ifdef FPC_HAS_TYPE_EXTENDED}
function SameValue(const A, B: Extended; Epsilon: Extended): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=Max(Min(Abs(A),Abs(B))*EZeroResolution,EZeroResolution);
  if (A>B) then
    Result:=((A-B)<=Epsilon)
  else
    Result:=((B-A)<=Epsilon);
end;

function SameValue(const A, B: Extended): Boolean;inline;

begin
  Result:=SameValue(A,B,0.0);
end;
{$endif FPC_HAS_TYPE_EXTENDED}


{$ifdef FPC_HAS_TYPE_DOUBLE}
function SameValue(const A, B: Double): Boolean;inline;

begin
  Result:=SameValue(A,B,0.0);
end;

function SameValue(const A, B: Double; Epsilon: Double): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=Max(Min(Abs(A),Abs(B))*DZeroResolution,DZeroResolution);
  if (A>B) then
    Result:=((A-B)<=Epsilon)
  else
    Result:=((B-A)<=Epsilon);
end;
{$endif FPC_HAS_TYPE_DOUBLE}

function SameValue(const A, B: Single): Boolean;inline;

begin
  Result:=SameValue(A,B,0);
end;

function SameValue(const A, B: Single; Epsilon: Single): Boolean;

begin
  if (Epsilon=0) then
    Epsilon:=Max(Min(Abs(A),Abs(B))*SZeroResolution,SZeroResolution);
  if (A>B) then
    Result:=((A-B)<=Epsilon)
  else
    Result:=((B-A)<=Epsilon);
end;

// Some CPUs probably allow a faster way of doing this in a single operation...
// There we should define  FPC_MATH_HAS_CPUDIVMOD in the header mathuh.inc and implement it using asm.
{$ifndef FPC_MATH_HAS_DIVMOD}
procedure DivMod(Dividend: LongInt; Divisor: Word; var Result, Remainder: Word);
begin
  if Dividend < 0 then
    begin
      { Use DivMod with >=0 dividend }
	  Dividend:=-Dividend;
      { The documented behavior of Pascal's div/mod operators and DivMod
        on negative dividends is to return Result closer to zero and
        a negative Remainder. Which means that we can just negate both
        Result and Remainder, and all it's Ok. }
      Result:=-(Dividend Div Divisor);
      Remainder:=-(Dividend+(Result*Divisor));
    end
  else
    begin
	  Result:=Dividend Div Divisor;
      Remainder:=Dividend-(Result*Divisor);
	end;
end;


procedure DivMod(Dividend: LongInt; Divisor: Word; var Result, Remainder: SmallInt);
begin
  if Dividend < 0 then
    begin
      { Use DivMod with >=0 dividend }
	  Dividend:=-Dividend;
      { The documented behavior of Pascal's div/mod operators and DivMod
        on negative dividends is to return Result closer to zero and
        a negative Remainder. Which means that we can just negate both
        Result and Remainder, and all it's Ok. }
      Result:=-(Dividend Div Divisor);
      Remainder:=-(Dividend+(Result*Divisor));
    end
  else
    begin
	  Result:=Dividend Div Divisor;
      Remainder:=Dividend-(Result*Divisor);
	end;
end;


procedure DivMod(Dividend: DWord; Divisor: DWord; var Result, Remainder: DWord);
begin
  Result:=Dividend Div Divisor;
  Remainder:=Dividend-(Result*Divisor);
end;


procedure DivMod(Dividend: LongInt; Divisor: LongInt; var Result, Remainder: LongInt);
begin
  if Dividend < 0 then
    begin
      { Use DivMod with >=0 dividend }
      Dividend:=-Dividend;
      { The documented behavior of Pascal's div/mod operators and DivMod
        on negative dividends is to return Result closer to zero and
        a negative Remainder. Which means that we can just negate both
        Result and Remainder, and all it's Ok. }
      Result:=-(Dividend Div Divisor);
      Remainder:=-(Dividend+(Result*Divisor));
    end
  else
    begin
      Result:=Dividend Div Divisor;
      Remainder:=Dividend-(Result*Divisor);
    end;
end;
{$endif FPC_MATH_HAS_DIVMOD}

procedure DivMod(Dividend: QWord; Divisor: QWord; var Result, Remainder: QWord);
begin
  Result:=Dividend Div Divisor;
  Remainder:=Dividend-(Result*Divisor);
end;

{ Floating point modulo}
{$ifdef FPC_HAS_TYPE_SINGLE}
function FMod(const a, b: Single): Single;inline;overload;
begin
  result:= a-b * Int(a/b);
end;
{$endif FPC_HAS_TYPE_SINGLE}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function FMod(const a, b: Double): Double;inline;overload;
begin
  result:= a-b * Int(a/b);
end;
{$endif FPC_HAS_TYPE_DOUBLE}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function FMod(const a, b: Extended): Extended;inline;overload;
begin
  result:= a-b * Int(a/b);
end;
{$endif FPC_HAS_TYPE_EXTENDED}

operator mod(const a,b:float) c:float;inline;
begin
  c:= a-b * Int(a/b);
  if SameValue(abs(c),abs(b)) then
    c:=0.0;
end;

function ifthen(val:boolean;const iftrue:integer; const iffalse:integer= 0) :integer;
begin
  if val then result:=iftrue else result:=iffalse;
end;

function ifthen(val:boolean;const iftrue:int64  ; const iffalse:int64 = 0)  :int64;
begin
  if val then result:=iftrue else result:=iffalse;
end;

function ifthen(val:boolean;const iftrue:double ; const iffalse:double =0.0):double;
begin
  if val then result:=iftrue else result:=iffalse;
end;

// dilemma here. asm can do the two comparisons in one go?
// but pascal is portable and can be inlined. Ah well, we need purepascal's anyway:
function CompareValue(const A, B  : Integer): TValueRelationship;

begin
  result:=GreaterThanValue;
  if a=b then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;

function CompareValue(const A, B: Int64): TValueRelationship;

begin
  result:=GreaterThanValue;
  if a=b then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;

function CompareValue(const A, B: QWord): TValueRelationship;

begin
  result:=GreaterThanValue;
  if a=b then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;

{$ifdef FPC_HAS_TYPE_SINGLE}
function CompareValue(const A, B: Single; delta: Single = 0.0): TValueRelationship;
begin
  result:=GreaterThanValue;
  if abs(a-b)<=delta then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function CompareValue(const A, B: Double; delta: Double = 0.0): TValueRelationship;
begin
  result:=GreaterThanValue;
  if abs(a-b)<=delta then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function CompareValue (const A, B: Extended; delta: Extended = 0.0): TValueRelationship;
begin
  result:=GreaterThanValue;
  if abs(a-b)<=delta then
    result:=EqualsValue
  else
   if a<b then
     result:=LessThanValue;
end;
{$endif}

{ RoundTo uses the ordinary MoonCompiler FP contract: nearest/even rounding
  with the default exception masks.  Common finite values stay on the
  table-driven hardware path.  Decimal midpoints and values outside its proven
  range use exact fixed-width integer arithmetic. }
{$push}{$Q-}{$R-}

type
  TUInt192 = record
    Limb: array[0..5] of DWord;
  end;

const
  DecimalQuantumExponent: array[TRoundToRange] of ShortInt =
    (-123,-120,-117,-113,-110,-107,-103,-100,-97,-94,-90,-87,-84,-80,-77,-74,-70,-67,-64,
     -60,-57,-54,-50,-47,-44,-40,-37,-34,-30,-27,-24,-20,-17,-14,-10,-7,-4,0,3,6,9,13,16,
     19,23,26,29,33,36,39,43,46,49,53,56,59,63,66,69,73,76,79,83,86,89,93,96,99,102,106,
     109,112,116,119,122);

function BigFromQWord(Value: QWord): TUInt192; inline;
begin
  FillChar(Result,SizeOf(Result),0);
  Result.Limb[0]:=DWord(Value);
  Result.Limb[1]:=DWord(Value shr 32);
end;

function BigBitLength(const Value: TUInt192): Integer; inline;
var
  I: Integer;
begin
  for I:=High(Value.Limb) downto Low(Value.Limb) do
    if Value.Limb[I]<>0 then
      Exit(I*32+BsrDWord(Value.Limb[I])+1);
  Result:=0;
end;

function BigCompare(const Left,Right: TUInt192): Integer; inline;
var
  I: Integer;
begin
  for I:=High(Left.Limb) downto Low(Left.Limb) do
    if Left.Limb[I]<>Right.Limb[I] then
      begin
        if Left.Limb[I]<Right.Limb[I] then
          Exit(-1);
        Exit(1);
      end;
  Result:=0;
end;

procedure BigSubtract(var Left: TUInt192; const Right: TUInt192); inline;
var
  I: Integer;
  OldValue,Subtrahend,Borrow: QWord;
begin
  Borrow:=0;
  for I:=Low(Left.Limb) to High(Left.Limb) do
    begin
      OldValue:=Left.Limb[I];
      Subtrahend:=QWord(Right.Limb[I])+Borrow;
      Left.Limb[I]:=DWord(OldValue-Subtrahend);
      Borrow:=Ord(OldValue<Subtrahend);
    end;
end;

function BigShiftLeft(const Value: TUInt192; Shift: Integer; out Shifted: TUInt192): Boolean;
var
  I,Target,WordShift,BitShift: Integer;
  Part: QWord;
begin
  FillChar(Shifted,SizeOf(Shifted),0);
  if Shift<0 then
    Exit(False);
  WordShift:=Shift div 32;
  BitShift:=Shift and 31;
  for I:=Low(Value.Limb) to High(Value.Limb) do
    if Value.Limb[I]<>0 then
      begin
        Target:=I+WordShift;
        if Target>High(Shifted.Limb) then
          Exit(False);
        Part:=QWord(Value.Limb[I]) shl BitShift;
        Shifted.Limb[Target]:=Shifted.Limb[Target] or DWord(Part);
        if Part shr 32<>0 then
          begin
            if Target=High(Shifted.Limb) then
              Exit(False);
            Shifted.Limb[Target+1]:=Shifted.Limb[Target+1] or DWord(Part shr 32);
          end;
      end;
  Result:=True;
end;

function BigMultiplySmall(var Value: TUInt192; Factor: DWord): Boolean; inline;
var
  I: Integer;
  Product,Carry: QWord;
begin
  Carry:=0;
  for I:=Low(Value.Limb) to High(Value.Limb) do
    begin
      Product:=QWord(Value.Limb[I])*Factor+Carry;
      Value.Limb[I]:=DWord(Product);
      Carry:=Product shr 32;
    end;
  Result:=Carry=0;
end;

function BigPowerOfFive(Power: Integer): TUInt192;
begin
  Result:=BigFromQWord(1);
  while Power>0 do
    begin
      BigMultiplySmall(Result,5);
      Dec(Power);
    end;
end;

function BigRoundRatioPow2(const Numerator,Denominator: TUInt192; BinaryShift: Integer;
  out RoundedPastQWord: Boolean): QWord;
var
  N,D,Aligned,DistanceToDenominator: TUInt192;
  I,QuotientBits: Integer;
  RoundUp: Boolean;
begin
  Result:=0;
  RoundedPastQWord:=False;
  if BigBitLength(Numerator)=0 then
    Exit;
  if BinaryShift>=0 then
    begin
      if not BigShiftLeft(Numerator,BinaryShift,N) then
        begin
          RoundedPastQWord:=True;
          Exit;
        end;
      D:=Denominator;
    end
  else
    begin
      N:=Numerator;
      if not BigShiftLeft(Denominator,-BinaryShift,D) then
        Exit;
    end;

  QuotientBits:=BigBitLength(N)-BigBitLength(D);
  If QuotientBits>=0 then begin
    BigShiftLeft(D,QuotientBits,Aligned);
    If BigCompare(N,Aligned)<0 then Dec(QuotientBits);
  end;
  if QuotientBits>63 then
    begin
      RoundedPastQWord:=True;
      Exit;
    end;
  if QuotientBits>=0 then
    for I:=QuotientBits downto 0 do
      begin
        BigShiftLeft(D,I,Aligned);
        if BigCompare(N,Aligned)>=0 then
          begin
            BigSubtract(N,Aligned);
            Result:=Result or (QWord(1) shl I);
          end;
      end;

  DistanceToDenominator:=D;
  BigSubtract(DistanceToDenominator,N);
  RoundUp:=(BigCompare(N,DistanceToDenominator)>0) or
    ((BigCompare(N,DistanceToDenominator)=0) and Odd(Result));
  if RoundUp then
    if Result=High(QWord) then
      RoundedPastQWord:=True
    else
      Inc(Result);
end;

function BigFloorLog2Ratio(const Numerator,Denominator: TUInt192): Integer;
var
  Shifted: TUInt192;
begin
  Result:=BigBitLength(Numerator)-BigBitLength(Denominator);
  if Result>=0 then
    begin
      BigShiftLeft(Denominator,Result,Shifted);
      if BigCompare(Numerator,Shifted)<0 then
        Dec(Result);
    end
  else
    begin
      BigShiftLeft(Numerator,-Result,Shifted);
      if BigCompare(Shifted,Denominator)<0 then
        Dec(Result);
    end;
end;

function BigRoundRatioWide(const Numerator,Denominator: TUInt192; BinaryShift: Integer): TUInt192;
var
  N,D,Aligned,Distance: TUInt192;
  I,LimbIndex,Cmp: Integer;
begin
  Result:=BigFromQWord(0);
  If BigBitLength(Numerator)=0 then Exit;
  If BinaryShift>=0 then begin
    If not BigShiftLeft(Numerator,BinaryShift,N) then
      raise EOverflow.Create('RoundTo internal precision overflow');
    D:=Denominator;
  end else begin
    N:=Numerator;
    If not BigShiftLeft(Denominator,-BinaryShift,D) then Exit;
  end;
  I:=BigBitLength(N)-BigBitLength(D);
  If I>High(Result.Limb)*32+31 then
    raise EOverflow.Create('RoundTo internal quotient overflow');
  for I:=I downto 0 do begin
    BigShiftLeft(D,I,Aligned);
    If BigCompare(N,Aligned)>=0 then begin
      BigSubtract(N,Aligned);
      Result.Limb[I shr 5]:=Result.Limb[I shr 5] or (DWord(1) shl (I and 31));
    end;
  end;
  Distance:=D;
  BigSubtract(Distance,N);
  Cmp:=BigCompare(N,Distance);
  If (Cmp>0) or ((Cmp=0) and Odd(Result.Limb[0])) then begin
    LimbIndex:=0;
    repeat
      Inc(Result.Limb[LimbIndex]);
      If Result.Limb[LimbIndex]<>0 then Break;
      Inc(LimbIndex);
    until LimbIndex=6;
  end;
end;

procedure BuildRoundedDecimal(Mantissa: QWord; BinaryExponent: Integer; Digits: TRoundToRange;
  out Numerator,Denominator: TUInt192; out BinaryScale: Integer);
var
  Dividend,Divisor,Pow5: TUInt192;
  I,K: Integer;
begin
  K:=Abs(Digits);
  Pow5:=BigPowerOfFive(K);
  Dividend:=BigFromQWord(Mantissa);
  If Digits>=0 then begin
    Numerator:=BigRoundRatioWide(Dividend,Pow5,BinaryExponent-Digits);
    for I:=1 to Digits do BigMultiplySmall(Numerator,5);
    Denominator:=BigFromQWord(1);
    BinaryScale:=Digits;
  end else begin
    for I:=1 to K do BigMultiplySmall(Dividend,5);
    Divisor:=BigFromQWord(1);
    Numerator:=BigRoundRatioWide(Dividend,Divisor,BinaryExponent+K);
    Denominator:=Pow5;
    BinaryScale:=-K;
  end;
end;

function RoundRationalToSingleBits(const Numerator,Denominator: TUInt192;
  BinaryScale: Integer; SignBits: DWord): DWord;
var
  Exponent,RatioExponent,Shift: Integer;
  Significand: QWord;
  Carry: Boolean;
begin
  if BigBitLength(Numerator)=0 then
    Exit(SignBits);
  RatioExponent:=BigFloorLog2Ratio(Numerator,Denominator);
  Exponent:=RatioExponent+BinaryScale;
  if Exponent>127 then
    Exit(SignBits or $7f800000);
  if Exponent>=-126 then
    begin
      Shift:=23-RatioExponent;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Carry or (Significand=QWord(1) shl 24) then
        begin
          Significand:=QWord(1) shl 23;
          Inc(Exponent);
          if Exponent>127 then
            Exit(SignBits or $7f800000);
        end;
      Result:=SignBits or (DWord(Exponent+127) shl 23) or (DWord(Significand) and $7fffff);
    end
  else
    begin
      Shift:=BinaryScale+149;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Significand>=QWord(1) shl 23 then
        Result:=SignBits or $00800000
      else
        Result:=SignBits or DWord(Significand);
    end;
end;

function RoundRationalToDoubleBits(const Numerator,Denominator: TUInt192;
  BinaryScale: Integer; SignBits: QWord): QWord;
var
  Exponent,RatioExponent,Shift: Integer;
  Significand: QWord;
  Carry: Boolean;
begin
  if BigBitLength(Numerator)=0 then
    Exit(SignBits);
  RatioExponent:=BigFloorLog2Ratio(Numerator,Denominator);
  Exponent:=RatioExponent+BinaryScale;
  if Exponent>1023 then
    Exit(SignBits or QWord($7ff0000000000000));
  if Exponent>=-1022 then
    begin
      Shift:=52-RatioExponent;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Carry or (Significand=QWord(1) shl 53) then
        begin
          Significand:=QWord(1) shl 52;
          Inc(Exponent);
          if Exponent>1023 then
            Exit(SignBits or QWord($7ff0000000000000));
        end;
      Result:=SignBits or (QWord(Exponent+1023) shl 52) or
        (Significand and QWord($000fffffffffffff));
    end
  else
    begin
      Shift:=BinaryScale+1074;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Significand>=QWord(1) shl 52 then
        Result:=SignBits or QWord($0010000000000000)
      else
        Result:=SignBits or Significand;
    end;
end;

{$if sizeof(extended)=10}
function RoundRationalToExtended(const Numerator,Denominator: TUInt192;
  BinaryScale: Integer; SignBits: Word): Extended;
var
  Output: TExtended80Rec;
  Exponent,RatioExponent,Shift: Integer;
  Significand: QWord;
  Carry: Boolean;
begin
  if BigBitLength(Numerator)=0 then
    begin
      Output._Exp:=SignBits;
      Output.Frac:=0;
      Exit(Output.Value);
    end;
  RatioExponent:=BigFloorLog2Ratio(Numerator,Denominator);
  Exponent:=RatioExponent+BinaryScale;
  if Exponent>16383 then
    begin
      Output._Exp:=SignBits or $7fff;
      Output.Frac:=QWord(1) shl 63;
      Exit(Output.Value);
    end;
  if Exponent>=-16382 then
    begin
      Shift:=63-RatioExponent;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Carry then
        begin
          Significand:=QWord(1) shl 63;
          Inc(Exponent);
          if Exponent>16383 then
            begin
              Output._Exp:=SignBits or $7fff;
              Output.Frac:=QWord(1) shl 63;
              Exit(Output.Value);
            end;
        end;
      Output._Exp:=SignBits or Word(Exponent+16383);
      Output.Frac:=Significand;
    end
  else
    begin
      Shift:=BinaryScale+16445;
      Significand:=BigRoundRatioPow2(Numerator,Denominator,Shift,Carry);
      if Carry or (Significand=QWord(1) shl 63) then
        Output._Exp:=SignBits or 1
      else
        Output._Exp:=SignBits;
      Output.Frac:=Significand;
    end;
  Result:=Output.Value;
end;
{$endif}

function DecimalQuantumBelowUlp(BinaryExponent: Integer; Digits: TRoundToRange): Boolean; inline;
begin
  Result:=BinaryExponent>DecimalQuantumExponent[Digits]+1;
end;


function ExactRoundToDouble(const AValue: Double; const Digits: TRoundToRange): Double;
var
  Bits,SignBits,Mantissa: QWord;
  RawExponent,BinaryExponent,BinaryScale: Integer;
  Numerator,Denominator: TUInt192;
begin
  Bits:=TDoubleRec(AValue).Data;
  SignBits:=Bits and QWord($8000000000000000);
  RawExponent:=(Bits shr 52) and $7ff;
  Mantissa:=Bits and QWord($000fffffffffffff);
  if RawExponent=0 then
    begin
      if Mantissa=0 then
        Exit(AValue);
      BinaryExponent:=-1074;
    end
  else
    begin
      if RawExponent=$7ff then
        Exit(AValue);
      Mantissa:=Mantissa or QWord(1) shl 52;
      BinaryExponent:=RawExponent-1023-52;
    end;
  if DecimalQuantumBelowUlp(BinaryExponent,Digits) then
    Exit(AValue);
  BuildRoundedDecimal(Mantissa,BinaryExponent,Digits,Numerator,Denominator,BinaryScale);
  TDoubleRec(Result).Data:=RoundRationalToDoubleBits(Numerator,Denominator,BinaryScale,SignBits);
end;

function ExactRoundToSingle(const AValue: Single; const Digits: TRoundToRange): Single;
var
  Bits,SignBits: DWord;
  Mantissa: QWord;
  RawExponent,BinaryExponent,BinaryScale: Integer;
  Numerator,Denominator: TUInt192;
begin
  Bits:=TSingleRec(AValue).Data;
  SignBits:=Bits and $80000000;
  RawExponent:=(Bits shr 23) and $ff;
  Mantissa:=Bits and $7fffff;
  if RawExponent=0 then
    begin
      if Mantissa=0 then
        Exit(AValue);
      BinaryExponent:=-149;
    end
  else
    begin
      if RawExponent=$ff then
        Exit(AValue);
      Mantissa:=Mantissa or QWord(1) shl 23;
      BinaryExponent:=RawExponent-127-23;
    end;
  if DecimalQuantumBelowUlp(BinaryExponent,Digits) then
    Exit(AValue);
  BuildRoundedDecimal(Mantissa,BinaryExponent,Digits,Numerator,Denominator,BinaryScale);
  TSingleRec(Result).Data:=RoundRationalToSingleBits(Numerator,Denominator,BinaryScale,SignBits);
end;

{$if sizeof(extended)=10}
function ExactRoundToExtended(const AValue: Extended; const Digits: TRoundToRange): Extended;

var
  Input: TExtended80Rec;
  SignBits: Word;
  Mantissa: QWord;
  RawExponent,BinaryExponent,BinaryScale: Integer;
  Numerator,Denominator: TUInt192;
begin
  Input.Value:=AValue;
  SignBits:=Input._Exp and $8000;
  RawExponent:=Input._Exp and $7fff;
  Mantissa:=Input.Frac;
  if RawExponent=0 then
    begin
      if Mantissa=0 then
        Exit(AValue);
      BinaryExponent:=-16445;
    end
  else
    begin
      if RawExponent=$7fff then
        Exit(AValue);
      BinaryExponent:=RawExponent-16383-63;
    end;
  if DecimalQuantumBelowUlp(BinaryExponent,Digits) then
    Exit(AValue);
  BuildRoundedDecimal(Mantissa,BinaryExponent,Digits,Numerator,Denominator,BinaryScale);
  Result:=RoundRationalToExtended(Numerator,Denominator,BinaryScale,SignBits);
end;
{$endif}

{$ifdef cpux86_64}
{$asmmode intel}

const
  Powers5: array[0..27] of QWord = (
    1,5,25,125,625,3125,15625,78125,390625,1953125,9765625,48828125,
    244140625,1220703125,6103515625,30517578125,152587890625,762939453125,
    3814697265625,19073486328125,95367431640625,476837158203125,
    2384185791015625,11920928955078125,59604644775390625,298023223876953125,
    1490116119384765625,7450580596923828125);

function MulWide(A, B: QWord; out Hi: QWord): QWord; assembler; nostackframe;
asm
  {$ifdef FPC_ABI_WIN64}
  mov rax,rcx
  mul rdx
  mov [r8],rdx
  {$else}
  mov rcx,rdx
  mov rax,rdi
  mul rsi
  mov [rcx],rdx
  {$endif}
end;

function DivWide(Lo, Hi, Den: QWord; out Rem: QWord): QWord; assembler; nostackframe;
asm
  {$ifdef FPC_ABI_WIN64}
  mov rax,rcx
  div r8
  mov [r9],rdx
  {$else}
  mov r8,rdx
  mov rax,rdi
  mov rdx,rsi
  div r8
  mov [rcx],rdx
  {$endif}
end;

function RoundShift(Lo, Hi: QWord; Shift: Integer): QWord; inline;
var
  R, Half: QWord;
begin
  If Shift <= 0 then
    Exit(Lo shl (-Shift));
  If Shift < 64 then begin
    Result := (Lo shr Shift) or (Hi shl (64-Shift));
    Half := QWord(1) shl (Shift-1);
    R := Lo and ((Half shl 1)-1);
    If (R > Half) or ((R = Half) and Odd(Result)) then
      Inc(Result);
  end else If Shift = 64 then begin
    Result := Hi;
    Half := QWord(1) shl 63;
    If (Lo > Half) or ((Lo = Half) and Odd(Result)) then
      Inc(Result);
  end else If Shift < 128 then begin
    Dec(Shift,64);
    Result := Hi shr Shift;
    Half := QWord(1) shl (Shift-1);
    R := Hi and ((Half shl 1)-1);
    If (R > Half) or ((R = Half) and ((Lo <> 0) or Odd(Result))) then
      Inc(Result);
  end else begin
    Result := 0;
    If (Shift = 128) and ((Hi > QWord($8000000000000000)) or
      ((Hi = QWord($8000000000000000)) and (Lo <> 0))) then
      Result := 1;
  end;
end;

function RoundDivision(Lo, Hi, Den: QWord): QWord; inline;
var
  Rem: QWord;
begin
  Result := DivWide(Lo,Hi,Den,Rem);
  If (Rem > Den-Rem) or ((Rem = Den-Rem) and Odd(Result)) then
    Inc(Result);
end;

function FractionBits(Num, Den: QWord; BinaryScale: Integer): QWord;
var
  RatioExponent, Shift: Integer;
  Lo, Hi, Sig: QWord;
begin
  If Num = 0 then
    Exit(0);
  RatioExponent := BsrQWord(Num)-BsrQWord(Den);
  If RatioExponent >= 0 then begin
    If Num < (Den shl RatioExponent) then
      Dec(RatioExponent);
  end else If (Num shl (-RatioExponent)) < Den then
    Dec(RatioExponent);
  Shift := 52-RatioExponent;
  If Shift < 64 then begin
    Lo := Num shl Shift;
    If Shift = 0 then
      Hi := 0
    else
      Hi := Num shr (64-Shift);
  end else begin
    Lo := 0;
    Hi := Num shl (Shift-64);
  end;
  Sig := RoundDivision(Lo,Hi,Den);
  If Sig = (QWord(1) shl 53) then begin
    Sig := Sig shr 1;
    Inc(RatioExponent);
  end;
  Result := (QWord(RatioExponent+BinaryScale+1023) shl 52) or (Sig and QWord($fffffffffffff));
end;

function IntegerBits(Lo, Hi: QWord; BinaryScale: Integer): QWord;
var
  Top: Integer;
  Sig: QWord;
begin
  If (Hi or Lo) = 0 then
    Exit(0);
  If Hi = 0 then
    Top := BsrQWord(Lo)
  else
    Top := 64+BsrQWord(Hi);
  Sig := RoundShift(Lo,Hi,Top-52);
  If Sig = (QWord(1) shl 53) then begin
    Sig := Sig shr 1;
    Inc(Top);
  end;
  Result := (QWord(Top+BinaryScale+1023) shl 52) or (Sig and QWord($fffffffffffff));
end;

function RoundToDoubleInteger(Value: Double; Digits: TRoundToRange): Double;
var
  Bits, Sign, M, P5, Lo, Hi, Q, Den: QWord;
  E, K, Shift, Top: Integer;
begin
  Bits := TDoubleRec(Value).Data;
  Sign := Bits and QWord($8000000000000000);
  E := Integer((Bits shr 52) and $7ff);
  If E = $7ff then
    Exit(Value);
  If E = 0 then begin
    TDoubleRec(Result).Data := Sign;
    Exit;
  end;
  M := (Bits and QWord($fffffffffffff)) or (QWord(1) shl 52);
  Dec(E,1075);
  K := Abs(Digits);
  If K > High(Powers5) then
    Exit(ExactRoundToDouble(Value,Digits));
  If Digits = 0 then begin
    If E >= 0 then
      Exit(Value);
    Q := RoundShift(M,0,-E);
    TDoubleRec(Result).Data := Sign or IntegerBits(Q,0,0);
    Exit;
  end;
  P5 := Powers5[K];
  If Digits < 0 then begin
    Lo := MulWide(M,P5,Hi);
    If Hi = 0 then
      Top := BsrQWord(Lo)
    else
      Top := 64+BsrQWord(Hi);
    Shift := -E-K;
    If Top-Shift > 52 then
      Exit(ExactRoundToDouble(Value,Digits));
    Q := RoundShift(Lo,Hi,Shift);
    TDoubleRec(Result).Data := Sign or FractionBits(Q,P5,-K);
  end else begin
    Shift := E-K;
    If Shift < 0 then begin
      Shift := -Shift;
      If (Shift >= 64) or (BsrQWord(P5)+Shift > 53) then begin
        TDoubleRec(Result).Data := Sign;
        Exit;
      end;
      Den := P5 shl Shift;
      Q := RoundDivision(M,0,Den);
    end else begin
      If (Shift > 63) or (52+Shift-BsrQWord(P5) > 52) then
        Exit(ExactRoundToDouble(Value,Digits));
      Lo := M shl Shift;
      If Shift = 0 then
        Hi := 0
      else
        Hi := M shr (64-Shift);
      Q := RoundDivision(Lo,Hi,P5);
    end;
    Lo := MulWide(Q,P5,Hi);
    TDoubleRec(Result).Data := Sign or IntegerBits(Lo,Hi,K);
  end;
end;

type
  TRoundToDoubleParam = record
    Scale: Double;
    Low, Span: QWord;
  end;
const
  RoundToDoubleParams: array[-22..22] of TRoundToDoubleParam = (
    (Scale:1e22; Low:QWord($3b5e392010175ee7); Span:QWord($33ffffffffffffe)),
    (Scale:1e21; Low:QWord($3b92e3b40a0e9b50); Span:QWord($33ffffffffffffe)),
    (Scale:1e20; Low:QWord($3bc79ca10c924224); Span:QWord($33ffffffffffffe)),
    (Scale:1e19; Low:QWord($3bfd83c94fb6d2ad); Span:QWord($33ffffffffffffe)),
    (Scale:1e18; Low:QWord($3c32725dd1d243ad); Span:QWord($33ffffffffffffe)),
    (Scale:1e17; Low:QWord($3c670ef54646d498); Span:QWord($33ffffffffffffe)),
    (Scale:1e16; Low:QWord($3c9cd2b297d889bd); Span:QWord($33ffffffffffffe)),
    (Scale:1e15; Low:QWord($3cd203af9ee75617); Span:QWord($33ffffffffffffe)),
    (Scale:1e14; Low:QWord($3d06849b86a12b9c); Span:QWord($33ffffffffffffe)),
    (Scale:1e13; Low:QWord($3d3c25c268497683); Span:QWord($33ffffffffffffe)),
    (Scale:1e12; Low:QWord($3d719799812dea12); Span:QWord($33ffffffffffffe)),
    (Scale:1e11; Low:QWord($3da5fd7fe1796496); Span:QWord($33ffffffffffffe)),
    (Scale:1e10; Low:QWord($3ddb7cdfd9d7bdbc); Span:QWord($33ffffffffffffe)),
    (Scale:1e9; Low:QWord($3e112e0be826d696); Span:QWord($33ffffffffffffe)),
    (Scale:1e8; Low:QWord($3e45798ee2308c3b); Span:QWord($33ffffffffffffe)),
    (Scale:1e7; Low:QWord($3e7ad7f29abcaf49); Span:QWord($33ffffffffffffe)),
    (Scale:1e6; Low:QWord($3eb0c6f7a0b5ed8e); Span:QWord($33ffffffffffffe)),
    (Scale:1e5; Low:QWord($3ee4f8b588e368f2); Span:QWord($33ffffffffffffe)),
    (Scale:1e4; Low:QWord($3f1a36e2eb1c432e); Span:QWord($33ffffffffffffe)),
    (Scale:1e3; Low:QWord($3f50624dd2f1a9fd); Span:QWord($33ffffffffffffe)),
    (Scale:1e2; Low:QWord($3f847ae147ae147c); Span:QWord($33ffffffffffffe)),
    (Scale:1e1; Low:QWord($3fb999999999999b); Span:QWord($33ffffffffffffe)),
    (Scale:1e0; Low:QWord($3ff0000000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e1; Low:QWord($4024000000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e2; Low:QWord($4059000000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e3; Low:QWord($408f400000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e4; Low:QWord($40c3880000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e5; Low:QWord($40f86a0000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e6; Low:QWord($412e848000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e7; Low:QWord($416312d000000000); Span:QWord($33fffffffffffff)),
    (Scale:1e8; Low:QWord($4197d78400000000); Span:QWord($33fffffffffffff)),
    (Scale:1e9; Low:QWord($41cdcd6500000000); Span:QWord($33fffffffffffff)),
    (Scale:1e10; Low:QWord($4202a05f20000000); Span:QWord($33fffffffffffff)),
    (Scale:1e11; Low:QWord($42374876e8000000); Span:QWord($33fffffffffffff)),
    (Scale:1e12; Low:QWord($426d1a94a2000000); Span:QWord($33fffffffffffff)),
    (Scale:1e13; Low:QWord($42a2309ce5400000); Span:QWord($33fffffffffffff)),
    (Scale:1e14; Low:QWord($42d6bcc41e900000); Span:QWord($33fffffffffffff)),
    (Scale:1e15; Low:QWord($430c6bf526340000); Span:QWord($33fffffffffffff)),
    (Scale:1e16; Low:QWord($4341c37937e08000); Span:QWord($33fffffffffffff)),
    (Scale:1e17; Low:QWord($4376345785d8a000); Span:QWord($33fffffffffffff)),
    (Scale:1e18; Low:QWord($43abc16d674ec800); Span:QWord($33fffffffffffff)),
    (Scale:1e19; Low:QWord($43e158e460913d00); Span:QWord($33fffffffffffff)),
    (Scale:1e20; Low:QWord($4415af1d78b58c40); Span:QWord($33fffffffffffff)),
    (Scale:1e21; Low:QWord($444b1ae4d6e2ef50); Span:QWord($33fffffffffffff)),
    (Scale:1e22; Low:QWord($4480f0cf064dd592); Span:QWord($33fffffffffffff)));

{ The three RoundTo routines are laid out by hand (doc/ASM_LAYOUT_RULES.md): no jump, fused
  compare+jump pair or return crosses or ends on a 32-byte boundary.  The Win64 spelling of the
  first instruction is a byte shorter than the SysV one; a DS prefix (db $3E: ignored in long
  mode, no uop) makes both ABIs share one layout.  The other prefixes and the dead bytes behind
  a return move a pair off a boundary; edx is zero-extended into rdx by the movsx, so the 64-bit
  address forms give the same eax without the address-size prefix.
  cvtsi2sd/cvtsi2ss write only the low lane of xmm3 and so wait for the value xmm3 held before:
  nothing else in the routine writes xmm3, so that value came from the previous call, and a loop of
  calls became one dependency chain through the divide, both conversions and the midpoint test
  (roundto-minus2: 15 -> 30 core cycles per call against the Pascal RoundTo of the 1.0 release;
  zeroing xmm3 in the caller alone gave 1.76x).  xorps xmm3,xmm3 is a zeroing idiom resolved at
  register rename; it breaks the chain before the conversion, the same fix GCC and LLVM emit. }
function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double; assembler; nostackframe;
asm
  {$ifdef FPC_ABI_WIN64}
  db $3E
  movsx edx,dl
  {$else}
  movsx edx,dil
  {$endif}
  test edx,edx
  jz @integral
  lea eax,[rdx+22]
  cmp eax,44
  ja @fallback
  lea eax,[rax+rax*2]
  lea r11,[rip+RoundToDoubleParams]
  lea r11,[r11+rax*8]
  movq r8,xmm0
  db $3E
  btr r8,63
  sub r8,[r11+8]
  cmp r8,[r11+16]
  ja @fallback
  movsd xmm1,[r11]
  xorps xmm3,xmm3                 { breaks the false dependency of cvtsi2sd below }
  movapd xmm2,xmm0
  test edx,edx
  jg @divide
  mulsd xmm2,xmm1
  jmp @round
@divide:
  divsd xmm2,xmm1
@round:
  cvtsd2si rax,xmm2
  cvtsi2sd xmm3,rax
  test rax,rax
  jne @midpoint
  movq rax,xmm2
  shr rax,63
  shl rax,63
  movq xmm3,rax
@midpoint:
  movq rax,xmm2
  mov rcx,rax
  shr rcx,52
  add ecx,13
  shl rax,cl
  mov r8,$8000000000000000
  cmp rax,r8
  je @fallback
  movapd xmm0,xmm3
  test edx,edx
  jg @multiply
  divsd xmm0,xmm1
  ret
@multiply:
  mulsd xmm0,xmm1
  ret
  { dead bytes: the Digits=0 path is reached by a jump and is 58 bytes up to its last
    compare - inside one line from a line start, across two from byte 46 }
  align 64
@integral:
  movq r8,xmm0
  mov r9,r8
  btr r9,63
  mov r11,$7ff0000000000000
  cmp r9,r11
  jae @unchanged
  mov r11,$4330000000000000
  cmp r9,r11
  jae @unchanged
  mov r11,$0010000000000000
  cmp r9,r11
  jae @round0
  shr r8,63
  shl r8,63
  movq xmm0,r8
@unchanged:
  ret
  { dead bytes: like @integral, @round0 starts a line.  On byte 59 the block lay across the
    line, and RoundTo(x, 0) went from 7.4 to 8.2 ns on the Ryzen }
  align 64
@round0:
  cvtsd2si rax,xmm0
  test rax,rax
  jne @integer_result
  movq rax,xmm0
  shr rax,63
  shl rax,63
  movq xmm0,rax
  ret
@integer_result:
  cvtsi2sd xmm0,rax
  ret
@fallback:
  jmp RoundToDoubleInteger
end;

type
  TRoundToSingleParam = record
    Scale: Single;
    Low,Span,Identity: DWord;
  end;
const
  RoundToSingleParams: array[-10..10] of TRoundToSingleParam = (
    (Scale:1e10; Low:$2edbe700; Span:$b7ffffe; Identity:$3b000000),
    (Scale:1e9; Low:$30897060; Span:$b7ffffe; Identity:$3d000000),
    (Scale:1e8; Low:$322bcc78; Span:$b7ffffe; Identity:$3e800000),
    (Scale:1e7; Low:$33d6bf96; Span:$b7ffffe; Identity:$40000000),
    (Scale:1e6; Low:$358637be; Span:$b7ffffe; Identity:$42000000),
    (Scale:1e5; Low:$3727c5ad; Span:$b7ffffe; Identity:$43800000),
    (Scale:1e4; Low:$38d1b718; Span:$b7ffffe; Identity:$45000000),
    (Scale:1e3; Low:$3a831270; Span:$b7ffffe; Identity:$47000000),
    (Scale:1e2; Low:$3c23d70b; Span:$b7ffffe; Identity:$48800000),
    (Scale:1e1; Low:$3dccccce; Span:$b7ffffe; Identity:$4a000000),
    (Scale:1e0; Low:$3f800000; Span:$b7fffff; Identity:$4b800000),
    (Scale:1e1; Low:$41200000; Span:$b7fffff; Identity:$4d800000),
    (Scale:1e2; Low:$42c80000; Span:$b7fffff; Identity:$4f000000),
    (Scale:1e3; Low:$447a0000; Span:$b7fffff; Identity:$50800000),
    (Scale:1e4; Low:$461c4000; Span:$b7fffff; Identity:$52800000),
    (Scale:1e5; Low:$47c35000; Span:$b7fffff; Identity:$54000000),
    (Scale:1e6; Low:$49742400; Span:$b7fffff; Identity:$55800000),
    (Scale:1e7; Low:$4b189680; Span:$b7fffff; Identity:$57800000),
    (Scale:1e8; Low:$4cbebc20; Span:$b7fffff; Identity:$59000000),
    (Scale:1e9; Low:$4e6e6b28; Span:$b7fffff; Identity:$5a800000),
    (Scale:1e10; Low:$501502f9; Span:$b7fffff; Identity:$5c800000));
{ Laid out by hand like the Double routine above.  The jump to the exact routine stands behind
  the two returns of the fast path, where every jump to it is a short one, and the two early
  "unchanged" exits take the nearest return. }
function RoundTo(const AValue: Single; const Digits: TRoundToRange): Single; assembler; nostackframe;
asm
  {$ifdef FPC_ABI_WIN64}
  db $3E
  movsx edx,dl
  {$else}
  movsx edx,dil
  {$endif}
  test edx,edx
  jz @integral
  lea eax,[rdx+10]
  cmp eax,20
  db $77,$79                      { ja @fallback (rel8 written out, doc/ASM_LAYOUT_RULES.md) }
  shl eax,4
  lea r11,[rip+RoundToSingleParams]
  add r11,rax
  movd eax,xmm0
  db $3E,$3E
  and eax,$7fffffff
  cmp eax,$7f800000
  jae @return_now
  cmp eax,[r11+12]
  jae @return_now
  xorps xmm3,xmm3                 { breaks the false dependency of cvtsi2ss below, in the place
                                    of three DS prefixes: the cmp/ja behind stays on byte 64 }
  sub eax,[r11+4]
  cmp eax,[r11+8]
  ja @fallback
  movss xmm1,[r11]
  movaps xmm2,xmm0
  test edx,edx
  jg @divide
  mulss xmm2,xmm1
  jmp @round
@divide:
  divss xmm2,xmm1
@round:
  cvtss2si eax,xmm2
  cvtsi2ss xmm3,eax
  movd eax,xmm2
  mov ecx,eax
  shr ecx,23
  add ecx,10
  shl eax,cl
  cmp eax,$80000000
  je @fallback
  test edx,edx
  jg @multiply
  movaps xmm0,xmm3
  divss xmm0,xmm1
@return_now:
  ret
@multiply:
  movaps xmm0,xmm3
  mulss xmm0,xmm1
  ret
@fallback:
  jmp ExactRoundToSingle
  db $66,$90                      { dead: the first compare of @integral on byte 32 }
@integral:
  movd eax,xmm0
  mov ecx,eax
  and ecx,$7fffffff
  cmp ecx,$4b000000
  jae @unchanged
  cmp ecx,$00800000
  jb @signedzero
  cvtss2si ecx,xmm0
  test ecx,ecx
  jz @signedzero
  cvtsi2ss xmm0,ecx
@unchanged:
  ret
  align 64                        { dead bytes: the block would lie across the line }
@signedzero:
  and eax,$80000000
  movd xmm0,eax
end;

{$ifdef FPC_HAS_TYPE_EXTENDED}
{$if sizeof(extended)=10}
type
  TRoundToBinary80 = packed record
    Mantissa: QWord;
    Exponent: Word;
  end;
const
  { Integer payloads retain all 64 significand bits even when decimal
    floating literals are parsed through binary64. }
  RoundToExtendedPowers10: array[0..27] of TRoundToBinary80 = (
    (Mantissa:QWord($8000000000000000); Exponent:$3fff),
    (Mantissa:QWord($a000000000000000); Exponent:$4002),
    (Mantissa:QWord($c800000000000000); Exponent:$4005),
    (Mantissa:QWord($fa00000000000000); Exponent:$4008),
    (Mantissa:QWord($9c40000000000000); Exponent:$400c),
    (Mantissa:QWord($c350000000000000); Exponent:$400f),
    (Mantissa:QWord($f424000000000000); Exponent:$4012),
    (Mantissa:QWord($9896800000000000); Exponent:$4016),
    (Mantissa:QWord($bebc200000000000); Exponent:$4019),
    (Mantissa:QWord($ee6b280000000000); Exponent:$401c),
    (Mantissa:QWord($9502f90000000000); Exponent:$4020),
    (Mantissa:QWord($ba43b74000000000); Exponent:$4023),
    (Mantissa:QWord($e8d4a51000000000); Exponent:$4026),
    (Mantissa:QWord($9184e72a00000000); Exponent:$402a),
    (Mantissa:QWord($b5e620f480000000); Exponent:$402d),
    (Mantissa:QWord($e35fa931a0000000); Exponent:$4030),
    (Mantissa:QWord($8e1bc9bf04000000); Exponent:$4034),
    (Mantissa:QWord($b1a2bc2ec5000000); Exponent:$4037),
    (Mantissa:QWord($de0b6b3a76400000); Exponent:$403a),
    (Mantissa:QWord($8ac7230489e80000); Exponent:$403e),
    (Mantissa:QWord($ad78ebc5ac620000); Exponent:$4041),
    (Mantissa:QWord($d8d726b7177a8000); Exponent:$4044),
    (Mantissa:QWord($878678326eac9000); Exponent:$4048),
    (Mantissa:QWord($a968163f0a57b400); Exponent:$404b),
    (Mantissa:QWord($d3c21bcecceda100); Exponent:$404e),
    (Mantissa:QWord($84595161401484a0); Exponent:$4052),
    (Mantissa:QWord($a56fa5b99019a5c8); Exponent:$4055),
    (Mantissa:QWord($cecb8f27f4200f3a); Exponent:$4058));
  RoundToExtendedMaxInputExponent: array[-27..27] of Word = (
    16355,16358,16361,16365,16368,16371,16375,16378,16381,16385,16388,
    16391,16395,16398,16401,16405,16408,16411,16415,16418,16421,16425,
    16428,16431,16435,16438,16441,16445,16448,16451,16454,16458,16461,
    16464,16468,16471,16474,16478,16481,16484,16488,16491,16494,16498,
    16501,16504,16508,16511,16514,16518,16521,16524,16528,16531,16534);

{ Linux x86-64 SysV. Value is the native 80-bit stack argument, result ST(0).
  The red zone holds one scaled payload. No floating control state is changed. }
{$push}{$codealign proc=64}       { layout: the entry on a 64-byte line }
function RoundTo(const AValue: Extended; const Digits: TRoundToRange): Extended; assembler; nostackframe;
asm
  movzx eax,word ptr [rsp+16]
  and eax,$7fff
  cmp eax,$7fff
  je @unchanged
  test eax,eax
  jz @zero
  movsx ecx,dil
  test ecx,ecx
  jz @integral
  lea edx,[ecx+27]
  cmp edx,54
  ja @fallback
  lea r11,[rip+RoundToExtendedMaxInputExponent]
  movzx edx,word ptr [r11+rdx*2]
  cmp eax,edx
  ja @fallback
  mov eax,ecx
  neg eax
  cmovs eax,ecx
  lea eax,[eax+eax*4]
  lea r11,[rip+RoundToExtendedPowers10]
  fld tbyte ptr [r11+rax*2]
  fld tbyte ptr [rsp+8]
  test ecx,ecx
  jg @divide
  fmul st,st(1)
  jmp @midpoint
@divide:
  fdiv st,st(1)
@midpoint:
  fld st
  fstp tbyte ptr [rsp-16]
  movzx ecx,word ptr [rsp-8]
  db $3E                          { the compare and its jump behind the line }
  and ecx,$7fff
  cmp ecx,$3fff
  jb @fallback_pop
  db $3E,$3E,$3E                  { the next compare and its jump behind byte 32 }
  add ecx,2
  mov rax,qword ptr [rsp-16]
  shl rax,cl
  mov rdx,$8000000000000000
  cmp rax,rdx
  je @fallback_pop
  frndint
  test dil,dil
  jg @multiply
  fdiv st,st(1)
  fstp st(1)
  ret
@multiply:
  fmulp st(1),st
  ret
@integral:
  fld tbyte ptr [rsp+8]
  frndint
  ret
  db $0F,$1F,$44,$00,$00          { dead: @zero on a line start, its test+jz inside the line }
@zero:
  fldz
  test word ptr [rsp+16],$8000
  jz @return
  fchs
@return:
  ret
@unchanged:
  fld tbyte ptr [rsp+8]
  ret
@fallback_pop:
  fstp st
  fstp st
@fallback:
  jmp ExactRoundToExtended
end;
{$pop}
{$else}
function RoundTo(const AValue: Extended; const Digits: TRoundToRange): Extended;
begin
  Result:=RoundTo(Double(AValue),Digits);
end;
{$endif}
{$endif}

{$asmmode gas}
{$endif}

{$ifndef cpux86_64}
{$ifdef FPC_HAS_TYPE_DOUBLE}
function RoundTo(const AValue: Double; const Digits: TRoundToRange): Double;
begin
  Result:=ExactRoundToDouble(AValue,Digits);
end;
{$endif}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function RoundTo(const AValue: Extended; const Digits: TRoundToRange): Extended;
begin
  {$if sizeof(extended)=8}
  Result:=RoundTo(Double(AValue),Digits);
  {$else}
  Result:=ExactRoundToExtended(AValue,Digits);
  {$endif}
end;
{$endif}

{$ifdef FPC_HAS_TYPE_SINGLE}
function RoundTo(const AValue: Single; const Digits: TRoundToRange): Single;
begin
  Result:=ExactRoundToSingle(AValue,Digits);
end;
{$endif}
{$endif}
{$pop}

{$ifdef FPC_HAS_TYPE_SINGLE}
function SimpleRoundTo(const AValue: Single; const Digits: TRoundToRange = -2): Single;

var
  RV : Single;

begin
  RV := IntPower(10, -Digits);
  if AValue < 0 then
    Result := Int((AValue*RV) - 0.5)/RV
  else
    Result := Int((AValue*RV) + 0.5)/RV;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_DOUBLE}
function SimpleRoundTo(const AValue: Double; const Digits: TRoundToRange = -2): Double;

var
  RV : Double;

begin
  RV := IntPower(10, -Digits);
  if AValue < 0 then
    Result := Int((AValue*RV) - 0.5)/RV
  else
    Result := Int((AValue*RV) + 0.5)/RV;
end;
{$endif}

{$ifdef FPC_HAS_TYPE_EXTENDED}
function SimpleRoundTo(const AValue: Extended; const Digits: TRoundToRange = -2): Extended;

var
  RV : Extended;

begin
  RV := IntPower(10, -Digits);
  if AValue < 0 then
    Result := Int((AValue*RV) - 0.5)/RV
  else
    Result := Int((AValue*RV) + 0.5)/RV;
end;
{$endif}

function RandomFrom(const AValues: array of Double): Double; overload;
begin
  result:=AValues[random(High(AValues)+1)];
end;

function RandomFrom(const AValues: array of Integer): Integer; overload;
begin
  result:=AValues[random(High(AValues)+1)];
end;

function RandomFrom(const AValues: array of Int64): Int64; overload;
begin
  result:=AValues[random(High(AValues)+1)];
end;

{$if FPC_FULLVERSION >=30101}
generic function RandomFrom<T>(const AValues:array of T):T;
begin
  result:=AValues[random(High(AValues)+1)];
end;
{$endif}

function FutureValue(ARate: Float; NPeriods: Integer;
  APayment, APresentValue: Float; APaymentTime: TPaymentTime): Float;
var
  q, qn, factor: Float;
begin
  if ARate = 0 then
    Result := -APresentValue - APayment * NPeriods
  else begin
    q := 1.0 + ARate;
    qn := power(q, NPeriods);
    factor := (qn - 1) / (q - 1);
    if APaymentTime = ptStartOfPeriod then
      factor := factor * q;
    Result := -(APresentValue * qn + APayment*factor);
  end;
end;

function InterestRate(NPeriods: Integer; APayment, APresentValue, AFutureValue: Float;
  APaymentTime: TPaymentTime): Float;
{ The interest rate cannot be calculated analytically. We solve the equation
  numerically by means of the Newton method:
  - guess value for the interest reate
  - calculate at which interest rate the tangent of the curve fv(rate)
    (straight line!) has the requested future vale.
  - use this rate for the next iteration. }
const
  DELTA = 0.001;
  EPS = 1E-9;   // required precision of interest rate (after typ. 6 iterations)
  MAXIT = 20;   // max iteration count to protect against non-convergence
var
  r1, r2, dr: Float;
  fv1, fv2: Float;
  iteration: Integer;
begin
  iteration := 0;
  r1 := 0.05;  // initial guess
  repeat
    r2 := r1 + DELTA;
    fv1 := FutureValue(r1, NPeriods, APayment, APresentValue, APaymentTime);
    fv2 := FutureValue(r2, NPeriods, APayment, APresentValue, APaymentTime);
    dr := (AFutureValue - fv1) / (fv2 - fv1) * delta;  // tangent at fv(r)
    r1 := r1 + dr;      // next guess
    inc(iteration);
  until (abs(dr) < EPS) or (iteration >= MAXIT);
  Result := r1;
end;

function NumberOfPeriods(ARate, APayment, APresentValue, AFutureValue: Float;
  APaymentTime: TPaymentTime): Float;
{ Solve the cash flow equation (1) for q^n and take the logarithm }
var
  q, x1, x2: Float;
begin
  if ARate = 0 then
    Result := -(APresentValue + AFutureValue) / APayment
  else begin
    q := 1.0 + ARate;
    if APaymentTime = ptStartOfPeriod then
      APayment := APayment * q;
    x1 := APayment - AFutureValue * ARate;
    x2 := APayment + APresentValue * ARate;
    if   (x2 = 0)                    // we have to divide by x2
      or (sign(x1) * sign(x2) < 0)   // the argument of the log is negative
    then
      Result := Infinity
    else begin
      Result := ln(x1/x2) / ln(q);
    end;
  end;
end;

function Payment(ARate: Float; NPeriods: Integer;
  APresentValue, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
var
  q, qn, factor: Float;
begin
  if ARate = 0 then
    Result := -(AFutureValue + APresentValue) / NPeriods
  else begin
    q := 1.0 + ARate;
    qn := power(q, NPeriods);
    factor := (qn - 1) / (q - 1);
    if APaymentTime = ptStartOfPeriod then
      factor := factor * q;
    Result := -(AFutureValue + APresentValue * qn) / factor;
  end;
end;

function PresentValue(ARate: Float; NPeriods: Integer;
  APayment, AFutureValue: Float; APaymentTime: TPaymentTime): Float;
var
  q, qn, factor: Float;
begin
  if ARate = 0.0 then
    Result := -AFutureValue - APayment * NPeriods
  else begin
    q := 1.0 + ARate;
    qn := power(q, NPeriods);
    factor := (qn - 1) / (q - 1);
    if APaymentTime = ptStartOfPeriod then
      factor := factor * q;
    Result := -(AFutureValue + APayment*factor) / qn;
  end;
end;

{$else}
implementation
{$endif FPUNONE}

end.
