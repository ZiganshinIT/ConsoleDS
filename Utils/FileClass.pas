unit FileClass;

interface

uses
  Winapi.ActiveX,

  System.SysUtils, System.Classes, System.IOUtils, System.TypInfo, System.RegularExpressions,
  System.StrUtils, System.Generics.Collections,

  Vcl.StdCtrls,

  XMLDoc, XMLIntf,

  DSUtils, DSTypes, DSDprojTypes;

type
  {Основные настройки проекта}
  TMainSettings = record
    FMainSource: string;
    FPlatform:  TPlatform;
    FConfig:    TConfig;
  end;

  {Конфигурационные настройки}
  TConfigSettings = array [TPlatformEnum, TConfigEnum, TFields] of string;

  TDprojFile = class
  private
    FPath: string;
    FXMLDoc: IXMLDocument;
    FResources: TArray<TResource>;
    FUnits: TDictionary<string, string>;
  protected
    procedure TakeSettingsFrom(const Source: TDprojFile);
    function TryParseCondition(const Condition: string; out PlatformType: TPlatformEnum;
      out Config: TConfigEnum): Boolean;
  public
    MainSettings: TMainSettings;
    ConfigSettings: TConfigSettings;
    {Load Opertions}
    procedure LoadPropertyGroup;
    procedure LoadItemGroup;
    {Refresh Operations}
    procedure RefreshPropertyGroup;
    procedure RefreshItemGroup;
    {Load Operations}
    procedure LoadSettings;
    procedure GenerateBase;
    {Other}
    procedure Refresh;
    procedure AddValue(const Platforms: array of TPlatformEnum; const Configs: array of TConfigEnum;
      const Field: TFields; const Value: string);
  public
    constructor Create;                                                         overload;
    constructor Create(const Path: string);                                     overload;

    procedure LoadSettingsFrom(const Source: TDprojFile);                       overload;
    procedure LoadSettingsFrom(const Source: string);                           overload;

    procedure SaveFile;

    property Resources: TArray<TResource> read FResources write FResources;
    property Units: TDictionary<string, string> read FUnits;
    property Path: string read FPath write FPath;

    function GetField(const Platforms: array of TPlatformEnum; const Configs: array of TConfigEnum;
      const Field: TFields): TArray<string>;

    function Copy(const Path: string): TDprojFile;

    destructor Destroy;
  end;

  TDprFile = class
  private
    FName: string;
    FPath: string;
    FStrings: TStringList;
    FDprojFile: TDprojFile;
    FUnits: TArray<String>;
  public
    constructor Create(const Path: string);

    procedure BuildBaseStructure;
    procedure LoadStructure(const Path: string);                                overload;
    procedure LoadStructure(const DprFile: TDprFile);                           overload;

    procedure UpdateResources(const OldDprojFile: TDprojFile);
    procedure UpdateUses(const List: TStringList);

    procedure SaveFile;

    procedure Assign(const DprojFile: TDprojFile);

    property Path: string read FPath;

    destructor Destroy;
  end;

  TDpkFile = class
  private
    FPath: string;
    FRequires: TArray<string>;
    FContains: TDictionary<string, string>;
  protected
    procedure LoadFromFile;
  public
    constructor Create(const Path: string);

    property Requires: TArray<string> read FRequires;
    property Contains: TDictionary<string, string> read FContains;
    property Path: string read FPath;

    destructor Destroy;
  end;

  TGroupProjFile = class
  private
    FPath: string;
    FProjects: TStringList;
  protected
    procedure LoadProjects;
    procedure SetPath(const Value: string);
  public
    constructor Create(const Path: string);                                     overload;

    procedure AddProject(const ProjectPath: string);
    procedure SaveFile;

    property Path: string read FPath write SetPath;
    property Projects: TStringList read FProjects;

    destructor  Destroy;
  end;

implementation

{ TDprFile }

procedure TDprFile.Assign(const DprojFile: TDprojFile);
begin
  FDprojFile := DprojFile;
end;

procedure TDprFile.BuildBaseStructure;

  procedure AddLine(const Text: string = '');
  begin
    FStrings.Add(Text);
  end;

begin
  FStrings.Clear;

  AddLine('program ' + FName + ';');
  AddLine('uses');
  AddLine(';');
  AddLine('begin');
  AddLine('end.');
end;

constructor TDprFile.Create(const Path: string);
begin
  FStrings := TStringList.Create;
  FPath := Path;
  FName := StringReplace(ExtractFileName(FPath), ExtractFileExt(FPath), '', [rfIgnoreCase]);
