#!/bin/bash
# Exercise the shipped syncer and config merger against real archives and an HTTP server.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
docker run --rm -v "$repo":/src:ro mcr.microsoft.com/dotnet/sdk:9.0 bash -c '
set -eu
mkdir /tmp/test
cp /src/ConfigPolicy.cs /src/Syncer.cs /src/Tooling.cs /src/Downloader.cs /src/Ui.cs /tmp/test/
cp /src/dev_tools/ConfigPolicyHarness.cs.txt /tmp/test/Program.cs
printf "%s" "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net9.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup></Project>" > /tmp/test/test.csproj
cd /tmp/test
dotnet run -v quiet
'
