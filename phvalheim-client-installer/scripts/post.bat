@echo off
REM likely Debug or Release
set buildType=%1
set versionNumber=%2

set sdk=C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64
set codeSignPfx=\\cerebrum.phospher.com\development\phvalheim-client\not_git\code_signing_certs\MyKey.pfx

echo Build Type: %buildType%
echo Version: %versionNumber%
echo SDK: %sdk%



REM sign our msi
"%sdk%\signtool.exe" sign /f %codeSignPfx% /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /v "..\%buildType%\phvalheim-client-installer.msi"

REM rename our msi
move "..\%buildType%\phvalheim-client-installer.msi" "..\%buildType%\phvalheim-client-%versionNumber%.msi"

