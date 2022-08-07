@echo off

set buildType=%1
set seven=..\selfExtractingExe7Za\7za\7z.exe




del .\phvalheim_installer.7z
del .\phvalheim_installer.exe

"%seven%" a -t7z phvalheim_installer.7z .\*
copy /b ..\selfExtractingExe7Za\7za\7zS.sfx + config.txt + .\phvalheim_installer.7z .\phvalheim_installer.exe
