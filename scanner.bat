@echo off
::
REM Важно! не ставить пробелы после "=", иначе код работать не будет
::


set "RegistryPath=HKCU\Software\ConsoleDS"
set "ValueName=Path"

for /f "tokens=2,*" %%A in ('reg query "%RegistryPath%" /v "%ValueName%" 2^>nul ^| find "%ValueName%"') do set "RegistryValue=%%B"

set Program=%RegistryValue%
REM Исходный файл (*.pas, *.dpr, *.dproj)
set SeedFile=NCKernel\NCKernel.dpr
REM Вывод
set TargetDir=C:\Test111\
REM Путь до файла *.groupproj
set GroupProjFile=SprutCAM.groupproj
REM 1 представляет "истина", 0 представляет "ложь"
set NeedCopy=0
REM Текущая папка
set Location=%~dp0

@echo on

start %Program% %SeedFile% %TargetDir% %GroupProjFile% %NeedCopy% %Location%


