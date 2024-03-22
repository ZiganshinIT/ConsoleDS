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

  TScanner = class
  private
    FPasFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;
    FFiles:      TDictionary<string, integer>;
    FUsedFiles:  TStringList;
    FIgnoreFiles: TStringList;
    FPascalUnitExtractor: TPascalUnitExtractor;
  protected
    procedure StartScan;
    procedure FindFilesFromProject(const ProjectPath: string);

    {Add Files Operations}
    procedure AddFile(const FilePath: string);
    procedure AddFiles(const Files: array of string);
    procedure AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);

    {Add Ignore Files Operations}
    procedure AddIgnoreFile(const F: string);
    procedure AddIgnoreFiles(const Files: array of string);
    procedure AddIngoreFilesFromResource;

    {Scan Operations}
    procedure DoScan(const FilePath: string);
    procedure DoScanUnit(const UnitPath: string);
    procedure DoScanRCFiles(const RCFilePath: string);

  public
    constructor Create;

    procedure LoadSettings(const DprojFile: TDprojFile);
    procedure Scan(const Dprojfile: TDprojFile);                                overload;
    procedure Scan(const Files: array of string);                               overload;

    destructor Destroy;
  end;

  // Syncronizer
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
  ProjGroupFile: string;

  SeedFiles: TFileArray;
  AssociatedFiles: TFileArray;
  UpdatedFiles: TFileArray;

  UpdateItem: array of string;

  // Threads
  InputThread: TInputThread;
  CopyThread: TCopyThread;

  //
  UndetectedUnits: TStringList;

const
  Step: TStep = stParsing;
  Counter: Integer = 0;

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
          for var I := 0 to UndetectedUnits.Count-1 do begin
            DestStream.WriteString(DoubleSpace + UndetectedUnits[I]);

            if (I = UndetectedUnits.Count) AND (AssociatedFiles.GetCount = 0) then
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
//  DprojFile.ReLinkSearchPathTo(dproj.path);
  dproj.Update;
end;

{ Other}

procedure Initialize;
begin
  SearchPath := 'C:\Source\SprutCAM';
  SeedFile   := 'C:\Source\SprutCAM\SprutCAM40\SCKernel\main\SCKernel.dproj';
  TargetPath := 'C:\TestSource';
  ProjGroupFile := 'C:\Source\SprutCAM\SprutCAM.groupproj';

  SeedFiles := TFileArray.Create;
  AssociatedFiles := TFileArray.Create;
  UpdatedFiles := TFileArray.Create;

  UndetectedUnits := TStringList.Create;
end;

procedure Finalize;
begin
  FreeAndNil(SeedFiles);
  FreeAndNil(AssociatedFiles);
  FreeAndNil(UpdatedFiles);
  FreeAndNil(UndetectedUnits);
end;

{ TScanner }

procedure TScanner.AddFile(const FilePath: string);
begin
  if FileExists(FilePath) AND (not FFiles.ContainsKey(ExtractFileName(FilePath))) then begin
    var index := fUsedFiles.Add(FilePath);
    FFiles.Add(ExtractFileName(FilePath), index);
    var F := TFile.Create(FilePath);
    F.Name := LowerCase(ExtractFileName(FilePath));
    SeedFiles.Add(F);
    UpdatedFiles.Add(F);

    // Debug
    Writeln(index.ToString + ' -- ' + F.Path);
  end;
end;

procedure TScanner.AddFiles(const Files: array of string);
begin
  for var F in Files do begin
    AddFile(F);
  end;
end;

procedure TScanner.AddIgnoreFile(const F: string);
begin
  if FIgnoreFiles.IndexOf(ExtractFileNameWithoutExt(F)) = -1 then begin
    FIgnoreFiles.Add(ExtractFileNameWithoutExt(F));
  end;
end;

procedure TScanner.AddIgnoreFiles(const Files: array of string);
begin
  for var F in Files do begin
    AddIgnoreFile(F);
  end;
end;

procedure TScanner.AddIngoreFilesFromResource;
var
  RS: TResourceStream;
