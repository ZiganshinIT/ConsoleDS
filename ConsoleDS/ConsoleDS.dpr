program ConsoleDS;

{$APPTYPE CONSOLE}

{$R Resources/DSres.RES}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.Threading,
  System.Generics.Collections,
  System.SyncObjs,
  Duds.Common.Classes in '..\DUDS\Duds.Common.Classes.pas',
  Duds.Common.Delphi in '..\DUDS\Duds.Common.Delphi.pas',
  Duds.Common.Files in '..\DUDS\Duds.Common.Files.pas',
  Duds.Common.Interfaces in '..\DUDS\Duds.Common.Interfaces.pas',
  Duds.Common.Parser.Pascal in '..\DUDS\Duds.Common.Parser.Pascal.pas',
  Duds.Common.Parser.Pascal.Tokeniser in '..\DUDS\Duds.Common.Parser.Pascal.Tokeniser.pas',
  Duds.Common.Strings in '..\DUDS\Duds.Common.Strings.pas',
  Duds.Common.Types in '..\DUDS\Duds.Common.Types.pas',
  Duds.Common.Utils in '..\DUDS\Duds.Common.Utils.pas',

  DSTypes in '..\Utils\DSTypes.pas',
  DSUtils in '..\Utils\DSUtils.pas',
  FileClass in '..\Utils\FileClass.pas';
//  Dproj in '..\Utils\Dproj.pas';

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
    FDcuFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;
    FFiles:      TDictionary<string, integer>;
    FUsedFiles:  TStringList;
    FIgnoreFiles: TStringList;
    FUndetectedFiles: TStringList; // Файлы необходимые для формирования DPR
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

    procedure Scan(const Dprojfile: TDprojFile);                                overload;
    procedure Scan(const Files: array of string);                               overload;

    {Get Result}
    procedure GetResultArrays(out DetectedFiles: TStringList);

  public
    constructor Create;

    procedure LoadSettings(const DprojFile: TDprojFile);

    procedure Scan(const FilePath: string; FileType: TFileType);                overload;

    procedure FindFilesInFolder(const Folder: string);

    destructor Destroy;
  end;

var
  SeedFile: string;
  TargetPath: string;

  GroupProjFile: string;
  ProjFile:  string;

  WithCopy: Boolean;

  FileType: TFileType;

  DprojFile: TDprojFile;

  // Threads
  InputThread: TInputThread;

  DetectedUnits: TStringList;
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

{ Other}

procedure Initialize;
begin
  UndetectedUnits := TStringList.Create;
end;

procedure Finalize;
begin
  FreeAndNil(UndetectedUnits);
end;

{ TScanner }

procedure TScanner.AddFile(const FilePath: string);
begin
  if FileExists(FilePath) AND (not FFiles.ContainsKey(ExtractFileName(FilePath))) then begin
    var index := fUsedFiles.Add(FilePath);
    FFiles.Add(ExtractFileName(FilePath), index);

    // Debug
    Writeln(index.ToString + ' -- ' + FilePath);
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
  FDcuFiles     :=   TDictionary<string, string>.Create;
  if not GroupProjFile.IsEmpty then
    FDprojFiles   :=   ParseUsedProject(GroupProjFile);
  FFiles        :=   TDictionary<string, integer>.Create;
  FUsedFiles    :=   TStringList.Create;
  FIgnoreFiles  :=   TStringList.Create;
  FPascalUnitExtractor := TPascalUnitExtractor.Create(nil);
end;

