unit DSCacher;

interface

uses
  System.SysUtils, System.Classes, System.Types;

type

  TCacher = class
  private
    FList: TStringList;
    FGroupProjFile: string;

    FIsUnitCache : Boolean;
    FCurrentFileName: string;
    FUnitName: string;
    FUnits: TArray<string>;
    FIndex: Integer;
  protected

  public
    constructor Create(const GroupProjFile: string);

    procedure Load(const DprojName: string);

    procedure StartCacheUnit(const UnitPath: string);
    procedure AddElement(const ElementPath: string);
    procedure EndCacheUnit;

    procedure Save;

    function TryGetUnits(const UnitName: string; var Arr: TArray<string>): Boolean;

    property IsUnitCache: Boolean read FIsUnitCache;

    destructor Destroy;
  end;

implementation

{ TCacher }

constructor TCacher.Create(const GroupProjFile: string);
begin
  FGroupProjFile := GroupProjFile;
  FList := TStringList.Create;
end;

destructor TCacher.Destroy;
begin
  FreeAndNil(FList);
end;

procedure TCacher.Save;
begin
  FList.SaveToFile(FCurrentFileName);
end;

procedure TCacher.StartCacheUnit(const UnitPath: string);
begin
  if FIsUnitCache then
    raise Exception.Create('Процесс кэширования уже начата');
  FIsUnitCache := True;
  SetLength(FUnits, 0);
  FUnitName := UnitPath;
  FIndex := FList.Count;
    for var I := 0 to FList.Count-1 do begin
      if FList.Strings[I].StartsWith(UnitPath) then begin
        FIndex := i;
        break;
      end;
    end;
end;

function TCacher.TryGetUnits(const UnitName: string; var Arr: TArray<string>): Boolean;
begin
  var UnitAge := FileAge(UnitName);
  var I := 0;
  while I < FList.Count do begin
    var Line := FList.Strings[I].Trim;
    result := Line.StartsWith(UnitName);
    if result then begin
      var StartAge := Line.IndexOf('{') + 1;
      var FinishAge := Line.IndexOf('}');
      var AgeStr :=  Line.Substring(StartAge, FinishAge-StartAge);
      var AgeInt := Integer.Parse(AgeStr);

      result := FileAge(UnitName) = AgeInt;
      if result then begin
        var Start := Line.IndexOf('[') + 1;
        var Finish := Line.IndexOf(']');
        var UnitsTxt := Line.Substring(Start, Finish - Start);
        Arr := UnitsTxt.Split([';']);
        exit;
      end;
    end;
    Inc(I);
  end;
end;

procedure TCacher.AddElement(const ElementPath: string);
begin
  if FIsUnitCache then begin
    FUnits := FUnits + [ElementPath];
  end;
end;

procedure TCacher.EndCacheUnit;
begin
  FIsUnitCache := False;
  var Text := FUnitName + ' {' + FileAge(FUnitName).ToString  + '}' + ' [' + string.Join(';', FUnits) + ']';
  FList.Insert(FIndex, Text);
end;

procedure TCacher.Load(const DprojName: string);
begin
  FList.Clear;
  var APPDATA := GetEnvironmentVariable('APPDATA');
  var GPName  := StringReplace(ExtractFileName(FGroupProjFile), ExtractFileExt(FGroupProjFile), '', [rfIgnoreCase]);
  var GPAge   := FileAge(FGroupProjFile);
  var SFName  := StringReplace(ExtractFileName(DprojName), ExtractFileExt(DprojName), '', [rfIgnoreCase]);
  var SFAge   := FileAge(DprojName);

  FCurrentFileName := APPDATA + '\' + GPName + '_' + GPAge.ToString + '_' + SFName + '.cache';

  if FileExists(FCurrentFileName) then begin
    FList.LoadFromFile(FCurrentFileName);
  end;
end;

end.
