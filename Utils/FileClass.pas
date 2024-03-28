unit FileClass;

interface

uses
  Winapi.ActiveX,

  System.SysUtils, System.Classes, System.IOUtils, System.TypInfo, System.RegularExpressions,
  System.StrUtils,

  XMLDoc, XMLIntf,

  DSUtils, DSTypes;

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
  {�������� ��������� �������}
  TMainSettings = record
    FMainSource: string;
    FPlatform:  TPlatform;
    FConfig:    TConfig;
  end;

  {���������������� ���������}
  TConfigSettings = array [TPlatformEnum, TConfigEnum, TSettingsFields] of string;

  TResource = record
    Include: string;
    Form: string;
  end;

  TDprojFile = class
  private
    FName: string;
    FPath: string;
    FXMLDoc: IXMLDocument;
    procedure ParseCondition(const Condition: string;
      out PlatformType: TPlatformEnum;
      out Config: TConfigEnum);
    function CreateNew(const FilePath: string): TDprojFile;
  protected
    // Item Group
    FResources: TArray<TResource>;
    procedure RelinkAll(const Dest: TDprojFile);
  public
    // Property Groups
    MainSettings: TMainSettings;
    ConfigSettings: TConfigSettings;

    // Load Operations
    procedure LoadPropertyGroup;
    procedure LoadItemGroup;

    // Refresh Operations
    procedure RefreshPropertyGroup;
    procedure RefreshItemGroup;
  public
    constructor Create;                                                         overload;
    constructor Create(const Path: string);                                     overload;

    // Save\Load Operations
    procedure LoadFromFile(const Path: string);
    procedure SaveFile(const FilePath: string);

    function CreateCopy(const FilePath: string): TDprojFile;

    procedure Refresh;

    // Getters
    function GetDefinies(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): TArray<string>;                       overload;
    function GetDefinies(const PlatformTyp: array of TPlatformEnum; const ConfigTyp: array of TConfigEnum): TArray<string>;     overload;

    function GetSearchPath(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): TArray<string>;
    function GetDebuggerSourcePath(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): TArray<string>;

    function GetHostApplication(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum): string;

    //Setters
    procedure SetDefines(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum; const Defines: TArray<string>);
    procedure SetSearchPath(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum; const SearchPaths: TArray<string>);

    procedure SetHostApplication(const PlatformTyp: TPlatformEnum; const ConfigTyp: TConfigEnum; HostApplication: string);

    property Resources: TArray<TResource> read FResources write FResources;
    property Path: string read FPath;

    destructor Destroy;
  end;

    TDprFile = class
  private
    FName: string;
    FPath: string;
    FStrings: TStringList;
    FDprojFile: TDprojFile;
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

              var FilePath := CalcPath(NewPath, ParamStr(1));
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
      {���������� ���������� uses}
      while (not Text.Contains(';')) AND (Line < FStrings.Count) do begin
        Inc(Line);
        Text := FStrings[Line];
      end;
      Inc(Line);
      {��������� uses}
      List.Sort;

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

constructor TDprojFile.Create(const Path: string);
begin
  FXMLDoc := TXMLDocument.Create(nil);
  self.LoadFromFile(Path);
end;

function TDprojFile.CreateCopy(const FilePath: string): TDprojFile;
begin
  result := TDprojFile.Create;
  result.LoadFromFile(self.FPath);
  result.FPath := FilePath;

  self.RelinkAll(result);
end;

function TDprojFile.CreateNew(const FilePath: string): TDprojFile;
begin
  result := TDprojFile.Create;
  result.LoadFromFile(self.FPath);
  result.FPath := FilePath;

end;

constructor TDprojFile.Create;
begin
 FXMLDoc := TXMLDocument.Create(nil);
end;

destructor TDprojFile.Destroy;
begin
  FXMLDoc := nil;
end;

function TDprojFile.GetDebuggerSourcePath(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum): TArray<string>;
begin
  var DebuggerSourcePath := Self.ConfigSettings[PlatformTyp][ConfigTyp][DebuggerSourcePath];
  var Arr := DebuggerSourcePath.Split([';']);
  for var I := 0 to Length(Arr)-2 do begin
    result := result + [Arr[I]];
  end;
end;

function TDprojFile.GetDefinies(const PlatformTyp: array of TPlatformEnum;
  const ConfigTyp: array of TConfigEnum): TArray<string>;
