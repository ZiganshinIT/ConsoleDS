unit DSUtils;

interface

uses
  Winapi.Windows,

  Vcl.Dialogs, Vcl.StdCtrls,

  DSTypes,

  System.SysUtils, System.StrUtils, System.Math, System.Classes, System.IOUtils,
  System.Types;

  // Dialogs
//  function OpenDialog(out Path: string; PickFolder: Boolean = False; const FileType: string = ''): Boolean;
//  function SaveDialog(out Path: string; const FileType: string = ''; DefaultName: string = ''): Boolean;

  // Path opertaion
  function ExtractFileNameWithoutExt(const fn: string): string;
  function ExtractCommonPrefix(const path1, path2: string): string;             overload;
  function ExtractCommonPrefix(list: TListBox): string;                         overload;
  function GetRelativeLink(const FromFile, ToFile: string): string;
  function CalcPath(RelPath: string; AbsPath: string): string;

  function InsertPlatformPath(const Path: string; const PlatType: TPlatform): string;
  function InsertProjectName(const Path: string; const ProjectName: string): string;

  function GetDownPath(const path: string): string;


  // Copy operation
  procedure CopyWithDir(const SourceDir, DestDir: string);
  procedure CopyFolder(const SourceDir, DestDir: string);

  // Read operation
  function ReadRCFile(const FileName: string): TArray<string>;
  function ReadAndFildLocation(const DPRName: string; const FileName: string): string;

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

function GetRelativeLink(const FromFile, ToFile: string): string;
/// ��������� ������������� ���� �� FromFile �� ToFile
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
/// ��������� ��������� ���� �� � RelPath
var
  path: string;
begin
  // �������� ���� �� unit �����
  var Path1Parts := SplitString(ExtractFileDir(AbsPath), PathDelim);
  // �������� ���� �� �������� ����� (�������������)
  var Path2Parts := SplitString(RelPath, PathDelim);

  for var part in Path2Parts do begin
    if SameText(part, '..') then begin
      SetLength(Path1Parts, Length(Path1Parts)-1)
    end else begin
      // ������������� ����
      if part.StartsWith('*.') then
        path := ExtractFileNameWithoutExt(AbsPath) + ExtractFileExt(part)
      else
        path := part;

      Path1Parts := Path1Parts + [path];
    end;
  end;

  result := string.Join(PathDelim, Path1Parts);
end;

function InsertPlatformPath(const Path: string; const PlatType: TPlatform): string;
/// �������� ${Platform} �� ��� ������� ���������
begin
  result := StringReplace(Path, '$(Platform)', PlatType.GetPlatformAsStr, [rfReplaceAll, rfIgnoreCase]);
end;

function InsertProjectName(const Path: string; const ProjectName: string): string;
/// �������� $(MSBuildProjectName) �� ��� ������� ���������
begin
  result := StringReplace(Path, '$(MSBuildProjectName)', ProjectName, [rfReplaceAll, rfIgnoreCase]);
end;

function GetDownPath(const path: string): string;
// ����������� ���������� ����� ��� ��������� ������������ ���������
begin
  var PathParts := SplitString(path, PathDelim);
  SetLength(PathParts, Length(PathParts)-1);
  result := string.Join('\', PathParts);
end;

{ Copy operation}

procedure CopyWithDir(const SourceDir, DestDir: string);
begin
  ForceDirectories(ExtractFileDir(DestDir));
  CopyFile(PChar(SourceDir), PChar(DestDir), True);
end;

procedure CopyFolder(const SourceDir, DestDir: string);
var
  Files: TStringDynArray;
  SourceFile, DestFile: string;
  i: Integer;
begin
  if not TDirectory.Exists(DestDir) then
    TDirectory.CreateDirectory(DestDir);

  Files := TDirectory.GetFiles(SourceDir);
  for i := 0 to Length(Files) - 1 do
  begin
    SourceFile := Files[i];
    DestFile := TPath.Combine(DestDir, TPath.GetFileName(SourceFile));
    TFile.Copy(SourceFile, DestFile, True);
  end;

  for var SubDir in TDirectory.GetDirectories(SourceDir) do
    CopyFolder(SubDir, TPath.Combine(DestDir, TPath.GetFileName(SubDir)));
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
    // ��������� ���� ��� ������
    FileStream := TFileStream.Create(FileName, fmOpenRead);
    try
      // ������� ������ TStreamReader ��� ������ �� �����
      StreamReader := TStreamReader.Create(FileStream);
      try
        // ������ ���� ��������� � ������� ������ ������
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
      Writeln('������ ��� �������� ����� .rc: ', E.Message);
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
    // ��������� ���� ��� ������
    FileStream := TFileStream.Create(DPRName, fmOpenRead);
    try
      // ������� ������ TStreamReader ��� ������ �� �����
      StreamReader := TStreamReader.Create(FileStream);
      try
        // ������ ���� ��������� � ������� ������ ������
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
      Writeln('������ ��� �������� ����� .rc: ', E.Message);
  end;
end;


end.
