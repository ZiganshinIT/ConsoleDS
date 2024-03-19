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

const
  SytsemDelimiter = '\';

type
  TStep =
  (
    stParsing,
    stCoping,
    stNone
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

    function TryAddFileWithExt(const filename, ext: string): Boolean;
    function TryAddFile(const FilePath: string): Boolean;
    function TryAddFiles(const Files: array of string): Integer;

    procedure DoScan(const FilePath: string);
    procedure DoScanUnit(const UnitPath: string);
    procedure DoScanRCFiles(const RCFilePath: string);

    {Unit Location}
    procedure AddFileLocation(const F: string);
    procedure AddFilesLocation(const Files: array of string);

    {Ignore Files}
    procedure AddIgnoreFile(const F: string);
    procedure AddIgnoreFiles(const Files: array of string);
  public
    constructor Create; overload;
    destructor Destroy; overload;
  end;

  TCopyThread = class(TThread)
  private
    FTargetDir: string;
  protected
    procedure Execute;                                                          override;
  public
    constructor Create(const TargetDir: string);                                overload;
  end;

var
  SearchPath: string;
  SeedFile: string;
  TargetPath: string;

  List: TStringList;
  CS: TCriticalSection;

  // Threads
  InputThread: TInputThread;
  ScanThread: TScanThread;
  CopyThread: TCopyThread;

  // DprojFile:
  DprojFile: TDprojInfo;

const
  Step: TStep = stParsing;
  Finish: Boolean = False;
  Counter: Integer = 0;


{ TScanThread }

{Добавляет файл меня расширение}
function TScanThread.TryAddFileWithExt(const filename, ext: string): Boolean;
begin
  var fn := ExtractFilePath(filename)+ExtractFileNameWithoutExt(filename)+ext;
  result := TryAddFile(fn);
end;

{Добавляет в словарь имя юнита и проект в кототром он определен}
procedure TScanThread.AddFileLocation(const F: string);
var
  FoundFiles: TStringDynArray;
  FileName: string;
  Location: string;
begin
  if DirectoryExists(f) then begin
    FoundFiles := TDirectory.GetFiles(f, '*.*', TSearchOption.soAllDirectories);
    for FileName in FoundFiles do begin
      var name := ExtractFileNameWithoutExt(FileName);
      if not fUnitLocation.ContainsKey(name) then begin
        Location := ExtractFileName(ExtractFileDir(FileName));
        fUnitLocation.Add(name, Location);
      end;
    end;
  end;
end;

{Добавляет в словарь имя юнита и проект в кототром он определен}
procedure TScanThread.AddFilesLocation(const Files: array of string);
begin
  for var f in Files do begin
    AddFileLocation(f);
  end;
end;

{Формирует массив файлов которые нужно проигнорировать}
procedure TScanThread.AddIgnoreFiles(const Files: array of string);
begin
  for var f in Files do begin
    AddIgnoreFile(f);
  end;
end;

{Формирует массив файлов которые нужно проигнорировать}
procedure TScanThread.AddIgnoreFile(const F: string);
begin
  if FIgnoreFiles.IndexOf(ExtractFileNameWithoutExt(F)) = -1 then begin
    FIgnoreFiles.Add(ExtractFileNameWithoutExt(F));
  end;
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

      {Пропуск файлов без пути распложения}
      if (UnitPath.EndsWith('.dpr')) AND (un.InFilePosition = 0) then begin
        continue;
      end;

      var du := LowerCase(un.DelphiUnitName);

      {Нужно ли проигнорировать?}
      if FIgnoreFiles.IndexOf(du) <> -1 then
        continue;

      if fPasFiles.TryGetValue(du + '.pas', pas) OR fDcuFiles.TryGetValue(du + '.dcu', pas) then begin
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
    if TryAddFileWithExt(SeedFile, '.dproj') then begin
      var dprojPath := StringReplace(SeedFile, '.dpr', '.dproj', [rfReplaceAll, rfIgnoreCase]);
      DprojFile := TDprojInfo.Create(dprojPath);
      TryAddFiles(DprojFile.Resources); // Добавляет ресурсы проекта

      { Добавляет доступные define проекта }
      with FPascalUnitExtractor do begin
        DefineAnalizator.EnableDefines := DprojFile.GetDefinies([All, Win64], [Base, Cfg_2]);
      end;

      {Формируем словарь юнитов и мест их определения}
      AddFileLocation(DprojFile.GetOutput(All, Base));
      AddFilesLocation(DprojFile.GetSearchPath([All], [Base]));

      {Формируем массив файлов, которые нужно проигнорировать}
      AddIgnoreFile('SVG2Png');
      AddIgnoreFiles(DprojFile.GetDebuggerFiles(Win64, Cfg_2));

    end;
    TryAddFileWithExt(SeedFile, '._icon.ico');
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

function TScanThread.TryAddFiles(const Files: array of string): Integer;
begin
  result := 0;
  for var f in Files do begin
    if TryAddFile(f) then
      Inc(result);
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

{ TCopierThread }

constructor TCopyThread.Create(const TargetDir: string);
begin
  inherited Create(False);
  FTargetDir := TargetDir
end;

procedure TCopyThread.Execute;
begin
  inherited;

  var CommonDir := ExtractCommonPrefix(List); // Общий префикс
  var Name := StringReplace(CommonDir, GetDownPath(ExtractFileDir(CommonDir)), '', [rfReplaceAll, rfIgnoreCase]);  // Название результирующией папки

  for var F in List do begin
    var LocalPath := StringReplace(F, CommonDir, '', [rfReplaceAll, rfIgnoreCase]); // путь без общего префикса

    var DestPath := FTargetDir + Name + LocalPath; // результирующее место файла
    var SourcePath := F;

    if F.EndsWith('.dproj') then begin
      DprojFile.ReLinkSearchPathTo(DestPath);
      continue;
    end;

    CopyWithDir(SourcePath, DestPath)
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
          Inc(Counter);
        end;

        if ScanThread.Finished then begin
          Step := stCoping;
          Writeln('Просканировано - ' + List.Count.ToString + ' файлов.');
          Writeln('Конец сканирования');
          ScanThread.Terminate;
          ScanThread.Free;
        end;

      end;

      // 2 Этап: копирование
      stCoping: begin

        if CopyThread = nil then begin
          CopyThread := TCopyThread.Create(TargetPath);
          Writeln('Начало копирования.....');
        end;

        if CopyThread.Finished then begin
          Step := stNone;
          Writeln('Конец копирования');
        end;

      end;
    end;
  end;

  ReadLn;

  InputThread.Free;
  ScanThread.Free;
  CopyThread.Free;

end.

