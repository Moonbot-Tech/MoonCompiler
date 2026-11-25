{ Clip an invalidation rectangle before scrolling, then merge an overlay at the new location. }

procedure RunBreadthViewportGeometry;
var
  Viewport, Damage, Clipped: TRect;
  Overlay, Fractional: TRectF;
begin
  Viewport := Rect(Integer(OpaqueI(-19)), -7, 13, 21);
  Damage := Rect(5, -15, 22, 12);
  Clipped := TRect.Intersect(Viewport, Damage);
  Check((Clipped.Left = 5) and (Clipped.Top = -7) and (Clipped.Right = 13) and (Clipped.Bottom = 12),
    'breadth-viewport-clip-preserves-negative-screen-origin');
  Check(Clipped.Contains(Point(5, -7)) and Clipped.Contains(Point(12, 11)),
    'breadth-viewport-hit-test-includes-left-top-and-final-interior-pixel');
  Check(not Clipped.Contains(Point(13, 0)) and not Clipped.Contains(Point(5, 12)),
    'breadth-viewport-hit-test-excludes-right-and-bottom-edges');
  Clipped.Offset(Point(Integer(OpaqueI(-9)), 23));
  Check((Clipped.Left = -4) and (Clipped.Top = 16) and (Clipped.Width = 8) and (Clipped.Height = 19),
    'breadth-viewport-scrolling-keeps-pixel-size');
  Clipped := TRect.Union(Clipped, Rect(-7, 31, -1, 40));
  Check((Clipped.Left = -7) and (Clipped.Top = 16) and (Clipped.Right = 4) and (Clipped.Bottom = 40),
    'breadth-viewport-merge-covers-both-dirty-regions');
  Mix(UInt64(Clipped.Width * 100 + Clipped.Height));

  Overlay := RectF(Single(OpaqueD(-2.25)), -1.5, 6.75, 4);
  Fractional := TRectF.Intersect(Overlay, RectF(3.5, -2.25, 7.5, 1.25));
  Check((Fractional.Left = 3.5) and (Fractional.Top = -1.5) and (Fractional.Right = 6.75) and (Fractional.Bottom = 1.25),
    'breadth-overlay-clip-keeps-exact-subpixel-boundaries');
  Fractional.Offset(-0.5, 2.25);
  Check((Fractional.Left = 3) and (Fractional.Top = 0.75) and (Fractional.Width = 3.25) and (Fractional.Height = 2.75),
    'breadth-overlay-scroll-keeps-fractional-width-and-height');
  Check(Fractional.Contains(PointF(6.125, 2)) and not Fractional.Contains(PointF(6.25, 2)),
    'breadth-overlay-hit-test-uses-half-open-subpixel-right-edge');
end;
