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
  Dproj in '..\Utils\Dproj.pas',
  DSTypes in '..\Utils\DSTypes.pas',
  DSUtils in '..\Utils\DSUtils.pas',
  DprojStructure in '..\Utils\DprojStructure.pas';

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

    procedure FindFilesInFolder(const Folder: string);

    destructor Destroy;
  end;

  TSyncronizer = class
  private
    function GetLinkedPath(const path: string): string;
    procedure UpdateDPR(const FileName: string);
    procedure CreateDpr(const FileName: string);
  public
    procedure Syncronize;
  end;

var
  SeedFile: string;
  TargetPath: string;

  GroupProjFile: string;
  ProjFile:  string;

  SearchDir: string;

  SeedFiles: TFileArray;
  AssociatedFiles: TFileArray;
  UpdatedFiles: TFileArray;

  DprojFile: TDprojFile;

  // Threads
  InputThread: TInputThread;

  UndetectedUnits: TStringList;

  IsPasFile: Boolean;

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
    var F := TFile.Create(FilePath, True);
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

      {Нужно ли проигнорировать?}
      if (fIgnoreFiles.IndexOf(du) <> -1) And (not SameText(ExtractFileExt(UnitPath), '.dpr')) then
        continue;

        if fPasFiles.TryGetValue(du + '.pas', pas) then begin
          AddFile(pas);
        end else if fDcuFiles.TryGetValue(du + '.dcu', pas) then begin
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
    AddFile(DprojFile.FilePath);
    AddFile(ReplacePathExtension(DprojFile.FilePath, '.dpr'));
    AddFile(ReplacePathExtension(DprojFile.FilePath, '_icon.ico'));
    for var Res in Dprojfile.Resources do begin
      AddFile(CalcPath(Res, Dprojfile.FilePath));
    end;
    StartScan;
  end;
end;

{ TSyncronizer }

{Возвращает связаннный путь}
procedure TSyncronizer.CreateDpr(const FileName: string);
// Отступы
const
  Level: Integer = 0;

  procedure IncLevel;
  begin
    Inc(Level);
  end;

  procedure DecLevel;
  begin
    If Level > 0 then
      Dec(Level);
  end;

