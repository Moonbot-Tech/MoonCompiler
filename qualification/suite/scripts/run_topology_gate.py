#!/usr/bin/env python3
"""Топология модулей как перебираемая ось.

Компилятор собирает не файл, а граф файлов, и порядок, в котором он их
разбирает, задаётся этим графом. Легальные циклы — не редкость и не экзотика:
заголовки библиотек, обёртки над чужим кодом, пары «менеджер и его элемент»
ссылаются друг на друга сплошь и рядом. Для компилятора же цикл — неудобная
середина: когда разбирается реализация одного юнита, интерфейс другого уже
готов, а его реализация ещё нет, и символы в ней ещё не получили номеров,
пригодных для записи в готовый модуль.

В эту середину попадает перенос кода между юнитами. Маленькое тело из соседа
компилятор вправе вставить в место вызова, но вместе с телом туда обязаны
приехать и символы, которых оно касается. Если символ закрытый, статический и
живёт в юните, чья реализация ещё в работе, — вставка обращается к тому, чего
ещё нет.

Здесь это пространство перебирается целиком: **топология графа × вид символа ×
способ переноса**. Каждая тройка — своя маленькая программа из трёх-четырёх
юнитов, которая считает известное число.

Проверяются две вещи, и обе — находки:

* **сборка**. Корректный исходник обязан собираться при любой топологии и любом
  наборе ключей. Падение сборки — дефект компилятора сам по себе.
* **ответ**. Программа печатает то, что посчитала; ожидаемое известно заранее
  из арифметики, а не из прошлого прогона.

Прогон идёт в матрице профилей и отдельных ключей: слитный профиль может не
задействовать преобразование, из-за которого форма и ломается.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]

HEAD = """unit %(name)s;

{$mode delphi}
{$Q-}{$R-}

interface
"""

# --- виды символов, к которым тянется переносимое тело -----------------------
#
# Для каждого: объявления в секции реализации соседа, тело функции и вклад в
# ожидаемый ответ. Тело всегда короткое — таким его охотнее переносят.

SYMBOLS = {
    "private-class-var": {
        "decl": """type
  THolder = class
  private
    class var FValue: Int64;
  end;
""",
        "body": """  THolder.FValue := THolder.FValue + Delta;
  Result := THolder.FValue;""",
        "kind": "accumulate",
    },
    "private-class-var-pointer": {
        "decl": """type
  THolder = class
  private
    class var FSlot: Pointer;
  end;
""",
        "body": """  if THolder.FSlot = nil then
    THolder.FSlot := Pointer(1);
  Result := Delta + Int64(NativeInt(THolder.FSlot));""",
        "kind": "plus-one",
    },
    "threadvar": {
        "decl": """threadvar
  Local: Int64;
""",
        "body": """  Local := Local + Delta;
  Result := Local;""",
        "kind": "accumulate",
    },
    "typed-const": {
        "decl": """const
  Base: Int64 = 100;
""",
        "body": """  Result := Base + Delta;""",
        "kind": "base100",
    },
    "unit-global": {
        "decl": """var
  Total: Int64;
""",
        "body": """  Total := Total + Delta;
  Result := Total;""",
        "kind": "accumulate",
    },
    "class-const": {
        "decl": """type
  THolder = class
  public
    const Step = 100;
  end;
""",
        "body": """  Result := THolder.Step + Delta;""",
        "kind": "base100",
    },
    "class-method": {
        "decl": """type
  THolder = class
  private
    class var FValue: Int64;
  public
    class function Bump(D: Int64): Int64;
  end;

class function THolder.Bump(D: Int64): Int64;
begin
  FValue := FValue + D;
  Result := FValue;
end;
""",
        "body": """  Result := THolder.Bump(Delta);""",
        "kind": "accumulate",
    },
    "generic-holder": {
        "decl": """type
  TBox<T> = class
  private
    class var FValue: T;
  public
    class function Add(D: T): T;
  end;

class function TBox<T>.Add(D: T): T;
begin
  FValue := FValue + D;
  Result := FValue;
