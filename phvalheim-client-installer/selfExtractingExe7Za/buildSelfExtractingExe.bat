@echo off

set buildType=%1
set seven=..\selfExtractingExe7Za\7za\7z.exe

"%seven%" a -t7z phvalheim-client-installer.7z .\*
copy /b ..\selfExtractingExe7Za\7za\7zS.sfx + config.txt + .\phvalheim-client-installer.7z .\phvalheim-client-installer.exe


dir .\phvalheim-client-installer.exe

if %buildType%==Release (
	copy /b .\phvalheim-client-installer.exe ..\..\published_build\phvalheim-client-installer.exe
)
