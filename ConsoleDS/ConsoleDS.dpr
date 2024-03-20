program ConsoleDS;

{$APPTYPE CONSOLE}

{$R Resources/DSres.RES}
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
    stUpdate,
    stFinish,
    stNone
  );

  TInputThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TScanThread = class(TThread)
  private
    FScanFile: string;

    FPasFiles:   TDictionary<string, string>;
    FDcuFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;
    FFiles:      TDictionary<string, integer>;
    // <имя юнита | проект, в котором объявляется>
    FUnitLocation: TDictionary<string, string>;

    FUsedFiles:   TStringList;

    FPascalUnitExtractor: TPascalUnitExtractor;
  protected
    procedure Execute;                                                          override;

    procedure FindFilesInDPR(const Path: string);
    procedure FindFilesInFolder(const Folder: string);

    procedure AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);

    function TryAddFileWithExt(const filename, ext: string): Boolean;
    function TryAddFile(const FilePath: string; const Prefix: string = ''): Boolean;
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
    constructor Create(CreateSuspended: Boolean; const ScanFile: string = ''); overload;
    destructor Destroy; overload;
  end;

  TCopyThread = class(TThread)
  private
    FTargetDir: string;
  protected
    procedure Execute;                                                          override;
    procedure UpdateDPR(const FileName: string);
  public
    constructor Create(CreateSuspended: Boolean; const TargetDir: string);      overload;
  end;

var
  SearchPath: string;
  SeedFile: string;
  TargetPath: string;

  SeedFiles: TFileArray;
  AssociatedFiles: TFileArray;
  UpdatedFiles: TFileArray;

  // Файлы без пути
  NessaseryFiles: TStringList;
  IgnoreFiles: TStringList;

  CS: TCriticalSection;

  UpdateItem: array of string;

  // Threads
  InputThread: TInputThread;
  ScanThread: TScanThread;
  CopyThread: TCopyThread;

  // DprojFile:
  DprojFile: TDprojInfo;

const
  PriorityPrefix: array of string = ['IDL.SprutCAMTech.', ''];
  Step: TStep = stParsing;
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
  if IgnoreFiles.IndexOf(ExtractFileNameWithoutExt(F)) = -1 then begin
    IgnoreFiles.Add(ExtractFileNameWithoutExt(F));
  end;
end;

{Добавляет дополнительные файлы, использующиеся в юните}
procedure TScanThread.AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);
begin
  for var ValuesArr in UnitInfo.OtherUsedItems.Values do begin
    for var Value in ValuesArr do begin
      var path := CalcPath(Value, UnitPath);
      TryAddFile(path);
    end;
  end;
end;

constructor TScanThread.Create(CreateSuspended: Boolean; const ScanFile: string = '');
begin
  inherited Create(CreateSuspended);

  FScanFile := SeedFile;
  if ScanFile.IsEmpty then
    FScanFile := ScanFile;

  FPasFiles     :=   TDictionary<string, string>.Create;
  FDcuFiles     :=   TDictionary<string, string>.Create;
  FDprojFiles   :=   TDictionary<string, string>.Create;
  FFiles        :=   TDictionary<string, integer>.Create;
  FUsedFiles    :=   TStringList.Create;
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
//      if (UnitPath.EndsWith('.dpr')) AND (un.InFilePosition = 0) then begin
////        NessaseryFiles.Add(un.DelphiUnitName);
//        continue;
//      end;

      var du := LowerCase(un.DelphiUnitName);

//      if SameText(du, 'STDimensionTypes') then
//        var a := 1;

      if NessaseryFiles.IndexOf(ExtractFileNameWithoutExt(UnitPath)) <> -1 then begin
        NessaseryFiles.Add(du);
        continue;
      end;

      {Нужно ли проигнорировать?}
      if IgnoreFiles.IndexOf(du) <> -1 then
        continue;