end;
""",
        "body": """  Result := TBox<Int64>.Add(Delta);""",
        "kind": "accumulate",
    },
    "interface-var": {
        "decl": "",
        "interface_decl": """var
  Shared: Int64;
""",
        "body": """  Shared := Shared + Delta;
  Result := Shared;""",
        "kind": "accumulate",
    },
    "record-operator": {
        "decl": """type
  TCounter = record
    Value: Int64;
    class operator Add(const A: TCounter; const B: Int64): TCounter;
  end;

class operator TCounter.Add(const A: TCounter; const B: Int64): TCounter;
begin
  Result.Value := A.Value + B;
end;

var
  Held: TCounter;
""",
        "body": """  Held := Held + Delta;
  Result := Held.Value;""",
        "kind": "accumulate",
    },
}

# --- способ, которым тело попадает в чужой юнит ------------------------------

CARRIERS = {
    "plain": {"directive": "", "wrap": False},
    "explicit-inline": {"directive": " inline;", "wrap": False},
    "through-wrapper": {"directive": "", "wrap": True},
}

# --- топологии графа юнитов --------------------------------------------------
#
# "edges": (кто, кого, где) — где: 'i' интерфейс, 'm' реализация.
# Точка входа всегда первый юнит; тело-донор всегда в последнем.

TOPOLOGIES = {
    # Форма, на которой ломался боевой билд: донор называет потребителя в
    # своём интерфейсе, потребитель донора — в реализации.
    "cycle-iface-impl": {"units": 2, "edges": [(0, 1, "m"), (1, 0, "i")]},
    # Оба видят друг друга только из реализации.
    "cycle-impl-impl": {"units": 2, "edges": [(0, 1, "m"), (1, 0, "m")]},
    # Цикл из трёх, замкнутый через реализацию.
    "triangle-impl": {"units": 3, "edges": [(0, 1, "m"), (1, 2, "m"), (2, 0, "m")]},
    # Цикл из трёх, где замыкание идёт через интерфейсы. Цепочка вызовов
    # всегда следует рёбрам: иначе юнит не увидел бы того, кого зовёт.
    "triangle-mixed": {"units": 3, "edges": [(0, 1, "m"), (1, 2, "i"), (2, 0, "i")]},
    # Цепочка с обратной дугой: длинный путь вперёд, короткий назад.
    "chain-back-edge": {"units": 4,
                        "edges": [(0, 1, "i"), (1, 2, "i"), (2, 3, "m"), (3, 0, "m")]},
    # Кольцо из четырёх через реализацию.
    "ring-four": {"units": 4,
                  "edges": [(0, 1, "m"), (1, 2, "m"), (2, 3, "m"), (3, 0, "m")]},
    # Без цикла вовсе: контрольная точка, на которой всё обязано работать.
    "acyclic": {"units": 2, "edges": [(0, 1, "m")]},
}

KNOWN_GENERIC_CYCLE_TOPOLOGIES = {
    "cycle-iface-impl", "cycle-impl-impl", "triangle-impl",
    "triangle-mixed", "ring-four",
}


def accepted_build_failure(row: dict) -> bool:
    """Exact dvl-0066 boundary, without hiding other build failures."""
    if row.get("symbol") != "generic-holder" or \
            row.get("topology") not in KNOWN_GENERIC_CYCLE_TOPOLOGIES:
        return False
    errors = [line for line in row.get("errors", []) if "Error:" in line]
    if not errors or not all("registered with current module" in line
                             for line in errors):
        return False
    if row.get("carrier") == "explicit-inline":
        return True
    return row.get("profile") == "release" or \
        row.get("extra") == ["-OoAUTOINLINE"]


def emit_unit(prefix: str, index: int, total: int, topo: dict, symbol: dict,
              carrier: dict, donor: int) -> str:
    name = f"{prefix}_U{index}"
    uses_iface = [f"{prefix}_U{b}" for (a, b, where) in topo["edges"]
                  if a == index and where == "i"]
    uses_impl = [f"{prefix}_U{b}" for (a, b, where) in topo["edges"]
                 if a == index and where == "m"]

    lines = [HEAD % {"name": name}]
    if uses_iface:
        lines.append("uses\n  " + ", ".join(uses_iface) + ";\n")
    if index == donor:
        lines.append(symbol.get("interface_decl", ""))
        lines.append(f"function Touch(Delta: Int64): Int64;{carrier['directive']}\n")
        if carrier["wrap"]:
            lines.append("function TouchWrapped(Delta: Int64): Int64;\n")
    else:
        lines.append(f"function Step{index}(Delta: Int64): Int64;\n")

    lines.append("\nimplementation\n")
    if uses_impl:
        lines.append("\nuses\n  " + ", ".join(uses_impl) + ";\n")

    if index == donor:
        lines.append("\n" + symbol["decl"])
        lines.append(f"\nfunction Touch(Delta: Int64): Int64;{carrier['directive']}\n"
                     "begin\n" + symbol["body"] + "\nend;\n")
        if carrier["wrap"]:
            lines.append("\nfunction TouchWrapped(Delta: Int64): Int64;\n"
                         "begin\n  Result := Touch(Delta);\nend;\n")
    else:
        nxt = index + 1
        call = "TouchWrapped" if (nxt == donor and carrier["wrap"]) else \
               ("Touch" if nxt == donor else f"Step{nxt}")
        lines.append(f"\nfunction Step{index}(Delta: Int64): Int64;\n"
                     f"begin\n  Result := {call}(Delta);\nend;\n")

    lines.append("\nend.\n")
    return "".join(lines)


def expected_answer(kind: str) -> int:
    # Программа зовёт цепочку трижды с 5, 7 и 9.
    if kind == "accumulate":
        return 5 + 12 + 21          # 5, 5+7, 5+7+9
    if kind == "base100":
        return 105 + 107 + 109
    if kind == "plus-one":
        return 6 + 8 + 10
    raise ValueError(kind)


def emit_program(prefix: str, topo: dict, symbol: dict, carrier: dict,
                 donor: int) -> str:
    entry = "Step0" if donor != 0 else ("TouchWrapped" if carrier["wrap"] else "Touch")
    want = expected_answer(symbol["kind"])
    return f"""program {prefix}_Main;

