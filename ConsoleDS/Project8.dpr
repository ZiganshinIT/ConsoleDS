program Project8;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Types,
  System.IOUtils,
  System.Threading,

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

var
  SearchPath: string;
  SeedFile: string;
  TargetPath: string;

  List: TStringList;

  ExitFlag: Boolean;

type
  TScanThread = class(TThread)
  private
    FList: TStringList;
    FAddItem: string;

    FPasFiles:   TDictionary<string, string>;
    FDcuFiles:   TDictionary<string, string>;
    FDprojFiles: TDictionary<string, string>;

    FUsedFiles:   TStringList;
    FIgnoreFiles: TStringList;

    // <имя юнита, проект, в котором объявляется>
    FUnitLocation: TDictionary<string, string>;

    FPascalUnitExtractor: TPascalUnitExtractor;
  protected
    procedure Execute; override;

    procedure FindFilesInFolder(const Folder: string);

    function AddFileWithExt(const filename, ext: string): string;

    function TryAddFile(const FilePath: string): Boolean;

    procedure UpdateUI;
  public
    constructor Create;
    destructor Destroy;
  end;

procedure MainThread;
begin
  // Основная работа приложения
  while not ExitFlag do
  begin
    // Выполнение основной работы
    Writeln('Основная работа приложения...');

    for var I := 0 to Pred(List.Count) do begin
      Writeln(List[I]);
    end;

    Sleep(1000); // Задержка в 1 секунду
  end;
end;

{ TScanThread }

function TScanThread.AddFileWithExt(const filename, ext: string): string;
/// Добавление файла с измененным расширением
begin
  result := ExtractFilePath(filename)+ExtractFileNameWithoutExt(filename)+ext;
  TryAddFile(result);
end;

constructor TScanThread.Create;
begin
  inherited Create(False);

  FList := List;

  FPasFiles     :=   TDictionary<string, string>.Create;
  FDcuFiles     :=   TDictionary<string, string>.Create;
  FDprojFiles   :=   TDictionary<string, string>.Create;

  FUsedFiles    :=   TStringList.Create;
  FIgnoreFiles  :=   TStringList.Create;

  FUnitLocation := TDictionary<string, string>.Create;
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

procedure TScanThread.Execute;
begin
  inherited;

  TryAddFile(SeedFile);

  if SameText(ExtractFileExt(SeedFile), '.dpr') then begin
    AddFileWithExt(SeedFile, '.dproj');
    AddFileWithExt(SeedFile, '._icon.ico');
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
    UpdateUI;
  end;
end;

procedure ConsoleInputThread;
var
  InputChar: Char;
begin
  repeat
    // Считываем символ с консоли
    Read(InputChar);
    // Проверяем, был ли введен символ для завершения
    if InputChar = 'q' then
    begin
      ExitFlag := True;
      Break;
    end;
  until False;
end;

procedure TScanThread.UpdateUI;
begin
  FList.Add(FAddItem);
end;

begin
  List := TStringList.Create;

  SearchPath := 'C:\Source\SprutCAM';
  SeedFile   := 'C:\Source\SprutCAM\NCKernel\NCKernel.dpr';
  TargetPath := 'C:\TestSource';


  try
    // Устанавливаем флаг завершения в false
    ExitFlag := False;

    // Запускаем поток для чтения ввода с консоли
    TTask.Run(ConsoleInputThread);

    var T := TScanThread.Create;
    // Запускаем основной поток
    MainThread;
  except
    on E: Exception do
      Writeln('Ошибка: ', E.Message);
  end;




end.
