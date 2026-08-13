unit MemProf;

{ Гистограмма размеров аллокаций работающего бота. Подключать в
  MoonBot.dpr ПОСЛЕ юнитов менеджера памяти (FastMM/EurekaLog) под
  дефайном MEMPROF: шим оборачивает УЖЕ установленный менеджер.
  Оверхед — один AtomicIncrement на вызов, торговле не мешает.
  При выходе бота пишет MemProf_<pid>.txt рядом с exe: сколько
  GetMem/Realloc пришлось на каждый диапазон размеров. Границы
  бакетов = границы small/medium/large у FastMM и mormot fpcx64mm,
  чтобы профиль напрямую отвечал на вопрос «что у нас в hot path». }

interface

implementation

uses
  Winapi.Windows, System.SysUtils;

const
  BucketCount = 10;
  BucketLim: array[0..BucketCount - 1] of NativeInt =
    (64, 128, 256, 512, 1200, 2600, 9000, 65536, 262144, High(NativeInt));

var
  OldMM: TMemoryManagerEx;
  CntGet: array[0..BucketCount - 1] of Int64;
  CntRe: array[0..BucketCount - 1] of Int64;
  CntFree: Int64;

function BucketOf(Size: NativeInt): Integer; inline;
var
  k: Integer;
begin
  for k := 0 to BucketCount - 2 do
    If Size <= BucketLim[k] then
      Exit(k);
  Result := BucketCount - 1;
end;

function PGetMem(Size: NativeInt): Pointer;
begin
  AtomicIncrement(CntGet[BucketOf(Size)]);
  Result := OldMM.GetMem(Size);
end;

function PFreeMem(P: Pointer): Integer;
begin
  AtomicIncrement(CntFree);
  Result := OldMM.FreeMem(P);
end;

function PReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  AtomicIncrement(CntRe[BucketOf(Size)]);
  Result := OldMM.ReallocMem(P, Size);
end;

function PAllocMem(Size: NativeInt): Pointer;
begin
  AtomicIncrement(CntGet[BucketOf(Size)]);
  Result := OldMM.AllocMem(Size);
end;

procedure Dump;
var
  f: TextFile;
  k: Integer;
  TotG, TotR: Int64;
  Lim: string;

  function PctOf(V, Tot: Int64): Double;
  begin
    If Tot = 0 then
      Result := 0
    else
      Result := V * 100.0 / Tot;
  end;

begin
  TotG := 0;
  TotR := 0;
  for k := 0 to BucketCount - 1 do
  begin
    Inc(TotG, CntGet[k]);
    Inc(TotR, CntRe[k]);
  end;
  AssignFile(f, ExtractFilePath(ParamStr(0)) +
    Format('MemProf_%d.txt', [GetCurrentProcessId]));
  Rewrite(f);
  try
    WriteLn(f, Format('GetMem+AllocMem: %d   ReallocMem: %d   FreeMem: %d',
      [TotG, TotR, CntFree]));
    WriteLn(f, 'size <=       get              %       realloc          %');
    for k := 0 to BucketCount - 1 do
    begin
      If k = BucketCount - 1 then
        Lim := '   >262144'
      else
        Lim := Format('%10d', [BucketLim[k]]);
      WriteLn(f, Format('%s  %12d  %8.2f%%  %12d  %8.2f%%',
        [Lim, CntGet[k], PctOf(CntGet[k], TotG),
         CntRe[k], PctOf(CntRe[k], TotR)]));
    end;
  finally
    CloseFile(f);
  end;
end;

var
  NewMM: TMemoryManagerEx;

initialization
  GetMemoryManager(OldMM);
  NewMM := OldMM;
  NewMM.GetMem := PGetMem;
  NewMM.FreeMem := PFreeMem;
  NewMM.ReallocMem := PReallocMem;
  NewMM.AllocMem := PAllocMem;
  SetMemoryManager(NewMM);

finalization
  SetMemoryManager(OldMM);
  Dump;

end.
