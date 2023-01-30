$buildType=$args[0]
 

$sdk = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64"
$codeSignPfx = "\\cerebrum.phospher.com\development\phvalheim-client\not_git\code_signing_certs\self-signed\MyKey.pfx"
$versionNumber = $versionNumber = $(ls ..\..\bin\Release\net6.0\phvalheim-client.exe | % versioninfo | Select-Object -ExpandProperty ProductVersion)


write-host ""
write-host "Build Type: $buildType"
write-host "Version: $versionNumber"
write-host "SDK: $sdk"
write-host ""


# sign our msi
& "$sdk\signtool.exe" sign /f $codeSignPfx /tr http://timestamp.comodoca.com/rfc3161 /td SHA256 /fd SHA256 /v "..\$buildType\phvalheim-client-installer.msi"


# rename our msi
& move -Force "..\$buildType\phvalheim-client-installer.msi" "..\..\builds\phvalheim-client-$versionNumber.msi"