var
  pe: TPlatformEnum;
  ce: TConfigEnum;
begin
  for pe in PlatformTyp do begin
    for ce in ConfigTyp do begin
      result := result + self.GetDefinies(pe, ce);
    end;
  end;
end;

function TDprojFile.GetHostApplication(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum): string;
begin
  result := Self.ConfigSettings[PlatformTyp][ConfigTyp][Debugger_HostApplication];
end;

function TDprojFile.GetDefinies(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum): TArray<string>;
begin
  var Defines := Self.ConfigSettings[PlatformTyp][ConfigTyp][Definies];
  var Arr := Defines.Split([';']);
  for var I := 0 to Length(Arr)-2 do begin
    result := result + [Arr[I]];
  end;
end;

function TDprojFile.GetSearchPath(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum): TArray<string>;
begin
  var SearchPath := Self.ConfigSettings[PlatformTyp][ConfigTyp][SearchPath];
  var Arr := SearchPath.Split([';']);
  for var I := 0 to Length(Arr)-2 do begin
    result := result + [Arr[I]];
  end;
end;

procedure TDprojFile.LoadFromFile(const Path: string);
begin
  CoInitializeEx(nil, COINIT_MULTITHREADED);

  FPath := Path;
  FXMLDoc.LoadFromFile(Path);

  self.LoadPropertyGroup;
  self.LoadItemGroup;

end;

{������ �������� ������}
procedure TDprojFile.LoadItemGroup;
var
  RootNode, ItemGroupNode: IXMLNode;
begin
  RootNode := FXMLDoc.DocumentElement;

  ItemGroupNode := RootNode.ChildNodes.FindNode('ItemGroup');
  if Assigned(ItemGroupNode) then begin
    for var I := 0 to ItemGroupNode.ChildNodes.Count-1 do begin
      var Node := ItemGroupNode.ChildNodes.Get(I);

      if SameText(Node.LocalName, 'RcCompile') then begin
        var Resource: TResource;
        Resource.Include := node.Attributes['Include'];
        if node.ChildNodes['Form'] <> nil then begin
          Resource.Form := node.ChildNodes['Form'].NodeValue;
        end;
        FResources := FResources + [Resource];
      end;

    end;
  end;

  RootNode := nil;
  ItemGroupNode := nil;
end;

{������ ��������� �������}
procedure TDprojFile.LoadPropertyGroup;
var
  RootNode, PropertyGroupNode: IXMLNode;
  SettingField: TSettingsFields;
  PlatformType: TPlatformEnum;
  ConfigType: TConfigEnum;
begin
  RootNode := FXMLDoc.DocumentElement;

  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');

  while Assigned(PropertyGroupNode) do begin
    if PropertyGroupNode.AttributeNodes.Count = 0 then begin
    // ������ �������� ���������
      if PropertyGroupNode.ChildNodes.FindNode('MainSource') <> nil then
        self.MainSettings.FMainSource := PropertyGroupNode.ChildNodes['MainSource'].Text;
      if PropertyGroupNode.ChildNodes.FindNode('Platform') <> nil then
        self.MainSettings.FPlatform.SetPlatform(PropertyGroupNode.ChildNodes['Platform'].Text);
      if PropertyGroupNode.ChildNodes.FindNode('Config') <> nil then
        self.MainSettings.FConfig.SetConfig(PropertyGroupNode.ChildNodes['Config'].Text);
    end else begin
    // ������ ��������� ������������
      // ���������� ����
      for SettingField := Low(TSettingsFields) to High(TSettingsFields) do begin
        if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[SettingField]) <> nil then begin
          var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[SettingField]].Text;
          if not Text.IsEmpty then begin
            var condition := PropertyGroupNode.Attributes['Condition'];
            // �������� ������� �����������
            ParseCondition(condition, PlatformType, ConfigType);
            self.ConfigSettings[PlatformType][ConfigType][SettingField] := Text
          end;
        end;
      end;
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;

end;

