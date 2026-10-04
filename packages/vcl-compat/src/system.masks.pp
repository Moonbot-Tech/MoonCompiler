{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the MoonCompiler contributors

    Wildcard masks with the Delphi System.Masks surface.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 2.4) and
    from the usual glob semantics.  No Embarcadero source, interface text or
    documentation excerpt was consulted or copied.  Author: MoonCompiler
    team, 2026-09-21.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.Masks;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils;

type
  EMaskException = class(Exception);

  { A compiled mask.  Syntax:
      *        any run of characters, the empty one included;
      ?        exactly one character (the end of the text is not one);
      [abc]    one character out of the set, [a-z] a range, [!...] the
               complement of the set ("!" only as the first character);
      others   themselves.
    Letters a..z match either case (ASCII only; other letters match as they
    are).  A "?" right behind a "*" is dropped ("*?" is "*") and repeated "*"
    collapse into one run.  Sets hold the characters #0..#255 only: a
    character above #255 in the mask is not a member, one in the text is in
    no set (so a negated set accepts it), and a surrogate pair inside a set
    is skipped; outside a set a surrogate pair is one literal of two Chars.
    The empty mask matches only the empty text.  Matching backtracks over
    every "*".
    EMaskException, with the mask and the 1-based position of the offending
    character (Length + 1 when the mask ends too early): "-" as the first
    character of a set, "-" without an end ("[a-]"), an empty set, an
    unclosed "[", more than 30 runs of "*".
    Where Delphi's matcher reads the terminating #0 of the text as a
    character - a negated set at the end of the text, "[!a]" against "" -
    this one does not: the end of the text is not a character.  A #0 inside
    the mask or the text is a character here, not the end. }
  TMask = class
  private
    type
      TNodeKind = (nkLiteral, nkLiteralPair, nkAnyOne, nkAnyRun, nkSet);
      TNode = record
        Kind: TNodeKind;
        Ch: Char;         { nkLiteral: the (ASCII-upcased) character }
        Ch2: Char;        { nkLiteralPair: the low surrogate }
        Negate: Boolean;  { nkSet }
        Chars: set of Byte;
      end;
    var
      FMask: string;
      FNodes: array of TNode;
      FCount: Integer;
    procedure Compile;
    procedure Error(Position: Integer);
    function MatchFrom(NodeIndex, TextIndex: Integer; const Text: string): Boolean;
  public
    constructor Create(const MaskValue: string);
    destructor Destroy; override;
    function Matches(const Filename: string): Boolean;
  end;

function MatchesMask(const Filename, Mask: string): Boolean;

implementation

resourcestring
  SInvalidMask = 'Invalid mask "%s" at position %d';

const
  MaxRuns = 30;

{ letters a..z only: the mask is case-insensitive for ASCII alone }
function AsciiUpCase(C: Char): Char; inline;
begin
  if (C >= 'a') and (C <= 'z') then
    Result := Char(Ord(C) - 32)
  else
    Result := C;
end;

function IsHighSurrogate(C: Char): Boolean; inline;
begin
  Result := (Ord(C) >= $D800) and (Ord(C) <= $DBFF);
end;

function IsLowSurrogate(C: Char): Boolean; inline;
begin
  Result := (Ord(C) >= $DC00) and (Ord(C) <= $DFFF);
end;

constructor TMask.Create(const MaskValue: string);
begin
  inherited Create;
  FMask := MaskValue;
  Compile;
end;

destructor TMask.Destroy;
begin
  FNodes := nil;
  inherited Destroy;
end;

procedure TMask.Error(Position: Integer);
begin
  raise EMaskException.CreateFmt(SInvalidMask, [FMask, Position]);
end;

