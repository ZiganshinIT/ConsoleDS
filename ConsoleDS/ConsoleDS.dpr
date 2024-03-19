program ConsoleDS;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,

  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.Threading,
  System.Generics.Collections, System.SyncObjs,

  Duds.Common.Classes in '..\DUDS\Duds.Common.Classes.pas',
  Duds.Common.Delphi in '..\DUDS\Duds.Common.Delphi.pas',
  Duds.Common.Files in '..\DUDS\Duds.Common.Files.pas',
  Duds.Common.Interfaces in '..\DUDS\Duds.Common.Interfaces.pas',
  Duds.Common.Parser.Pascal in '..\DUDS\Duds.Common.Parser.Pascal.pas',
  Duds.Common.Parser.Pascal.Tokeniser in '..\DUDS\Duds.Common.Parser.Pascal.Tokeniser.pas',
  Duds.Common.Strings in '..\DUDS\Duds.Common.Strings.pas',
  Duds.Common.Types in '..\DUDS\Duds.Common.Types.pas',
  Duds.Common.Utils in '..\DUDS\Duds.Common.Utils.pas',

  Dproj in '..\Utils\Dproj.pas',
  DSTypes in '..\Utils\DSTypes.pas',
  DSUtils in '..\Utils\DSUtils.pas';

type
  TStep =
  (
    stParsing,
    stCoping
  );

  TInputThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TScanThread = class(TThread)
  private

    FPasFiles:   TDictionary<string, string>;
    FDcuFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;
    FFiles:      TDictionary<string, integer>;
    // <имя юнита | проект, в котором объявляется>
    FUnitLocation: TDictionary<string, string>;

    FUsedFiles:   TStringList;
    FIgnoreFiles: TStringList;

    FPascalUnitExtractor: TPascalUnitExtractor;
  protected
    procedure Execute;                                                          override;

    procedure FindFilesInFolder(const Folder: string);

    procedure AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);
    function AddFileWithExt(const filename, ext: string): string;

    function TryAddFile(const FilePath: string): Boolean;

    procedure DoScan(const FilePath: string);

    procedure DoScanUnit(const UnitPath: string);
    procedure DoScanRCFiles(const RCFilePath: string);
  public
    constructor Create; overload;
    destructor Destroy; overload;
  end;

var
  SearchPath: string;
  SeedFile: string;
  TargetPath: string;

  List: TStringList;
  CS: TCriticalSection;

  // Threads
  ScanThread: TScanThread;
  InputThread: TInputThread;

const
  Step: TStep = stParsing;
  Finish: Boolean = False;
  Counter: Integer = 0;


{ TScanThread }

{Добавляет файл меня расширение}
function TScanThread.AddFileWithExt(const filename, ext: string): string;
begin
  result := ExtractFilePath(filename)+ExtractFileNameWithoutExt(filename)+ext;
  TryAddFile(result);
end;

{Добавляет дополнительные файлы, использующиеся в юните}
procedure TScanThread.AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);
begin
  for var ValuesArr in UnitInfo.OtherUsedItems.Values do begin
    for var Value in ValuesArr do begin
      var path := CalcPath(Value, UnitPath);
      if FileExists(path) then begin
        TryAddFile(path);
      end;
    end;
  end;
end;

constructor TScanThread.Create;
begin
  inherited Create(False);

  FPasFiles     :=   TDictionary<string, string>.Create;
  FDcuFiles     :=   TDictionary<string, string>.Create;
  FDprojFiles   :=   TDictionary<string, string>.Create;
  FFiles        :=   TDictionary<string, integer>.Create;
  FUsedFiles    :=   TStringList.Create;
  FIgnoreFiles  :=   TStringList.Create;
  FUnitLocation :=   TDictionary<string, string>.Create;
  FPascalUnitExtractor := TPascalUnitExtractor.Create(nil);
end;


destructor TScanThread.Destroy;
begin
  inherited;
  FreeAndNil(fPasFiles);
  FreeAndNil(fDcuFiles);
  FreeAndNil(fDprojFiles);
  FreeAndNil(FFiles);
  FreeAndNil(fUsedFiles);
  FreeAndNil(FIgnoreFiles);
  FreeAndNil(fUnitLocation);
  FreeAndNil(FPascalUnitExtractor);
end;

{Анализ сканируемого файла}
procedure TScanThread.DoScan(const FilePath: string);
var
  UnitInfo: IUnitInfo;
begin
  if self.Terminated then
    exit;
  var Extension := LowerCase(ExtractFileExt(FilePath));
  if SameText(Extension, '.pas') OR SameText(Extension, '.dpr') then begin
    self.DoScanUnit(FilePath);
  end else if SameText(Extension, '.rc') then begin
    self.DoScanRCFiles(FilePath);
  end;
end;

{Сканирует файлы ресурсов}
procedure TScanThread.DoScanRCFiles(const RCFilePath: string);
begin
  if FileExists(RCFilePath) then begin
    var files := ReadRCFile(RCFilePath);
    for var f in files do begin
      if self.Terminated then
        exit;
      var InnerFilePath := CalcPath(f, RCFilePath);
      TryAddFile(InnerFilePath)
    end;
  end else
    raise Exception.Create(RCFilePath + ' не существует')
end;