procedure TDprojFile.ParseCondition(const Condition: string;
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
  SettingField: TSettingsFields;
  PlatformType: TPlatformEnum;
  ConfigType: TConfigEnum;
begin
  RootNode := FXMLDoc.DocumentElement;

  PropertyGroupNode := RootNode.ChildNodes.FindNode('PropertyGroup');

  while Assigned(PropertyGroupNode) do begin
    if PropertyGroupNode.AttributeNodes.Count = 0 then begin
    // ������������� �������� ���������
      if PropertyGroupNode.ChildNodes.FindNode('MainSource') <> nil then
        PropertyGroupNode.ChildNodes['MainSource'].Text := self.MainSettings.FMainSource;
      if PropertyGroupNode.ChildNodes.FindNode('Platform') <> nil then
        PropertyGroupNode.ChildNodes['Platform'].Text := self.MainSettings.FPlatform.GetPlatformAsStr;
      if PropertyGroupNode.ChildNodes.FindNode('Config') <> nil then
        PropertyGroupNode.ChildNodes['Config'].Text := self.MainSettings.FConfig.GetConfigAsStr

    end else begin
    // ������������� ��������� ������������
      // ���������� ����
      for SettingField := Low(TSettingsFields) to High(TSettingsFields) do begin
        if PropertyGroupNode.ChildNodes.FindNode(SettingsFieldsStr[SettingField]) <> nil then begin
          var Text := PropertyGroupNode.ChildNodes[SettingsFieldsStr[SettingField]].Text;
          if not Text.IsEmpty then begin
            var condition := PropertyGroupNode.Attributes['Condition'];
            // �������� ������� �����������
            ParseCondition(condition, PlatformType, ConfigType);

            PropertyGroupNode.ChildNodes[SettingsFieldsStr[SettingField]].Text := self.ConfigSettings[PlatformType][ConfigType][SettingField];
          end;
        end;
      end;
    end;
    PropertyGroupNode := PropertyGroupNode.NextSibling;
  end;

end;

procedure TDprojFile.RelinkAll(const Dest: TDprojFile);
begin
  Dest.MainSettings.FMainSource := ExtractFileNameWithoutExt(Dest.FPath) + '.dpr';

  var spArr := Dest.GetSearchPath(All, Base);
    for var I := 0 to Length(spArr)-1 do begin
      var spPath := CalcPath(spArr[I], self.Path);
      spArr[I] := GetRelativeLink(Dest.Path, spPath);
    end;

    Dest.SetSearchPath(All, Base, spArr);

    for var pe := Low(TPlatformEnum) to High(TPlatformEnum) do begin
      for var ce := Low(TConfigEnum) to High(TConfigEnum) do begin

      var HA := Dest.GetHostApplication(pe, ce);
      HA := CalcPath(HA, self.FPath);
      Dest.SetHostApplication(pe, ce, GetRelativeLink(Dest.Path, HA));

      end;
    end;

    var Prefix := Dest.ConfigSettings[All][Base][ResourceOutputPath];
    var ResArr := Dest.Resources;
    for var I := 0 to Length(ResArr)-1 do begin
      // Include
      var Include := CalcPath(ResArr[I].Include, self.Path);
      ResArr[I].Include := GetRelativeLink(Dest.Path, Include);
      //Form
      if not ResArr[I].Form.Contains(Prefix) then
        ResArr[I].Form := Prefix + '\' + ResArr[I].Form;
      var Form := CalcPath(ResArr[I].Form, self.Path);
      ResArr[I].Form := GetRelativeLink(Dest.Path, Form);

    end;

    Dest.Refresh;
end;

procedure TDprojFile.SaveFile(const FilePath: string);
begin
  ForceDirectories(GetDownPath(FilePath));
  FXMLDoc.SaveToFile(FilePath);

end;

procedure TDprojFile.SetDefines(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum; const Defines: TArray<string>);
begin
  var Arr := Defines;
  Arr := Arr + ['$(DCC_Define)'];
  Self.ConfigSettings[PlatformTyp][ConfigTyp][Definies] := string.Join(';', Arr);
end;

procedure TDprojFile.SetHostApplication(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum; HostApplication: string);
begin
  Self.ConfigSettings[PlatformTyp][ConfigTyp][Debugger_HostApplication] := HostApplication;
end;

procedure TDprojFile.SetSearchPath(const PlatformTyp: TPlatformEnum;
  const ConfigTyp: TConfigEnum; const SearchPaths: TArray<string>);
begin
  var Arr := SearchPaths;
  Arr := Arr + ['$(DCC_UnitSearchPath)'];
  Self.ConfigSettings[PlatformTyp][ConfigTyp][SearchPath] := string.Join(';', Arr);
end;

end.