destructor TScanner.Destroy;
begin
  FreeAndNil(FPasFiles);
  FreeAndNil(FDcuFiles);
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

      if SameText(du, 'ElTree') then
        var a := 1;

      {Нужно ли проигнорировать?}
      if (fIgnoreFiles.IndexOf(du) <> -1) And (not SameText(ExtractFileExt(UnitPath), '.dpr')) then
        continue;

        if fPasFiles.TryGetValue(du + '.pas', pas) then begin
          AddFile(pas);
        end else if fDcuFiles.TryGetValue(du + '.dcu', pas) then begin
          AddFile(pas);
        end else if SameText(ExtractFileExt(UnitPath), '.dpr') then begin
          FUsedFiles.Add(du);
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

        if Length(Words) > 1 then begin
          var name := Words[0];
          if not FPasFiles.ContainsKey(LowerCase(name + '.pas')) then begin
            var pasPath := Line.Substring(Line.IndexOf('''') + 1,  Line.LastIndexOf('''') - Line.IndexOf('''')-1);
            PasPath := CalcPath(PasPath, WorkPath);
            FPasFiles.Add(LowerCase(Words[0] + '.pas'), PasPath);
          end;
        end;

        Inc(Counter);
      end;
    end;
    Inc(Counter);
  end;

  FreeAndNil(List);
end;

procedure TScanner.FindFilesInFolder(const Folder: string);
var
  FoundFiles: TStringDynArray;
  FileName: string;
begin
  FoundFiles := TDirectory.GetFiles(Folder, '*.*', TSearchOption.soAllDirectories);
  for FileName in FoundFiles do
  begin
    var ext := ExtractFileExt(FileName);
    if SameText(ext, '.pas') then begin
      if not fPasFiles.ContainsKey(ExtractFileName(FileName))then begin
        fPasFiles.AddOrSetValue(LowerCase(ExtractFileName(FileName)), FileName);
      end;
    end else if SameText(ext, '.dcu') then begin
      if not fDcuFiles.ContainsKey(LowerCase(ExtractFileName(FileName))) then
        fDcuFiles.AddOrSetValue(ExtractFileName(FileName), FileName);
    end;
  end;
end;

procedure TScanner.GetResultArrays(out DetectedFiles: TStringList);
begin
  DetectedFiles := FUsedFiles;
end;

procedure TScanner.LoadSettings(const DprojFile: TDprojFile);
begin
   { Добавляет доступные define проекта }
    FPascalUnitExtractor.DefineAnalizator.EnableDefines := DprojFile.GetDefinies([All, Win64], [Base, Cfg_2]);


   {Формируем массив файлов, которые нужно проигнорировать}
   AddIngoreFilesFromResource;
   AddIgnoreFiles(DprojFile.GetDebuggerSourcePath(Win64, Cfg_2));
   AddIgnoreFile('SVG2Png');

  {Формируем словарь юнитов проекта и пути к ним}
  FindFilesFromProject(DprojFile.Path);
  var SearchPaths := DprojFile.GetSearchPath(All, Base);
  for var SearchPath in SearchPaths do begin
    var PathParts := SearchPath.Split(['\']);
    var ProjectName := PathParts[Length(PathParts)-1];
    var ProjectPath: string;
    if FDprojFiles.TryGetValue(LowerCase(ProjectName), ProjectPath) then begin
      ProjectPath := CalcPath(ProjectPath, GroupProjFile);
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

procedure TScanner.Scan(const FilePath: string; FileType: TFileType);
begin
  if FileExists(FilePath) then begin
    case FileType of
      ftDproj, ftDpr: begin
        self.Scan(DprojFile);
      end;
      ftPas: begin
        self.Scan(FilePath);
      end;
    end;
  end;
end;

procedure TScanner.StartScan;
const
  I: Integer = 0;
begin
  while I < FUsedFiles.Count do begin
    if Step = stFinish then
      exit;
    DoScan(FUsedFiles[I]);
    Inc(I);
  end;
end;

procedure TScanner.Scan(const Dprojfile: TDprojFile);
const
  I: Integer = 0;
begin
  if DprojFile <> nil then begin
    AddFile(DprojFile.Path);
    AddFile(ReplacePathExtension(DprojFile.Path, '.dpr'));
    AddFile(ReplacePathExtension(DprojFile.Path, '_icon.ico'));
    for var Res in Dprojfile.Resources do begin
      AddFile(CalcPath(Res.Include, Dprojfile.Path));
      if not Res.Form.IsEmpty then
        AddFile(CalcPath(Res.Form, Dprojfile.Path));
    end;
    StartScan;
  end;
end;

begin
  // Ini Files
  // Абсолютные и относительные ссылки
  // Добавить в файл в PATH

  {ConsoleDC.exe SeedFile, TargetDir, GroupProject|SearchPath, WithCopy (Flag)};

//  SeedFile := 'C:\Source\SprutCAM\SCKernelConsole\main\SCKernelConsole.dpr';
//  SeedFile := 'C:\Source\SprutCAM\SprutCAM40\SCKernel\main\SCKernel.dpr';
  SeedFile := 'C:\Source\SprutCAM\NCKernel\NCKernel.dpr';
  TargetPath := 'C:\TestSource\';
  GroupProjFile := 'C:\Source\SprutCAM\SprutCAM.groupproj';
  //ProjFile := 'C:\Source\SprutCAM\NCKernel\NCKernel.dproj';
  WithCopy := False;

  // Этап 0: Обратока входных параметров
  FileType := GetFileType(SeedFile);

  Initialize;

  InputThread := TInputThread.Create(True);
  InputThread.FreeOnTerminate := True;
  InputThread.Start;

  var Scanner := TScanner.Create;

  case FileType of
    ftDproj: begin
      DprojFile := TDprojFile.Create(SeedFile);
      Scanner.LoadSettings(DprojFile);
    end;
    ftDpr: begin
      var DprojPath := StringReplace(SeedFile, '.dpr', '.dproj', [rfIgnoreCase]);
      if FileExists(DprojPath) then begin
        DprojFile := TDprojFile.Create(DprojPath);
        Scanner.LoadSettings(DprojFile);
      end;
    end;
    ftPas: begin
      if (not ProjFile.IsEmpty) AND FileExists(ProjFile) then begin
        DprojFile := TDprojFile.Create(ProjFile);
        Scanner.LoadSettings(DprojFile);
      end;
    end;
    ftUndefined:
      raise Exception.Create('Ошибка');
  end;

  while True do begin

    case Step of
      // 1 Этап: Парсинг
      stParsing: begin
        Writeln('Начало сканирования.....');
        Scanner.Scan(SeedFile, FileType);
        Scanner.GetResultArrays(DetectedUnits);
        Writeln('Конец Сканироания...');
        Step := stCoping;
      end;

      stCoping: begin
        Writeln('Начало копирования...');
        if WithCopy then begin

        end else begin
          var NewDprojPath := TargetPath + ExtractFileNameWithoutExt(SeedFile) + '.dproj';



              var spArr := DprojFile.GetSearchPath(All, Base);
              for var I := 0 to Length(spArr)-1 do begin
                var spPath := CalcPath(spArr[I], DprojFile.Path);
                spArr[I] := GetRelativeLink(NewDprojPath, spPath);
              end;

              DprojFile.SetSearchPath(All, Base, spArr);

              for var pe := Low(TPlatformEnum) to High(TPlatformEnum) do begin
            for var ce := Low(TConfigEnum) to High(TConfigEnum) do begin

              var HA := DprojFile.GetHostApplication(pe, ce);
              HA := CalcPath(HA, SeedFile);
              DprojFile.SetHostApplication(pe, ce, GetRelativeLink(NewDprojPath, HA));

            end;
          end;

              var Prefix := DprojFile.ConfigSettings[All][Base][ResourceOutputPath];
              var ResArr := DprojFile.Resources;
              for var I := 0 to Length(ResArr)-1 do begin
                // Include
                var Include := CalcPath(ResArr[I].Include, DprojFile.Path);
                ResArr[I].Include := GetRelativeLink(NewDprojPath, Include);
                //Form
                if not ResArr[I].Form.Contains(Prefix) then
                  ResArr[I].Form := Prefix + '\' + ResArr[I].Form;
                var Form := CalcPath(ResArr[I].Form, DprojFile.Path);
                ResArr[I].Form := GetRelativeLink(NewDprojPath, Form);

              end;



          DprojFile.Refresh;
          DprojFile.SaveFile(NewDprojPath);

          var DPR := TDPRFile.Create(TargetPath + ExtractFileNameWithoutExt(SeedFile) + '.dpr');
          DPR.LoadStructure(SeedFile);
          DPR.Assign(TDprojFile.Create(NewDprojPath));
          DPR.UpdateResources(DprojFile);
          DPR.UpdateUses(DetectedUnits);
          DPR.SaveFile;

        end;
        Writeln('Конец копирования...');
        Step := stFinish;
      end;

      // 4 Этап: Завершение
      stFinish: begin
        if InputThread <> nil then begin
          InputThread.Terminate;
        end;

        BREAK;
      end;
    end;
  end;

  Finalize;
end.

