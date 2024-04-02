unit DSTypes;

interface

uses
  System.SysUtils, System.TypInfo, System.Classes,

  DSUtils;

type
  TPlatformEnum = (All, Win32, Win64);
  TConfigEnum = (Base, Cfg_1, Cfg_2);

  TFields =
  (
    SearchPath,
    Definies,
    DebuggerSourcePath,
    ResourceOutputPath,
    HostApplication,
    WriteableConstants,
    NameSpace
  );

const
  PathRegex = '^([a-zA-Z]:)?(?:\\[^\\/:*?"<>|]+)+\\?$';

implementation


end.
