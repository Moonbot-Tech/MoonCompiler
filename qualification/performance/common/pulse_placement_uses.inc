{ Keep the number of imported modules equal: module IDs enter generic names. }
{$ifdef FPC}
  {$if defined(PULSE_FILLER_1)}pulse_filler_1,
  {$elseif defined(PULSE_FILLER_2)}pulse_filler_2,
  {$elseif defined(PULSE_FILLER_3)}pulse_filler_3,
  {$else}pulse_filler_0,
  {$endif}
{$endif}
