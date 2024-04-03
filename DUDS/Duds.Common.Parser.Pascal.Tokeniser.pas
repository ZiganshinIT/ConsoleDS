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

unit Duds.Common.Parser.Pascal.Tokeniser;

interface

uses
  Classes, SysUtils, System.RegularExpressions;

const
  Junk: Array[0..3] of String = (
    #09,
    ' ',
    #13,
    #10
    //';'
  );

  LineDelimiters: Array[0..0] of String = (
    #13#10
  );

  WordDelimiters: Array[0..2] of String = (
    ' ',
    #13#10,
    ';'
  );

  CommentBegin: Array[0..2] of String = (
    '//',
    '{',
    '(*'
  );

  CommentEnd: Array[0..2] of String = (
    #13#10,
    '}',
    '*)'
  );

type
  TReadMode = (
    byWord,
    byLine
  );

  TInComment = (
    icNone,
    icDoubleSlash,
    icCurlyBracket,
    icSlashStar
  );

  TPascalToken = record
  public
    Text: String;
    Position: Integer;
  end;

  TPascalTokeniser = class(TInterfacedObject)
  private
    FLastPosition, FPosition: Integer;
    FToken: TPascalToken;
    FReadMode: TReadMode;
    FCode: String;
  protected
    procedure SkipJunk;
    procedure NextChar;
    function IsJunk(var JunkText: String): Boolean;
    function Matches(const Value: String): Boolean; overload;
    function Matches(const Value: String; Position: Integer): Boolean overload;
    function Matches(const Values: Array of String; var MatchValue: String; var Index: Integer): Boolean; overload;
    function Matches(const Values: array of String): Boolean; overload;
    function Matches(const Values: array of String; var MatchValue: String): Boolean; overload;
    function Matches(const Values: array of String; var MatchIndex: Integer): Boolean; overload;
    procedure SkipText(const Value: String);
    procedure SetCode(const Value: String);
    procedure SetReadMode(const Value: TReadMode);
  public
    procedure First;
    procedure Next; overload;
    procedure Next(const Delimiters: Array of String); overload;
    procedure Next(const Delimiters: Array of String; var MatchedDelimiter: String); overload;

    procedure Next(var MatchedDelimiter: String); overload;

    procedure NextLine;
    function Token: TPascalToken;
    function Eof: Boolean;
    function Position: Integer;
    function FindNextToken(const Token: String): Boolean; overload;
    function FindNextToken(const Tokens: array of String): Boolean; overload;

    function FindNextStartsWithToken(const Token: String): Boolean;
    function FindNextEndsWithToken(const Token: String): Boolean;

    property Code: String read FCode write SetCode;
    property ReadMode: TReadMode read FReadMode write SetReadMode;
  end;

  TDefineType =
  (
    _IFDEF,
    _IFNDEF,
    _ELSEIF,
    _ELSE,
    _ENDIF,
    _DEFINE,
    _NONE
  );

  TDefine = record
    DefineTyp: TDefineType;
    Expression: string;
    IsEnable: Boolean;
  end;

  TDefineAnalizator = class
  private
    FFileDefine: TArray<string>;
    FStack: TArray<TDefine>;
    FEnableDefines: TStringList;
    FResult: Boolean;
    procedure TrimDefine(var define: string);
    function GetDefineType(const Define: string): TDefineType;
    function GetDefineExpression(const Define: string): string;
    function IsDefineEnable(const Define: string): Boolean;

    // Stack
    procedure Add(const define: TDefine);
    procedure Remove;
    function Top: TDefine;
  public
    constructor Create;

    procedure Analize(const Defines: string);
    procedure ClearStack;
    procedure ClearFileDefine;

    property Result: Boolean read FResult;
    property EnableDefines: TStringList read FEnableDefines write FEnableDefines;
    property Stack: TArray<TDefine> read FStack;

    function GetDefines: TArray<string>;

    destructor Destroy;
  end;

implementation

{ TPascalParser }

function TPascalTokeniser.Eof: Boolean;
begin
  Result := FPosition > length(FCode);
