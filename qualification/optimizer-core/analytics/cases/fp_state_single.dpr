program FPState_single;
{$mode delphiunicode}{$H+}{$inline off}
{$EXCESSPRECISION OFF}
{$define SMALL_FLOAT}
uses SysUtils, Math;
type TFloat=Single; TBits=Cardinal;
{$include fp_state_case.inc}