end;

destructor TDprFile.Destroy;
begin
  FreeAndNil(FStrings);
end;

procedure TDprFile.LoadStructure(const DprFile: TDprFile);
begin
  self.LoadStructure(DprFile.FPath);
end;

procedure TDprFile.LoadStructure(const Path: string);
var
  Source: TStringList;
  Line: Integer;
begin
  FStrings.Clear;

  Source := TStringList.Create;
  Source.LoadFromFile(Path);
  Line := 0;
  while Line < Source.Count do begin
    var Text := Source.Strings[Line];
    FStrings.Add(Text);
    Inc(Line);
  end;
end;

procedure TDprFile.SaveFile;
begin
  ForceDirectories(GetDownPath(FPath));
  FStrings.SaveToFile(FPath);
end;

procedure TDprFile.UpdateResources(const OldDprojFile: TDprojFile);

  procedure Trim(var str: string);
    begin
      str := str.Trim([' ', '"', '''']);
      str := str.TrimStart(['{', '"', '''']);
      str := str.TrimEnd(['}', '"', '''']);
    end;

begin
  var SearchExt := 'res|inc|rc|dres|dfm';

  if FDprojFile <> nil then begin
    for var I := 0 to Pred(FStrings.Count) do begin
      var Text := FStrings[I];
      if TRegEx.IsMatch(Text, '(\{\$)(.+)(\.)(' + SearchExt + ')(.*)(\})', [roIgnoreCase]) then begin
        var words := Text.Split([' ']);
        var Extensions := SearchExt.Split(['|']);
        for var word in words do begin
          var res := word;
          Trim(res);
          for var Extension in Extensions do begin

            if ContainsText(res, '.'+Extension) then begin
              var OriginalName := res;

              var Prefix := FDprojFile.ConfigSettings[All][Base][ResourceOutputPath];
              var NewPath: string;
              if not OriginalName.Contains(Prefix) AND Text.StartsWith('{$R') then begin
                NewPath := Prefix + '\' + OriginalName;
              end else
                NewPath := OriginalName;

              var FilePath := CalcPath(NewPath, OldDprojFile.FPath);
              var TextPath := GetRelativeLink(FPath, FilePath);


              FStrings[I] := StringReplace(FStrings[I], OriginalName, TextPath, [rfIgnoreCase]);

            end
          end;
        end;
      end;
    end;
  end;
end;

procedure TDprFile.UpdateUses(const List: TStringList);
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
      Inc(Line);

      for var Index := 0 to Pred(List.Count) do begin
        var un: string;
        var F := List[Index];

        if SameText(ExtractFilePath(F), '') then begin
          un := F;
        end else if SameText(ExtractFileExt(F), '.pas')  then begin
          var Name := StringReplace(ExtractFileName(F), ExtractFileExt(F), '', [rfIgnoreCase]);
          un := Name + ' in ''' + GetRelativeLink(FPath, F) + '''';
        end else
          continue;

        if  Index < Pred(List.Count) then
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

{ TDprojFile }

procedure TDprojFile.AddValue(const Platforms: array of TPlatformEnum;
  const Configs: array of TConfigEnum; const Field: TFields;
  const Value: string);
var
  Arr: array of string;
begin
  for var PlatformValue in Platforms do begin
    for var ConfigValue in Configs do begin
      var Text := self.ConfigSettings[PlatformValue][ConfigValue][Field];
      if Text.CountChar(';') > 0 then begin
        var Values := Text.Split([';']);
        for var I := 0 to Length(Values)-2 do begin
          Arr := Arr + [Values[I]];
        end;
        Arr := Arr + [Value];
        Arr := Arr + [Values[Length(Values)-1]];
      end;
      self.ConfigSettings[PlatformValue][ConfigValue][Field] := string.Join(';', Arr);
    end;
  end;
end;

function TDprojFile.Copy(const Path: string): TDprojFile;
begin
  result := TDprojFile.Create;
  result.FPath := Path;
  result.FXMLDoc.LoadFromFile(self.FPath);
  result.LoadSettingsFrom(self);
end;

constructor TDprojFile.Create(const Path: string);
begin
  self.Create;
  FPath := Path;
  LoadSettings;
end;

constructor TDprojFile.Create;
begin
  FXMLDoc := TXMLDocument.Create(nil);
  FXMLDoc.Options := FXMLDoc.Options + [doNodeAutoIndent];
  FUnits  := TDictionary<string, string>.Create;
end;

destructor TDprojFile.Destroy;
begin
  FXMLDoc := nil;
  FreeAndNil(FUnits);
end;

procedure TDprojFile.GenerateBase;
var
  List: TStringList;
begin
  List := TStringList.Create;
  List := GenerateDproj;
  FXMLDoc.LoadFromXML(List.GetText);
end;

function TDprojFile.GetField(const Platforms: array of TPlatformEnum;
  const Configs: array of TConfigEnum; const Field: TFields): TArray<string>;
var
  List: TList<string>;
begin
  List := TList<string>.Create;

  for var P in Platforms do begin
    for var C in Configs do begin
      var SettingsText := ConfigSettings[P][C][Field];
      var Values := SettingsText.Split([';']);
      for var I := 0 to Length(Values)-2 do begin
        if not List.Contains(Values[I]) then begin
          List.Add(Values[I])
        end;
      end;
    end;
  end;

  result := List.ToArray;
  FreeAndNil(List);

end;

procedure TDprojFile.LoadSettings;
begin
  CoInitializeEx(nil, COINIT_MULTITHREADED);

  if FileExists(FPath) then
    FXMLDoc.LoadFromFile(Path)
  else
    GenerateBase;

  self.LoadPropertyGroup;
  self.LoadItemGroup;
end;

procedure TDprojFile.LoadSettingsFrom(const Source: string);
begin
  var Dproj := TDprojFile.Create(Source);
  self.LoadSettingsFrom(Dproj);
  FreeAndNil(Dproj);
end;

procedure TDprojFile.LoadItemGroup;
var
  RootNode, ItemGroupNode: IXMLNode;
begin
  RootNode := FXMLDoc.DocumentElement;

  ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');

  if Assigned(ItemGroupNode) then begin
    for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
      var Node := ItemGroupNode.ChildNodes.Get(I);

      {Ресурсы}
      if SameText(Node.LocalName, 'RcCompile') then begin
        var Resource: TResource;
        Resource.Include := node.Attributes['Include'];
        if node.ChildNodes['Form'] <> nil then begin
          Resource.Form := node.ChildNodes['Form'].NodeValue;
        end;
        FResources := FResources + [Resource];
      end;

      {Элементы}
      if SameText(Node.LocalName, 'DCCReference') then begin
        var LocalPath := node.Attributes['Include'];
        var AbsolutePath := CalcPath(LocalPath, self.FPath);
        FUnits.Add(LowerCase(ExtractFileName(AbsolutePath)), AbsolutePath)
      end;

    end;
  end;
end;

{Парсит настройки проекта}
procedure TDprojFile.LoadPropertyGroup;
var
  RootNode, PropertyGroupNode: IXMLNode;
  PlatformType: TPlatformEnum;
  ConfigType: TConfigEnum;
  Field: TFields;
begin
  RootNode := FXMLDoc.DocumentElement;

  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');

  while Assigned(PropertyGroupNode) do begin
    if PropertyGroupNode.AttributeNodes.Count = 0 then begin
    {Парсим основные настройки}
      if PropertyGroupNode.ChildNodes.FindNode('MainSource') <> nil then
        self.MainSettings.FMainSource := PropertyGroupNode.ChildNodes['MainSource'].Text;
      if PropertyGroupNode.ChildNodes.FindNode('Platform') <> nil then
        self.MainSettings.FPlatform.StrValue := PropertyGroupNode.ChildNodes['Platform'].Text;
      if PropertyGroupNode.ChildNodes.FindNode('Config') <> nil then
        self.MainSettings.FConfig.StrValue := PropertyGroupNode.ChildNodes['Config'].Text;
    end else begin
    {Парсим найстроки конфигурации}
      for Field := Low(TFields) to High(TFields) do begin
        if PropertyGroupNode.ChildNodes.FindNode(FieldsStr[Field]) <> nil then begin
          var Text := PropertyGroupNode.ChildNodes[FieldsStr[Field]].Text;
          if not Text.IsEmpty then begin
            var condition := PropertyGroupNode.Attributes['Condition'];
            TryParseCondition(condition, PlatformType, ConfigType);
            self.ConfigSettings[PlatformType][ConfigType][Field] := Text
          end;
        end;
      end;
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;

end;

procedure TDprojFile.LoadSettingsFrom(const Source: TDprojFile);
begin
  self.TakeSettingsFrom(Source);
end;

function TDprojFile.TryParseCondition(const Condition: string;
  out PlatformType: TPlatformEnum; out Config: TConfigEnum): Boolean;
var
  PlatformEnum: TPlatformEnum;
  ConfigEnum: TConfigEnum;
begin
  result := False;
  PlatformType := All;
  Config := Base;
  var Start := Condition.IndexOf('(') + 1;
  var Finish := Condition.IndexOf(')');
  var TrimedCondition := LowerCase(Condition.Substring(Start, Finish - Start));

  for PlatformEnum := Low(TPlatformEnum) to High(TPlatformEnum) do begin
    var Value := LowerCase(GetEnumName(TypeInfo(TPlatformEnum), Ord(PlatformEnum)));
    if TrimedCondition.EndsWith(Value) then begin
      PlatformType := PlatformEnum;
      Break
    end;
  end;

  for ConfigEnum := Low(TConfigEnum) to High(TConfigEnum) do begin
    var Value := LowerCase(GetEnumName(TypeInfo(TConfigEnum), Ord(ConfigEnum)));
    if TrimedCondition.StartsWith(Value) then begin
      Config := ConfigEnum;
      Exit(True);
    end;
  end;
end;

procedure TDprojFile.Refresh;
begin
  self.RefreshPropertyGroup;
  self.RefreshItemGroup;
end;

procedure TDprojFile.RefreshItemGroup;
var
  RootNode, ItemGroupNode: IXMLNode;
  ResourceCounter: Integer;
begin
  ResourceCounter := -1;

  RootNode := FXMLDoc.DocumentElement;

  ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
  if Assigned(ItemGroupNode) then begin
    for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
      var Node := ItemGroupNode.ChildNodes.Get(I);

      if SameText(Node.LocalName, 'RcCompile') then begin
        Inc(ResourceCounter);
        if ResourceCounter < Length(FResources) then begin
          node.Attributes['Include'] := FResources[ResourceCounter].Include;
          if node.ChildNodes['Form'] <> nil then begin
            node.ChildNodes['Form'].NodeValue := FResources[ResourceCounter].Form;
          end;
        end;
      end;

    end;
  end;

  RootNode := nil;
  ItemGroupNode := nil;
end;

procedure TDprojFile.RefreshPropertyGroup;
var
  RootNode, PropertyGroupNode: IXMLNode;
  PlatformType: TPlatformEnum;
  ConfigType: TConfigEnum;
  Field: TFields;
begin
  RootNode := FXMLDoc.DocumentElement;
  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');
  while Assigned(PropertyGroupNode) AND SameText(PropertyGroupNode.NodeName, 'PropertyGroup')  do begin
    if PropertyGroupNode.AttributeNodes.Count = 0 then begin
    {Устанавливаем основные настройки}
      if PropertyGroupNode.ChildNodes.FindNode('MainSource') <> nil then
        PropertyGroupNode.ChildNodes['MainSource'].Text := self.MainSettings.FMainSource;
      if PropertyGroupNode.ChildNodes.FindNode('Platform') <> nil then
        PropertyGroupNode.ChildNodes['Platform'].Text := self.MainSettings.FPlatform.StrValue;
      if PropertyGroupNode.ChildNodes.FindNode('Config') <> nil then
        PropertyGroupNode.ChildNodes['Config'].Text := self.MainSettings.FConfig.StrValue;
    end else begin
    {Устанавливаем настройки конфигураций}
      for Field := Low(TFields) to High(TFields) do begin
        if TryParseCondition(PropertyGroupNode.Attributes['Condition'], PlatformType, ConfigType) then begin
          var Text := self.ConfigSettings[PlatformType][ConfigType][Field];
          if not Text.IsEmpty then begin
            if PropertyGroupNode.ChildNodes.FindNode(FieldsStr[Field]) = nil then begin
              PropertyGroupNode.AddChild(FieldsStr[Field])
            end;
            PropertyGroupNode.ChildNodes[FieldsStr[Field]].Text := self.ConfigSettings[PlatformType][ConfigType][Field];
          end;
        end;
      end;
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;
end;

procedure TDprojFile.SaveFile;
begin
  if not FPath.IsEmpty then begin
    ForceDirectories(GetDownPath(self.FPath));
    FXMLDoc.SaveToFile(self.FPath);
  end;
end;

procedure TDprojFile.TakeSettingsFrom(const Source: TDprojFile);
var
  PlatformValue: TPlatformEnum;
  ConfigValue  : TConfigEnum;
  Field       : TFields;
begin
  self.MainSettings.FConfig.Value := Source.MainSettings.FConfig.Value;
  self.MainSettings.FPlatform.Value := Source.MainSettings.FPlatform.Value;

  for PlatformValue := Low(TPlatformEnum) to High(TPlatformEnum) do begin
    for ConfigValue := Low(TConfigEnum)   to High(TConfigEnum)   do begin
      for Field     := Low(TFields)       to High(TFields)       do begin
        case Field of

          SearchPath: begin
            var SearchPaths := Source.ConfigSettings[PlatformValue][ConfigValue][Field];
            var Arr := SearchPaths.Split([';']);
            for var I := 0 to Length(Arr)-2 do begin
              var AbsolutePath := CalcPath(Arr[I], Source.Path);
              Arr[I] := GetRelativeLink(self.Path, AbsolutePath);
            end;

            // DPK -> DPR
            if (Field = SearchPath) AND (Length(Arr) <> 0) then begin
              if SameText(ExtractFileExt(Source.MainSettings.FMainSource), '.dpk') then begin
                if Arr[0].EndsWith('dcu') then begin
                  var NewArr: TArray<string>;
                  var AbsolutePath := CalcPath(Arr[0], self.Path);
                  AbsolutePath := StringReplace(AbsolutePath, '$(Platform)', Source.MainSettings.FPlatform.StrValue, [rfIgnoreCase]);
                  var Folders := TDirectory.GetDirectories(AbsolutePath);
                  for var Folder in Folders do begin
                    NewArr := NewArr + [Folder];
                  end;
                  Arr := NewArr + [Arr[Length(Arr)-1]];
                end;
              end;
            end;

            self.ConfigSettings[PlatformValue][ConfigValue][Field] := string.Join(';', Arr);
          end;

          HostApplication, OutputDirectory: begin
            var Link := Source.ConfigSettings[PlatformValue][ConfigValue][Field];
            if not  Link.IsEmpty then begin
              var AbsoluteLink := CalcPath(Link, Source.Path);
              AbsoluteLink := GetRelativeLink(self.Path, AbsoluteLink);
              self.ConfigSettings[PlatformValue][ConfigValue][Field] := AbsoluteLink;
            end;
          end;

          NameSpace: begin
            self.ConfigSettings[PlatformValue][ConfigValue][Field] := Source.ConfigSettings[PlatformValue][ConfigValue][Field];
            self.AddValue(PlatformValue, ConfigValue, Field, 'IDL');
          end;

          else begin
            self.ConfigSettings[PlatformValue][ConfigValue][Field] := Source.ConfigSettings[PlatformValue][ConfigValue][Field];
          end;

        end;
      end;
    end;
  end;

  self.Resources := Source.Resources;
  for var I := 0 to Length(self.Resources)-1 do begin
    var Res := self.Resources[I];
    var IncludeAbsolutePath := CalcPath(Res.Include, Source.FPath);
    self.Resources[I].Include := GetRelativeLink(self.FPath, IncludeAbsolutePath);
    var FormAbsolutePath: string;
    if  ExtractFilePath(IncludeAbsolutePath).EndsWith(self.ConfigSettings[All][Base][ResourceOutputPath]) then
      FormAbsolutePath := ExtractFilePath(IncludeAbsolutePath) + ExtractFileName(Res.Form)
    else
      FormAbsolutePath := ExtractFilePath(IncludeAbsolutePath) + self.ConfigSettings[All][Base][ResourceOutputPath] + ExtractFileName(Res.Form);
    self.Resources[I].Form    :=  GetRelativeLink(self.FPath, FormAbsolutePath)
  end;

  self.Refresh;
end;

{ TDpkFile }

constructor TDpkFile.Create(const Path: string);
begin
  FPath := Path;
  FContains := TDictionary<string, string>.Create;
  LoadFromFile;
end;

destructor TDpkFile.Destroy;
begin
  FreeAndNil(FContains);
end;

procedure TDpkFile.LoadFromFile;
var
  List: TStringList;
begin
  List := TStringList.Create;
  List.LoadFromFile(FPath);

  var Line := 0;
  while Line < Pred(List.Count) do begin
    var Text := List.Strings[Line];

    if Text.Contains('requires') then begin
      while not Text.Contains(';') AND (Line < Pred(List.Count)) do begin
        Inc(Line);
        Text := List.Strings[Line];
        FRequires := FRequires + [Text.Trim([',', ';', ' '])];
      end;
    end;

    if Text.Contains('contains') then begin
      while not Text.Contains(';') AND (Line < Pred(List.Count)) do begin
        Inc(Line);
        Text := List.Strings[Line];
        Text := Text.TrimLeft;
        var Words := Text.Split([' ']);
        var Path := Text.Substring(Text.IndexOf('''') + 1, Text.LastIndexOf('''') - Text.IndexOf('''') - 1);
        if not FContains.ContainsKey(Words[0]) then
          FContains.Add(Words[0], Path);
      end;
    end;

    Inc(Line);
  end;
end;

{ TGroupProjFile }

procedure TGroupProjFile.AddProject(const ProjectPath: string);
begin
  if FProjects.IndexOf(ProjectPath) = -1 then begin
    FProjects.Add(ProjectPath);
  end;
end;

constructor TGroupProjFile.Create(const Path: string);
begin
  FProjects := TStringList.Create;
  FPath := Path;
  if FileExists(FPath) then
    LoadProjects;
end;

destructor TGroupProjFile.Destroy;
begin
  FreeAndNil(FProjects);
end;

procedure TGroupProjFile.LoadProjects;
begin
//  var Projects := ParseProjects(FPath);
//  for var Project in Projects do begin
//    var DprojFile := TDprojFile.Create(Project);
//    DprojFile.LoadFromFile(Project); // исправить
//    FProjects.Add(LowerCase(ExtractFileNameWithoutExt(Project)), DprojFile);
//  end;
end;

procedure TGroupProjFile.SaveFile;
var
  GUID: TGUID;
  Strings: TStringList;

  TargetFiles: TArray<string>;
begin
  Strings := TStringList.Create;

  CreateGUID(GUID);

  Strings.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    Strings.Add('<PropertyGroup>');
      Strings.Add(Format('<ProjectGuid>%s</ProjectGuid>', [GUID.ToString]));
    Strings.Add('</PropertyGroup>');
    Strings.Add('<ItemGroup>');
      for var Project in Projects do begin
        Strings.Add(Format('<Projects Include="%s">', [Project]));
          Strings.Add('<Dependencies/>');
        Strings.Add('</Projects>');
      end;
    Strings.Add('</ItemGroup>');
    Strings.Add('<ProjectExtensions>');
      Strings.Add('<Borland.Personality>Default.Personality.12</Borland.Personality>');
      Strings.Add('<Borland.ProjectType/>');
      Strings.Add('<BorlandProject>');
        Strings.Add('<Default.Personality/>');
      Strings.Add('</BorlandProject>');
    Strings.Add('</ProjectExtensions>');

    for var Project in Projects do begin
      var Targets: string;
      for var I := 1 to 3 do begin
        case I of
          2: Targets := 'Clean';
          3: Targets := 'Make';
        end;
        var Name := TStringBuilder.Create;
        Name.Append(ExtractFileNameWithoutExt(Project));
        if not Targets.IsEmpty then begin
          Name.Append(':' + Targets);
        end;

        var msBuildAttr := TStringBuilder.Create;
        msBuildAttr.Append(Format('Projects="%s"', [Project]));
        if not Targets.IsEmpty then begin
          msBuildAttr.Append(Format(' Targets="%s"', [Targets]));
        end;
        msBuildAttr.Append('/');

        Strings.Add(Format('<Target Name="%s">', [Name.ToString]));
          Strings.Add(Format('<MSBuild %s>', [msBuildAttr.ToString]));
        Strings.Add('</Target>');
      end;
      TargetFiles := TargetFiles + [ExtractFileNameWithoutExt(Project)];
    end;

    for var I := 1 to 3 do begin
      var TargetName: string;
      case I of
        1: TargetName := 'Build';
        2: TargetName := 'Clean';
        3: TargetName := 'Make';
      end;

      var FilesString := TStringBuilder.Create;
      for var II := 0 to High(TargetFiles) do begin
        var F := TargetFiles[II];

        FilesString.Append(F);
        if I > 1 then
          FilesString.Append(':' + TargetName);

        if II < High(TargetFiles) then begin
          FilesString.Append(';')
        end;

      end;

      Strings.Add(Format('<Target Name="%s">', [TargetName]));
        Strings.Add(Format('<CallTarget Targets="%s"/>', [FilesString.ToString]));
      Strings.Add('</Target>');
    end;
  Strings.Add('<Import Project="$(BDS)\Bin\CodeGear.Group.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Group.Targets'')"/>');
  Strings.Add('</Project>');

  Strings.SaveToFile(FPath);
end;

procedure TGroupProjFile.SetPath(const Value: string);
begin
  if FileExists(Value) then begin
    FPath := Value;
    LoadProjects;
  end;
end;

end.
