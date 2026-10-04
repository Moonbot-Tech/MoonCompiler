#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE = Path(__file__).with_name("check_surface.py")
SPEC = importlib.util.spec_from_file_location("check_surface", MODULE)
assert SPEC is not None and SPEC.loader is not None
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class SurfaceParserTests(unittest.TestCase):
    def test_comments_strings_and_parameter_semicolons(self) -> None:
        source = """
unit Sample;
interface
{ procedure Hidden; }
procedure Split(A: Integer;
  const B: string);
function Quoted: string;
implementation
procedure Split(A: Integer; const B: string);
begin
  WriteLn('procedure Fake;');
end;
function Quoted: string;
begin
  Result := 'x';
end;
end.
"""
        public = CHECK.declarations(source, "interface")
        implementation = CHECK.declarations(source, "implementation")
        self.assertEqual([item["name"] for item in public], ["Split", "Quoted"])
        self.assertEqual(
            public[0]["signature"], "procedure Split(A: Integer; const B: string)"
        )
        self.assertEqual(
            [item["name"] for item in implementation], ["Split", "Quoted"]
        )

    def test_usage_ignores_comments_and_strings(self) -> None:
        masked = CHECK.mask_comments_and_strings(
            "Foo(1); // Foo(2)\nWriteLn('Foo(3)');"
        )
        self.assertEqual(CHECK.name_use_count("Foo", masked), 1)

    def test_nested_includes_are_part_of_the_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "public.inc").write_text(
                "procedure Included(A: Integer);\n", encoding="utf-8"
            )
            (root / "body.inc").write_text(
                "procedure Included(A: Integer); begin end;\n", encoding="utf-8"
            )
            (root / "sample.pp").write_text(
                "unit Sample;\ninterface\n{$i public.inc}\nimplementation\n"
                "{$include body.inc}\nend.\n",
                encoding="utf-8",
            )
            facts = CHECK.unit_facts(root / "sample.pp")
            self.assertEqual(facts["public_count"], 1)
            self.assertEqual(facts["implementation_count"], 1)


if __name__ == "__main__":
    unittest.main()
