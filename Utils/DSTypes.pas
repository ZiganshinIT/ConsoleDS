unit DSTypes;

interface

uses
  System.TypInfo;

type

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

end.
