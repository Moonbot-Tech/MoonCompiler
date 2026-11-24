{ Line-break normalization counts embedded NUL and treats adjacent LF and CR as separate breaks. }

procedure RunBreadthLineNormalization;
const
  Original = 'A'#13'B'#13#10#0'C'#10'D'#10#13'E'#13;
  ExpectLF = 'A'#10'B'#10#0'C'#10'D'#10#10'E'#10;
  ExpectCRLF = 'A'#13#10'B'#13#10#0'C'#13#10'D'#13#10#13#10'E'#13#10;
var
  Input, LfText, CrLfText: string;
begin
  Input := Copy(Original, Integer(OpaqueI(1)), Length(Original));
  LfText := AdjustLineBreaks(Input, tlbsLF);
  CrLfText := AdjustLineBreaks(Input, tlbsCRLF);
  Check(LfText = ExpectLF, 'breadth-line-normalization-preserves-nul-and-collapses-crlf');
  Check(CrLfText = ExpectCRLF, 'breadth-line-normalization-expands-independent-breaks-to-crlf');
  Check(AdjustLineBreaks(CrLfText, tlbsLF) = ExpectLF, 'breadth-line-normalization-composes-crlf-and-lf');
  Check(Input = Original, 'breadth-line-normalization-keeps-counted-source-unchanged');
end;
