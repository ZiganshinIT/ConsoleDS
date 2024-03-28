unit DSScanner;

{$R ../Resources/DSres.RES}

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  System.IOUtils,

  Duds.Common.Parser.Pascal,
  Duds.Common.Interfaces,

  DSTypes, DSUtils, FileClass, DSConst;

type

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

    procedure GetResultArrays(out DetectedFiles: TStringList);

    destructor Destroy;
  end;

implementation

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
  var Param := ParamStr(3);

  FPasFiles     :=   TDictionary<string, string>.Create;
  FDcuFiles     :=   TDictionary<string, string>.Create;

  if SameText(ExtractFileExt(Param), '.groupproj') AND FileExists(Param) then
    FDprojFiles   :=   ParseUsedProject(Param);

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

        if (Length(Words) > 1) AND (Line.Contains('''')) then begin
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

procedure TScanner.GetResultArrays(out DetectedFiles: TStringList);
begin
  DetectedFiles := FUsedFiles;
end;

{Опеределяет настройки сканера}
procedure TScanner.LoadSettings(const DprojFile: TDprojFile);
begin
   { Добавляет доступные define проекта }
    FPascalUnitExtractor.DefineAnalizator.EnableDefines := DprojFile.GetDefinies([All, Win64], [Base, Cfg_2]);
    FPascalUnitExtractor.DefineAnalizator.EnableDefines := FPascalUnitExtractor.DefineAnalizator.EnableDefines + ['MSWINDOWS'];

   {Формируем массив файлов, которые нужно проигнорировать}
   AddIngoreFilesFromResource;
   AddIgnoreFiles(DprojFile.GetDebuggerSourcePath(Win64, Cfg_2));
   AddIgnoreFile('SVG2Png');

  {Формируем словарь юнитов проекта и пути к ним}
  FindFilesFromProject(DprojFile.Path);
  var SearchPaths := DprojFile.GetSearchPath(All, Base);
  for var SearchPath in SearchPaths do begin

    // Dcu
      var Path := CalcPath(SearchPath, DprojFile.Path);
      Path := StringReplace(Path, '$(Platform)', DprojFile.MainSettings.FPlatform.GetPlatformAsStr, [rfIgnoreCase]);

      var FoundFiles: TStringDynArray;
      var FileName: string;

      if DirectoryExists(Path) then begin
        FoundFiles := TDirectory.GetFiles(Path, '*.dcu', TSearchOption.soAllDirectories);
        for FileName in FoundFiles do
        begin
          if not fDcuFiles.ContainsKey(ExtractFileName(FileName))then begin
            fDcuFiles.AddOrSetValue(LowerCase(ExtractFileName(FileName)), FileName);
          end;
        end;
      end;


    // Pas
    var PathParts := SearchPath.Split(['\']);
    var ProjectName := PathParts[Length(PathParts)-1];
    if SameText(ProjectName, 'dcu') then begin
      for var Proj in FDprojFiles.Values do begin
        FindFilesFromProject(CalcPath(Proj, ParamStr(3)));
      end;
    end;
    var ProjectPath: string;
    if FDprojFiles.TryGetValue(LowerCase(ProjectName), ProjectPath) then begin
      ProjectPath := CalcPath(ProjectPath, ParamStr(3));
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
begin
  var I := 0;
  while I < FUsedFiles.Count do begin
    if IsEscPressed then
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

end.
