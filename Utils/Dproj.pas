unit Dproj;

interface

uses
  Winapi.Windows, Registry,

  System.SysUtils, System.Variants, System.Classes, System.StrUtils, System.TypInfo,
  System.Types, System.IOUtils, ActiveX,

  DSUtils, DSTypes,

  XMLDoc, XMLIntf;

const
  DprojText =
  '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'       + #13#10 +
  '<PropertyGroup>'                                                             + #13#10 +
  '<ProjectGuid>%s</ProjectGuid>'                                               + #13#10 +
  '<ProjectVersion>19.5</ProjectVersion>'                                       + #13#10 +
  '<FrameworkType>None</FrameworkType>'                                         + #13#10 +
  '<Base>True</Base>'                                                           + #13#10 +
  '<Config Condition="''$(Config)''==''''">Debug</Config>'                      + #13#10 +
  '<Platform Condition="''$(Platform)''==''''">Win64</Platform>'                + #13#10 +
  '<TargetedPlatforms>3</TargetedPlatforms>'                                    + #13#10 +
  '<MainSource>%s</MainSource>'                                                 + #13#10 +
  '</PropertyGroup>'                                                            + #13#10 +


  '<PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">'    + #13#10 +
  '<Base>true</Base>'                                                           + #13#10 +
  '</PropertyGroup>'                                                            + #13#10 +
  '<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">'   + #13#10 +
  '<Base_Win64>true</Base_Win64>'                                               + #13#10 +
  '<CfgParent>Base</CfgParent>'                                                 + #13#10 +
  '<Base>true</Base>'                                                           + #13#10 +
  '</PropertyGroup>'                                                            + #13#10 +
  '<PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_1)''!=''''">'   + #13#10 +
  '<Cfg_1>true</Cfg_1>'                                                         + #13#10 +
  '<CfgParent>Base</CfgParent>'                                                 + #13#10 +
  '<Base>true</Base>'                                                           + #13#10 +
  '</PropertyGroup> '                                                           + #13#10 +
  '<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_1)''==''true'') or ''$(Cfg_1_Win64)''!=''''">'     + #13#10 +
  '<Cfg_1_Win64>true</Cfg_1_Win64> '                                            + #13#10 +
  '<CfgParent>Cfg_1</CfgParent>'                                                + #13#10 +
  '<Cfg_1>true</Cfg_1> '                                                        + #13#10 +
  '<Base>true</Base>'                                                           + #13#10 +
  '</PropertyGroup> '                                                            + #13#10 +
  '<PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_2)''!=''''"> '    + #13#10 +
  '<Cfg_2>true</Cfg_2>  '                                                       + #13#10 +
  '<CfgParent>Base</CfgParent>'                                                 + #13#10 +
  '<Base>true</Base> '                                                          + #13#10 +
  '</PropertyGroup>'                                                            + #13#10 +
  '<PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Cfg_2)''==''true'') or ''$(Cfg_2_Win64)''!=''''"> '   + #13#10 +
  '<Cfg_2_Win64>true</Cfg_2_Win64> '                                            + #13#10 +
  '<CfgParent>Cfg_2</CfgParent>'                                                + #13#10 +
  '<Cfg_2>true</Cfg_2>  '                                                       + #13#10 +
  '<Base>true</Base> '                                                          + #13#10 +
  '</PropertyGroup> '                                                           + #13#10 +


  '<PropertyGroup Condition="''$(Base)''!=''''">'                               + #13#10 +
  '<DCC_UnitSearchPath>%s</DCC_UnitSearchPath>'                                 + #13#10 +
  '<DCC_Define>%s</DCC_Define>'                                                 + #13#10 +
  '</PropertyGroup>'                                                            + #13#10 +

  '</Project>'                                                                  ;

type
  TDprojFile = class
  public
    MainSettings: TMainSettings;
    ConfigSettings: TConfigSettings;
  private
    FFilePath: string;
    FXMLDoc: IXMLDocument;
    FResources: TArray<string>;
    procedure GetConfigAndPlatformByCondition(const Condition: string; out PlatformType: TPlatformEnum; out Config: TConfigEnum);
    procedure LoadSettings;
  public
    constructor Create;                                                         overload;
    constructor Create(const FileName: string);                                 overload;
    destructor Destroy;

    procedure LoadFromFile(const FileName: string);
    property Resources: TArray<string> read FResources write FResources;
    function GetDefinies(const Platforms : array of TPlatformEnum; const Configs: array of TConfigEnum): TArray<string>;
    function GetSearchPath(const Platforms : array of TPlatformEnum; const Configs: array of TConfigEnum): TArray<string>;
    function GetOutput(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): string;
    function GetDebuggerFiles(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): TArray<string>;
    procedure ReLinkSearchPathTo(const NewLink: string);
    property FilePath: string read FFilePath;

    procedure GenerateBasicDProj(const ProjectName, ProjectGUID, DPRFileName, SearchPath: string);
  end;

implementation

{ Assist functions }

function Сontains(const Value: string; const Arr: TArray<string>): Boolean;
begin
  result := False;
  for var Elem in Arr do begin
    if SameText(Elem, Value) then
      exit(True);
  end;
end;

{ TDprojInfo }

constructor TDprojFile.Create;
begin
  FXMLDoc := TXMLDocument.Create(nil);
end;

constructor TDprojFile.Create(const FileName: string);
begin
  self.Create;
  self.LoadFromFile(FileName);
end;

destructor TDprojFile.Destroy;
begin
  FXMLDoc := nil;
end;

procedure TDprojFile.GenerateBasicDProj(const ProjectName, ProjectGUID, DPRFileName, SearchPath: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  sl.Add(Format(DprojText, [ProjectGUID, ExtractFileName(DPRFileName), SearchPath, '']));
  sl.SaveToFile(ProjectName);
end;

procedure TDprojFile.GetConfigAndPlatformByCondition(const Condition: string;
  out PlatformType: TPlatformEnum; out Config: TConfigEnum);
var
  pe: TPlatformEnum;
  ce: TConfigEnum;
  value: string;
begin
  var TrimedCondition := Condition.Substring(3, Length(Condition)-9);

  // platform
  for pe := Low(TPlatformEnum) to High(TPlatformEnum) do begin
    value := GetEnumName(TypeInfo(TPlatformEnum), Ord(pe));
    if LowerCase(TrimedCondition).EndsWith(LowerCase(value)) then begin
      PlatformType := pe;
      BREAK;
    end;
  end;

  //config
  for ce := Low(TConfigEnum) to High(TConfigEnum) do begin
    value := GetEnumName(TypeInfo(TConfigEnum), Ord(ce));
    if LowerCase(TrimedCondition).EndsWith(LowerCase(value)) then begin
      Config := ce;
      BREAK;
    end;
  end;
end;

function TDprojFile.GetDebuggerFiles(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum): TArray<string>;

  function IsContain(const f: string; const Arr: TArray<string>): Boolean;
  begin
    result := False;
    for var Value in Arr do begin
      if SameText(Value, f) then
        exit(True);
    end;
  end;

  function ParseFiles(const Dir: string): TArray<string>;
  var
    FoundFiles: TStringDynArray;
    FileName: string;
  begin
    if DirectoryExists(Dir) then begin
      FoundFiles := TDirectory.GetFiles(Dir, '*.*', TSearchOption.soAllDirectories);
      for FileName in FoundFiles do begin
        var name := ExtractFileNameWithoutExt(FileName);
        if not IsContain(name, result) then
          result := result + [name];
      end;
    end;
  end;

begin
  var debuggerPaths := self.ConfigSettings[PlatformTyp][ConfigTyp][DebuggerSourcePath];
  var PathArr := debuggerPaths.Split([';']);
  for var I := 0 to Length(PathArr)-2 do begin
    result := result + ParseFiles(CalcPath(PathArr[I], FFilePath));
  end;
end;

function TDprojFile.GetDefinies(const Platforms: array of TPlatformEnum;
  const Configs: array of TConfigEnum): TArray<string>;
var
  pe: TPlatformEnum;
  ce: TConfigEnum;
begin
  // Win приложение
  result := result + ['MSWINDOWS', 'USE_SVG2'];

  for pe in Platforms do begin
    for ce in Configs do begin
      var Defines := self.ConfigSettings[pe][ce][Definies];
      if not Defines.IsEmpty then begin
        var DefArr := defines.Split([';']);
        SetLength(DefArr, Length(defArr)-1);
        for var Def in DefArr do begin
          if not Сontains(Def, Result) then begin
            result := result + [Def];
          end;
        end;
      end;
    end;
  end;
end;

function TDprojFile.GetOutput(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): string;
begin
  var output := self.ConfigSettings[PlatformTyp][ConfigTyp][DcuOutput];
//  output := InsertPlatformPath(output, self.MainSettings.FPlatform);
//  output := InsertProjectName(output, ExtractFileNameWithoutExt(self.FFilePath));
  result := CalcPath(output, self.FFilePath);
end;

function TDprojFile.GetSearchPath(const Platforms: array of TPlatformEnum;
  const Configs: array of TConfigEnum): TArray<string>;
var
  pe: TPlatformEnum;
  ce: TConfigEnum;
begin
  for pe in Platforms do begin
    for ce in Configs do begin
      var SearchPath := self.ConfigSettings[pe][ce][SearchPath];
      if not SearchPath.IsEmpty then begin
        var SearchPathArr := SearchPath.Split([';']);
        SetLength(SearchPathArr, Length(SearchPathArr)-1);
        for var SP in SearchPathArr do begin
          if not Сontains(SP, Result) then begin
            result := result + [SP];
          end;
        end;
      end;
    end;
  end;
end;

procedure TDprojFile.LoadFromFile(const FileName: string);
begin
  CoInitializeEx(nil, COINIT_MULTITHREADED);

  if FileExists(FileName) then begin
    if FileName.EndsWith('.dproj') then begin
      FFilePath := FileName;
    end else begin
      raise Exception.Create('Файл ' + FileName + ' не соответувует формату');
    end;
  end else begin
    raise Exception.Create('Файла ' + FileName + ' не существует');
  end;

  FXMLDoc.LoadFromFile(FileName);
  self.LoadSettings;
end;

procedure TDprojFile.LoadSettings;
var
  RootNode, PropertyGroupNode, ItemGroupNode: IXMLNode;
  SettingField: TSettingsFields;
  PlatformType: TPlatformEnum;
  ConfigType: TConfigEnum;
begin
  RootNode := FXMLDoc.DocumentElement;

  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');
  while Assigned(PropertyGroupNode) do begin
    if PropertyGroupNode.AttributeNodes.Count = 0 then begin
    // Парсим основные настройки
      if PropertyGroupNode.ChildNodes.FindNode('Platform') <> nil then
        self.MainSettings.FPlatform.SetPlatform(PropertyGroupNode.ChildNodes['Platform'].Text);
      if PropertyGroupNode.ChildNodes.FindNode('Config') <> nil then
        self.MainSettings.FConfig.SetConfig(PropertyGroupNode.ChildNodes['Config'].Text);
    end else begin
    // Парсим настройки конфигураций
      // Перебираем поля
      for SettingField := Low(TSettingsFields) to High(TSettingsFields) do begin
        if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[SettingField]) <> nil then begin
          var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[SettingField]].Text;
          if not Text.IsEmpty then begin
            var condition := PropertyGroupNode.Attributes['Condition'];
            // Получаем текущую кофигурацию
            GetConfigAndPlatformByCondition(condition, PlatformType, ConfigType);
            self.ConfigSettings[PlatformType][ConfigType][SettingField] := Text
          end;
        end;
      end;
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;

  ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
  if Assigned(ItemGroupNode) then begin
    for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
      var node := ItemGroupNode.ChildNodes.Get(I);
      // Парсим ресурсы
        if node.LocalName = 'RcCompile' then begin
          self.FResources := self.FResources + [node.Attributes['Include']];
          if node.ChildNodes['Form'] <> nil then begin
            var OutPath := self.ConfigSettings[All][Base][ResourceOutputPath];
            self.FResources := self.FResources + [OutPath + '\' + node.ChildNodes['Form'].NodeValue];
          end;
        end;
    end;
  end;
end;

procedure TDprojFile.ReLinkSearchPathTo(const NewLink: string);
var
  RootNode, PropertyGroupNode, ItemGroupNode: IXMLNode;
  ResourcePath: string;
begin
  RootNode := FXMLDoc.DocumentElement;

  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');

  while Assigned(PropertyGroupNode) do begin
    if PropertyGroupNode.AttributeNodes.Count <> 0 then begin

      if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[SearchPath]) <> nil then begin
        var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[SearchPath]].Text;
        if not Text.IsEmpty then begin

          var spArr := Text.Split([';']);
          for var I := 0 to Length(spArr) -2 do begin
            var path := CalcPath(spArr[I], FFilePath);
            spArr[I] := GetRelativeLink(NewLink, path);
          end;

//        PropertyGroupNode.ChildNodes[SettingsFieldsStr[SearchPath]].Text := string.Join(';', spArr);
          PropertyGroupNode.ChildNodes[SettingsFieldsStr[SearchPath]].NodeValue := string.Join(';', spArr);
        end;
      end;

      if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[Debugger_HostApplication]) <> nil then begin
         var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[Debugger_HostApplication]].Text;
         var path := CalcPath(Text, FFilePath);
         var newBug := GetRelativeLink(NewLink, path);
         PropertyGroupNode.ChildNodes[SettingsFieldsStr[Debugger_HostApplication]].NodeValue := GetRelativeLink(NewLink, path);
      end;
      if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[ResourceOutputPath]) <> nil then begin
        var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[ResourceOutputPath]].Text;
        var path := CalcPath(Text, FFilePath);
        ResourcePath := GetRelativeLink(NewLink, path);
        PropertyGroupNode.ChildNodes[SettingsFieldsStr[ResourceOutputPath]].NodeValue := GetRelativeLink(NewLink, path);
      end;

    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;

  ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
  if Assigned(ItemGroupNode) then begin
    for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
      var node := ItemGroupNode.ChildNodes.Get(I);
      // Парсим ресурсы
        if node.LocalName = 'RcCompile' then begin
          var rcPath: string :=  node.Attributes['Include'];
          var rcPathParts := rcPath.split(['\']);
          var path := ResourcePath + '\' + rcPathParts[Length(rcPathParts)-1];
          node.Attributes['Include'] := path;

//          if node.ChildNodes['Form'] <> nil then begin
//            var OutPath := self.ConfigSettings[All][Base][ResourceOutputPath];
//            self.FResources := self.FResources + [OutPath + '\' + node.ChildNodes['Form'].NodeValue];
//          end;
        end;
    end;
  end;

//  FXMLDoc.Refresh;
  FXMLDoc.SaveToFile(NewLink);
end;

end.




