unit DSTypes;

interface

uses
  System.SysUtils, System.TypInfo, System.Classes,

  DSUtils;

type

  

  TFile = class
  private
    FAge: Integer;
    FPath: string;
    FName: string;
    FIsSeed: Boolean;
    FAssociatedFile: TFile;
    function GetFileName: string;
    procedure SetAssociatedFile(const F: TFile);
  public
    constructor Create(const FilePath: string; IsSeedFile: Boolean = False);

    property Age: Integer read FAge;
    property Path: string read FPath;
    property Name: string read GetFileName write FName;
    property AssociatedFile: TFile read FAssociatedFile write SetAssociatedFile;
    property IsSeed: Boolean read FIsSeed;

    function IsUpdated: Boolean;
    procedure Update;

    destructor Destroy;
  end;

  TFileArray = class
  private
    FArr: array of TFile;
    function GetItem(Index: Integer): TFile;
    procedure SetItem(Index: Integer; Value: TFile);
  public
    procedure Add(const f: TFile);
    procedure CreateAndAdd(const Path: string);
    function GetByName(const FileName: string): TFile;
    function Contains(const F: TFile): Boolean;
    procedure Clear;
    property Items[Index: Integer]: TFile read GetItem write SetItem; default;
    function GetCount: Integer;
  end;

  TDPRFile = class
  private
    FName: string;
    FPath: string;
    FStrings: TStringList;
  public
    constructor Create(const Path: string);
    procedure LoadBaseStructure;
    procedure LoadStructureFrom(const DPRPath: string);
    procedure UpdateUses(const UsedFiles: TStringList);
    procedure SaveToFile(const Path: string);
//    constructor Create(const FilePath: string);                                 overload;
//    constructor Create(const F: TFile);                                         overload;
//    procedure UpdateUses
    destructor Destroy;
  end;


{ Platform }

  TPlatformEnum =
  (
    All,
    Win32,
    Win64
  );

  TPlatform = record
    FValue: TPlatformEnum;
    procedure SetPlatform(const Value: string);                                 overload;
    procedure SetPlatform(const Value: TPlatformEnum);                          overload;
    function GetPlatform: TPlatformEnum;
    function GetPlatformAsStr: string;
  end;

{ Config }

    TConfigEnum =
  (
    Base,
    Cfg_1, // Release
    Cfg_2  // Debug
  );

  TConfig = record
    FValue: TConfigEnum;
    procedure SetConfig(const Value: string);                                   overload;
    procedure SetConfig(const Value: TConfigEnum);                              overload;
    function GetConfig: TConfigEnum;
    function GetConfigAsStr: string;
  end;

{ Settigns }

  TMainSettings = record
    FPlatform: TPlatform;
    FConfig: TConfig;

  end;

type
  TSettingsFields =
  (
    SearchPath,
    DebuggerSourcePath,
    Definies,
    ResourceOutputPath,
    DcuOutput,
    Debugger_HostApplication
  );

const
  SettingsFieldsStr: array[TSettingsFields] of string =
  (
    'DCC_UnitSearchPath',                         // Search Path Fields
    'Debugger_DebugSourcePath',                   // Debugger Path Fileds
    'DCC_Define',                                 // Defines
    'BRCC_OutputDir',                             // Resources Prefix
    'DCC_DcuOutput',                              // DCU Output Path
    'Debugger_HostApplication'                    // EXE location
  );

type
  TConfigSettings = array [TPlatformEnum, TConfigEnum, TSettingsFields] of string;

implementation

{ TPlatform }

function TPlatform.GetPlatform: TPlatformEnum;
begin
  result := FValue;
end;

procedure TPlatform.SetPlatform(const Value: string);
var
  pe: TPlatformEnum;
begin
  for pe := Low(TPlatformEnum) to High(TPlatformEnum) do begin
    if GetEnumName(TypeInfo(TPlatformEnum), Ord(pe)) = Value then
      self.FValue := pe;
  end;
end;

function TPlatform.GetPlatformAsStr: string;
begin
  result := GetEnumName(TypeInfo(TPlatformEnum), Ord(FValue));
end;

procedure TPlatform.SetPlatform(const Value: TPlatformEnum);
begin
  self.FValue := Value;
end;

{ TConfig }

function TConfig.GetConfig: TConfigEnum;
begin
  result := fValue;
end;

procedure TConfig.SetConfig(const Value: string);
var
  ce: TConfigEnum;
begin
  for ce := Low(TConfigEnum) to High(TConfigEnum) do begin
    if GetEnumName(TypeInfo(TConfigEnum), Ord(ce)) = Value then
      self.FValue := ce;
  end;
end;

function TConfig.GetConfigAsStr: string;
begin
  result := GetEnumName(TypeInfo(TConfigEnum), Ord(FValue));
end;

