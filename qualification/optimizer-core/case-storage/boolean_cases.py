"""Boolean case producer/consumer matrix with independent truth and exact-once oracles."""


def generate(directory, delphi=False):
    code = ['program bool_matrix;', '{$APPTYPE CONSOLE}', '{$IFDEF FPC}{$mode delphi}{$ENDIF}',
            'uses SysUtils;', 'var Reads,Visits,Checks:Integer;',
            'procedure Require(Ok:Boolean; const Id:string);',
            "begin Inc(Checks); if not Ok then begin Writeln('FAIL ',Id); Halt(1); end; end;"]
    main = ['begin']
    count = 0
    functions = 0
    for typ, width in [('Boolean', 1), ('ByteBool', 1), ('WordBool', 2), ('LongBool', 4)]:
        code += ['{$INLINE OFF}', f'function Read{typ}(B:{typ}):{typ};',
                 'begin Inc(Reads); Result:=B; end;', '{$INLINE ON}']
        other = 'LongBool' if typ == 'Boolean' else 'Boolean'
        forms = [
            ('plain', 'False:Result:=7; True:Result:=9;', 7, 9, True),
            ('typed', f'{typ}(False):Result:=7; {typ}(True):Result:=9;', 7, 9, True),
            ('reverse', f'{typ}(True):Result:=9; {typ}(False):Result:=7;', 7, 9, True),
            ('mixed', f'{typ}(True):Result:=9; False:Result:=7;', 7, 9, True),
            ('cross', f'{other}(False):Result:=7; {other}(True):Result:=9;', 7, 9, True),
            ('trueonly', f'{typ}(True):Result:=9;', -1, 9, True),
            ('falseonly', f'{typ}(False):Result:=7;', 7, -1, True),
            ('truenoelse', f'{typ}(True):Result:=9;', -77, 9, False),
            ('falsenoelse', f'{typ}(False):Result:=7;', 7, -77, False),
            ('grouped', f'{typ}(False),{typ}(True):Result:=11;', 11, 11, True),
            ('truerange', f'{typ}(True)..{typ}(True):Result:=9;', -1, 9, True),
            ('falserange', f'{typ}(False)..{typ}(False):Result:=7;', 7, -1, True),
        ]
        bounds = ('False', 'True') if typ == 'Boolean' else ('True', 'False')
        forms += [('fullrange', f'{typ}({bounds[0]})..{typ}({bounds[1]}):Result:=11;', 11, 11, True)]
        if typ != 'Boolean':
            forms += [('twolabel', f'{typ}(2):Result:=9;', -1, 9, True),
                      ('nonzerorange', f'{typ}(2)..{typ}(3):Result:=9;', -1, 9, True)]
            if not delphi:
                forms += [('plainrange', 'False..True:Result:=11;', 11, 11, True),
                          ('signedrange', f'{typ}(-1)..{typ}(1):Result:=11;', 11, 11, True)]
        forms += [('crossnonzero', 'LongBool(256):Result:=9;', -1, 9, True)]
        inputs = [0, 1] if typ == 'Boolean' else list(range(256)) + [256, 32768, 65535, 65536, 2147483647, 2147483648, 4294967295]
        if delphi and typ != 'Boolean':
            # Delphi's dynamic raw cbool dispatch compares canonical storage;
            # it disagrees with its own nonzero constant folding. Use only
            # canonical dynamic values as a cross-compiler control.
            inputs = [0, (1 << (8*width))-1]
        for form, labels, false_result, true_result, has_else in forms:
            name = typ+'_'+form
            code += [f'function F{name}(B:{typ}):Integer; inline;',
                     f'begin Result:=-77; case Read{typ}(B) of', labels,
                     'else Result:=-1;' if has_else else '', 'end; end;',
                     f'procedure Check{name};', f'var Raw:UInt64; B:{typ};', 'begin']
            for raw in inputs:
                truth = bool(raw & ((1 << (8*width))-1))
                expected = true_result if truth else false_result
                code += [f'Raw:=${raw:X}; Move(Raw,B,SizeOf(B)); Reads:=0;',
                         f"Require((F{name}(B)={expected}) and (Reads=1),'{name}:{raw}');"]
                count += 1
            code += ['end;']
            main += [f'Check{name};']
            functions += 1
        # Constant selector folding must also route typed True correctly.
        code += [f'function Constant{typ}(B:{typ}):Integer; inline;',
                 f'begin case B of {typ}(False):Result:=7; {typ}(True):Result:=9; else Result:=-1; end; end;']
        main += [f"Require(Constant{typ}(False)=7,'constant-{typ}-false');",
                 f"Require(Constant{typ}(True)=9,'constant-{typ}-true');"]
        count += 2
        if typ != 'Boolean':
            main += [f"Require(Constant{typ}({typ}(2))=9,'constant-{typ}-two');"]
            count += 1
    code += ['type TBox=class', '  Value:LongBool; Fail:Boolean;',
             '  function GetValue:LongBool;', '  property Current:LongBool read GetValue;', 'end;',
             '{$INLINE OFF}', 'function TBox.GetValue:LongBool;',
             "begin Inc(Reads); if Fail then raise ERangeError.Create('selector'); Result:=Value; end;",
             'procedure PropertyRange(Box:TBox);',
             # Use the typed full range that both compilers accept.
             'begin case Box.Current of LongBool(True)..LongBool(False): Inc(Visits); end; end;',
             'procedure CheckProperty;', 'var Box:TBox; Caught:Boolean;', 'begin Box:=TBox.Create;',
             'try Box.Value:=False; Reads:=0; Visits:=0; PropertyRange(Box);',
             "Require((Reads=1) and (Visits=1),'property-exact-once');",
             'Box.Fail:=True; Reads:=0; Visits:=0; Caught:=False;',
             'try PropertyRange(Box); except on E:ERangeError do Caught:=True; end;',
             "Require(Caught and (Reads=1) and (Visits=0),'property-exception-order');",
             'finally Box.Free; end; end;', '{$B-}',
             'function NoValue:Boolean; begin Inc(Reads); Result:=False; end;',
             'function YesValue:Boolean; begin Inc(Reads); Result:=True; end;',
             "function BadValue:Boolean; begin Inc(Reads); raise ERangeError.Create('short circuit'); end;",
             'procedure AndSkip; begin case NoValue and BadValue of False..True:Inc(Visits); end; end;',
             'procedure OrSkip; begin case YesValue or BadValue of False..True:Inc(Visits); end; end;',
             'procedure AndBoth; begin case YesValue and NoValue of False..True:Inc(Visits); end; end;',
             'var Values:array[0..0] of Boolean;',
             'function OutsideIndex:Integer; begin Inc(Reads); Result:=1; end;',
             'procedure CheckedAccess; begin case Values[OutsideIndex] of False..True:Inc(Visits); end; end;',
             'procedure CheckEffects;', 'var Caught:Boolean;', 'begin',
             'Reads:=0; Visits:=0; AndSkip;',
             "Require((Reads=1) and (Visits=1),'short-circuit-and');",
             'Reads:=0; Visits:=0; OrSkip;',
             "Require((Reads=1) and (Visits=1),'short-circuit-or');",
             'Reads:=0; Visits:=0; AndBoth;',
             "Require((Reads=2) and (Visits=1),'short-circuit-both');",
             '{$IFOPT R+}',
             'Reads:=0; Visits:=0; Caught:=False;',
             'try CheckedAccess; except on E:ERangeError do Caught:=True; end;',
             "if not (Caught and (Reads=1) and (Visits=0)) then begin Writeln('FAIL checked-bounds'); Halt(2); end;",
             '{$ENDIF}', 'end;']
    count += 5
    main += ['CheckProperty;', 'CheckEffects;', f"Writeln('BOOL_FORMS_PASS checks=',Checks); end."]
    source = directory/'bool_matrix.dpr'
    source.write_text('\n'.join(code+main)+'\n', encoding='utf-8')
    return source, count, functions


def negative_sources(directory):
    forms = {
        'duplicate_truth': 'case B of LongBool(True):; LongBool(2):; end;',
        'overlap_truth': 'case B of LongBool(True)..LongBool(False):; LongBool(2):; end;',
        'typed_reverse_order': 'case B of LongBool(False)..LongBool(True):; end;',
    }
    result = []
    for name, case in forms.items():
        source = directory/(name+'.dpr')
        source.write_text('program negative; {$IFDEF FPC}{$mode delphi}{$ENDIF}\nvar B:LongBool;\nbegin B:=False; '+case+' end.\n')
        result.append(source)
    return result
