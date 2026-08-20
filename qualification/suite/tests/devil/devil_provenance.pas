unit devil_provenance;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}

interface

{ нетипизированные константы: по тексту ремонта именно их }
{ провенанс сериализуется в PPU и обязан пережить границу }
const
  DvlProvOne = 1;
  DvlProvSeven = 7;
  DvlProvThreeHundred = 300;
  DvlProvBig = 5000000000;
  DvlProvChar = 'a';
  DvlProvText = 'ab';

implementation

end.
