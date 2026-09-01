# Delphi visibility oracle

The oracle pins the Delphi 12.2 Win64 `TRttiContext.GetTypes` visibility
boundary used by the compiler gate: a linked top-level interface type is
listed, while linked nested and implementation-only types are not.

Run from a Delphi 12.2 command prompt:

```cmd
dcc64 -B rtti_visibility_oracle.dpr
rtti_visibility_oracle.exe > actual.txt
fc /b expected.txt actual.txt
```
