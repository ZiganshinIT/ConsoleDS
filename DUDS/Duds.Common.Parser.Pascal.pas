//------------------------------------------------------------------------------
//
// The contents of this file are subject to the Mozilla Public License
// Version 2.0 (the "License"); you may not use this file except in compliance
// with the License. You may obtain a copy of the License at
// http://www.mozilla.org/MPL/
//
// Alternatively, you may redistribute this library, use and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation; either version 2.1 of the License, or (at your
// option) any later version. You may obtain a copy of the LGPL at
// http://www.gnu.org/copyleft/.
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
// the specific language governing rights and limitations under the License.
//
// Orginally released as freeware then open sourced in July 2017.
//
// The initial developer of the original code is Easy-IP AS
// (Oslo, Norway, www.easy-ip.net), written by Paul Spencer Thornton -
// paul.thornton@easy-ip.net.
//
// (C) 2017 Easy-IP AS. All Rights Reserved.
//
//------------------------------------------------------------------------------

unit Duds.Common.Parser.Pascal;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.RegularExpressions, System.StrUtils,

  DSTypes,

  Duds.Common.Utils,
  Duds.Common.Files,
  Duds.Common.Types,
  Duds.Common.Interfaces,
  Duds.Common.Parser.Pascal.Tokeniser;

type
  TUnitInfo = class(TInterfacedObject, IUnitInfo)
  strict private
    FDelphiUnitName: String;
    FFilename: String;
    FLineCount: Integer;
    FDelphiUnitNamePosition: Integer;
    FDelphiFileType: TDelphiFileType;
    FUsedUnits: TList<IUsedUnitInfo>;
    FOtherUsedItems: TDictionary<string, TArray<string>>;
    FPreviousUnitName: String;
  private
    function GetDelphiUnitName: String;
    function GetDelphiFileType: TDelphiFileType;
    function GetFilename: String;
    function GetLineCount: Integer;
    function GetDelphiUnitNamePosition: Integer;
    function GetUsedUnits: TList<IUsedUnitInfo>;
    function GetOtherUsedItems: TDictionary<string, TArray<string>>;
    function GetPreviousUnitName: String;

    procedure SetDelphiUnitName(const Value: String);
    procedure SetDelphiFileType(const Value: TDelphiFileType);
    procedure SetFilename(const Value: String);
    procedure SetLineCount(const Value: Integer);
    procedure SetDelphiUnitNamePosition(const Value: Integer);
    procedure SetPreviousUnitName(const Value: String);
  public
    property DelphiUnitName: String read GetDelphiUnitName write SetDelphiUnitName;
    property Filename: String read GetFilename write SetFilename;
    property LineCount: Integer read GetLineCount write SetLineCount;
    property DelphiUnitNamePosition: Integer read GetDelphiUnitNamePosition write SetDelphiUnitNamePosition;
    property DelphiFileType: TDelphiFileType read GetDelphiFileType write SetDelphiFileType;
    property UsedUnits: TList<IUsedUnitInfo> read GetUsedUnits;
    property OtherUsedItems: TDictionary<string, TArray<string>> read GetOtherUsedItems;
    property PreviousUnitName: String read GetPreviousUnitName write SetPreviousUnitName;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TUsedUnitInfo = class(TInterfacedObject, IUsedUnitInfo)
  strict private
    FDelphiUnitName: String;
    FPosition: Integer;
    FInFilePosition: Integer;
    FUsesType: TUsedUnitType;
    FFilename: String;
    FOrder: Integer;
  private
    function GetPosition: Integer;
    function GetInFilePosition: Integer;
    function GetDelphiUnitName: String;
    function GetUsesType: TUsedUnitType;
    function GetOrder: Integer;

    procedure SetPosition(const Value: Integer);
    procedure SetInFilePosition(const Value: Integer);
    procedure SetDelphiUnitName(const Value: String);
    procedure SetUsesType(const Value: TUsedUnitType);
    procedure SetOrder(const Value: Integer);
    procedure SetFilename(const Value: String);
    function GetFilename: String;
  public
    property DelphiUnitName: String read GetDelphiUnitName write SetDelphiUnitName;
    property Position: Integer read GetPosition write SetPosition;
    property InFilePosition: Integer read GetInFilePosition write SetInFilePosition;
    property UsesType: TUsedUnitType read GetUsesType write SetUsesType;
    property Order: Integer read GetOrder write SetOrder;
    property Filename: String read GetFilename write SetFilename;
  end;

  TUsedUnits = class(TList<IUsedUnitInfo>);

  TPascalUnitExtractor = class(TComponent)
  private
    FTokeniser: TPascalTokeniser;
    FTokeniser2: TPascalTokeniser;
    FDefineAnalizor: TDefineAnalizator;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function GetUsedUnits(const UnitFileName: String; var UnitInfo: IUnitInfo): Boolean;

    property DefineAnalizator: TDefineAnalizator read FDefineAnalizor;
  end;

