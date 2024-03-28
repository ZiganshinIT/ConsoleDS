unit DSThreads;

interface

uses
  Winapi.Windows,

  System.Classes, System.SysUtils,

  DSConst;

type

  {Поток ввода}
  TInputThread = class(TThread)
  protected
    FFlag: boolean;
  protected
    procedure Execute; override;
  public
    property Flag: Boolean write FFlag;
  end;

implementation

{ TInputThread }

{Проверяем нажатие клавиш}
procedure TInputThread.Execute;
var
  InputRecord: TInputRecord;
  EventsRead: DWORD;
  ConsoleHandle: THandle;
begin
  inherited;
  try
    ConsoleHandle := GetStdHandle(STD_INPUT_HANDLE);
    if ConsoleHandle <> INVALID_HANDLE_VALUE then begin
      while True do begin
        ReadConsoleInput(ConsoleHandle, InputRecord, 1, EventsRead);
        if (InputRecord.EventType = KEY_EVENT) and InputRecord.Event.KeyEvent.bKeyDown then begin
          case InputRecord.Event.KeyEvent.wVirtualKeyCode of
            VK_ESCAPE: begin
              Writeln('Нажата клавиша Escape.');
              IsEscPressed := True;
            end;
          end;
        end;
      end;
    end;
  except
    on E: Exception do
      Writeln('Ошибка: ', E.Message);
  end;
end;

end.
