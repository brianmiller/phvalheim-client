$buildType=$args[0]
 
$codeSignPfx = "\\wopr.phospher.com\development\brian\phvalheim-client.pfx"
$codeSignPfxPw = Get-Content "\\wopr.phospher.com\development\brian\phvalheim-client-pfx.pw" -Raw
$signTool = "..\scripts\signtool.exe"
$versionNumber = $versionNumber = $(ls ..\..\bin\$buildType\net9.0\win-x64\publish\phvalheim-client.exe | % versioninfo | Select-Object -ExpandProperty FileVersion)


write-host ""
write-host "Build Type: $buildType"
write-host "Version: $versionNumber"
write-host "SDK: $sdk"
write-host ""


# sign our msi
& ls
& $signTool sign /f $codeSignPfx /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /p $codeSignPfxPw /v "..\$buildType\phvalheim-client-installer.msi"


# rename our msi
& move -Force "..\$buildType\phvalheim-client-installer.msi" "..\..\builds\phvalheim-client-$versionNumber-x86_64.msi"