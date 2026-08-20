"""Свести dvl-gen-00109 к отдельной программе: какая часть формы обязательна.

Форма из генератора: значение присваивается внутри `with`-блока над записью,
затем сужается к беззнаковому той же ширины. release теряет сужение.
Стенд собирает несколько вариантов формы и печатает, какой из них
воспроизводит потерю, а какой нет.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from pathlib import Path

SUITE = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(SUITE / "scripts"))
import devil_toolchain as tc  # noqa: E402

HERE = SUITE / "results" / "runs" / "devil-dvl-0043-min109"
HEAD = """program {name};
{{$ifdef FPC}}{{$mode delphiunicode}}{{$H+}}{{$modeswitch advancedrecords}}{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}
uses
{{$ifdef FPC}}
  mormot.core.fpcx64mm,
{{$endif}}
  SysUtils;

type
  TBox = record
    Fi8: ShortInt;
    Fu8: Byte;
    Fi16: SmallInt;
    Fu16: Word;
    Fi32: Integer;
    Fu32: Cardinal;
    Fi64: Int64;
    Fu64: UInt64;
  end;

function OpaqueI(V: Int64): Int64;
begin
  Result := V xor 0;
end;

function RawI16(V: SmallInt): UInt64;
begin
  Result := UInt64(Word(V));
end;

"""


def say(*parts: object) -> None:
    print("[%s]" % time.strftime("%H:%M:%S"), *parts, flush=True)


VARIANTS = {
    # ровно та форма, что в генераторе
    "with-record": """var
  Val: SmallInt;
  W1: TBox;
begin
  W1.Fi32 := Integer(OpaqueI(1));
  with W1 do
  begin
    Val := SmallInt(-32767);
    if Fi32 <> 1 then
      WriteLn('unreachable');
  end;
  WriteLn(RawI16(Val));
end.""",
    # без with: то же самое, но поле читается напрямую
    "no-with": """var
  Val: SmallInt;
  W1: TBox;
begin
  W1.Fi32 := Integer(OpaqueI(1));
  Val := SmallInt(-32767);
  if W1.Fi32 <> 1 then
    WriteLn('unreachable');
  WriteLn(RawI16(Val));
end.""",
    # with есть, но записи внутри него нет
    "with-empty": """var
  Val: SmallInt;
  W1: TBox;
begin
  W1.Fi32 := Integer(OpaqueI(1));
  Val := SmallInt(-32767);
  with W1 do
    if Fi32 <> 1 then
      WriteLn('unreachable');
  WriteLn(RawI16(Val));
end.""",
    # без непрозрачного источника у поля
    "with-const-field": """var
  Val: SmallInt;
  W1: TBox;
begin
  W1.Fi32 := 1;
  with W1 do
  begin
    Val := SmallInt(-32767);
    if Fi32 <> 1 then
      WriteLn('unreachable');
  end;
  WriteLn(RawI16(Val));
end.""",
    # сужение прямо на месте, без вызова функции
    "inline-narrow": """var
  Val: SmallInt;
  W1: TBox;
begin
  W1.Fi32 := Integer(OpaqueI(1));
  with W1 do
  begin
    Val := SmallInt(-32767);
    if Fi32 <> 1 then
      WriteLn('unreachable');
  end;
  WriteLn(UInt64(Word(Val)));
end.""",
}

EXPECTED = 0x8001


def main() -> None:
    if HERE.exists():
        shutil.rmtree(HERE)
    HERE.mkdir(parents=True)
    for name, body in VARIANTS.items():
        stem = name.replace("-", "_")
        source = HERE / (stem + ".dpr")
        source.write_text(HEAD.format(name=stem) + body, encoding="utf-8")
        line = []
        for profile in ("debug", "o2", "release"):
            out = HERE / ("out-%s-%s" % (stem, profile))
            out.mkdir(parents=True, exist_ok=True)
            r = subprocess.run(tc.compile_command(source, out, profile),
                               capture_output=True, text=True, timeout=300)
            if r.returncode:
                line.append("%s=ОТКАЗ" % profile)
                continue
            run = subprocess.run([str(out / (stem + ".exe"))],
                                 capture_output=True, text=True, timeout=120)
            got = run.stdout.strip()
            mark = "верно" if got == str(EXPECTED) else "ПОТЕРЯ " + got
            line.append("%s=%s" % (profile, mark))
        say("%-18s %s" % (name, "  ".join(line)))


main()