end;

procedure TPascalTokeniser.First;
begin
  FToken.Text := '';
  FToken.Position := 0;
  FPosition := 1;
  FReadMode := byWord;

  SkipJunk;
  Next;
end;

function TPascalTokeniser.Matches(const Value: String): Boolean;
begin
  Result := SameText(Value, copy(FCode, FPosition, length(Value)));
end;

function TPascalTokeniser.Matches(const Value: String;
  Position: Integer): Boolean;
begin
  Result := SameText(Value, copy(FCode, Position, length(Value)));
end;

function TPascalTokeniser.Matches(const Values: Array of String; var MatchValue: String; var Index: Integer): Boolean;
var
  i: Integer;
begin
  Result := FALSE;
  Index := 0;
  MatchValue := '';

  for i := Low(Values) to High(Values) do
    if (Matches(Values[i]) AND (not Matches('$', FPosition+1))) then
    begin
      Result := TRUE;
      MatchValue := Values[i];
      Index := i;

      Break;
    end;
end;

function TPascalTokeniser.Matches(const Values: Array of String; var MatchValue: String): Boolean;
var
  MatchIndex: Integer;
begin
  Result := Matches(Values, MatchValue, MatchIndex);
end;

function TPascalTokeniser.Matches(const Values: Array of String; var MatchIndex: Integer): Boolean;
var
  MatchValue: String;
begin
  Result := Matches(Values, MatchValue, MatchIndex);
end;

function TPascalTokeniser.Matches(const Values: Array of String): Boolean;
var
  MatchValue: String;
  MatchIndex: Integer;
begin
  Result := Matches(Values, MatchValue, MatchIndex);
end;

function TPascalTokeniser.IsJunk(var JunkText: String): Boolean;
begin
  Result := Matches(Junk, JunkText);
end;

procedure TPascalTokeniser.SetCode(const Value: String);
begin
  FCode := Value;

  First;
end;

procedure TPascalTokeniser.SetReadMode(const Value: TReadMode);
begin
  FReadMode := Value;
  FPosition := FLastPosition;
  Next;
end;

procedure TPascalTokeniser.SkipJunk;
var
  JunkText: String;
begin
  while (not Eof) and (IsJunk(JunkText))do
    SkipText(JunkText);
end;

function TPascalTokeniser.FindNextToken(const Token: String): Boolean;
begin
  Result := FALSE;

  while not Eof do
  begin
    if SameText(FToken.Text, Token) Or FToken.Text.StartsWith(Token) then
    begin
      Result := TRUE;

      Break;
    end
    else
      Next;
  end;
end;

function TPascalTokeniser.FindNextEndsWithToken(const Token: String): Boolean;
begin
  RESULT := FALSE;

  while not Eof do
  begin
    if FToken.Text.EndsWith(Token) then
    begin
      RESULT := TRUE;

      Break;
    end else
      Next;
  end;
end;

function TPascalTokeniser.FindNextStartsWithToken(const Token: String): Boolean;
begin
  RESULT := FALSE;

  while not Eof do
  begin
    if FToken.Text.StartsWith(Token) then
    begin
      RESULT := TRUE;

      Break;
    end else
      Next;
  end;
end;

function TPascalTokeniser.FindNextToken(const Tokens: Array of String): Boolean;
var
  i: Integer;
  ReadModeStore: TReadMode;
begin
  Result := FALSE;

  while not Eof do
  begin

    for i := Low(Tokens) to High(Tokens) do
    begin

      if LowerCase(FToken.Text).StartsWith(Tokens[I]) then begin
        RESULT := TRUE;

        exit;
      end;

    end;
    Next;
  end;
end;

procedure TPascalTokeniser.Next(const Delimiters: array of String; var MatchedDelimiter: String);
var
  InComment: TInComment;
  MatchIndex: Integer;
  MatchValue: String;