const
  DelphiFileTypeStrings: Array[TDelphiFileType] of String = (
    'Unknown',
    'Pascal',
    'Program',
    'Package',
    'Library'
  );

  UsesTypeStrings: Array[TUsedUnitType] of String = (
    'Interface',
    'Implementation',
    'Contains'
  );

implementation

resourcestring
  StrUnsupportedFileType = 'Unsupported file type "%s"';

constructor TPascalUnitExtractor.Create(AOwner: TComponent);
begin
  inherited;

  FTokeniser := TPascalTokeniser.Create;
  FTokeniser2 := TPascalTokeniser.Create;
  FDefineAnalizor := TDefineAnalizator.Create;
end;

destructor TPascalUnitExtractor.Destroy;
begin
  FreeAndNil(FTokeniser);
  FreeAndNil(FTokeniser2);
  FreeAndNil(FDefineAnalizor);

  inherited;
end;

function TPascalUnitExtractor.GetUsedUnits(const UnitFileName: String; var UnitInfo: IUnitInfo): Boolean;

var
  IsAvailable: Boolean;

  function StripQuotes(const Value: String): String;
  begin
    Result := Trim(Value);

    while (Result.Length > 0) and
          (CharInSet(Result[1], ['''', '"'])) do
      Result := copy(Result, 2, MaxInt);

    while (Result.Length > 0) and
          (CharInSet(Result[Result.Length], ['''', '"'])) do
      Result := copy(Result, 1, Result.Length - 1);

    Result := Trim(Result);
  end;

  function SplitText(const Text: string): TArray<string>;
  var
    word: TStringBuilder;
  begin
    word := TStringBuilder.Create;
    for var letter in Text do begin
      if SameText(letter, #13) OR SameText(letter, #10) then begin
        continue;
      end else if SameText(letter, '{') then begin
        if word.Length <> 0 then begin
          result := result + [Trim(word.ToString)];
          word.Clear;
        end;
        word.Append(letter);
      end else if SameText(letter, '}') then begin
        word.Append(letter);
        result := result + [word.ToString];
        word.Clear;
      end else
        word.Append(letter);
    end;
    result := result + [Trim(word.ToString)];
  end;

  procedure ExtractFiles(const ExtsArr: array of string; const FindTo: array of string);

    function IsContains(const Text: string; Token: array of string): Boolean;
    begin
      result := False;
      for var T in Token do begin
        if ContainsText(Text, T) then
          exit(True);
      end;
    end;

    function BuildRegExString(const ExtsArr: array of string): string;
    /// ['.res', '.inc'] -> 'res|inc'
    begin
      var res := TStringBuilder.Create;
      for var Elem in ExtsArr do begin
        for var Ext in Elem.Split([',']) do begin
          if res.Length>0 then
            res.Append('|');
          // имя расширение (без точки в начале)
          res.Append(Trim(Ext).Substring(1, Length(Ext)));
        end;
      end;
      result := res.ToString;
      FreeAndNil(res);
    end;

    procedure Trim(var str: string);
    begin
      str := str.Trim([' ', '"', '''']);
      str := str.TrimStart(['{', '"', '''']);
      str := str.TrimEnd(['}', '"', '''']);
    end;

  var
    ReadModeStore: TReadMode;
  begin
    // сохраняем текущий режим
    ReadModeStore := FTokeniser.ReadMode;

    // Режим "Построчный"
    FTokeniser.ReadMode := byLine;

    // Предстваление массива расширений в допустимый для рег.выражения представлении
    var SearchExt := BuildRegExString(ExtsArr);

    while not (FTokeniser.Eof) AND not (IsContains(FTokeniser.Token.Text, FindTo)) do
    begin

      if TRegEx.IsMatch(FTokeniser.Token.Text, '(\{\$)(.+)(\.)(' + SearchExt + ')(.*)(\})', [roIgnoreCase]) then begin
        var words := FTokeniser.Token.Text.Split([' ']);
        var Extensions := SearchExt.Split(['|']);
        // Поиск
        for var word in words do begin
          var res := word;
          // Отчистка
          Trim(res);
          for var Extension in Extensions do begin

            if ContainsText(res, '.'+Extension) then begin

              // Сохранение
              var Arr: TArray<string>;
              UnitInfo.OtherUsedItems.TryGetValue('.'+Extension, Arr);
              Arr := Arr + [res];
              UnitInfo.OtherUsedItems.AddOrSetValue('.'+Extension, Arr);
              continue
            end;
          end;
        end;

      end else if FTokeniser.Token.Text.StartsWith('{$') then begin
        var words := SplitText(FTokeniser.Token.Text);
        for var w in words do begin
          FDefineAnalizor.Analize(w);
          IsAvailable := FDefineAnalizor.Result;
        end;
      end;
      FTokeniser.Next;
    end;
    // Восставнавливаем режим
    FTokeniser.ReadMode := ReadModeStore;
  end;



  procedure ExtractUnits(UsesType: TUsedUnitType);
  var
    Delimiter: string; // текущий разделитель
    UnitText: string;
    UsedUnitInfo: IUsedUnitInfo;
    InFilePos: Integer;
  begin
    FDefineAnalizor.ClearStack;
//    var IsAvailable := True; // флаг определяющий будет ли добавлен unit
    while not FTokeniser.Eof do begin
      FTokeniser.Next([',' , ';'], Delimiter);

      if not FTokeniser.Eof then begin
        var words := SplitText(FTokeniser.Token.Text);

        for var word in words do begin

          if word.StartsWith('{$') then begin

            FDefineAnalizor.Analize(word);
            IsAvailable := FDefineAnalizor.Result;

          end else if IsAvailable then begin
            UsedUnitInfo := TUsedUnitInfo.Create;
            UnitInfo.UsedUnits.Add(UsedUnitInfo);

            FTokeniser2.Code := word;
            InFilePos := 0;

            if FTokeniser2.Eof then begin
              UnitText := FTokeniser2.Token.Text;
            end else begin
              UnitText := FTokeniser2.Token.Text;
              FTokeniser2.Next;
              if SameText(FTokeniser2.Token.Text, 'in') then
              begin
                FTokeniser2.Next;
                InFilePos := pos(LowerCase(UnitText), LowerCase(FTokeniser2.Token.Text));
                if InFilePos > 0 then
                begin
                  UsedUnitInfo.Filename := ExpandFileNameRelBaseDir(StripQuotes(FTokeniser2.Token.Text), ExtractFilePath(UnitFilename));
                  InFilePos := FTokeniser.Token.Position + FTokeniser2.Token.Position - 1;
                end;
              end;

            end;

            UsedUnitInfo.DelphiUnitName := Trim(UnitText);
            UsedUnitInfo.Position := FTokeniser.Token.Position - 1;
            UsedUnitInfo.InFilePosition := InFilePos;
            UsedUnitInfo.UsesType := UsesType;
            UsedUnitInfo.Order := UnitInfo.UsedUnits.Count - 1;

          end;
        end;
        if Delimiter = ';' then
          Break;
      end;
    end;
  end;

const
  InterfaceStr = 'interface';
  ImplementationStr = 'implementation';
  UsesStr = 'uses';
  ContainsStr = 'contains';
  UnitStr = 'unit';
  ProgramStr = 'program';
  PackageStr = 'package';
  LibraryStr = 'library';

  ResourceExts = '.res, .rc, .dres';
  IncludeExts  = '.inc, .obj';
  OtherExts    = '.dfm';
var
  UnitStrings: TStringList;
  Extension: String;
begin
  Result := TRUE;

  FDefineAnalizor.ClearStack;
  FDefineAnalizor.ClearFileDefine;
  IsAvailable := True;

  UnitInfo := TUnitInfo.Create;
  UnitInfo.Filename := UnitFileName;

  Extension := ExtractFileExt(UnitFilename);

  UnitStrings := TStringList.Create;
  try
    UnitStrings.LoadFromFile(UnitFilename);
    UnitInfo.LineCount := UnitStrings.Count;
    FTokeniser.Code := UnitStrings.Text;
  finally
    FreeAndNil(UnitStrings);
  end;

  ExtractFiles([ResourceExts, IncludeExts, OtherExts], [UnitStr, ProgramStr, PackageStr, LibraryStr]);

  if FTokeniser.Token.Text.Contains(UnitStr) then
    UnitInfo.DelphiFileType := ftPAS else
  if FTokeniser.Token.Text.Contains(ProgramStr) then
    UnitInfo.DelphiFileType := ftDPR else
  if FTokeniser.Token.Text.Contains(PackageStr) then
    UnitInfo.DelphiFileType := ftDPK else
  if FTokeniser.Token.Text.Contains(LibraryStr) then
    UnitInfo.DelphiFileType := ftLIB
  else
  begin
    UnitInfo.DelphiFileType := ftUnknown;
    Exit(FALSE);
  end;

  // Move to the unit name
  FTokeniser.Next;

  UnitInfo.DelphiUnitName := FTokeniser.Token.Text;

  if SameText(UnitInfo.DelphiUnitName, 'gp') then
    var a := 1;

  if SameText(UnitInfo.DelphiUnitName, ExtractFilenameNoExt(UnitFilename)) then
  begin
    // This should always be the case as a unit name should match the filename
    UnitInfo.DelphiUnitNamePosition := FTokeniser.Token.Position - 1;
  end;

  case UnitInfo.DelphiFileType of
    ftPAS:
      begin
        ExtractFiles([ResourceExts, IncludeExts, OtherExts], [InterfaceStr]);
        if FTokeniser.FindNextToken(InterfaceStr) then
        begin
          ExtractFiles([ResourceExts, IncludeExts, OtherExts], [UsesStr, ImplementationStr]);
          if FTokeniser.FindNextToken([UsesStr, ImplementationStr]) then
          begin
            if SameText(FTokeniser.Token.Text, UsesStr)   then
            begin
              ExtractUnits(utInterface);
              ExtractFiles([ResourceExts, IncludeExts, OtherExts], [ImplementationStr]);
              if not FTokeniser.FindNextToken(ImplementationStr) then
                Exit;
            end;
            ExtractFiles([ResourceExts, IncludeExts, OtherExts], [UsesStr]);
            if FTokeniser.FindNextToken(UsesStr) then
              ExtractUnits(utImplementation);
            ExtractFiles([ResourceExts, IncludeExts, OtherExts], ['']);
          end;
        end;
      end;

    ftDPR,
    ftLIB:
      begin
        ExtractFiles([ResourceExts, IncludeExts, OtherExts], [UsesStr]);
        if FTokeniser.FindNextToken(UsesStr) then begin
          ExtractUnits(utImplementation);
        end;
        ExtractFiles([ResourceExts, IncludeExts, OtherExts], ['']);
      end;

    ftDPK:
      begin
        ExtractFiles([ResourceExts, IncludeExts, OtherExts], [ContainsStr]);
        if FTokeniser.FindNextToken(ContainsStr) then
          ExtractUnits(utContains);
        ExtractFiles([ResourceExts, IncludeExts, OtherExts], ['']);
      end;
    // Unknown file type
    else
      Result := FALSE;
  end;
end;

{ TUnitInfo }

function TUsedUnitInfo.GetFilename: String;
begin
  Result := FFilename;
end;

function TUsedUnitInfo.GetInFilePosition: Integer;
begin
  Result := FInFilePosition;
end;

function TUsedUnitInfo.GetPosition: Integer;
begin
  Result := FPosition;
end;

function TUsedUnitInfo.GetDelphiUnitName: String;
begin
  Result := FDelphiUnitName;
end;

function TUsedUnitInfo.GetUsesType: TUsedUnitType;
begin
  Result := FUsesType;
end;

procedure TUsedUnitInfo.SetInFilePosition(const Value: Integer);
begin
  FInFilePosition := Value;
end;

procedure TUsedUnitInfo.SetPosition(const Value: Integer);
begin
  FPosition := Value;
end;

procedure TUsedUnitInfo.SetDelphiUnitName(const Value: String);
begin
  FDelphiUnitName := Value;
end;

procedure TUsedUnitInfo.SetFilename(const Value: String);
begin
  FFilename := Value;
end;

procedure TUsedUnitInfo.SetUsesType(const Value: TUsedUnitType);
begin
  FUsesType := Value;
end;

function TUsedUnitInfo.GetOrder: Integer;
begin
  Result := FOrder;
end;

procedure TUsedUnitInfo.SetOrder(const Value: Integer);
begin
  FOrder := Value;
end;

{ TUnitInfo }

constructor TUnitInfo.Create;
begin
  FUsedUnits := TList<IUsedUnitInfo>.Create;
  FOtherUsedItems := TDictionary<string, TArray<string>>.Create;
end;

destructor TUnitInfo.Destroy;
begin
  FreeAndNil(FUsedUnits);
  FreeAndNil(FOtherUsedItems);

  inherited;
end;

function TUnitInfo.GetDelphiFileType: TDelphiFileType;
begin
  Result := FDelphiFileType;
end;

function TUnitInfo.GetFilename: String;
begin
  Result := FFilename;
end;

function TUnitInfo.GetLineCount: Integer;
begin
  Result := FLineCount;
end;

function TUnitInfo.GetOtherUsedItems: TDictionary<string, TArray<string>>;
begin
  Result := FOtherUsedItems;
end;

function TUnitInfo.GetPreviousUnitName: String;
begin
  Result := FPreviousUnitName;
end;

function TUnitInfo.GetDelphiUnitName: String;
begin
  Result := FDelphiUnitName;
end;

function TUnitInfo.GetDelphiUnitNamePosition: Integer;
begin
  Result := FDelphiUnitNamePosition;
end;

function TUnitInfo.GetUsedUnits: TList<IUsedUnitInfo>;
begin
  Result := FUsedUnits;
end;

procedure TUnitInfo.SetDelphiFileType(const Value: TDelphiFileType);
begin
  FDelphiFileType := Value;
end;

procedure TUnitInfo.SetFilename(const Value: String);
begin
  FFilename := Value;
end;

procedure TUnitInfo.SetLineCount(const Value: Integer);
begin
  FLineCount := Value;
end;

procedure TUnitInfo.SetPreviousUnitName(const Value: String);
begin
  FPreviousUnitName := Value;
end;

procedure TUnitInfo.SetDelphiUnitName(const Value: String);
begin
  FDelphiUnitName := Value;
end;

procedure TUnitInfo.SetDelphiUnitNamePosition(const Value: Integer);
begin
  FDelphiUnitNamePosition := Value;
end;

end.