procedure TMask.Compile;
var
  I, L, Stars, SetStart: Integer;
  C, Lo, Hi: Char;
  LastWasStar: Boolean;

  procedure Add(const Node: TNode);
  begin
    if FCount = Length(FNodes) then
      SetLength(FNodes, FCount + 8);
    FNodes[FCount] := Node;
    Inc(FCount);
  end;

  { members are #0..#255: a range is clipped to them }
  procedure AddRange(var Node: TNode; ALo, AHi: Char);
  var
    B, Last: Integer;
  begin
    ALo := AsciiUpCase(ALo);
    AHi := AsciiUpCase(AHi);
    Last := Ord(AHi);
    if Last > 255 then
      Last := 255;
    for B := Ord(ALo) to Last do
      Include(Node.Chars, B);
  end;

var
  Node: TNode;
begin
  FCount := 0;
  L := Length(FMask);
  Stars := 0;
  LastWasStar := False;
  I := 1;
  while I <= L do
  begin
    C := FMask[I];
    Node := Default(TNode);
    case C of
      '*':
        begin
          if not LastWasStar then
          begin
            Inc(Stars);
            if Stars > MaxRuns then
              Error(I);
            Node.Kind := nkAnyRun;
            Add(Node);
          end;
          LastWasStar := True;
          Inc(I);
          Continue;
        end;
      '?':
        begin
          { "*?" is "*": the "?" behind a run adds nothing }
          if not LastWasStar then
          begin
            Node.Kind := nkAnyOne;
            Add(Node);
          end;
          Inc(I);
          Continue;
        end;
      '[':
        begin
          Node.Kind := nkSet;
          SetStart := I;
          Inc(I);
          if (I <= L) and (FMask[I] = '!') then
          begin
            Node.Negate := True;
            Inc(I);
          end;
          if I > L then
            Error(I);            { unclosed: nothing follows the "[" }
          if FMask[I] = ']' then
            Error(I);            { empty set }
          if FMask[I] = '-' then
            Error(I);            { a range without a start }
          while (I <= L) and (FMask[I] <> ']') do
          begin
            Lo := FMask[I];
            if IsHighSurrogate(Lo) or IsLowSurrogate(Lo) then
            begin
              { surrogates cannot be set members: skipped }
              Inc(I);
              Continue;
            end;
            if (I < L) and (FMask[I + 1] = '-') then
            begin
              if (I + 2 > L) or (FMask[I + 2] = ']') then
                Error(I + 1);    { a range without an end }
              Hi := FMask[I + 2];
              AddRange(Node, Lo, Hi);
              Inc(I, 3);
            end
            else
            begin
              if Ord(Lo) <= 255 then
                Include(Node.Chars, Byte(AsciiUpCase(Lo)));
              Inc(I);
            end;
          end;
          if I > L then
            Error(I);            { unclosed set }
          Inc(I);                { the "]" }
          Add(Node);
        end;
      else
        begin
          if IsHighSurrogate(C) and (I < L) and IsLowSurrogate(FMask[I + 1]) then
          begin
            Node.Kind := nkLiteralPair;
            Node.Ch := C;
            Node.Ch2 := FMask[I + 1];
            Inc(I, 2);
          end
          else
          begin
            Node.Kind := nkLiteral;
            Node.Ch := AsciiUpCase(C);
            Inc(I);
          end;
          Add(Node);
        end;
    end;
    LastWasStar := False;
  end;
end;

{ a character above #255 is in no set }
function InSet(const Node: TMask.TNode; C: Char): Boolean; inline;
begin
  Result := (Ord(C) <= 255) and (Byte(AsciiUpCase(C)) in Node.Chars);
end;

function TMask.MatchFrom(NodeIndex, TextIndex: Integer; const Text: string): Boolean;
var
  L, StarNode, StarText: Integer;
begin
  L := Length(Text);
  StarNode := -1;
  StarText := TextIndex;
  while True do
  begin
    while NodeIndex < FCount do
    begin
      with FNodes[NodeIndex] do
        case Kind of
          nkAnyRun:
            begin
              { The last run swallows the rest; an interior run starts with
                an empty match and grows only if the following segment fails. }
              if NodeIndex = FCount - 1 then
                Exit(True);
              StarNode := NodeIndex + 1;
              StarText := TextIndex;
              Inc(NodeIndex);
              Continue;
            end;
          nkAnyOne:
            if TextIndex > L then
              Break;
          nkLiteral:
            if (TextIndex > L) or (AsciiUpCase(Text[TextIndex]) <> Ch) then
              Break;
          nkLiteralPair:
            begin
              if (TextIndex + 1 > L) or (Text[TextIndex] <> Ch) or (Text[TextIndex + 1] <> Ch2) then
                Break;
              Inc(TextIndex);
            end;
          nkSet:
            if (TextIndex > L) or (InSet(FNodes[NodeIndex], Text[TextIndex]) = Negate) then
              Break;
        end;
      Inc(NodeIndex);
      Inc(TextIndex);
    end;
    if (NodeIndex = FCount) and (TextIndex > L) then
      Exit(True);
    { Each fixed segment is accepted at its earliest position.  Once a later
      star is reached it can absorb anything an earlier star could add, so
      only this last star needs a retry point. }
    if (StarNode < 0) or (StarText > L) then
      Exit(False);
    Inc(StarText);
    TextIndex := StarText;
    NodeIndex := StarNode;
  end;
end;

function TMask.Matches(const Filename: string): Boolean;
begin
  Result := MatchFrom(0, 1, Filename);
end;

function MatchesMask(const Filename, Mask: string): Boolean;
var
  M: TMask;
begin
  M := TMask.Create(Mask);
  try
    Result := M.Matches(Filename);
  finally
    M.Free;
  end;
end;

end.