{{$mode delphi}}
{{$Q-}}{{$R-}}
{{$APPTYPE CONSOLE}}

uses
{{$ifdef FPC}}
  mormot.core.fpcx64mm,
{{$endif}}
  SysUtils, {prefix}_U0;

var
  A, B, C, Total: Int64;
begin
  {{ по одному вызову на оператор: порядок вычисления операндов внутри одного
    выражения язык не задаёт, и накопитель в теле сделал бы ответ зависящим от
    выбора компилятора }}
  A := {entry}(5);
  B := {entry}(7);
  C := {entry}(9);
  Total := A + B + C;
  if Total = {want} then
    WriteLn('TOPO_OK')
  else
    WriteLn('TOPO_BAD got=', Total, ' want={want}');
end.
"""


def build_case(work: Path, prefix: str, topo_name: str, symbol_name: str,
               carrier_name: str) -> Path:
    topo = TOPOLOGIES[topo_name]
    symbol = SYMBOLS[symbol_name]
    carrier = CARRIERS[carrier_name]
    donor = topo["units"] - 1

    case_dir = work / prefix
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True)

    for index in range(topo["units"]):
        text = emit_unit(prefix, index, topo["units"], topo, symbol, carrier, donor)
        (case_dir / f"{prefix}_U{index}.pas").write_text(text, encoding="utf-8")
    (case_dir / f"{prefix}_Main.dpr").write_text(
        emit_program(prefix, topo, symbol, carrier, donor), encoding="utf-8")
    return case_dir


def run_case(case_dir: Path, prefix: str, profile: str, extra: list[str],
             timeout: int) -> dict:
    out = case_dir / ("out-" + profile + ("-" + "".join(extra) if extra else ""))
    out.mkdir(parents=True, exist_ok=True)
    build = subprocess.run(
        tc.compile_command(case_dir / f"{prefix}_Main.dpr", out, profile,
                           search=[case_dir], extra=extra),
        cwd=case_dir, capture_output=True, text=True, errors="replace",
        timeout=timeout)
    if build.returncode != 0:
        text = (build.stdout or "") + (build.stderr or "")
        errors = [l for l in text.splitlines() if "Error" in l or "Fatal" in l]
        return {"built": False, "errors": errors[:4]}

    run = subprocess.run([str(tc.executable(out, f"{prefix}_Main"))], cwd=case_dir,
                         capture_output=True, text=True, errors="replace",
                         timeout=timeout)
    return {"built": True, "exit": run.returncode,
            "output": (run.stdout or "").strip()[:200]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profiles", default="debug,release")
    parser.add_argument("--switches", default="AUTOINLINE,CSE,DFA,STRENGTH,CONSTPROP",
                        help="ключи, каждый включается поверх -O1 отдельно")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "topology")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--topology")
    parser.add_argument("--symbol")
    args = parser.parse_args()

    tc.preflight()
    args.work.mkdir(parents=True, exist_ok=True)

    profiles = [p.strip() for p in args.profiles.split(",") if p.strip()]
    switches = [s.strip().upper() for s in args.switches.split(",") if s.strip()]

    topologies = [args.topology] if args.topology else list(TOPOLOGIES)
    symbols = [args.symbol] if args.symbol else list(SYMBOLS)

    rows: list[dict] = []
    findings: list[dict] = []
    known_findings: list[dict] = []
    started = time.time()
    counter = 0

    for topo_name in topologies:
        for symbol_name in symbols:
            for carrier_name in CARRIERS:
                counter += 1
                prefix = f"T{counter:03d}"
                case_dir = build_case(args.work, prefix, topo_name, symbol_name,
                                      carrier_name)
                label = f"{topo_name} / {symbol_name} / {carrier_name}"

                plan = [(p, []) for p in profiles]
                plan += [("o1", ["-Oo" + s]) for s in switches]

                for profile, extra in plan:
                    result = run_case(case_dir, prefix, profile, extra, args.timeout)
                    row = {"case": prefix, "topology": topo_name,
                           "symbol": symbol_name, "carrier": carrier_name,
                           "profile": profile, "extra": extra, **result}
                    rows.append(row)

                    if not result["built"]:
                        finding = {"kind": "build-failed", "label": label,
                                   "profile": profile, "extra": extra,
                                   "case": prefix, "topology": topo_name,
                                   "symbol": symbol_name,
                                   "carrier": carrier_name,
                                   "errors": result["errors"]}
                        if accepted_build_failure(finding):
                            finding["known"] = "dvl-0066"
                            known_findings.append(finding)
                            prefix_text = "KNOWN dvl-0066"
                        else:
                            findings.append(finding)
                            prefix_text = "BUILD FAILED"
                        print(f"{prefix_text}  {label}  {profile} {' '.join(extra)}")
                        for line in result["errors"][:2]:
                            print("    ", line[:150])
                    elif result["output"] != "TOPO_OK":
                        findings.append({"kind": "wrong-answer", "label": label,
                                         "profile": profile, "extra": extra,
                                         "case": prefix,
                                         "output": result["output"]})
                        print(f"WRONG ANSWER  {label}  {profile} {' '.join(extra)}  "
                              f"{result['output']}")

    report = {"rows": rows, "findings": findings,
              "known_findings": known_findings,
              "seconds": round(time.time() - started, 1)}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")

    print()
    print(f"cases={counter} builds={len(rows)} in {report['seconds']}s")
    if findings:
        print(f"TOPOLOGY FINDINGS findings={len(findings)}")
        return 1
    print(f"TOPOLOGY OK cases={counter} builds={len(rows)} "
          f"known={len(known_findings)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