procedure TConfig.SetConfig(const Value: TConfigEnum);
begin
  self.FValue := Value;
end;


{ TFile }

constructor TFile.Create(const FilePath: string; IsSeedFile: Boolean = False);
begin
  FPath := FilePath;
  FAge := FileAge(FilePath);
  FAssociatedFile := nil;
  FIsSeed := IsSeedFile;
end;

destructor TFile.Destroy;
begin
  FreeAndNil(FAssociatedFile);
end;

function TFile.GetFileName: string;
begin
  result := FName;
  if result = '' then
    result := ExtractFileName(FPath);
end;

function TFile.IsUpdated: Boolean;
begin
  result := FAge <> FileAge(FPath);
end;

procedure TFile.SetAssociatedFile(const F: TFile);
begin
  if F <> nil then begin
    self.FAssociatedFile := F;
    F.FAssociatedFile := self;
  end;
end;

procedure TFile.Update;
begin
  FAge := FileAge(FPath);
end;

{ TFileArray }

procedure TFileArray.Add(const f: TFile);
begin
  for var Item in FArr do begin
    if SameText(ExtractFileName(F.Path), ExtractFileName(Item.FPath)) then
      exit;
  end;
  FArr := FArr + [F];
end;

procedure TFileArray.Clear;
begin
  SetLength(FArr, 0);
end;

function TFileArray.Contains(const F: TFile): Boolean;
begin
  result := False;
  for var Item in FArr do begin
    if SameText(Item.Path, F.Path) then begin
      exit(True)
    end;
  end;
end;

procedure TFileArray.CreateAndAdd(const Path: string);
begin
  var F := TFile.Create(Path);
  Self.Add(F);
end;

function TFileArray.GetByName(const FileName: string): TFile;
begin
  result := nil;
  for var Item in FArr do begin
    if SameText(Item.Name, FileName) then begin
      result := Item;
    end;
  end;
end;

function TFileArray.GetCount: Integer;
begin
  result := Length(FArr);
end;

function TFileArray.GetItem(Index: Integer): TFile;
begin
  result := FArr[Index];
end;

procedure TFileArray.SetItem(Index: Integer; Value: TFile);
begin
  FArr[Index] := Value;
end;

{ TDPRFile }

constructor TDPRFile.Create(const Path: string);
begin
  FStrings := TStringList.Create;
  FPath := Path;
  FName := StringReplace(ExtractFileName(FPath), ExtractFileExt(FPath), '', [rfIgnoreCase]);
end;

destructor TDPRFile.Destroy;
begin
  FreeAndNil(FStrings);
end;

procedure TDPRFile.LoadBaseStructure;

  procedure AddLine(const Text: string = '');
  begin
    FStrings.Add(Text + #13#10);
  end;

begin
  AddLine('program ' + FName + ';');
  AddLine('uses');
  AddLine('begin');
  AddLine('end.');
end;

procedure TDPRFile.LoadStructureFrom(const DPRPath: string);
var
  Source: TStringList;
  Line: Integer;
begin
  Source := TStringList.Create;
  Source.LoadFromFile(DPRPath);

  Line := 0;
  while Line < Source.Count do begin
    var Text := Source.Strings[Line];
    FStrings.Add(Text);
    Inc(Line);
  end;

end;

procedure TDPRFile.SaveToFile(const Path: string);
begin
  FStrings.SaveToFile(Path);
end;

procedure TDPRFile.UpdateUses(const UsedFiles: TStringList);
const
  DoubleSpace = '  ';
var
  Line: Integer;
  NewList: TStringList;
begin
  NewList := TStringList.Create;

  Line := 0;
  while Line < FStrings.Count do begin
    var Text := FStrings.Strings[Line];
    if SameText(Text, 'uses') then begin
      NewList.Add(Text);
      {Пропускаем содержимое uses}
      while (not Text.Contains(';')) AND (Line < FStrings.Count) do begin
        Inc(Line);
        Text := FStrings[Line];
      end;
      {Заполняем uses}
      UsedFiles.Sort;


      for var Index := 0 to Pred(UsedFiles.Count) do begin
        var un: string;
        var F := UsedFiles[Index];

        if SameText(ExtractFilePath(F), '') then begin
          un := F;
        end else if SameText(ExtractFileExt(F), '.pas')  then begin
          var Name := StringReplace(ExtractFileName(F), ExtractFileExt(F), '', [rfIgnoreCase]);
          un := Name + ' in ' + GetRelativeLink(FPath, F);
        end else
          continue;

        if  Index < Pred(UsedFiles.Count) then
          un := DoubleSpace + un + ','
        else
          un := DoubleSpace + un + ';';

        NewList.Add(un);
      end;
    end else begin
      NewList.Add(Text);
      Inc(Line);
    end;
  end;
  FreeAndNil(FStrings);
  FStrings := NewList;
end;

end.
