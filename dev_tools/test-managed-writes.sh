#!/usr/bin/env bash
# Every write the client makes into its own folders (the cached world, its BepInEx config, the sync
# record, the backend file) goes through ManagedFile. On Windows a plain overwrite is refused with
# access denied when the existing file is Hidden or System (issue #25); ManagedFile replaces it in
# place. This fails if a plain overwrite comes back into one of those files.
set -u
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1
files=(ConfigPolicy.cs Syncer.cs PhValheimPrep.cs)
pattern='(^|[^A-Za-z_])File\.(WriteAllText|WriteAllBytes|WriteAllLines|AppendAllText|Copy)\(|FileMode\.(Create|Truncate)\b'
found=$(grep -nE "$pattern" "${files[@]}" || true)
if [ -n "$found" ]; then
    echo "Plain overwrite in a managed folder (use ManagedFile.WriteText / ManagedFile.Copy / ManagedFile.Write):"
    echo "$found"
    exit 1
fi
for helper in 'internal static void WriteText(' 'internal static void Copy(' 'internal static void Write('; do
    grep -qF "$helper" ManagedFile.cs || { echo "ManagedFile.cs lacks ${helper%(}"; exit 1; }
done
echo "managed writes: ${#files[@]} files use ManagedFile only"
