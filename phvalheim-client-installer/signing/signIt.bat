@echo off
REM likely Debug or Release
set buildType=%1
set sdk=C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64

echo Build Type: %buildType%
echo SDK: %sdk%

REM create a self-signed cert
"%sdk%\MakeCert.exe" /n CN=posixone -a SHA256 /r /h 0 /eku "1.3.6.1.5.5.7.3.3,1.3.6.1.4.1.311.10.3.13" /e 01/01/2055 /sv ..\signing\MyKey.pvk ..\signing\MyKey.cer

REM convert the cert so we can sign code with it
"%sdk%\Pvk2Pfx.exe" -f /pvk "..\signing\MyKey.pvk" /spc "..\signing\MyKey.cer" /pfx "..\signing\MyKey.pfx"

REM sign our msi
REM "%sdk%\signtool.exe" sign /f "..\signing\MyKey.pfx" /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /v "..\%buildType%\phvalheim-client-installer.msi"












REM ## Removed 7zip dependency by building in "self-contained" mode, resulting in a single file that needs to be installed.

REM sign our exe
REM "%sdk%\signtool.exe" sign /f "..\signing\MyKey.pfx" /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /v "..\%buildType%\Setup.exe"

REM build self extracting and auto executing exe wrapper
REM "..\selfExtractingExe7Za\buildSelfExtractingExe.bat" %buildType%

REM sign our new exe wrapper
REM "%sdk%\signtool.exe" sign /f "..\signing\MyKey.pfx" /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /v "..\%buildType%\phvalheim-client-installer.exe"