begin
  try
    RS := TResourceStream.Create(HInstance, 'LIB', RT_RCDATA);
    fIgnoreFiles.LoadFromStream(RS);
  finally
    RS.Free;
  end;
end;

procedure TScanner.AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);
begin
  for var ValuesArr in UnitInfo.OtherUsedItems.Values do begin
    for var Value in ValuesArr do begin
      var path := CalcPath(Value, UnitPath);
      AddFile(path);
    end;
  end;
end;

constructor TScanner.Create;
begin
  FPasFiles     :=   TDictionary<string, string>.Create;
  FDprojFiles   :=   ParseUsedProject(ProjGroupFile);
  FFiles        :=   TDictionary<string, integer>.Create;
  FUsedFiles    :=   TStringList.Create;
  FIgnoreFiles  :=   TStringList.Create;
  FPascalUnitExtractor := TPascalUnitExtractor.Create(nil);
end;

destructor TScanner.Destroy;
begin
  FreeAndNil(FPasFiles);
  FreeAndNil(FDprojFiles);
  FreeAndNil(FFiles);
  FreeAndNil(FUsedFiles);
  FreeAndNil(FIgnoreFiles);
  FreeAndNil(FPascalUnitExtractor);
end;

procedure TScanner.DoScan(const FilePath: string);
var
  UnitInfo: IUnitInfo;
begin
  var Extension := LowerCase(ExtractFileExt(FilePath));
  if SameText(Extension, '.pas') OR SameText(Extension, '.dpr') then begin
    self.DoScanUnit(FilePath);
  end else if SameText(Extension, '.rc') then begin
    self.DoScanRCFiles(FilePath);
  end;
end;

procedure TScanner.DoScanRCFiles(const RCFilePath: string);
begin
  if FileExists(RCFilePath) then begin
    var files := ReadRCFile(RCFilePath);
    for var f in files do begin
      var InnerFilePath := CalcPath(f, RCFilePath);
      AddFile(InnerFilePath)
    end;
  end else
    raise Exception.Create(RCFilePath + ' не существует')
end;

procedure TScanner.DoScanUnit(const UnitPath: string);
var
  UnitInfo: IUnitInfo;
  Parsed: Boolean;
  pas: string;
begin
  Parsed := FPascalUnitExtractor.GetUsedUnits(UnitPath, UnitInfo);
  if Parsed then begin

    if UnitInfo.OtherUsedItems.Count > 0 then begin
      AddOtherFiles(UnitPath, UnitInfo);
    end;

    for var un in UnitInfo.UsedUnits do begin

      var du := LowerCase(un.DelphiUnitName);

      {Нужно ли проигнорировать?}
      if (fIgnoreFiles.IndexOf(du) <> -1) And (not SameText(ExtractFileExt(UnitPath), '.dpr')) then
        continue;

        if fPasFiles.TryGetValue(du + '.pas', pas) then begin
          AddFile(pas);
        end else if SameText(ExtractFileExt(UnitPath), '.dpr') then begin
          UndetectedUnits.Add(du);
        end;
    end;
  end;
end;

procedure TScanner.FindFilesFromProject(const ProjectPath: string);
var
  Extension: string;
  List: TStringList;
  Line: string;
  FindBlock: string;
  WorkPath: string;
