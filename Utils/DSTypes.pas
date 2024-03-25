unit DSTypes;

interface

uses
  System.SysUtils, System.TypInfo;

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
    FPath: string;
  public
//    constructor Create(const FilePath: string);                                 overload;
//    constructor Create(const F: TFile);                                         overload;
//    procedure UpdateUses
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

  TSettingsFields =
  (
    SearchPath,
    DebuggerSourcePath,
    Definies,
    ResourceOutputPath,
    DcuOutput
  );

  TConfigSettings = array [TPlatformEnum, TConfigEnum, TSettingsFields] of string;

const
  SettingsFieldsStr: array[TSettingsFields] of string =
  (
    'DCC_UnitSearchPath',
    'Debugger_DebugSourcePath',
    'DCC_Define',
    'BRCC_OutputDir',
    'DCC_DcuOutput'
  );

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

end.
