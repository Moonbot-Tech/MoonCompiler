program FPState_single_wide;
{$mode delphiunicode}{$H+}{$inline off}

{$define SMALL_FLOAT}
uses SysUtils, Math;
type TFloat=Single; TBits=Cardinal;
{$include fp_state_case.inc}
