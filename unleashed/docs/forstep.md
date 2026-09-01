# `for ... step`

`step N` clause in `for` loops advances the counter by an arbitrary positive amount on each iteration. Works with both `to` and `downto`, and with inline `var` counters.

Modeswitch: `forstep`, enabled by default in `{$mode unleashed}`; opt in elsewhere with `{$modeswitch forstep}`.

## Basic use

```pascal
for i := 1 to 10 step 2 do
  write(i, ' '); // 1 3 5 7 9

for i := 20 downto 1 step 3 do
  write(i, ' '); // 20 17 14 11 8 5 2

for var k := 5 to 50 step 5 do
  write(k, ' '); // 5 10 15 ... 50
```

The step expression must be ordinal and positive. Use `downto` for descending loops - the step itself is always positive, and a non-positive constant is a parse error.

## Single evaluation

The step expression is evaluated **once** before the loop starts, so calls with side effects fire exactly one time - the same way the classic for-loop treats its upper bound:

```pascal
for i := 0 to 12 step computeStep do
  use(i); // computeStep called exactly once
```

## `step` is a context-sensitive keyword

`step` is **not** a reserved token. The parser checks for it in one position only: right after the `to` / `downto` expression and before `do`. Anywhere else `step` stays an ordinary identifier, so existing code keeps compiling:

```pascal
var step: integer = 5; // OK - a variable named step

function step: integer; // OK - a function named step

type TFoo = record step: integer end; // OK - a record field named step

for i := 1 to step do use(i); // OK - the upper bound is the variable

for i := 0 to step step 1 do use(i); // OK - first `step` is the upper bound, second is the keyword
```

The SynEdit highlighter in Unleashed Pascal IDE mirrors this: only the keyword position lights up.

## Constant `step 1` folds back

A literal `step 1` is dropped during `simplify`, so the loop reverts to the regular for-loop code path and keeps every existing optimization (range-check elision, unrolling, ...). Only `step N` for `N >= 2`, or a non-constant step, takes the dedicated path.

## Generated code

A surviving step lowers the for-loop to a rotated loop measured by physical distance. Step and the remaining distance live in a wide unsigned domain (64-bit, or 128-bit for 128-bit counters/steps), so no combination of counter and step widths can truncate, and the counter is advanced modulo its own width - the loop can neither wrap into an endless run nor trip `$Q`/`$R` on its own arithmetic:

```
steptemp := step;                     // evaluated once, own signedness
if steptemp <= 0 then RangeError;     // runtime contract, see Errors
totemp := to;  i := from;
if i <= totemp then                   // >= for downto
  repeat
    body;                             // continue lands on the latch
  latch:
    dist := bits(totemp) - bits(i);   // reversed for downto
    i := low_bits(i + steptemp);      // modular; exact while in range
    if steptemp > dist then break;    // i now holds the first-past value
  until false;
```

This shape lets every control-flow construct behave as in a regular for-loop:

- `continue` jumps to the latch: increment, distance check, then the next body pass. No infinite loop, also not from a `try/finally` inside the body.
- `break` exits cleanly; the counter holds the value at break time.
- `exit` and `raise` propagate normally; no temporaries to clean up.

Steady-state cost: one compare, one subtraction and one addition per iteration - no first-iteration flag, no wrap detection.

## Counter value after the loop

Unleashed mode preserves the for-loop counter after the loop (see [tweaks.md](tweaks.md)). With `step`, the guarantee is "last assigned value" - and because the lowering advances the counter *before* the range check, a natural exit leaves the **first value past the bound**, not the last one the body saw:

```pascal
for i := 1 to 10 step 4 do ; // body sees 1, 5, 9
{ i = 13 after the loop (9 + step) }

for i := 20 downto 1 step 3 do ; // body sees 20, 17, ..., 2
{ i = -1 after the loop (2 - step) }

for i := 1 to 10 step 4 do
  if i = 5 then break;
{ i = 5 - break keeps the exact value }
```

When the post-loop value matters, prefer `break` (exact), or derive the last body value as `i - step` (`i + step` for `downto`) after a natural exit.

## Type rules

The step expression must be ordinal; the compiler picks the wider of the step type and the counter's range type for the increment arithmetic.

| Counter type | Step | Status |
|---|---|---|
| integer of any width (`byte` ... `int64`) | any positive integer expression | works |
| enum | positive integer (ordinal distance) | works: `for var d := dMon to dFri step 2 do` visits every other value |
| `char` | - | not supported: rejected with `Illegal type conversion: "ShortString" to "AnsiChar"` |

Note the inline-var inference gotcha: `for var ch := 'a' to 'z' do` infers a **string** counter (char literals promote to string under inference) - a char counter needs the explicit type, `for var ch: char := 'a' to 'z' do`, and takes no `step`.

## Errors

| Message | Trigger |
|---|---|
| `Step value must be a positive integer` | constant `step 0` or `step -N` |
| `Step expression must be of ordinal type` | step is a real / string / pointer expression |
| `Step is not allowed in for-in loops` | `step` after a `for ... in` collection |
| runtime error 201 (range check) | a runtime step value `<= 0`, raised after the single step evaluation, before the bound and counter are touched and before the first body pass |

With the modeswitch off (`{$modeswitch forstep-}`), `step` in a for-header is not recognized at all and the parser reports `Syntax error, "DO" expected but "identifier STEP" found`.

## Edge cases

| Case | Behavior |
|---|---|
| `for i := 1 to 5 step 100 do` | body runs once (`i = 1`), then the remaining distance is exceeded and the loop exits |
| `for b := 0 to 10 step 256 do` (Byte counter) | body runs once (`b = 0`); the step is *not* truncated to the counter's width |
| `for i := 10 to 1 step 2 do` | empty range, body never runs, counter holds `from` |
| `for i := 5 to 5 step 3 do` | single iteration (`i = 5`) |
| step from a runtime variable holding `0` or a negative value | runtime error 201 before the first iteration |
| nested for-step loops | each level keeps its own step and counter |

`step` also composes with `for parallel` loops - see [parallelfor.md](parallelfor.md).

## Demo

```pascal
program for_step_demo;

{$mode unleashed}

type
  TDay = (dMon, dTue, dWed, dThu, dFri);

var
  calls: integer = 0;

function stride: integer;
begin
  inc(calls);
  result := 4;
end;

begin
  // every third number: 3 + 6 + ... + 99
  var sum := 0;
  for var i := 3 to 99 step 3 do sum += i;
  writeln($'sum of multiples of 3 up to 99: {sum}');

  // countdown by 25
  write('launch in:');
  for var t := 100 downto 0 step 25 do write(' ', t);
  writeln;

  // enum counters advance by ordinal distance
  write('every other day: ');
  for var d: TDay := dMon to dFri step 2 do write(d, ' ');
  writeln;

  // the step expression is evaluated once, before the loop starts
  var hits := 0;
  for var i := 0 to 20 step stride do inc(hits);
  writeln($'0..20 step stride(): {hits} iterations, stride evaluated {calls} time(s)');
  {$ifdef WINDOWS}readln;{$endif}
end.
```

Output:

```
sum of multiples of 3 up to 99: 1683
launch in: 100 75 50 25 0
every other day: dMon dWed dFri
0..20 step stride(): 6 iterations, stride evaluated 1 time(s)
```