var
  stream: TStringStream;

  procedure WriteLine(line: string = '');
  begin
    for var I := 1 to Level do begin
      stream.WriteString(#9);
    end;
    stream.WriteString(line + #13#10);
  end;

begin
  var Name := ExtractFileNameWithoutExt(FileName);
  stream := TStringStream.Create;
  try
  // Header
    var Header := 'program ' + Name + ';';
    WriteLine(Header);
    WriteLine;

  // Uses section
    WriteLine('uses');
    IncLevel;

    for var I := 0 to UndetectedUnits.Count-1 do begin
      var unitName := UndetectedUnits[I];
      if (I = UndetectedUnits.Count) AND (AssociatedFiles.GetCount = 0) then
        unitName := unitName + ','
      else
        unitName := unitName + ';';
      WriteLine(unitName);

    end;

    for var I := 1 to AssociatedFiles.GetCount-1 do begin
      if LowerCase(AssociatedFiles[I].Path).EndsWith('.pas') then begin
        var usedUnit := ExtractFilenameNoExt(AssociatedFiles[I].Path) + ' in ' + '''' + GetRelativeLink(FileName, AssociatedFiles[I].Path) + '''';
        if I < AssociatedFiles.GetCount-1 then
         usedUnit := usedUnit + ','
        else
          usedUnit := usedUnit + ';';
        WriteLine(usedUnit);


      end;
    end;

    DecLevel;
    WriteLine;

  // begin-end section
    WriteLine('begin');
    IncLevel;
    WriteLine;
    DecLevel;
    WriteLine('end.');

  //Save
    stream.SaveToFile(FileName);

  finally
    stream.Free;
  end;
end;

function TSyncronizer.GetLinkedPath(const path: string): string;
begin
  var CommonAssociatedPrefix := TargetPath;//ExtractCommonPrefix(AssociatedFiles);
  if not CommonAssociatedPrefix.EndsWith('\') then
    CommonAssociatedPrefix := CommonAssociatedPrefix + '\';
  var CommonSeedPrefix := ExtractCommonPrefix(SeedFiles);

  if path.StartsWith(TargetPath) then begin
  // связзаный файл
    result := StringReplace(path, CommonAssociatedPrefix, CommonSeedPrefix, [rfReplaceAll]);

  end else begin
  // исходный файл
    result := StringReplace(path, CommonSeedPrefix, CommonAssociatedPrefix, [rfReplaceAll]);
  end;
end;

procedure TSyncronizer.Syncronize;

var
  NewFile: TFile;
  Dpr: TFile;
  Dproj: TFile;
begin
  Dpr := nil;
  Dproj := nil;
  for var I := 0 to UpdatedFiles.GetCount-1 do begin
    var F := UpdatedFiles[I];
    var path := GetLinkedPath(F.Path);
    if F.AssociatedFile = nil then begin
      var IsSeedFile := not F.IsSeed;
      NewFile := TFile.Create(path, IsSeedFile);
      F.AssociatedFile := NewFile;
      if IsSeedFile then begin
        if not SeedFiles.Contains(NewFile) then
          SeedFiles.Add(NewFile);
      end else begin
        if not AssociatedFiles.Contains(NewFile) then
          AssociatedFiles.Add(NewFile);
      end;

      if IsPasFile then begin

      end else begin

        var Extension := ExtractFileExt(NewFile.Path);
        if SameText(Extension, '.dpr') then begin
          Dpr := NewFile
        end else if SameText(Extension, '.dproj') then begin
          Dproj := NewFile;
        end;

      end;


    end;
    CopyWithDir(F.Path, F.AssociatedFile.Path);

    F.Update;
    F.AssociatedFile.Update;
  end;

  if IsPasFile then begin
    var dprPath := ExtractFilePath(SeedFile) + ExtractFileNameWithoutExt(SeedFile) + '.dpr';
    dprPath := GetLinkedPath(dprPath);
    self.CreateDpr(dprPath);
    var dprojPath :=  ExtractFilePath(SeedFile) + ExtractFileNameWithoutExt(SeedFile) + '.dproj';
    dprojPath := GetLinkedPath(dprojPath);
    var dprojF := TDprojFile.Create;
    var guid: TGUID;
    CreateGUID(guid);

    if not ProjFile.IsEmpty then begin
      var searchPath := DprojFile.ConfigSettings[All][Base][SearchPath];
      var searchPathArr := SearchPath.Split([';']);
      for var I := 0 to Length(searchPathArr)-2 do begin
        var pathh := searchPathArr[I];
        pathh := CalcPath(pathh, ProjFile);
        pathh := GetRelativeLink(dprPath, pathh);
        searchPathArr[I] := pathh;
      end;
      dprojF.GenerateBasicDProj(dprojPath, guid.ToString, dprPath, string.Join(';' ,searchPathArr));
    end else begin
      dprojF.GenerateBasicDProj(dprojPath, guid.ToString, dprPath, '');
    end;
  end else begin
     if Dpr <> nil then begin
      self.UpdateDPR(Dpr.Path);
      Dpr.Update;
      Dpr.AssociatedFile.Update;
    end;

    if Dproj <> nil then begin
      DprojFile.ReLinkSearchPathTo(Dproj.Path);
      Dproj.Update;
      Dproj.AssociatedFile.Update;
    end;
  end;

  UpdatedFiles.Clear;
end;

procedure TSyncronizer.UpdateDPR(const FileName: string);
const
  DoubleSpace = '  ';
  IsUsesBlock: Boolean = False;
var
  DestStream: TStringStream;
  SourseList : TStringList;
begin
  try
    DestStream := TStringStream.Create;

    SourseList := TStringList.Create;
    SourseList.LoadFromFile(FileName);

    for var L := 0 to Pred(SourseList.Count) do begin
      var Line := SourseList.Strings[L];

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
            if LowerCase(AssociatedFiles[I].Path).EndsWith('.pas') then begin
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
    DestStream.SaveToFile(FileName);
    DestStream.Free;
    SourseList.Free;
  end;
end;

begin
{
  .dproj, .dpr, .dpk
    - Seed File
    - GroupProj File
    - Target Dir

  .pas
    - Seed File,
    - Dproj File  -- Для настройки парсинга
    - Target Dir

  .pas
    - Seed File,
    -
}
//  SeedFile := 'C:\Source\SprutCAM\NCKernel\NCKernel.dpr';
  SeedFile := 'C:\Source\SprutCAM\SprutCAM40\ComputingPart\Technology\Operations\Uni5DOp.pas';
//  SeedFile := 'C:\Source\SprutCAM\GECAD\geCADDef.pas';
  TargetPath := 'C:\TestSource\';
//  ProjFile := 'C:\Source\SprutCAM\GECAD\AVOCADO.dproj';
//  GroupProjFile := 'C:\Source\SprutCAM\SprutCAM.groupproj';

  SearchDir :=  'C:\Source\SprutCAM';


  // Этап 0: Обратока входных параметров
  var Extension := ExtractFileExt(SeedFile);//ExtractFileExt(ParamStr(1));
  IsPasFile := False;
          if SameText(Extension, '.pas') then
            IsPasFile := True;


  if ParamCount = 3 then begin
    for var I := 1 to ParamCount do begin
      case I of
        1: begin
          SeedFile := ParamStr(I);

          IsPasFile := False;
          if SameText(Extension, '.pas') then
            IsPasFile := True;

          if not FileExists(ParamStr(I)) then begin
            Writeln('Файла "' + ParamStr(I) + '" не существует');
            ReadLn;
            exit;
          end;
        end;

        2: begin
          if SameText(Extension, '.groupproj') then begin
            GroupProjFile := ParamStr(I);
            if not FileExists(ParamStr(I)) then begin
              Writeln('Файла "' + ParamStr(I) + '" не существует');
              ReadLn;
              exit;
            end;
          end else if SameTExt(Extension, '.dproj') And IsPasFile then begin
            ProjFile := ParamStr(I);
            if not FileExists(ParamStr(I)) then begin
              Writeln('Файла "' + ParamStr(I) + '" не существует');
              ReadLn;
              exit;
            end;
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

  var Scanner := TScanner.Create;

  if SameText(Extension, '.dproj') then begin
    DprojFile := TDprojFile.Create(SeedFile);
    Scanner.LoadSettings(DprojFile);
  end else if SameText(Extension, '.dpr') OR SameText(Extension, '.dpk') then begin
    var dproj := StringReplace(SeedFile, Extension, '.dproj', [rfIgnoreCase]);
    DprojFile := TDprojFile.Create(dproj);
    Scanner.LoadSettings(DprojFile);
  end else if SameText(Extension, '.pas') then begin
    if not ProjFile.IsEmpty then begin
      DprojFile := TDprojFile.Create(ProjFile);
      Scanner.LoadSettings(DprojFile);
    end else
      Scanner.FindFilesInFolder(SearchDir);
  end else
    raise Exception.Create('Файл ' + SeedFile + ' имееет недопустимое расширение');

  var Syncronizer := TSyncronizer.Create;

  while True do begin

    case Step of
      // 1 Этап: Парсинг
      stParsing: begin
        Writeln('Начало сканирования.....');

        if SameText(Extension, '.dproj') OR SameText(Extension, '.dpr') OR SameText(Extension, '.dpk') then
          Scanner.Scan(DprojFile)
        else if SameText(Extension, '.pas') then
          Scanner.Scan(SeedFile);

        Writeln('Конец Сканироания...');
        Writeln('Просканировано - ' + SeedFiles.GetCount.ToString + ' файлов.');
        Step := stCoping;
      end;

      // 2 Этап: Копирование
      stCoping: begin
        Syncronizer.Syncronize;
        Step := stUpdate;

      end;

      // 3 Этап: Синхронизация
      stUpdate: begin

        for var I := 0 to SeedFiles.GetCount-1 do begin
          var f := SeedFiles[I];
          if F.IsUpdated then begin
            Writeln(ExtractFileName(f.Path) + ' был обновлен.');
            UpdatedFiles.Add(F);
            Scanner.Scan(F.Path);
          end;
        end;

        for var I := 0 to AssociatedFiles.GetCount-1 do begin
          var f := AssociatedFiles[I];
          if F.IsUpdated then begin
            Writeln(ExtractFileName(f.Path) + ' был обновлен.');
            UpdatedFiles.Add(F);
            Scanner.Scan(F.Path);
          end;
        end;

        if UpdatedFiles.GetCount > 0 then
          Syncronizer.Syncronize;

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

