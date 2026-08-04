{ %OPT=-O3 -CpZEN -OpZEN }
program bsf_test_report;

var RedFlag : boolean;

function bsf_test_byte :sizeuint;
var k,nr : sizeuint;
    msk: byte;
begin
  k:=1024;
  msk:=1;
  for nr:=0 to sizeof(msk)*8 do
  begin
     k:=bsfByte(msk);
     //writeln('nr ',nr:2,'  msk ',hexstr(msk,sizeof(msk)*2),'   BsfByte ',k:3);
     if ((msk = 0) and (k<>$ff)) or ((msk<>0) and (k<>nr)) then
     begin
       writeln( 'BsfByte failed with input: $',hexstr(msk,sizeof(msk)*2),'   output : ',k);
       RedFlag:=true;
     end;
     msk:=msk shl 1;
  end;
  bsf_test_byte:=k;
end;

function bsf_test_word :sizeuint;
var k,nr : sizeuint;
    msk: word;
begin
  k:=1024;
  msk:=1;
  for nr:=0 to sizeof(msk)*8 do
  begin
     k:=bsfWord(msk);
     //writeln('nr ',nr:2,'  msk ',hexstr(msk,sizeof(msk)*2),'   BsfWord ',k:3);
     if ((msk = 0) and (k<>$ff)) or ((msk<>0) and (k<>nr)) then
     begin
       writeln( 'BsfWord failed with input: $',hexstr(msk,sizeof(msk)*2),'   output : ',k);
       RedFlag:=true;
     end;
     msk:=msk shl 1;
  end;
  bsf_test_word:=k;
end;

function bsf_test_qword_v1 : longword;
var k,nr : longword;   {  }
    msk: qword;
begin
  k:=1024;
  msk:=1;
  for nr:=0 to sizeof(msk)*8 do
  begin
     k:=bsfQword(msk);
     //writeln('nr ',nr:2,'  msk ',hexstr(msk,sizeof(msk)*2),'   BsfQword ',k:3);
     if ((msk = 0) and (k<>$ff)) or ((msk<>0) and (k<>nr)) then
     begin
       writeln( 'BsfQword v1 failed with input: $',hexstr(msk,sizeof(msk)*2),'   output : ',k);
       RedFlag:=true;
     end;
     msk:=msk shl 1;
  end;
  bsf_test_qword_v1:=k;
end;

function bsf_test_qword_v2 :sizeuint;
var k,nr : sizeuint;   { type SizeUint important for fail test }
    msk: qword;
begin
  k:=1024;
  msk:=1;
  for nr:=0 to sizeof(msk)*8 do
  begin
     k:=bsfQword(msk);
     //writeln('nr ',nr:2,'  msk ',hexstr(msk,sizeof(msk)*2),'   BsfQword ',k:3);
     if ((msk = 0) and (k<>$ff)) or ((msk<>0) and (k<>nr)) then
     begin
       writeln( 'BsfQword v2 failed with input: $',hexstr(msk,sizeof(msk)*2),'   output : ',k);
       RedFlag:=true;
     end;
     msk:=msk shl 1;
  end;
  bsf_test_qword_v2:=k;
end;

function bsf_test_dword :longword;
var k,nr : longword;
    msk: longword;
begin
  k:=1024;
  msk:=1;
  for nr:=0 to sizeof(msk)*8 do
  begin
     k:=bsfDword(msk);
     //writeln('nr ',nr:2,'  msk ',hexstr(msk,sizeof(msk)*2),'   BsfDword ',k:3);
     if ((msk = 0) and (k<>$ff)) or ((msk<>0) and (k<>nr)) then
     begin
       writeln( 'BsfDword failed with input: $',hexstr(msk,sizeof(msk)*2),'   output : ',k);
       RedFlag:=true;
     end;
     msk:=msk shl 1;
  end;
  bsf_test_dword:=k;
end;

begin
  RedFlag:=false;
  bsf_test_byte;
  bsf_test_word;
  bsf_test_dword;
  bsf_test_qword_v1;
  bsf_test_qword_v2;
  if RedFlag then
    halt(1);
  Writeln('Ok');
end.
