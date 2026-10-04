unit rtl_random_reference;
{ Frozen pre-optimization stream oracle. ObjFPC preserves System's width-aware Lo/Hi. }
{$mode objfpc}
interface
procedure ResetSeed(S:Cardinal);
function Draw32(l:LongInt):LongInt;
function Draw64(l:Int64):Int64;
function DrawFloat:Extended;
function CurrentSeed:Cardinal;
var RareDraws:Integer;
implementation
var LocalSeed:Cardinal=0;
    OldSeed:Cardinal=Cardinal(not Cardinal(0));
{$push} // random
{$r-,q-}

// SplitMix64, being a generator of fundamentally different nature,
// is a good (recommended by the author) way to seed Xoshiro.
//
// https://xoroshiro.di.unimi.it/splitmix64.c
//
// This is a generator with 64-bit state, 64-bit output, and 2^64 period.

type
  SplitMix64 = object
    procedure Setup(const seed: uint64); inline;
    function Next: uint64;
  private
    state: uint64;
  end;

procedure SplitMix64.Setup(const seed: uint64);
begin
  state := seed;
end;

function SplitMix64.Next: uint64;
var
  z: uint64;
begin
  z := state + $9e3779b97f4a7c15;
  state := z;
  z := (z xor (z shr 30)) * $bf58476d1ce4e5b9;
  z := (z xor (z shr 27)) * $94d049bb133111eb;
  result := z xor (z shr 31);
end;

// Xoshiro128** is an all-purpose RNG.
// http://prng.di.unimi.it/xoshiro128starstar.c
//
// State must not be everywhere zero. With SplitMix64 initialization, it won't. :)
// 128-bit state, 32-bit output, 2^128-1 period.

type
  Xoshiro128ss_32 = object
    procedure Setup(const seed: uint64);
    function Next: uint32; inline; // inlined as it is actually internal and called only through xsr128_32_u32rand
  private
    state: array[0 .. 3] of longword;
  end;

  procedure Xoshiro128ss_32.Setup(const seed: uint64);
  var
    sm: SplitMix64;
    x: uint64;
  begin
    sm.Setup(seed);
    x := sm.Next;
    state[0] := Lo(x); state[1] := Hi(x);
    x := sm.Next;
    state[2] := Lo(x); state[3] := Hi(x);
  end;

  function Xoshiro128ss_32.Next: uint32;
  var
    s0, s1, s2, s3: uint32;
  begin
    s0 := state[0];
    s1 := state[1];
    s2 := state[2] xor s0;
    s3 := state[3] xor s1;
    result := RolDWord(s1 * 5, 7) * 9;

    state[0] := s0 xor s3;
    state[1] := s1 xor s2;
    state[2] := s2 xor (s1 shl 9);
    state[3] := RolDWord(s3, 11);
  end;

var
  // Just in case user sets LocalSeed := not Cardinal(0) (LocalSeed := $FFFFFFFF) from the start,
  // thus bypassing first-time LocalSeed <> OldSeed check,
  // there will still be a precomputed initialization for LocalSeed = $FFFFFFFF.
  GlobalXsr128_32: Xoshiro128ss_32 = (state: ($AFF181C0, $73B13BA2, $1340D3B4, $61204305));

  procedure ReseedGlobalRNG;
  begin
    { Detect resets of randseed

      This will break if someone coincidentally uses not(randseed) as the
      next randseed, but it's much more common that you will reset randseed
      to the same value as before to regenerate the same sequence of numbers
    }
    GlobalXsr128_32.Setup(LocalSeed);
    LocalSeed := not LocalSeed;
    OldSeed := LocalSeed;
  end;

  function xsr128_32_u32rand: uint32;
  begin
    if LocalSeed <> OldSeed then ReseedGlobalRNG;
    result := GlobalXsr128_32.Next;
  end;

  // There's still a flaw: repeated assignments of LocalSeed := $FFFFFFFF from the start, i.e.
  // LocalSeed := $FFFFFFFF;
  // writeln(random(10));
  // LocalSeed := $FFFFFFFF;
  // writeln(random(10));
  // won't reset RNG.
  //
  // But this is already the case with carefully crafted LocalSeeds,
  // so I doubt an additional check like "if (LocalSeed <> OldSeed) or not RngInitialized" is justified.

function Draw32(l:longint): longint;
var
  t: uint32;
  m: uint64;
begin
  result:=l;
  if l<0 then
    result:=-result-1; { from now on, uint32(result) is a bound. }

  { https://lemire.me/blog/2019/06/06/nearly-divisionless-random-integer-generation-on-various-systems/ }
  m:=uint64(xsr128_32_u32rand)*uint32(result);
  if Lo(m)<uint32(result) then
    begin
      t:=uint32(-result) mod uint32(result);
      while Lo(m)<t do
        m:=uint64(xsr128_32_u32rand)*uint32(result);
    end;
  result:=Hi(m);

  if l<-1 then
    result:=-result-1;
end;

function Draw64(l:int64): int64;
var
  t, ul, mLo: uint64;
  a: uint32;
begin
  if l=int32(l) then
    { This makes random(NativeType) on 64-bit platforms match 32-bit when possible. }
    exit(Draw32(longint(l)));

  ul:=l;
  if l<0 then
    ul:=-ul-1;

  a:=xsr128_32_u32rand;
  mLo:=UMul64x64_128(uint64(a) shl 32 or xsr128_32_u32rand,ul,uint64(result));
  if mLo<ul then
    begin
      t:=uint64(-ul) mod ul;
      while mLo<t do
        begin
          a:=xsr128_32_u32rand;
          mLo:=UMul64x64_128(uint64(a) shl 32 or xsr128_32_u32rand,ul,uint64(result));
        end;
    end;

  if l<-1 then
    result:=-result-1;
end;

{$ifndef FPUNONE}
function DrawFloat: extended;
var
  res: double;
  r0, exponent: uint32;
begin
  { There are

    - 2⁵² floats uniformly distributed over the range [0.5; 1): exponent = 2⁻¹, mantissa = (1.)all 52-bit values from 00...0 to 11...1,
    - another 2⁵² in the range [0.25; 0.5): exponent = 2⁻²,
    - another 2⁵² in the range [0.125; 0.25): exponent = 2⁻³,

    and so on. Each next range is 0.5× the size of the previous one ⇒ 0.5× probability.
    So we determine the range by flipping a coin until we get heads (exponent = 2^(−1 − BSF(infinite stream of random bits)),
    and select one of 2⁵² values in that range.

    Compared to this, random_52_bits / 2⁵² value loses N bits of precision when it falls in the Nth range; as a consequence,
    minimum of 2^N random values has around N trailing zeros in its mantissa. }

  { 52 bits (double precision) go to mantissa: r0[0:19] + one_more_u32rand[0:31]. }
  r0:=xsr128_32_u32rand;
  PUint64(@res)^:=uint64(r0 and (1 shl 20-1)) shl 32 or xsr128_32_u32rand;

  { Exponent = −1 − (count of zeros in the stream of random bits). There are 12 bits left in r0. }
  exponent:=1023-1-31; { Biased exponent, - 31 for Bsr(r0). }
  if r0 shr 20=0 then
    begin
      inc(exponent,20); { Subtract 12 bits the first time and 32 on subsequent iterations. }
      repeat
        dec(exponent,32);
        Inc(RareDraws);
        r0:=xsr128_32_u32rand;
      until r0<>0;
    end;
  PUint64(@res)^:=PUint64(@res)^ or uint64(exponent+BsrDWord(r0)) shl 52;
  result:=res;
end;
{$endif}

{$pop} // random
procedure ResetSeed(S:Cardinal);
begin LocalSeed:=S;end;
function CurrentSeed:Cardinal;
begin Result:=LocalSeed;end;
end.
