program ConsoleDS;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils,
  Registry,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.Threading,
  System.Generics.Collections,
  System.SyncObjs,
  System.RegularExpressions,
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
  FileClass in '..\Utils\FileClass.pas',
  DSScanner in '..\Utils\DSScanner.pas',
  DSThreads in '..\Utils\DSThreads.pas',
  DSConst in '..\Utils\DSConst.pas',
  DSDprojTypes in '..\Utils\DSDprojTypes.pas',
  DSCacher in '..\Utils\DSCacher.pas';

var
  {Параметры}
  TargetPath    : string;
  GroupProjFile : string;
  WithCopy      : Boolean;
  BATLocation   : string;

  {Основыне файлы}
  SeedDprojFile: TDprojFile;
  SeedDprFile: TDprFile;

  NewDprojFile: TDprojFile;
  NewDprFile:  TDprFile;

  DpkFile: TDpkFile;

  FileType: TFileType;
  FileList: TStringList;

  SeedFiles: TArray<string>;

  Scanner: TScanner;

  NeedGroupProj: Boolean;
  GroupProj: TGroupProjFile;

procedure ShowHelp;
begin
  Writeln('Вспомогательная информация')
end;

begin

  var Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER; // Вы можете выбрать другой корневой ключ, если необходимо
    if Reg.OpenKey('\Software\ConsoleDS', True) then
    begin
      Reg.WriteString('Path', ParamStr(0)); // Замените на актуальный путь
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

  {Проверка параметров}
  case ParamCount of

    0, 1: begin
      if (ParamCount = 0) OR (ParamStr(1) = '?') then begin
        ShowHelp;
        Readln;
      end;
      exit;
    end;

    2..3: begin
      Writeln('Переданно недостаточно параметров');
      Readln;
      exit;
    end;

    5: begin
      {Параметр 5}
      BATLocation := ParamStr(5);

      {Параметр 1}
      SeedFiles := ParamStr(1).Split([';']);

      NeedGroupProj := Length(SeedFiles) > 1;

      for var I := 0 to Pred(Length(SeedFiles)) do begin

        if IsRelativePath(SeedFiles[I]) then
          SeedFiles[I] := CalcPath(SeedFiles[I], BATLocation);

        var sd := SeedFiles[I];

        if FileExists(sd) then begin
          FileType := GetFileType(sd);
          if FileType = ftUndefined then begin
            Writeln('Недопустимый файл');
            Readln;
            exit;
          end;
        end else
          Writeln('Файла ' + sd + ' не существует');

      end;

      {Параметр 2}
      TargetPath := ParamStr(2);

      if IsRelativePath(TargetPath) then
        TargetPath := CalcPath(TargetPath, BATLocation)
      else if SameText(TargetPath, '\') then
        TargetPath := BATLocation;



      if not TRegEx.IsMatch(TargetPath, PathRegex) then begin
        Writeln('Параметр ' + TargetPath + ' не является путем');
        Readln;
        exit;
      end;

      {Параметр 3}
      GroupProjFile := ParamStr(3);

      if IsRelativePath(GroupProjFile) then
        GroupProjFile := CalcPath(GroupProjFile, BATLocation);

      if not FileExists(GroupProjFile) then begin
        WriteLn('Файла ' + GroupProjFile + ' не существует');
        Readln;
        exit;
      end;
      if not SameText(ExtractFileExt(GroupProjFile), '.groupproj') then begin
        WriteLn('Файла ' + GroupProjFile + ' не соответвует расширению .groupproj');
        Readln;
        exit;
      end;

      {Параметр 4}
      WithCopy := ParamStr(4).ToBoolean;
    end;

    else begin
      Writeln('Переданно слишком много параметров');
      Readln;
      exit;
    end;

  end;

  var InputThread := TInputThread.Create(True);
  InputThread.FreeOnTerminate := True;
  InputThread.Start;

  var GroupProjPath := TargetPath + ExtractFileName(GroupProjFile);
  if NeedGroupProj then begin
    GroupProj := TGroupProjFile.Create(GroupProjPath);
  end;

  Scanner := TScanner.Create(GroupProjFile);

  for var sd in SeedFiles do begin
  FileType := GetFileType(sd);

  case FileType of
    ftDproj: begin
      SeedDprojFile := TDprojFile.Create(sd);
      Scanner.LoadSettings(SeedDprojFile);
      var Dpr := StringReplace(sd, '.dproj', '.dpr', [rfIgnoreCase]);
      if FileExists(Dpr) then
        SeedDprFile := TDprFile.Create(Dpr)
      else begin
        Writeln('Не найдет DPR файл');
        Readln;
        exit;
      end;
    end;
    ftDpr: begin
      SeedDprFile := TDprFile.Create(sd);
      var DprojPath := StringReplace(sd, '.dpr', '.dproj', [rfIgnoreCase]);
      if FileExists(DprojPath) then begin
        SeedDprojFile := TDprojFile.Create(DprojPath);
        Scanner.LoadSettings(SeedDprojFile);
      end else begin
        Writeln('Не найдет Dproj файл');
        Readln;
        exit;
      end;
    end;
    ftPas: begin
      var ProjFile := FindPasInGroupProj(sd, GroupProjFile);
      if (not ProjFile.IsEmpty) AND FileExists(ProjFile) then begin
        SeedDprojFile := TDprojFile.Create(ProjFile);
        Scanner.LoadSettings(SeedDprojFile);
      end else begin
        Writeln('Файл не найдет в группе проектов');
        Readln;
        exit;
      end;
    end;
    ftUndefined: begin
      Writeln('Недопустимый файл');
      Readln;
      exit;
    end;
  end;

  Writeln('Начало сканирования.....');
  case FileType of
    ftDproj, ftDpr:
      Scanner.Scan(SeedDprojFile);
    ftPas: begin
      Scanner.Scan(sd);
    end;

  end;
  Scanner.GetResultArrays(FileList);
  Writeln('Конец Сканироания...');

  Writeln('Начало копирования...');

  var Prefix := ExtractCommonPrefix(FileList);   // Вычисляем префикс исходный файлов

  if FileType = ftPas then
      FileList.Delete(0);

  if WithCopy then begin

    for var Index := 0 to Pred(FileList.Count) do begin
      var F := FileList[Index];
      if ExtractFilePath(F) <> '' then begin
        var NewPath := StringReplace(F, Prefix, TargetPath, [rfIgnoreCase]);
        CopyWithDir(PChar(F), PChar(NewPath));
        FileList[Index] := NewPath;
      end;
    end;
  end;

  {Создаем новый Dproj файл}
  var NewDprojPath := StringReplace(sd, Prefix, TargetPath, [rfIgnoreCase]);
  NewDprojPath := StringReplace(NewDprojPath, ExtractFileExt(sd), '.dproj', [rfIgnoreCase]);

  if (SeedDprojFile <> nil) and (FileType <> ftPas) then begin
    NewDprojFile := SeedDprojFile.Copy(NewDprojPath);
  end else if FileType = ftPas then begin
    NewDprojFile := TDprojFile.Create(NewDprojPath);
    NewDprojFile.LoadSettingsFrom(SeedDprojFile);
  end;
  NewDprojFile.SaveFile;

  if NeedGroupProj then begin
    GroupProj.AddProject(GetRelativeLink(GroupProjPath, NewDprojPath));
  end;


  {Создаем новый Dpr файл}
  var NewDprPath := StringReplace(sd, Prefix, TargetPath, [rfIgnoreCase]);
  NewDprPath := StringReplace(NewDprPath, ExtractFileExt(sd), '.dpr', [rfIgnoreCase]);

  NewDprFile := TDPRFile.Create(NewDprPath);
  NewDprFile.BuildBaseStructure;
  if SeedDprFile <> nil then begin
    NewDprFile.LoadStructure(SeedDprFile)
  end;
  NewDprFile.Assign(NewDprojFile);
  NewDprFile.UpdateResources(SeedDprojFile);
  NewDprFile.UpdateUses(FileList);
  NewDprFile.SaveFile;

  Writeln('Конец копирования...');

  FreeAndNil(SeedDprojFile);
  FreeAndNil(SeedDprFile);
  FreeAndNil(NewDprojFile);
  FreeAndNil(NewDprFile);
  FileList.clear;


  end;

  if NeedGroupProj then begin
    GroupProj.SaveFile;
  end;

  FreeAndNil(SeedDprojFile);
  FreeAndNil(SeedDprFile);
  FreeAndNil(NewDprojFile);
  FreeAndNil(NewDprFile);

  Scanner.Destroy;

end.

