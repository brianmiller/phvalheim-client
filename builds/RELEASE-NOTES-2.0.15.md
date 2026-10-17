This is the recommended client for every player, on every server. It pairs with **PhValheim
Server 2.55**, but nothing here requires it — against an older server this client behaves as
2.0.14 did, minus the per-launch delay described below.

There is no "stay on the old one" caveat: everything here is an improvement on any server.

## Fixes you will notice immediately

### "Valheim is damaged and can't be opened" — macOS

A macOS player reported Valheim refusing to start with *"'valheim' is damaged and can't be
opened. You should move it to the Trash."* Nothing was damaged. A signed `.app` seals its
contents, and a file we had placed under `Contents/MacOS/` invalidated that seal — so Gatekeeper
blocked the app. **Deleting the stray file restores the original signature exactly**, because the
seal was computed over a tree without it. This client removes it on launch and never re-signs
anything, which matters: re-signing would replace Apple's identity with ours and survive Steam's
"verify integrity of game files".

If you hit this, you do not need to reinstall Valheim. Launch through PhValheim once.

### The download progress stays on one line

The progress bar used to print a new line for every percent — about a hundred lines scrolling up
the window on a large modpack. It now rewrites a single line in place, and the finished line no
longer leaves fragments of the longer line behind it.

### The launch window stays open until you quit Valheim

It used to close itself ten seconds after launching, taking the whole launch log with it — so a
crash two minutes into a session had nothing left on screen to explain it. The window now closes
when Valheim does, and tells you plainly that **you can close it at any time and the game keeps
running.**

That last part is now true on macOS, where it was not before. The macOS app opens a Terminal
window to run this client, and macOS signals every process in that window when you close it —
which previously killed Valheim with it. The game is now started detached, so closing the window
really is safe.

## Launching is faster, on every launch, against every server

The client used to compute the MD5 of the world payload **every single time you launched**, just
to answer "which version do I already have". On a large modpack that is over half a gigabyte read
off disk and hashed before anything else happens.

It now keeps a small `<world>.sync` record beside the payload and reads that instead. The payload
is hashed in exactly two situations: the record is missing (a first run, or the first launch after
upgrading to this version), or a download just finished — in which case hashing it is the point.

**That second case is a correctness requirement, not an optimisation.** The old
hash-every-launch behaviour caught a truncated download by accident on the following run. A
client that wrote down "I have version X" without checking what it received would turn that
accidental self-healing into a permanent lie. So a completed download is verified against the
server's checksum before anything is recorded, and a payload that does not match is discarded
with your existing install left untouched rather than half-replaced.

## A settings change no longer costs you the whole modpack

This part needs a 2.55 server.

When an operator changed a mod setting, the only way to reach players was to rebuild the entire
client payload — so everyone re-downloaded the whole modpack to receive a few lines of changed
text. Measured on a real world: **577,604,696 bytes to deliver 80,174 bytes of actual change.**

The server can now publish a configuration-only update, and this client recognises one and
fetches just the configuration archive. Same world, same mods, 80 KB instead of 573 MB.

An older client talking to a 2.55 server is not broken by this — it simply does not take the
shortcut and downloads everything, exactly as it always did.

## Install

Pick the file for your platform below. On macOS, run `macinstall.sh` from the extracted tarball.
Windows users: the `.msi` is unsigned, so SmartScreen will warn — choose **More info → Run
anyway**.