begin
  List := TStringList.Create;
  Extension := ExtractFileExt(ProjectPath);

  {Анализируем переданный аргумент на возможность получения путей юнитов}
  if SameText(Extension, '.dproj') then begin
    if FileExists(ReplacePathExtension(ProjectPath, '.dpk')) then begin
      WorkPath := ReplacePathExtension(ProjectPath, '.dpk');
    end else if FileExists(ReplacePathExtension(ProjectPath, '.dpr')) then begin
      WorkPath := ReplacePathExtension(ProjectPath, '.dpr');
    end;
  end else if SameText(Extension, '.dpk') OR SameText(Extension, '.dpr') then begin
    WorkPath := ProjectPath;
  end else begin
    raise Exception.Create('Файл неправильный файл');
  end;

  List.LoadFromFile(WorkPath);


  {Блок, в котором находятся юниты и их пути}
  Extension := ExtractFileExt(WorkPath);
  if SameText(Extension, '.dpr') then
    FindBlock := 'uses'
  else if SameText(Extension, '.dpk') then
    FindBlock := 'contains';

  {Добавляем найденные юниты с путями}
  var Counter := 0;
  while Counter < List.Count-1 do begin
    Line := List.Strings[Counter];

    if SameText(Line, FindBlock) then begin
      Inc(Counter);
      while (not Line.EndsWith(';') AND (Counter < List.Count-1)) do begin
        Line := List.Strings[Counter].Trim;
        var Words := Line.Split([' ']);
        case Length(Words) of
          3, 4: begin
            if not FPasFiles.ContainsKey(LowerCase(Words[0] + '.pas')) then begin
              var PasPath := Words[2].Trim([' ', '''', '"', ',', ';']);
              PasPath := CalcPath(PasPath, WorkPath);
              FPasFiles.Add(LowerCase(Words[0] + '.pas'), PasPath);
            end;
          end;
        end;
        Inc(Counter);
      end;
    end;
    Inc(Counter);
  end;

  FreeAndNil(List);
end;

procedure TScanner.LoadSettings(const DprojFile: TDprojFile);
begin
   { Добавляет доступные define проекта }
   FPascalUnitExtractor.DefineAnalizator.EnableDefines := DprojFile.GetDefinies([All, Win64], [Base, Cfg_2]);

   {Формируем массив файлов, которые нужно проигнорировать}
   AddIngoreFilesFromResource;
   AddIgnoreFiles(DprojFile.GetDebuggerFiles(Win64, Cfg_2));
   AddIgnoreFile('SVG2Png');

  {Формируем словарь юнитов проекта и пути к ним}
  FindFilesFromProject(DprojFile.FilePath);
  var SearchPaths := DprojFile.GetSearchPath([All], [Base]);
  for var SearchPath in SearchPaths do begin
    var PathParts := SearchPath.Split(['\']);
    var ProjectName := PathParts[Length(PathParts)-1];
    var ProjectPath: string;
    if FDprojFiles.TryGetValue(LowerCase(ProjectName), ProjectPath) then begin
      ProjectPath := CalcPath(ProjectPath, ProjGroupFile);
      FindFilesFromProject(ProjectPath);
    end;
  end;
end;

procedure TScanner.Scan(const Files: array of string);

begin
  for var F in Files do begin
    AddFile(F);
  end;
  StartScan;
end;

procedure TScanner.StartScan;
const
  I: Integer = 0;
begin
  while I < FUsedFiles.Count do begin
    DoScan(FUsedFiles[I]);
    Inc(I);
  end;
end;

procedure TScanner.Scan(const Dprojfile: TDprojFile);
const
  I: Integer = 0;
begin
  if DprojFile <> nil then begin
    AddFile(DprojFile.FilePath);
    AddFile(ReplacePathExtension(DprojFile.FilePath, '.dpr'));
    AddFile(ReplacePathExtension(DprojFile.FilePath, '_icon.ico'));
    AddFiles(Dprojfile.Resources);
    StartScan;
  end;
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
  end;

  Initialize;

  InputThread := TInputThread.Create(True);
  InputThread.FreeOnTerminate := True;
  InputThread.Start;

  var DprojFile := TDprojFile.Create(SeedFile);

  var Scanner := TScanner.Create;
  Scanner.LoadSettings(DprojFile);

  while True do begin

    case Step of
      // 1 Этап: Парсинг
      stParsing: begin
        Writeln('Начало сканирования.....');
        Scanner.Scan(DprojFile);
        Writeln('Конец Сканироания...');
        Writeln('Просканировано - ' + SeedFiles.GetCount.ToString + ' файлов.');
        Step := stCoping;
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
//        if ScanThread <> nil then begin
//          ScanThread.Terminate;
//        end;
        if CopyThread <> nil then begin
          CopyThread.Terminate;
        end;

        BREAK;
      end;
    end;
  end;

  Finalize;
end.

