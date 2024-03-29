unit DSDprojStructure;

interface

uses
  System.Classes, System.SysUtils;

procedure GenerateDproj(var List: TStringList);

implementation

procedure GenerateDproj(var List: TStringList);
var
  Text: TStringList;
  GUID: TGUID;
begin
  Text := List;

  CreateGUID(GUID);

  Text.Append('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');

    Text.Append('<PropertyGroup>');

      Text.Append('<ProjectGuid>' + GUID.ToString +'</ProjectGuid>');
      Text.Append('<ProjectVersion>19.5</ProjectVersion>');
      Text.Append('<FrameworkType>None</FrameworkType>');
      Text.Append('<MainSource></MainSource>');
      Text.Append('<Base>True</Base>');
      Text.Append('<Config Condition="''$(Config)''==''''">Cfg_1</Config>');
      Text.Append('<Platform Condition="''$(Platform)''==''''">Win64</Platform>');
      Text.Append('<TargetedPlatforms>3</TargetedPlatforms>');
      Text.Append('<AppType>Application</AppType>');

    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">');
      Text.Append('<Base>true</Base>');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">');
      Text.Append('<Base_Win64>true</Base_Win64>');
      Text.Append('<CfgParent>Base</CfgParent>');
      Text.Append('<Base>true</Base>');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''">');
      Text.Append('<Cfg_1>true</Cfg_1>');
      Text.Append('<CfgParent>Base</CfgParent>');
      Text.Append('<Base>true</Base>');
    Text.Append('</PropertyGroup>');


    Text.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_1)''==''true'') or ''$(Cfg_1_Win64)''!=''''">');
      Text.Append('<Cfg_1_Win64>true</Cfg_1_Win64>');
      Text.Append('<CfgParent>Cfg_1</CfgParent>');
      Text.Append('<Cfg_1>true</Cfg_1>');
      Text.Append('<Base>true</Base>');
   Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_2)''==''true'') or ''$(Cfg_2_Win64)''!=''''">');
      Text.Append('<Cfg_2_Win64>true</Cfg_2_Win64>');
      Text.Append('<CfgParent>Cfg_2</CfgParent>');
      Text.Append('<Cfg_2>true</Cfg_2>');
      Text.Append('<Base>true</Base>');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Base)''!=''''">');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Base_Win64)''!=''''">');
    Text.Append('</PropertyGroup>');


    Text.Append('<PropertyGroup Condition="''$(Cfg_1)''!=''''">');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Cfg_1_Win64)''!=''''">');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Cfg_2)''!=''''">');
    Text.Append('</PropertyGroup>');

    Text.Append('<PropertyGroup Condition="''$(Cfg_2_Win64)''!=''''">');
    Text.Append('</PropertyGroup>');

    Text.Append('<ItemGroup>');
      Text.Append('<BuildConfiguration Include="Base">');
        Text.Append('<Key>Base</Key>');
      Text.Append('</BuildConfiguration>');

      Text.Append('<BuildConfiguration Include="Debug">');
        Text.Append('<Key>Cfg_1</Key>');
        Text.Append('<CfgParent>Base</CfgParent>');
      Text.Append('</BuildConfiguration>');

      Text.Append('<BuildConfiguration Include="Release">');
        Text.Append('<Key>Cfg_2</Key>');
        Text.Append('<CfgParent>Base</CfgParent>');
      Text.Append('</BuildConfiguration>');


    Text.Append('</ItemGroup>');

    Text.Append('<ProjectExtensions>');
      Text.Append('<Borland.Personality>Delphi.Personality.12</Borland.Personality>');
      Text.Append('<Borland.ProjectType>Application</Borland.ProjectType>');
      Text.Append('<BorlandProject>');
        Text.Append('<Delphi.Personality>');
        Text.Append('</Delphi.Personality>');
      Text.Append('</BorlandProject>');
    Text.Append('</ProjectExtensions>');

    Text.Append('<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>');
    Text.Append('<Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj" Condition="Exists(''$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj'')"/>');
    Text.Append('<Import Project="$(MSBuildProjectName).deployproj" Condition="Exists(''$(MSBuildProjectName).deployproj'')"/>');

  Text.Append('</Project>');
end;

end.
