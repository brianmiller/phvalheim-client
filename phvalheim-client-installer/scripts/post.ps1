$buildType=$args[0]
$versionNumber = $args[1]
 
$sdk = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64"
$codeSignPfx = "\\cerebrum.phospher.com\development\phvalheim-client\not_git\code_signing_certs\MyKey.pfx"

write-host "Build Type: $buildType"
write-host "Version: $versionNumber"
write-host "SDK: $sdk"
