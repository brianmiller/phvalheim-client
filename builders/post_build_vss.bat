echo off
set ProjectDir=%1
set Configuration=%2



REM mkdir %ProjectDir%\bin\%Configuration%\net6.0\linux-x64
mkdir %ProjectDir%\bin\%Configuration%\net6.0\win-x64
REM copy %ProjectDir%\bin\%Configuration%\net6.0\phvalheim-client.runtimeconfig.json %ProjectDir%\bin\%Configuration%\net6.0\linux-x64\phvalheim-client.runtimeconfig.json
copy %ProjectDir%\bin\%Configuration%\net6.0\phvalheim-client.runtimeconfig.json %ProjectDir%\bin\%Configuration%\net6.0\win-x64\phvalheim-client.runtimeconfig.json

echo

REM publish Windows x64 binaries
dotnet publish -c %Configuration% -r win-x64 -p:PublishSingleFile=true --self-contained true %ProjectDir%\phvalheim-client.csproj /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary /p:PublishTrimmed=false --no-build

REM publish Linux x64 binaries
REM dotnet publish -c %Configuration% -r linux-x64 -p:PublishSingleFile=true --self-contained true .\phvalheim-client.csproj /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary /p:PublishTrimmed=false --no-build

echo

echo Project Dir: %ProjectDir%
echo Configuration: %Configuration%
