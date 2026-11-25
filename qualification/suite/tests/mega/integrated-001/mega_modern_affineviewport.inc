{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Convert a point between model and device coordinates for rendering and hit testing. }

procedure RunBreadthAffineViewport;
var
  Scaling, Translation, ToDevice, ToModel: TMatrix;
  Model, Device, Recovered: TPointF;
begin
  Scaling := TMatrix.CreateScaling(Single(OpaqueD(2)), Single(OpaqueD(-4)));
  Translation := TMatrix.CreateTranslation(-5, 7);
  ToDevice := Scaling * Translation;
  Model := PointF(Single(OpaqueD(3.25)), -1.5);
  Device := Model * ToDevice;
  Check((Device.X = 1.5) and (Device.Y = 13), 'breadth-affine-applies-scale-before-screen-origin');
  Check(ToDevice.Determinant = -8, 'breadth-affine-reflection-has-negative-determinant');
  ToModel := ToDevice.Inverse;
  Recovered := PointF(1.5, 13) * ToModel;
  Check((Recovered.X = 3.25) and (Recovered.Y = -1.5), 'breadth-affine-inverts-known-device-point');
  Mix(UInt64(Round(Recovered.X * 100 + Recovered.Y * 10)));
end;
{$endif}
