unit variant_literal_type_unit;

{$ifdef FPC}
{$mode delphiunicode}{$H+}
{$endif FPC}

interface

const
  PpuPlainReal = 1.5;
  PpuExponentReal = 1.5e0;
  PpuFoldedReal = 1.0 + 0.5;
  PpuTypedDouble: Double = 1.5;

implementation

end.
