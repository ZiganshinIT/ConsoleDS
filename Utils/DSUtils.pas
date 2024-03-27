unit DSUtils;

interface

uses
  Winapi.Windows,

  Vcl.Dialogs, Vcl.StdCtrls,

  System.SysUtils, System.StrUtils, System.Math, System.Classes, System.IOUtils,
  System.Types, System.Generics.Collections,

  XMLDoc, XMLIntf;

type
  TFileType =
  (
    ftPas,
    ftDproj,
    ftDpr,
    ftDpk,
    ftUndefined
  );

  // Path opertaion
  function ExtractFileNameWithoutExt(const fn: string): string;
  function ExtractCommonPrefix(const path1, path2: string): string;             overload;
  function ExtractCommonPrefix(list: TListBox): string;                         overload;
  function ExtractCommonPrefix(list: TStringList): string;                      overload;
//  function ExtractCommonPrefix(list: array of TFile): string;                   overload;
//  function ExtractCommonPrefix(list: TFileArray): string;                       overload;
  function GetRelativeLink(const FromFile, ToFile: string): string;
  function CalcPath(RelPath: string; AbsPath: string): string;

//  function InsertPlatformPath(const Path: string; const PlatType: TPlatform): string;
//  function InsertProjectName(const Path: string; const ProjectName: string): string;

  function GetDownPath(const path: string): string;

  function ReplacePathExtension(const Path, NewExtension: string): string;

  // Copy operation
  procedure CopyWithDir(const SourceDir, DestDir: string);

  // Read operation
  function ReadRCFile(const FileName: string): TArray<string>;
  function ReadAndFildLocation(const DPRName: string; const FileName: string): string;

  // Dproj opertaion
  function GetUnitDeclaration(const DprojPath, UnitName: string): string;

  // Compare operation
  function IsSimilarity(const str1, str2: string): Boolean;

  // GroupProj file operation
  function ParseUsedProject(const GroupProjFile: string): TDictionary<string, string>;

  function GetFileType(const FilePath: string): TFileType;

implementation

{ Dialogs }
function OpenDialog(out Path: string; PickFolder: Boolean = False; const FileType: string = ''): Boolean;
var
  OD: TFileOpenDialog;
begin
  result := False;
  OD := TFileOpenDialog.Create(nil);
  if FileType <> '' then begin
    with OD.FileTypes.Add do begin
      DisplayName := UpperCase(FileType) + ' Files';
      FileMask    := '*.' + LowerCase(FileType);
    end;
  end;
  if PickFolder then
    OD.Options := [fdoPickFolders];
  if OD.Execute then begin
    result := True;
    Path := OD.FileName;
  end;
  OD.Free;
end;

function SaveDialog(out Path: string; const FileType: string = ''; DefaultName: string = ''): Boolean;
var
  SD: TFileSaveDialog;
  da: integer;
begin
  result := False;
  SD := TFileSaveDialog.Create(nil);
  if FileType <> '' then begin
    with SD.FileTypes.Add do begin
      DisplayName := UpperCase(FileType) + ' Files';
      FileMask    := '*.' + LowerCase(FileType);
    end;
  end;
  if DefaultName <> '' then
    SD.FileName := DefaultName;
  if SD.Execute then
    result := True;
    path := SD.FileName;
    if not path.EndsWith('.'+LowerCase(FileType)) then begin
      path := path + '.'+LowerCase(FileType);
    end;
  SD.Free;
end;


{ Path operation }

function ExtractFileNameWithoutExt(const fn: string): string;
begin
  result := ExtractFileName(fn);
  var ext := ExtractFileExt(fn);
  result := LowerCase(result.Substring(0, Length(result)-Length(ext)));
end;

function ExtractCommonPrefix(const Path1, Path2: string): string;
begin
  var Path1Parts := SplitString(ExtractFileDir(Path1), PathDelim);
  var Path2Parts := SplitString(ExtractFileDir(Path2), PathDelim);

  var MinParts := Min(Length(Path1Parts), Length(Path2Parts));

  Result := '';
  for var I := 0 to MinParts - 1 do begin
    if SameText(Path1Parts[I], Path2Parts[I]) then
      Result := Result + Path1Parts[I] + PathDelim
    else
      Break;
  end;
end;

function ExtractCommonPrefix(list: TListBox): string;
begin
  result := '';
  for var Item in list.Items do begin
    if result = '' then begin
      result := Item;
      continue;
    end else begin
      result := ExtractCommonPrefix(result, Item);
    end;
  end;
