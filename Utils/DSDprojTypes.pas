unit DSDprojTypes;

interface

uses
  System.Classes, System.SysUtils, System.TypInfo,

  DSTypes;

type
  TPlatform = record
  private
    FValue: TPlatformEnum;
    function GetStrValue: string;
    procedure SetStrValue(const Value: string);
  public
    property Value: TPlatformEnum read FValue write FValue;
    property StrValue: string read GetStrValue write SetStrValue;
  end;

  TConfig = record
  private
    FValue: TConfigEnum;
    function GetStrValue: string;
    procedure SetStrValue(const Value: string);
  public
    property Value: TConfigEnum read FValue write FValue;
    property StrValue: string read GetStrValue write SetStrValue;
  end;

  TResource = record
    Include: string;
    Form:    string;
  end;

const
  FieldsStr: array[TFields] of string =
  (
    'DCC_UnitSearchPath',
    'DCC_Define',
    'Debugger_DebugSourcePath',
    'BRCC_OutputDir',
    'Debugger_HostApplication',
    'DCC_WriteableConstants',
    'DCC_Namespace'
  );

  function GenerateDPROJ: TStringList;

implementation

  function GenerateDPROJ: TStringList;
  var
    GUID: TGUID;
  begin
    result := TStringList.Create;

    CreateGUID(GUID);

    result.Append('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    result.Append('<PropertyGroup>');
    result.Append('<ProjectGuid>' + GUID.ToString +'</ProjectGuid>');
    result.Append('<ProjectVersion>19.5</ProjectVersion>');
    result.Append('<FrameworkType>None</FrameworkType>');
    result.Append('<MainSource></MainSource>');
    result.Append('<Base>True</Base>');
    result.Append('<Config Condition="''$(Config)''==''''">Cfg_1</Config>');
    result.Append('<Platform Condition="''$(Platform)''==''''">Win64</Platform>');
    result.Append('<TargetedPlatforms>3</TargetedPlatforms>');
    result.Append('<AppType>Application</AppType>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">');
    result.Append('<Base>true</Base>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">');
    result.Append('<Base_Win64>true</Base_Win64>');
    result.Append('<CfgParent>Base</CfgParent>');
    result.Append('<Base>true</Base>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''">');
    result.Append('<Cfg_1>true</Cfg_1>');
    result.Append('<CfgParent>Base</CfgParent>');
    result.Append('<Base>true</Base>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_1)''==''true'') or ''$(Cfg_1_Win64)''!=''''">');
    result.Append('<Cfg_1_Win64>true</Cfg_1_Win64>');
    result.Append('<CfgParent>Cfg_1</CfgParent>');
    result.Append('<Cfg_1>true</Cfg_1>');
    result.Append('<Base>true</Base>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_2)''==''true'') or ''$(Cfg_2_Win64)''!=''''">');
    result.Append('<Cfg_2_Win64>true</Cfg_2_Win64>');
    result.Append('<CfgParent>Cfg_2</CfgParent>');
    result.Append('<Cfg_2>true</Cfg_2>');
    result.Append('<Base>true</Base>');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Base)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Base_Win64)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Cfg_1)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Cfg_1_Win64)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Cfg_2)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<PropertyGroup Condition="''$(Cfg_2_Win64)''!=''''">');
    result.Append('</PropertyGroup>');
    result.Append('<ItemGroup>');
    result.Append('<BuildConfiguration Include="Base">');
    result.Append('<Key>Base</Key>');
    result.Append('</BuildConfiguration>');
    result.Append('<BuildConfiguration Include="Debug">');
    result.Append('<Key>Cfg_1</Key>');
    result.Append('<CfgParent>Base</CfgParent>');
    result.Append('</BuildConfiguration>');
    result.Append('<BuildConfiguration Include="Release">');
    result.Append('<Key>Cfg_2</Key>');
    result.Append('<CfgParent>Base</CfgParent>');
    result.Append('</BuildConfiguration>');
    result.Append('</ItemGroup>');
    result.Append('<ProjectExtensions>');
    result.Append('<Borland.Personality>Delphi.Personality.12</Borland.Personality>');
    result.Append('<Borland.ProjectType>Application</Borland.ProjectType>');
    result.Append('<BorlandProject>');
    result.Append('<Delphi.Personality>');
    result.Append('</Delphi.Personality>');
    result.Append('</BorlandProject>');
    result.Append('</ProjectExtensions>');
    result.Append('<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>');
    result.Append('<Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj" Condition="Exists(''$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj'')"/>');
    result.Append('<Import Project="$(MSBuildProjectName).deployproj" Condition="Exists(''$(MSBuildProjectName).deployproj'')"/>');
    result.Append('</Project>');
  end;

{ TConfig }

function TConfig.GetStrValue: string;
begin
  result := GetEnumName(TypeInfo(TConfigEnum), Ord(FValue));
end;

procedure TConfig.SetStrValue(const Value: string);
var
  ConfigValue: TConfigEnum;
begin
  if SameText('Base', Value) then begin
    self.FValue := Base;
  end else if SameText('Release', Value) OR SameText('Cfg_1', Value) then begin
    self.FValue := Cfg_1;
  end else if SameText('Debug', Value) OR SameText('Cfg_2', Value) then begin
    self.FValue := Cfg_2;
  end;
end;

{ TPlatform }

function TPlatform.GetStrValue: string;
begin
  result := GetEnumName(TypeInfo(TPlatformEnum), Ord(FValue));
end;

procedure TPlatform.SetStrValue(const Value: string);
var
  PlatformValue: TPlatformEnum;
begin
  for PlatformValue := Low(TPlatformEnum) to High(TPlatformEnum) do begin
    if GetEnumName(TypeInfo(TPlatformEnum), Ord(PlatformValue)) = Value then begin
      self.Value := PlatformValue;
    end;
  end;
end;

end.
