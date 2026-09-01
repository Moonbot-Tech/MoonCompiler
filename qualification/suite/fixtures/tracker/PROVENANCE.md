# Provenance of the issue-tracker corpus

The corpus is not built from issue numbers for their own sake. For each entry
below, the original report was read in full, its trigger reduced to a standalone
program, and the expectation transferred into `manifest.json` as
`runtime-self-check`, `compile-success`, or `compile-rejection`. The exact-source
generator is `scripts/generate_issue_tracker_corpus.py`; it also prevents the
manifest and fixture from diverging. A MoonCompiler result is never used as an
oracle by itself.

`QP-21`, `QP-33`, `QP-39`, `QP-43`, `SO-12`, and `MB-01` were removed after
rechecking: `QP-21`, `QP-33`, and `SO-12` did not preserve the original
contract; `QP-43` created a legal reference cycle; `QP-39` remained red in
Delphi 12.2; and `MB-01` required sparse-enum RTTI absent even in Delphi. These
IDs are intentionally not reused.

## Embarcadero Quality Portal

| Fixture | Original report |
|---|---|
| QP-01 | [RSS-5590](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5590) |
| QP-02 | [RSP-42753](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-42753) |
| QP-03 | [RSS-5756](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5756) |
| QP-04 | [RSS-5806](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5806) |
| QP-05 | [RSP-15815](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-15815) |
| QP-06 | [RSP-16777](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-16777) |
| QP-07 | [RSP-17757](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-17757) |
| QP-08 | [RSP-43579](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-43579) |
| QP-09 | [RSP-43656](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-43656) |
| QP-10 | [RSP-39386](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-39386) |
| QP-11 | [RSP-35397](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-35397) |
| QP-12 | [RSP-30204](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-30204) |
| QP-13 | [RSP-40061](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-40061) |
| QP-14 | [RSP-13047](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-13047) |
| QP-15 | [RSP-16084](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-16084), [SO context](https://stackoverflow.com/questions/39995637/initialisation-of-delphi-record-containing-a-dynamic-array-with-implicit-class) |
| QP-16 | [RSP-9806](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-9806) |
| QP-17 | [RSP-18730](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-18730) |
| QP-18 | [RSP-13645](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-13645) |
| QP-19 | [RSP-26257](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-26257) |
| QP-20 | [RSS-5722](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5722) |
| QP-22 | [RSP-21386](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-21386) |
| QP-23 | [RSP-42664](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-42664) |
| QP-24 | [RSS-5629](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5629) |
| QP-25 | [RSS-5564](https://embt.atlassian.net/servicedesk/customer/portal/1/RSS-5564) |
| QP-26 | [RSP-16837](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-16837) |
| QP-27 | [RSP-27592](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-27592) |
| QP-28 | [RSP-41723](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-41723) |
| QP-29 | [RSP-36028](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-36028) |
| QP-30 | [RSP-17991](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-17991) |
| QP-31 | [RSP-20400](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-20400), [RSP-18861](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-18861) |
| QP-32 | [RSP-23428](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-23428) |
| QP-34 | [RSP-13681](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-13681) |
| QP-35 | [RSP-14390](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-14390) |
| QP-36 | [RSP-12597](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-12597) |
| QP-37 | [RSP-43586](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-43586) |
| QP-38 | [RSP-13489](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-13489) |
| QP-40 | [RSP-28268](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-28268) |
| QP-41 | [RSP-44063](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-44063) |
| QP-42 | [RSP-17007](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-17007) |
| QP-44 | [RSP-38338](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-38338) |
| QP-45 | [RSP-18148](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-18148) |
| QP-46 | [RSP-23747](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-23747) |
| QP-47 | [RSP-23898](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-23898) |
| QP-48 | [RSP-23417](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-23417) |
| QP-49 | [RSP-36738](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-36738), [RSP-32203](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-32203) |
| QP-50 | [RSP-11526](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-11526) |
| QP-51 | [RSP-37795](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-37795) |
| QP-52 | [RSP-17993](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-17993) |
| QP-53 | [RSP-20388](https://embt.atlassian.net/servicedesk/customer/portal/37/RSP-20388), [SO context](https://stackoverflow.com/questions/49894592/nested-generic-record) |

## Stack Overflow

| Fixture | Original question |
|---|---|
| SO-01 | [Win64 inherited open-array parameters](https://stackoverflow.com/questions/55692131/delphi-10-3-1-compiler-generates-code-that-issues-an-exception-when-compiled-to) |
| SO-02 | [Inline early Exit](https://stackoverflow.com/questions/30692000/is-it-a-bug-that-attempts-to-compile-this-code-results-in-ide-terminating-or-the) |
| SO-03 | [Generic forward declaration](https://stackoverflow.com/questions/11463888/compiler-bug-when-using-generics-and-forward-declaration-in-delphi-xe2) |
| SO-04 | [TList of dynamic arrays](https://stackoverflow.com/questions/41047688/how-to-work-around-delphi-10s-bug-with-tlist-anydynamicarrays) |
| SO-05 | [Inline var and anonymous procedure](https://stackoverflow.com/questions/62372257/inline-var-bug-with-anonymous-procedure) |
| SO-06 | [Managed record in TDictionary](https://stackoverflow.com/questions/76091308/how-to-use-record-with-class-operator-initialize-as-key-or-value-of-tdictionar) |
| SO-07 | [Generics and implements](https://stackoverflow.com/questions/49416211/f2084-compiler-error-with-generics-and-implements-in-delphi) |
| SO-08 | [Nested inline and record helper](https://stackoverflow.com/questions/51790648/delphi-inline-usage-causes-f2084-internal-error) |
| SO-09 | [Anonymous method in initialization](https://stackoverflow.com/questions/9005008/strange-bug-with-anonymous-methods-in-initialization-section) |
| SO-10 | [TList record corruption](https://stackoverflow.com/questions/29906723/delphi-xe8-bug-in-tlistt-need-workaround) |
| SO-11 | [TArray generic result inference](https://stackoverflow.com/questions/56005923/dcc32-fatal-error-f2084-internal-error-nc1921) |
| SO-13 | [Generic var array proc type](https://stackoverflow.com/questions/9429484/what-should-i-do-about-an-internal-error-when-i-declare-a-generic-array-of-t) |
| SO-14 | [Nested generic arrays and SetLength](https://stackoverflow.com/questions/12320635/is-it-safe-to-type-cast-tarrayx-to-array-of-x) |
| SO-15 | [Inline managed record initialization](https://stackoverflow.com/questions/54987996/delphi-10-3-rio-is-initializaiton-of-inline-declared-record-variables-needed) |
| SO-16 | [Generic inline const ShortString](https://stackoverflow.com/questions/31102217/is-it-a-user-error-to-declare-a-generic-inline-function-const-for-shortstring) |
| SO-17 | [Nil reference to procedure](https://stackoverflow.com/questions/29073867/how-to-check-if-a-reference-to-procedure-is-nil) |
| SO-18 | [Interface inheritance with generics](https://stackoverflow.com/questions/19682057/delphi-interface-inheritance-with-generics) |
| SO-19 | [Anonymous function passed to inline function](https://stackoverflow.com/questions/44336596/delphi-anonymous-function-passed-to-inlined-function) |

## In-house discovery forms

`MB-02` checks `finally` in a loop, `MB-03` range checking around mixed-width
arithmetic, `MB-04` a reversed runtime set range, and `MB-05` mixed-UInt64
equality. `MB-06` records the deliberately unaccepted Delphi contract
`Random(High(UInt64))`: Delphi 12.2 accepts the call with a warning that the
constant is out of range; MoonCompiler does not yet select an overload. These
are forms discovered by our lab, not external reports; their oracle is in the
corresponding fixture and, for `MB-06`, confirmed by DCC64 36.0.