end;

function ExtractCommonPrefix(list: TStringList): string;
begin
  result := '';
  for var Value in list do begin
    if result.IsEmpty then begin
      result := Value;
    end else begin
      result := ExtractCommonPrefix(result, Value);
    end;
  end;
end;

//function ExtractCommonPrefix(list: array of TFile): string;
//begin
//  result := '';
//  for var Value in list do begin
//    if result.IsEmpty then begin
//      result := Value.Path;
//    end else begin
//      result := ExtractCommonPrefix(result, Value.Path);
//    end;
//  end;
//end;

//function ExtractCommonPrefix(list: TFileArray): string;
//begin
//  result := '';
//  for var I := 0 to List.GetCount - 1 do begin
//    if result.IsEmpty then begin
//      result := List[I].Path;
//    end else begin
//      result := ExtractCommonPrefix(result, List[I].Path);
//    end;
//  end;
//end;

function GetRelativeLink(const FromFile, ToFile: string): string;
/// Формирует относительный путь от FromFile до ToFile
var
  path: TStringBuilder;
begin
  var CommonPrefix := ExtractCommonPrefix(FromFile, ToFile);

  var OriginalPath := StringReplace(ExtractFilePath(FromFile), CommonPrefix, '', [rfReplaceAll, rfIgnoreCase]);
  var TargetPath   := StringReplace(ExtractFilePath(ToFile), CommonPrefix, '', [rfReplaceAll, rfIgnoreCase]);

  path := TStringBuilder.Create;
  for var I := 1 to Length(OriginalPath.Split(['\']))-1 do begin
    path.Append('..\');
  end;
  path.Append(TargetPath);
  result := path.ToString + ExtractFileName(ToFile);
  FreeAndNil(path);
end;

function CalcPath(RelPath: string; AbsPath: string): string;
/// Вычисляет абсоютный путь от к RelPath
var
  path: string;
begin
  // Элементы пути до unit файла
  var Path1Parts := SplitString(ExtractFileDir(AbsPath), PathDelim);
  // Элементы пути до целевого файла (относительный)
  var Path2Parts := SplitString(RelPath, PathDelim);

  for var part in Path2Parts do begin
    if SameText(part, '..') then begin
      SetLength(Path1Parts, Length(Path1Parts)-1)
    end else begin
      // соответвующий файл
      if part.StartsWith('*.') then
        path := ExtractFileNameWithoutExt(AbsPath) + ExtractFileExt(part)
      else
        path := part;

      Path1Parts := Path1Parts + [path];
    end;
  end;

  result := string.Join(PathDelim, Path1Parts);
end;

//function InsertPlatformPath(const Path: string; const PlatType: TPlatform): string;
///// Заменяет ${Platform} на имя текущей платформы
//begin
//  result := StringReplace(Path, '$(Platform)', PlatType.GetPlatformAsStr, [rfReplaceAll, rfIgnoreCase]);
//end;

function InsertProjectName(const Path: string; const ProjectName: string): string;
/// Заменяет $(MSBuildProjectName) на имя текущей платформы
begin
  result := StringReplace(Path, '$(MSBuildProjectName)', ProjectName, [rfReplaceAll, rfIgnoreCase]);
end;

function GetDownPath(const path: string): string;
// возвращется директорию файла или возвращет родительскую диреторию
begin
  var PathParts := SplitString(path, PathDelim);
  SetLength(PathParts, Length(PathParts)-1);
  result := string.Join('\', PathParts);
end;

function ReplacePathExtension(const Path, NewExtension: string): string;
begin
  result := StringReplace(Path, ExtractFileExt(Path), NewExtension, [rfIgnoreCase]);
end;

{ Copy operation}

procedure CopyWithDir(const SourceDir, DestDir: string);
begin
  ForceDirectories(ExtractFileDir(DestDir));
  CopyFile(PChar(SourceDir), PChar(DestDir), False);
end;

{ Read Operation}

function ReadRCFile(const FileName: string): TArray<string>;
var
  FileStream: TFileStream;
  StreamReader: TStreamReader;
  Line: string;
  Words: TArray<string>;
begin
  try
    // Открываем файл для чтения
    FileStream := TFileStream.Create(FileName, fmOpenRead);
    try
      // Создаем объект TStreamReader для чтения из файла
      StreamReader := TStreamReader.Create(FileStream);
      try
        // Читаем файл построчно и выводим каждую строку
        while not StreamReader.EndOfStream do
        begin
          Line := StreamReader.ReadLine;
          Line := Line.Trim;
          if not Line.IsEmpty then begin
            Words := Line.Split([' ']);

            result := result + [Words[Length(Words)-1].Trim(['"'])];
          end;
        end;
      finally
        StreamReader.Free;
      end;
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
      Writeln('Ошибка при открытии файла .rc: ', E.Message);
  end;
end;

function ReadAndFildLocation(const DPRName: string; const FileName: string): string;
var
  FileStream: TFileStream;
  StreamReader: TStreamReader;
  Line: string;
  Words: TArray<string>;
begin
  try
    // Открываем файл для чтения
    FileStream := TFileStream.Create(DPRName, fmOpenRead);
    try
      // Создаем объект TStreamReader для чтения из файла
      StreamReader := TStreamReader.Create(FileStream);
      try
        // Читаем файл построчно и выводим каждую строку
        while not StreamReader.EndOfStream do
        begin
          Line := StreamReader.ReadLine;
          Line := Line.Trim;
          if not Line.IsEmpty then begin
            Words := Line.Split([' ']);
            if SameText(Words[0], FileName) then
              if Length(Words) > 1 then begin
                var res := Words[2].Trim(['"', '''', ' ', ',', ';']);
                result := res;
              end
          end;
        end;
      finally
        StreamReader.Free;
      end;
    finally
      FileStream.Free;
    end;
  except
    on E: Exception do
      Writeln('Ошибка при открытии файла .rc: ', E.Message);
  end;
end;

{ Dproj Operation }
function GetUnitDeclaration(const DprojPath, UnitName: string): string;
var
  XMLDoc: IXMLDocument;
  RootNode, ItemGroupNode: IXMLNode;
begin
  result := '';
  try
    XMLDoc := TXMLDocument.Create(nil);
    XMLDoc.LoadFromFile(DprojPath);

    // Найти корневой элемент проекта
    RootNode := XMLDoc.DocumentElement;
    ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
    if Assigned(ItemGroupNode) then begin
      for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
        var node := ItemGroupNode.ChildNodes.Get(I);
        if node.LocalName = 'DCCReference' then begin
          var path := node.Attributes['Include'];
          if ExtractFileNameWithoutExt(path) = UnitName then
            exit(path);
        end
      end;
    end;
  finally
    XMLDoc := nil;
  end;
end;

// Compare operation
function IsSimilarity(const str1, str2: string): Boolean;
begin
  var stdWords := str1.Split(['.']);
  var duWords := str2.Split(['.']);

  var count := 0;
  for var stdword in stdWords do begin
    for var duWord in duWords do begin
      if SameText(stdWord, duWord) then
        Inc(count);
    end;
  end;

  if count > 0 then
    result := True;
  end;

// GroupProj file operation
function ParseUsedProject(const GroupProjFile: string): TDictionary<string, string>;
var
  XMLDoc: IXMLDocument;
  RootNode, ItemGroupNode: IXMLNode;
begin
  result := TDictionary<string, string>.Create;
  try
    XMLDoc := TXMLDocument.Create(nil);
    XMLDoc.LoadFromFile(GroupProjFile);
    RootNode := XMLDoc.DocumentElement;
    ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
    if Assigned(ItemGroupNode) then begin
      for var I := 0 to Pred(ItemGroupNode.ChildNodes.Count) do begin
        var Node := ItemGroupNode.ChildNodes.Get(I);
        if Node.NodeName = 'Projects' then begin
          var Path := Node.Attributes['Include'];
          result.Add(LowerCase(ExtractFileNameWithoutExt(Path)), Path);
        end;
      end;
    end;

  finally
    XMLDoc := nil;
  end;

end;

function GetFileType(const FilePath: string): TFileType;
var
  Extension: string;
begin
  result := ftUndefined;
  if not FilePath.IsEmpty then begin
    Extension := ExtractFileExt(FilePath);
    if SameText(Extension, '.dproj') then
      result := ftDproj
    else if SameText(Extension, '.dpr') then
      result := ftDpr
    else if SameText(Extension, '.dpk') then
      result := ftDpk
    else if SameText(Extension, '.pas') then
      result := ftPas
  end;
end;

end.