//      var IsBreak: Boolean := False;
//      for var ignoreFile in IgnoreFiles do begin
//        if IsSimilarity(du, ignoreFile) then begin
//          IsBreak := True;
//          break;
//        end;
//      end;
//
//      if IsBreak then
//        continue;

      if SameText(du, 'STDimensionTypes') then
        var a := 1;

      {Ищем объявление юнита}
      var location: string;
      if FUnitLocation.TryGetValue(ExtractFileNameWithoutExt(UnitPath), location) then begin
        var DprojFile: string;
        if FDprojFiles.TryGetValue(location + '.dproj', DprojFile) then begin
          var path := GetUnitDeclaration(DprojFile, du);
          path := CalcPath(path, DprojFile);
          TryAddFile(path);
          continue;
        end;
      end;

      for var Prefix in PriorityPrefix do begin
        if fPasFiles.TryGetValue(LowerCase(Prefix) + du + '.pas', pas) OR fDcuFiles.TryGetValue(LowerCase(Prefix) + du + '.dcu', pas) then begin
          TryAddFile(pas, Prefix);
          break;
        end;
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

  // Добавляем юниты
  FindFilesInDPR(SeedFile);
  var currrentFolder := GetDownPath(SeedFile);
  while not SameText(currrentFolder, GetDownPath(SearchPath)) do begin
    FindFilesInFolder(currrentFolder);
    currrentFolder := GetDownPath(currrentFolder);
  end;

  var i := 0;
  while i<fUsedFiles.Count do begin
    if self.Terminated then
      exit;
    DoScan(fUsedFiles[i]);
    inc(i);
  end;
end;

procedure TScanThread.FindFilesInDPR(const Path: string);
var
  UnitInfo: IUnitInfo;
begin
  var Scaned := FPascalUnitExtractor.GetUsedUnits(Path, UnitInfo);
  if Scaned then begin
    for var unt in UnitInfo.UsedUnits do begin
      if Terminated then begin
        Exit;
      end;
      if not fPasFiles.ContainsKey(LowerCase(ExtractFileName(unt.Filename))) then
        fPasFiles.Add(LowerCase(ExtractFileName(unt.FileName)), unt.FileName);
    end;
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
      if not fPasFiles.ContainsKey(LowerCase(ExtractFileName(FileName))) then begin
        fPasFiles.AddOrSetValue(LowerCase(ExtractFileName(FileName)), FileName);
      end;

    end else if SameText(Extenshion, '.dcu') then begin
      if not fDcuFiles.ContainsKey(ExtractFileName(FileName)) then
        fDcuFiles.Add(ExtractFileName(FileName), FileName);

    end else if SameText(Extenshion, '.dproj') then begin
      if not fDprojFiles.ContainsKey(LowerCase(ExtractFileName(FileName))) then
        fDprojFiles.Add(LowerCase(ExtractFileName(FileName)), FileName);
    end;
  end;
end;

{Добавление файлов, синхронизация с основным потоком}
function TScanThread.TryAddFile(const FilePath: string; const Prefix: string = ''): Boolean;
begin
  result := False;
  var name := StringReplace(FilePath, Prefix, '', [rfReplaceAll]);
  if FileExists(FilePath) AND (not FFiles.ContainsKey(ExtractFileName(name))) then begin

    var NesIndex := NessaseryFiles.IndexOf(ExtractFileNameWithoutExt(FilePath));
    if NesIndex <> -1 then begin
      NessaseryFiles.Delete(NesIndex);
    end;

    result := True;
    var index := fUsedFiles.Add(FilePath);
    FFiles.Add(ExtractFileName(name), index);
    var F := TFile.Create(FilePath);
    F.Name := LowerCase(ExtractFileName(name));
    // Потокобезопасность
    CS.Enter;
      SeedFiles.Add(F);
    CS.Leave;

    UpdatedFiles.Add(F);
  end;
end;

function TScanThread.TryAddFiles(const Files: array of string): Integer;
begin
  result := 0;
  for var f in Files do begin
    if TryAddFile(CalcPath(f, SeedFile)) then
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
              Step := stFinish;
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

