$buildType=$args[0]
 
# Code signing material.
#
# Paths come from the environment -- this is a public repository, so it must not record
# where the Authenticode certificate or its password live.
#
#   $env:CODESIGN_PFX    = "\\your-host\share\phvalheim-client.pfx"
#   $env:CODESIGN_PFX_PW_FILE = "\\your-host\share\phvalheim-client-pfx.pw"
#
# CODESIGN_PFX_PW may be set directly instead of pointing at a file.
$codeSignPfx = $env:CODESIGN_PFX
if (-not $codeSignPfx) {
    Write-Error "CODESIGN_PFX is not set. Point it at the .pfx to sign with."
    exit 1
}

if ($env:CODESIGN_PFX_PW) {
    $codeSignPfxPw = $env:CODESIGN_PFX_PW
} elseif ($env:CODESIGN_PFX_PW_FILE) {
    $codeSignPfxPw = Get-Content $env:CODESIGN_PFX_PW_FILE -Raw
} else {
    Write-Error "Set CODESIGN_PFX_PW or CODESIGN_PFX_PW_FILE."
    exit 1
}
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