{Добавдение файлов Delphi}
procedure TScanThread.DoScanUnit(const UnitPath: string);
var
  UnitInfo: IUnitInfo;
  Parsed: Boolean;
  pas: string;
begin
  Parsed := FPascalUnitExtractor.GetUsedUnits(UnitPath, UnitInfo);
  if Parsed then begin
    if self.Terminated then
      exit;

    if UnitInfo.OtherUsedItems.Count > 0 then begin
      AddOtherFiles(UnitPath, UnitInfo);
    end;

    for var un in UnitInfo.UsedUnits do begin
      if self.Terminated then
        exit;
      var du := LowerCase(un.DelphiUnitName);
      if FUsedFiles.IndexOf(du) = -1 then begin
        if fPasFiles.TryGetValue(du + '.pas', pas) OR fDcuFiles.TryGetValue(du + '.dcu', pas) then
          TryAddFile(pas)
      end;
    end;
  end;
end;

procedure TScanThread.Execute;
begin
  inherited;
  TryAddFile(SeedFile);

  if SameText(ExtractFileExt(SeedFile), '.dpr') then begin
    AddFileWithExt(SeedFile, '.dproj');
    AddFileWithExt(SeedFile, '._icon.ico');
  end;

  FindFilesInFolder(SearchPath);

  var i := 0;
  while i<fUsedFiles.Count do begin
    if self.Terminated then
      exit;
    DoScan(fUsedFiles[i]);
    inc(i);
  end;
end;

procedure TScanThread.FindFilesInFolder(const Folder: string);
var
  FoundFiles: TStringDynArray;
  FileName: string;
  Extenshion: string;
begin
  FoundFiles := TDirectory.GetFiles(Folder, '*.*', TSearchOption.soAllDirectories);
  for FileName in FoundFiles do
  begin
    Extenshion := ExtractFileExt(FileName);
    if SameText(Extenshion, '.pas') then begin
      if not fPasFiles.ContainsKey(ExtractFileName(FileName)) then begin
        fPasFiles.AddOrSetValue(LowerCase(ExtractFileName(FileName)), FileName);
      end;

    end else if SameText(Extenshion, '.dcu') then begin
      if not fDcuFiles.ContainsKey(ExtractFileName(FileName)) then
        fDcuFiles.Add(ExtractFileName(FileName), FileName);

    end else if SameText(Extenshion, '.dproj') then begin
      if not fDprojFiles.ContainsKey(ExtractFileName(FileName)) then
        fDprojFiles.Add(ExtractFileName(FileName), FileName);
    end;
  end;
end;

{Добавление файлов, синхронизация с основным потоком}
function TScanThread.TryAddFile(const FilePath: string): Boolean;
begin
  result := False;
  if FileExists(FilePath) AND not FFiles.ContainsKey(ExtractFileName(FilePath)) then begin
    result := True;
    var index := fUsedFiles.Add(FilePath);
    FFiles.Add(ExtractFileName(FilePath), index);
    // Потокобезопасность
    CS.Enter;
      List.Add(FilePath);
    CS.Leave;
  end;
end;

{ TInputThread }

procedure TInputThread.Execute;
var
  InputRecord: TInputRecord;
  EventsRead: DWORD;
  ConsoleHandle: THandle;
begin
  inherited;
  try
    ConsoleHandle := GetStdHandle(STD_INPUT_HANDLE);
    if ConsoleHandle <> INVALID_HANDLE_VALUE then begin
      while True do begin
        ReadConsoleInput(ConsoleHandle, InputRecord, 1, EventsRead);
        if (InputRecord.EventType = KEY_EVENT) and InputRecord.Event.KeyEvent.bKeyDown then begin
          case InputRecord.Event.KeyEvent.wVirtualKeyCode of
            VK_ESCAPE: begin
              Writeln('Нажата клавиша Escape.');
              Finish := True;
            end;
          end;
        end;
      end;
    end;
  except
    on E: Exception do
      Writeln('Ошибка: ', E.Message);
  end;
end;

{ Other}

procedure Init;
begin
  SearchPath := 'C:\Source\SprutCAM';
  SeedFile   := 'C:\Source\SprutCAM\NCKernel\NCKernel.dpr';
  TargetPath := 'C:\TestSource';

  CS := TCriticalSection.Create;
  List := TStringList.Create;
end;

begin
  Init;

  InputThread := TInputThread.Create(True);
  InputThread.FreeOnTerminate := True;
  InputThread.Start;

  while True do begin

    case Step of
    // 1 Этап: Парсинг
    stParsing: begin

      if Finish then begin
        InputThread.Terminate;
        ScanThread.Terminate;
        ScanThread.Free;
        exit;
      end;

      if ScanThread = nil then begin
        ScanThread := TScanThread.Create;
        Writeln('Начало сканирования.....');
      end;

      while Counter < List.Count do begin
        // Progress Bar
//      Writeln(Counter.ToString + ' из ' + List.Count.ToString);
        Inc(Counter);
      end;

      if ScanThread.Finished then begin
        Step := stCoping;
        Writeln('Просканировано - ' + List.Count.ToString + ' файлов.');
        Writeln('Конец сканирования');
      end;

    end;

    // 2 Этап: копирование
    stCoping: begin
      Writeln('Начало копирования');
      exit;

    end;
  end;

  end;


end.

