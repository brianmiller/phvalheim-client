#!/bin/bash
#
# Mint a self-signed Authenticode code-signing certificate for the Windows .msi.
#
# The key material is written OUTSIDE the git tree on purpose -- this is a public
# repository and a committed .pfx is a published private key, recoverable by SHA
# long after any rewrite. Nothing here should ever be added to the repo.
#
# A self-signed cert does NOT make SmartScreen happy: Windows will still warn
# "Unknown Publisher", because the chain terminates at a root nobody trusts. What
# it does give you is a well-formed signature, a stable publisher identity, and a
# build pipeline already wired for signing, so swapping in a publicly trusted
# cert later is a one-line change to CODESIGN_PFX.
#
# Usage: builders/gen-codesign-cert.sh [outputDir]

set -eu

outDir="${1:-$HOME/.config/phvalheim-client/codesign}"
days=3650
cn="Phospher"

# Refuse to write inside a git work tree -- see above.
if git -C "$outDir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "ERROR: $outDir is inside a git work tree. Pick a path outside the repo."
	exit 1
fi

mkdir -p "$outDir"
chmod 700 "$outDir"

key="$outDir/phvalheim-client.key"
crt="$outDir/phvalheim-client.crt"
pfx="$outDir/phvalheim-client.pfx"
pwf="$outDir/phvalheim-client-pfx.pw"

if [ -e "$pfx" ]; then
	echo "ERROR: $pfx already exists. Move it aside first if you really mean to replace it."
	echo "       Re-signing with a new cert changes the publisher identity Windows sees."
	exit 1
fi

echo "Generating a self-signed code-signing certificate in $outDir"

# Password for the .pfx. Generated, not chosen -- it only ever has to be read
# by the builder, never typed.
openssl rand -base64 32 | tr -d '\n' > "$pwf"
chmod 600 "$pwf"

openssl req -x509 -newkey rsa:4096 -sha256 -days "$days" -nodes \
	-keyout "$key" -out "$crt" \
	-subj "/CN=$cn/O=$cn/C=US" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" \
	-addext "basicConstraints=critical,CA:FALSE" \
	2>/dev/null

openssl pkcs12 -export \
	-out "$pfx" \
	-inkey "$key" \
	-in "$crt" \
	-name "PhValheim Client Code Signing" \
	-passout "file:$pwf"

chmod 600 "$key" "$pfx"
chmod 644 "$crt"

echo
echo "Wrote:"
echo "  $key   (private key -- never commit)"
echo "  $crt   (public certificate)"
echo "  $pfx   (signing bundle -- never commit)"
echo "  $pwf   (pfx password)"
echo
echo "Fingerprint:"
openssl x509 -in "$crt" -noout -fingerprint -sha256 | sed 's/^/  /'
echo
echo "To build a signed msi:"
echo "  export CODESIGN_PFX=\"$pfx\""
echo "  export CODESIGN_PFX_PW_FILE=\"$pwf\""
echo "  builders/build_msi-outie"