{Обновляет ссылки на юниты}
procedure TCopyThread.UpdateDPR(const FileName: string);
const
  DoubleSpace = '  ';
  IsUsesBlock: Boolean = False;
var
  SourseStream: TStreamReader;
  DestStream: TStringStream;
begin
  try
    DestStream := TStringStream.Create;
    SourseStream := TStreamReader.Create(FileName);

    while not SourseStream.EndOfStream do begin
      var Line := SourseStream.ReadLine;

      if IsUsesBlock then begin
        if Line.EndsWith(';') then begin
          IsUsesBlock := False;
          for var I := 0 to NessaseryFiles.Count-1 do begin
            DestStream.WriteString(DoubleSpace + NessaseryFiles[I]);

            if (I = NessaseryFiles.Count) AND (AssociatedFiles.GetCount = 0) then
              DestStream.WriteString(';' + #13#10)
            else
              DestStream.WriteString(',' + #13#10);

          end;

          for var I := 0 to AssociatedFiles.GetCount-1 do begin
            if AssociatedFiles[I].Path.EndsWith('.pas') then begin
              var usedUnit := ExtractFilenameNoExt(AssociatedFiles[I].Path) + ' in ' + '''' + GetRelativeLink(FileName, AssociatedFiles[I].Path) + '''';
              DestStream.WriteString(DoubleSpace + usedUnit);

              if I < AssociatedFiles.GetCount-1 then
                DestStream.WriteString(',' + #13#10)
              else
                DestStream.WriteString(';' + #13#10);
            end;
          end;
        end;
        continue;
      end;

      if SameText(Line.Trim, 'uses') then
        IsUsesBlock := True;

      DestStream.WriteString(Line + #13#10);

    end;

  finally
    SourseStream.Free;
    DestStream.SaveToFile(FileName);
    DestStream.Free;
  end;
end;

constructor TCopyThread.Create(CreateSuspended: Boolean; const TargetDir: string);
begin
  inherited Create(CreateSuspended);
  FTargetDir := TargetDir
end;

procedure TCopyThread.Execute;
begin
  inherited;

  var CommonDir := ExtractCommonPrefix(SeedFiles); // Общий префикс
  var Name := StringReplace(CommonDir, GetDownPath(ExtractFileDir(CommonDir)), '', [rfReplaceAll, rfIgnoreCase]);  // Название результирующией папки

  for var I := 0 to UpdatedFiles.GetCount-1 do begin
    var LocalPath := StringReplace(UpdatedFiles[I].Path, CommonDir, '', [rfReplaceAll, rfIgnoreCase]); // путь без общего префикса

    var DestPath := FTargetDir + Name + LocalPath; // результирующее место файла
    var SourcePath := UpdatedFiles[I].Path;

    if AssociatedFiles.GetByName(UpdatedFiles[I].Name) = nil then begin

      var AssociatedFile := TFile.Create(DestPath, UpdatedFiles[I]);
      AssociatedFiles.Add(AssociatedFile);

      CopyWithDir(SourcePath, DestPath);
    end;
  end;

  // Обновляем uses в dpr
  var dpr := AssociatedFiles.GetByName(ExtractFileName(SeedFile));
  self.UpdateDPR(dpr.Path);
  dpr.Update;

  // Обновляем dproj
  var dproj := AssociatedFiles.GetByName(ExtractFileNameWithoutExt(SeedFile) + '.dproj');
  DprojFile.ReLinkSearchPathTo(dproj.path);
  dproj.Update;
end;

{ Other}

procedure Initialize;
begin
  SearchPath := 'C:\Source\SprutCAM';
  SeedFile   := 'C:\Source\SprutCAM\SprutCAM40\SCKernel\main\SCKernel.dpr';
  TargetPath := 'C:\TestSource';

  SeedFiles := TFileArray.Create;
  AssociatedFiles := TFileArray.Create;
  UpdatedFiles := TFileArray.Create;

  CS := TCriticalSection.Create;

  NessaseryFiles := TStringList.Create;
  IgnoreFiles := TStringList.Create;
end;

procedure LoadResources;
var
  RS: TResourceStream;
begin
  try
    RS := TResourceStream.Create(HInstance, 'LIB', RT_RCDATA);
    IgnoreFiles.LoadFromStream(RS);
  finally
    RS.Free;
  end;
end;

procedure Finalize;
begin
  FreeAndNil(CS);
  FreeAndNil(NessaseryFiles);
  FreeAndNil(IgnoreFiles);
  FreeAndNil(SeedFiles);
  FreeAndNil(AssociatedFiles);
  FreeAndNil(UpdatedFiles);
end;

begin
  // Этап 0: Обратока входных параметров
  if ParamCount = 3 then begin
    for var I := 1 to ParamCount do begin
      case I of
        1: begin
          SearchPath := ParamStr(I);
          if not DirectoryExists(SearchPath) then begin
            Writeln('Директроии "' + ParamStr(I) + '" не существует');
            exit;
          end;
        end;

        2: begin
          SeedFile := ParamStr(I);
          if not FileExists(ParamStr(I)) then begin
            Writeln('Файла "' + ParamStr(I) + '" не существует');
            exit;
          end;
        end;

        3: begin
          TargetPath := ParamStr(I);
        end;
      end;
    end;
  end else begin
//    Writeln('Неправильное число параметров');
//    ReadLn;
//    exit;
    SearchPath := 'C:\Source\SprutCAM';
    SeedFile   := 'C:\Source\SprutCAM\NCKernel\NCKernel.dpr';
    TargetPath := 'C:\TestSource';
  end;

  Initialize;
  LoadResources;

  InputThread := TInputThread.Create(True);
  InputThread.FreeOnTerminate := True;
  InputThread.Start;

  var ScanFile := SeedFile;

  while True do begin

    case Step of
      // 1 Этап: Парсинг
      stParsing: begin

        if ScanThread = nil then begin
          ScanThread := TScanThread.Create(True, ScanFile);
          ScanThread.FreeOnTerminate := True;
          ScanThread.Start;
          Writeln('Начало сканирования.....');
        end;

        while Counter < SeedFiles.GetCount do begin
          // Progress Bar
//          Writeln(Counter.ToString + ' -- ' + SeedFiles[Counter].Path);
          Inc(Counter);
        end;

        if ScanThread.Finished then begin
          Step := stCoping;
          Writeln('Просканировано - ' + SeedFiles.GetCount.ToString + ' файлов.');
          Writeln('Конец сканирования');
          ScanThread := nil;
        end;

      end;

      // 2 Этап: Копирование
      stCoping: begin

        if CopyThread = nil then begin
          CopyThread := TCopyThread.Create(True, TargetPath);
          CopyThread.FreeOnTerminate := true;
          CopyThread.Start;
          Writeln('Начало копирования.....');
        end;

        if CopyThread.Finished then begin
          Step := stUpdate;
          Writeln('Конец копирования');
          Writeln('Начало обновления');
          CopyThread := nil;
        end;

      end;

      // 3 Этап: Синхронизация
      stUpdate: begin

        for var I := 0 to AssociatedFiles.GetCount-1 do begin
          var f := AssociatedFiles[I];
          if F.IsUpdated then begin
            Writeln(ExtractFileName(f.Path) + ' был обновлен.');
            var Seed := F.AssociatedFile.Path;
            CopyFile(PChar(F), PChar(Seed), False);
            // Обновить файл исходного проекта
            F.Update;
          end;
        end;
      end;

      // 4 Этап: Завершение
      stFinish: begin
        if InputThread <> nil then begin
          InputThread.Terminate;
        end;
        if ScanThread <> nil then begin
          ScanThread.Terminate;
        end;
        if CopyThread <> nil then begin
          CopyThread.Terminate;
        end;

        BREAK;
      end;
    end;
  end;

  Finalize;
end.

