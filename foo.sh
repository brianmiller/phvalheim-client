dotnet publish \
                -c Linux-Release \
        -r linux-x64 \
        -p:PublishSingleFile=true \
        --self-contained true \
        ./phvalheim-client.csproj \
        /property:GenerateFullPaths=true \
        /consoleloggerparameters:NoSummary \
                /p:PublishTrimmed=false