begin
  FLastPosition := FPosition;
  FToken.Text := '';
  FToken.Position := -1;;

  InComment := icNone;

  while not Eof do
  begin
    // Are we starting a comment
    // If we're alrady in a comment, we can|t start a new one
    if InComment = icNone then
    begin
      if Matches(Delimiters, MatchedDelimiter) then
      begin
        SkipText(MatchedDelimiter);

        Break;
      end;

      if Matches(CommentBegin, MatchValue, MatchIndex) then
      begin
        // Set the tyoe of comment we are in
        InComment := TInComment(MatchIndex + 1);

        // Increment the position past the comment identifier
        SkipText(MatchValue);
      end;
    end;

    // Only check for identifiers if we're not in a comment
    if InComment = icNone then
    begin
      if FToken.Position = -1 then
        FToken.Position := FPosition;

      FToken.Text := FToken.Text + FCode[FPosition];
    end;

    // Are we in a comment and about to exit?
    if (InComment <> icNone) and
       (Matches(CommentEnd[Integer(InComment) - 1], MatchValue, MatchIndex)) then
    begin
      // Set the tyoe of comment we are in
      InComment := icNone;

      // Increment the position past the comment identifier
      SkipText(MatchValue);

      SkipJunk;

      Continue;
    end;

    NextChar;
  end;

  SkipJunk;
end;

procedure TPascalTokeniser.Next(const Delimiters: array of String);
var
  MatchedDelimiter: String;
begin
  Next(Delimiters, MatchedDelimiter);
end;

procedure TPascalTokeniser.NextChar;
begin
  FPosition := FPosition + 1
end;

