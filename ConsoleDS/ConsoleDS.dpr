program ConsoleDS;

{$APPTYPE CONSOLE}

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
  DSConst in '..\Utils\DSConst.pas';

var
  {Параметры}
//  SeedFile      : string;
  TargetPath    : string;
  GroupProjFile : string;
  WithCopy      : Boolean;

  {Основыне файлы}
  SeedDprojFile: TDprojFile;
  SeedDprFile: TDprFile;

  NewDprojFile: TDprojFile;
  NewDprFile:  TDprFile;

  FileType: TFileType;
  FileList: TStringList;

  SeedFiles: TArray<string>;

  Scanner: TScanner;

procedure ShowHelp;
begin
  Writeln('Вспомогательная информация')
end;

begin

  {Проверка параметров}
  case ParamCount of

    0, 1: begin
      if (ParamCount = 0) OR (ParamStr(1) = '?') then begin
        ShowHelp;
        Readln;
      end;
      exit;
    end;

    2, 3: begin
      Writeln('Переданно недостаточно параметров');
      Readln;
      exit;
    end;

    4: begin
      {Параметр 1}
      SeedFiles := ParamStr(1).Split([';']);

      for var sd in SeedFiles do begin

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
      if not TRegEx.IsMatch(TargetPath, PathRegex) then begin
        Writeln('Параметр ' + TargetPath + ' не является путем');
        Readln;
        exit;
      end;

      {Параметр 3}
      GroupProjFile := ParamStr(3);
      if not FileExists(ParamStr(3)) then begin
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

  for var sd in SeedFiles do begin

  if Scanner = nil then
    Scanner := TScanner.Create;
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
    ftPas:
      Scanner.Scan(sd);
  end;
  Scanner.GetResultArrays(FileList);
  Writeln('Конец Сканироания...');

  Writeln('Начало копирования...');

  var Prefix := ExtractCommonPrefix(FileList);   // Вычисляем префикс исходный файлов

  if WithCopy then begin
    if FileType = ftPas then
      FileList.Delete(0);
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

  if SeedDprojFile <> nil then begin
    NewDprojFile := SeedDprojFile.CreateCopy(NewDprojPath);
    NewDprojFile.SaveFile;
  end;

  {Создаем новый Dpr файл}
  var NewDprPath := StringReplace(sd, Prefix, TargetPath, [rfIgnoreCase]);
  NewDprPath := StringReplace(NewDprPath, ExtractFileExt(sd), '.dpr', [rfIgnoreCase]);

  NewDprFile := TDPRFile.Create(NewDprPath);
  NewDprFile.BuildBaseStructure;
  if SeedDprFile <> nil then begin
    NewDprFile.LoadStructure(SeedDprFile)
  end;

  {Обновляем пути файлов в dpr}
  NewDprFile.Assign(NewDprojFile);
  NewDprFile.UpdateResources(SeedDprojFile);

  {Обновляем пути к юнитам}
  NewDprFile.UpdateUses(FileList);
  NewDprFile.SaveFile;

  Writeln('Конец копирования...');

  FreeAndNil(SeedDprojFile);
  FreeAndNil(SeedDprFile);
  FreeAndNil(NewDprojFile);
  FreeAndNil(NewDprFile);
  FreeAndNil(Scanner);
//  FreeAndNil(FileList);

  end;

end.

