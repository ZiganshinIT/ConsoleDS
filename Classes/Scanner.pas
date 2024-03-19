unit Scanner;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Classes, System.Types,
  System.IOUtils,

  Duds.Common.Parser.Pascal, Duds.Common.Interfaces,

  DSUtils;


type
  TScanThread = class(TThread)
  private
    FList: TStringList;
    FAddItem: string;

    FSearchPath: string;
    FSeedFile: string;

    FPasFiles:   TDictionary<string, string>;
    FDcuFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;

    FUsedFiles:   TStringList;
    FIgnoreFiles: TStringList;

    FFinished: Boolean;

    // <имя юнита | проект, в котором объявляется>
    FUnitLocation: TDictionary<string, string>;

    FPascalUnitExtractor: TPascalUnitExtractor;
  protected
   procedure Execute; override;

    procedure FindFilesInFolder(const Folder: string);

    procedure AddOtherFiles(const UnitPath: string; var UnitInfo: IUnitInfo);
    function AddFileWithExt(const filename, ext: string): string;

    function TryAddFile(const FilePath: string): Boolean;

    procedure DoScan(const FilePath: string);

    procedure DoScanUnit(const UnitPath: string);
    procedure DoScanRCFiles(const RCFilePath: string);

    procedure UpdateUI;
  public

    constructor Create(var List: TStringList; const SearchPath, SeedFile: string); overload;
    destructor Destroy;                                                            overload;
    property Finished: Boolean read FFinished;
  end;

implementation

{ TScanThread }

function TScanThread.AddFileWithExt(const filename, ext: string): string;
/// Добавление файла с измененным расширением
begin
  result := ExtractFilePath(filename)+ExtractFileNameWithoutExt(filename)+ext;
  TryAddFile(result);
end;

procedure TScanThread.AddOtherFiles(const UnitPath: string;
  var UnitInfo: IUnitInfo);
var
  path: string;
begin
  for var Arr in UnitInfo.OtherUsedItems.Values do begin
//    if Terminated then begin
//      Exit;
//    end;

    for var Value in Arr do begin
//      if Terminated then begin
//        Exit;
//      end;

      path := CalcPath(Value, UnitPath);

      if FileExists(path) then begin
        TryAddFile(path);
      end;

    end;
  end;
end;

constructor TScanThread.Create(var List: TStringList; const SearchPath, SeedFile: string);
begin
  inherited Create(False);
  FFinished := False;

  FList := List;
  FSearchPath := SearchPath;
  FSeedFile := SeedFile;

  FPasFiles     :=   TDictionary<string, string>.Create;
  FDcuFiles     :=   TDictionary<string, string>.Create;
  FDprojFiles   :=   TDictionary<string, string>.Create;

  FUsedFiles    :=   TStringList.Create;
  FIgnoreFiles  :=   TStringList.Create;

  FUnitLocation := TDictionary<string, string>.Create;

  FPascalUnitExtractor := TPascalUnitExtractor.Create(nil);
end;

destructor TScanThread.Destroy;
begin
  inherited;
  FreeAndNil(fPasFiles);
  FreeAndNil(fDcuFiles);
  FreeAndNil(fDprojFiles);
  FreeAndNil(fUsedFiles);
  FreeAndNil(FIgnoreFiles);
  FreeAndNil(fUnitLocation);
  FreeAndNil(FPascalUnitExtractor);
end;

procedure TScanThread.DoScan(const FilePath: string);
var
  UnitInfo: IUnitInfo;
const
  DprExt = '.dpr';
  PasExt = '.pas';
  RCExt = '.rc';
begin
  var Extension := ExtractFileExt(FilePath);

  if SameText(LowerCase(Extension), LowerCase(PasExt)) OR SameText(LowerCase(Extension), LowerCase(DprExt)) then begin
    self.DoScanUnit(FilePath);
  end else if SameText(LowerCase(Extension), LowerCase(RCExt)) then begin
    self.DoScanRCFiles(FilePath);
  end;

end;

procedure TScanThread.DoScanRCFiles(const RCFilePath: string);
  /// Добавляем файлы, перечисленные в RC-файле
begin
  if FileExists(RCFilePath) then begin
    var files := ReadRCFile(RCFilePath);
    for var f in files do begin
      var InnerFilePath := CalcPath(f, RCFilePath);
      TryAddFile(InnerFilePath)
    end;
  end else
    raise Exception.Create(RCFilePath + ' не существует')
end;

procedure TScanThread.DoScanUnit(const UnitPath: string);
var
  UnitInfo: IUnitInfo;
  Parsed: Boolean;
  pas: string;
  index: Integer;
begin
  Parsed := FPascalUnitExtractor.GetUsedUnits(UnitPath, UnitInfo);
  if Parsed then begin

    // Add other files
    if UnitInfo.OtherUsedItems.Count > 0 then begin
      AddOtherFiles(UnitPath, UnitInfo);
    end;

    for var un in UnitInfo.UsedUnits do begin

      if (UnitPath.EndsWith('.dpr')) AND (un.InFilePosition = 0) then begin
        continue;
      end;

      // Add unit files, mostly .pas files
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

  TryAddFile(FSeedFile);
//
  if SameText(ExtractFileExt(FSeedFile), '.dpr') then begin
    AddFileWithExt(FSeedFile, '.dproj');
    AddFileWithExt(FSeedFile, '._icon.ico');
  end;

  FindFilesInFolder(FSearchPath);

  var i := 0;
  while i<fUsedFiles.Count do begin
    DoScan(fUsedFiles[i]);
    inc(i);
  end;

  FFinished := True;

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
        fPasFiles.AddOrSetValue(ExtractFileName(FileName), FileName);
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

function TScanThread.TryAddFile(const FilePath: string): Boolean;
begin
  result := False;
  if FileExists(FilePath) AND (fUsedFiles.IndexOf(ExtractFileName(FilePath)) = -1) then begin
    result := True;
    fUsedFiles.Add(FilePath);
    FAddItem := FilePath;
    Synchronize(UpdateUI);
  end;
end;

procedure TScanThread.UpdateUI;
begin
  FList.Add(FAddItem);
end;


end.
