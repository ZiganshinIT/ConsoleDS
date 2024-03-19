unit Dproj;

interface

uses
  Winapi.Windows,

  System.SysUtils, System.Variants, System.Classes, System.StrUtils, System.TypInfo,
  System.Types, System.IOUtils, ActiveX,

  DSUtils, DSTypes,

  XMLDoc, XMLIntf;

type
  TDprojInfo = class
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

constructor TDprojInfo.Create;
begin
  FXMLDoc := TXMLDocument.Create(nil);
end;

constructor TDprojInfo.Create(const FileName: string);
begin
  self.Create;
  self.LoadFromFile(FileName);
end;

destructor TDprojInfo.Destroy;
begin
  FXMLDoc := nil;
end;

procedure TDprojInfo.GetConfigAndPlatformByCondition(const Condition: string;
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

function TDprojInfo.GetDebuggerFiles(const PlatformTyp: TPlatformEnum;
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
        if IsContain(name, result) then
          result := result + [name];
      end;
    end;
  end;

begin
  var debuggerPaths := self.ConfigSettings[PlatformTyp][ConfigTyp][DebuggerSourcePath];
  var PathArr := debuggerPaths.Split([';']);
  for var path in PathArr do begin
    result := result + ParseFiles(path);
  end;
end;

function TDprojInfo.GetDefinies(const Platforms: array of TPlatformEnum;
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

function TDprojInfo.GetOutput(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): string;
begin
  var output := self.ConfigSettings[PlatformTyp][ConfigTyp][DcuOutput];
  output := InsertPlatformPath(output, self.MainSettings.FPlatform);
  output := InsertProjectName(output, ExtractFileNameWithoutExt(self.FFilePath));
  result := CalcPath(output, self.FFilePath);
end;

function TDprojInfo.GetSearchPath(const Platforms: array of TPlatformEnum;
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

procedure TDprojInfo.LoadFromFile(const FileName: string);
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

procedure TDprojInfo.LoadSettings;
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

procedure TDprojInfo.ReLinkSearchPathTo(const NewLink: string);
var
  RootNode, PropertyGroupNode, ItemGroupNode: IXMLNode;
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
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;
//  FXMLDoc.Refresh;
  FXMLDoc.SaveToFile(NewLink);
end;

end.