procedure TPascalTokeniser.NextLine;
begin
  FToken.Text := '';
  FToken.Position := -1;
  while not Eof do
  begin
    if Matches(#13#10) then begin
      SkipText(#13#10);
      SkipJunk;
      break
    end else
      NextChar;
    FToken.Text := FToken.Text + FCode[FPosition-1];
  end;

end;

procedure TPascalTokeniser.SkipText(const Value: String);
begin
  FPosition := FPosition + length(Value);
end;

procedure TPascalTokeniser.Next;
begin
  case FReadMode of
    byWord: Next(WordDelimiters);
    byLine: Next(LineDelimiters);
  end;
end;

function TPascalTokeniser.Position: Integer;
begin
  Result := FToken.Position;
end;

function TPascalTokeniser.Token: TPascalToken;
begin
  Result := FToken;
end;

procedure TPascalTokeniser.Next(var MatchedDelimiter: String);
begin
  case FReadMode of
    byWord: Next(WordDelimiters, MatchedDelimiter);
    byLine: Next(LineDelimiters, MatchedDelimiter);
  end;
end;

{ TDefineAnalizator }

procedure TDefineAnalizator.Add(const define: TDefine);
begin
  FStack := FStack + [define];
end;

procedure TDefineAnalizator.Analize(const Defines: string);
var
  Offset: Integer;

  function GetNext: string;
  begin
    result := '';
    var OpenDefineIndex := Defines.IndexOf('{$', Offset);
    var CloseDefineIndex := Defines.IndexOf('}', Offset) + 1;
    if OpenDefineIndex <> -1 then begin
      result := Defines.Substring(OpenDefineIndex, CloseDefineIndex - OpenDefineIndex);
      Offset := CloseDefineIndex;
    end;
  end;

begin
  Offset := 0;
  var define := GetNext;
  while not define.IsEmpty do begin

    var d: TDefine;
    d.DefineTyp := GetDefineType(define);
    d.Expression := GetDefineExpression(define);
    d.IsEnable := IsDefineEnable(define);

    case d.DefineTyp of

      _IFDEF, _ELSEIF: begin
        self.Add(d);
        FResult := d.IsEnable;
      end;

      _IFNDEF: begin
        d.IsEnable := not d.IsEnable;
        self.Add(d);
        FResult := d.IsEnable;
      end;

      _ELSE: begin
        if (Length(FStack) > 0) AND (not Top.IsEnable) then
          FResult := true;
      end;

      _ENDIF: begin
        self.Remove;
        FResult := true;
        if Length(FStack) > 0 then
          FResult := top.IsEnable;
      end;

      _DEFINE: begin
        if FResult then begin
          FFileDefine := FFileDefine + [d.Expression];
          FResult := True;
        end;
      end;
    end;

    define := GetNext;
  end;
end;

procedure TDefineAnalizator.ClearFileDefine;
begin
  SetLength(FFileDefine, 0);
end;

procedure TDefineAnalizator.ClearStack;
begin
  SetLength(FStack, 0);
end;

constructor TDefineAnalizator.Create;
begin
  FEnableDefines := TStringList.Create
end;

destructor TDefineAnalizator.Destroy;
begin
  FreeAndNil(FEnableDefines);
end;

function TDefineAnalizator.GetDefineExpression(const Define: string): string;
var
  skipCount: Integer;
begin
  var res := TStringBuilder.Create;

  var Def := Define;
  self.TrimDefine(Def);

  var defineType := GetDefineType(Def);
  var words := Def.Split([' ']);

  case definetype of
    _IFDEF   : skipCount := 1;
    _IFNDEF  : skipCount := 1;
    _ELSEIF  : skipCount := 2;
    _ELSE    : skipCount := 1;
    _ENDIF   : skipCount := 1;
    _DEFINE : skipCount := 1;
  end;

  for var I := skipCount to Length(words)-1 do begin
    if I > skipCount then
      res.Append(' ');
    res.Append(words[I]);
  end;
  result := res.ToString;
end;

function TDefineAnalizator.GetDefines: TArray<string>;

  function IsFileDefine(const DName: string): Boolean;
  begin
    result := False;
    for var FDefine in FFileDefine do begin
      if SameText(FDefine, DName) then
        exit(True);
    end;
  end;

var List: TStringList;
begin
  List := TStringList.Create;
  List.CaseSensitive := False;
  if Length(FStack) > 0 then begin
    for var D in FStack do begin
      if D.IsEnable AND (D.DefineTyp in [_IFDEF, _ELSEIF]) and (not IsFileDefine(D.Expression)) And (List.IndexOf(D.Expression) = -1) then begin
        List.Add(D.Expression);
      end;
    end;
  end;
  result := List.ToStringArray;
end;

function TDefineAnalizator.GetDefineType(const Define: string): TDefineType;
begin
  var Dfn := Define;
  self.TrimDefine(Dfn);
  var typ := Dfn.Split([' '])[0];

  if SameText(UpperCase(typ), 'IFDEF') then
    result := _IFDEF
  else if SameText(UpperCase(typ), 'IFNDEF') then
    result := _IFNDEF
  else if SameText(UpperCase(typ), 'ELSE IF') then
    result := _ELSEIF
  else if SameText(UpperCase(typ), 'ELSE') then
    result := _ELSE
  else if SameText(UpperCase(typ), 'ENDIF') then
    result := _ENDIF
  else if SameText(UpperCase(typ), 'DEFINE') then
    result := _DEFINE
  else
    result := _NONE;
end;

function TDefineAnalizator.IsDefineEnable(const Define: string): Boolean;
begin
  result := False;
  var exp := GetDefineExpression(Define);

  for var Enable in FEnableDefines do begin
    if SameText(LowerCase(exp), LowerCase(Enable)) then begin
      exit(True);
    end;
  end;

  if Length(FFileDefine) > 0 then begin
    for var Enable in FFileDefine do begin
      if SameText(LowerCase(exp), LowerCase(Enable)) then begin
        exit(True);
      end;
    end;
  end;

end;

procedure TDefineAnalizator.Remove;
begin
  if Length(FStack) > 0 then
    SetLength(FStack, Length(FStack)-1);
end;

function TDefineAnalizator.Top: TDefine;
begin
  result := FStack[Length(FStack)-1];
end;

procedure TDefineAnalizator.TrimDefine(var define: string);
begin
  define := define.TrimStart(['{', '$', ' ']);
  define := define.TrimEnd(['}', ' ']);
end;

end.
