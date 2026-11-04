**Pre-release.** This build makes config changes cheap, and the saving half of that has not yet
been confirmed against a real server by the maintainer — no 2.0.15 client has yet performed a
config-only sync in the wild. It pairs with **PhValheim Server 2.55**, which is also a
pre-release.

Unlike 2.0.14, there is no "stay on the old one" caveat: **everything here is an improvement on
any server.** Against a pre-2.55 server this client behaves exactly as 2.0.14 did, minus the
per-launch delay described below. Nothing in it requires a 2.55 server.

## What changed

### Launching is faster, on every launch, against every server

The client used to compute the MD5 of the world payload **every single time you launched** — just
to answer "which version do I already have". On a large modpack that payload is over half a
gigabyte, so every launch began by reading 573 MB off disk and hashing all of it. On a cold disk
that is several seconds of waiting before anything else happens, to learn something the client
already knew the last time it ran.

It now keeps a small `<world>.sync` record next to the payload and reads that instead. The
payload is hashed in exactly two situations:

- the record is missing — a first run, or the first launch after upgrading to this version; or
- a download just finished, in which case hashing it is the whole point.

**That second case is not an optimisation, it is a correctness requirement.** The old
hash-every-launch behaviour caught a truncated or corrupted download by accident on the following
run. A client that wrote down "I have version X" without checking what it actually received would
turn that accidental self-healing into a permanent lie — it would believe it held a good payload
forever and never fetch it again. So a completed download is verified against the server's
checksum before anything is recorded, and a payload that does not match is discarded with your
existing install left untouched rather than half-replaced.

### A settings change no longer costs you the whole modpack

This is the part that needs a 2.55 server.

When a server operator changed a mod setting, the only way to get it to players was to rebuild
the entire client payload — so every player re-downloaded the whole modpack to receive a few
lines of changed text. Measured on a real world: **577,604,696 bytes to deliver 80,174 bytes of
configuration.**

A 2.55 server now publishes a second, small archive containing just the configuration, with its
own checksum. This client compares both, and when only the configuration has changed it fetches
only that — **about 7,200× less data**. When the modpack itself changes, it downloads the full
payload exactly as before.

**What "only the configuration changed" is measured against.** Not the payload's checksum. The
server rebuilds the payload when an operator applies a config change — it has to, so a *new*
player downloading it finds the current settings inside — and re-zipping an unchanged tree
produces different bytes. So the payload's checksum moves every time, and a client that asked
"does my payload match?" first would answer "no" and fetch all 573 MB, every time. That is what
the first build of this did, confirmed against a real server: three applies, three different
payload checksums, three full downloads.

A 2.55 server therefore publishes a third value: the identity of the payload's **mod content**,
with the configuration excluded — the per-file checksums the archive already stores, hashed in a
fixed order. It is unchanged by a re-zip of the same mods and moves when a plugin does. This
client asks that one whether it needs the payload, and the configuration checksum whether it
needs the 80 KB. The payload checksum keeps its own job: verifying a finished download.

An install that predates this value asks the old question once — one full download if an apply
happened in the meantime — then records the new one and never pays again. An install already
current records it without downloading anything.

Three details worth recording, because each is a place this could have gone wrong quietly:

- **The configuration directory is replaced wholesale, not merged.** When an operator *resets* a
  setting they remove a key, and sometimes a whole file. Copying the new files over the old ones
  would leave the stale one behind, so the reset would never actually reach the player. This is
  no more destructive than the full path, which already deletes and re-extracts the entire world
  directory.
- **Both checksums are requested in one call.** Asked separately, an operator who republished
  between the two requests would hand this client a payload checksum describing one state of the
  server and a configuration checksum describing the next — and there is no way to detect that
  from here.
- **An unknown configuration checksum is treated as "different", never as "the same".** Being
  wrong in that direction costs one 80 KB download; being wrong in the other direction loses a
  setting change permanently.

### Compatibility, in both directions

- **This client against an older server:** the server publishes no configuration checksum, so the
  small-download path is simply never taken. The client falls back to the request every
  PhValheim server has always answered.
- **An older client against a 2.55 server:** unaffected. It keeps comparing the full payload and
  keeps downloading all of it, exactly as it does today. The server deliberately leaves that
  older contract untouched, and `clientMinVersion` has **not** been raised — nobody is forced to
  upgrade.

## Also in this build

Four pieces of dead code removed from the sync path while it was open: a declared-and-never-used
version-file path (the new sync record takes over the idea its name was reserved for), a flag
assigned in both branches and never read, and a check that was computed, never read, recomputed,
and whose guard had been commented out — so four small files were copied into the Valheim
directory on every launch regardless.

A failed extraction now cleans up the partial directory and keeps the verified payload, so the
next launch re-extracts from the copy already on disk instead of downloading it again. The old
client got that behaviour for free from hashing every launch; it had to be made deliberate here.
