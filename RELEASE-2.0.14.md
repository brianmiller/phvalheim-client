**Pre-release.** This build exists to carry one new thing to the PhValheim Companion, and that
path has not yet been confirmed end to end on a real Valheim client by the maintainer. It pairs
with **PhValheim Server 2.53**, which is also a pre-release. If you are not running a 2.53
server there is nothing here for you — stay on 2.0.13.

## What changed

**The client now hands the world's details to the Companion mod.**

Until now the client installed a world's mods and started Valheim, and the player still had to
join the world themselves — typing an address, or pasting a crossplay join code. The Companion
mod that PhValheim installs on every modded world can do that last step for the player, but it
had no way of knowing *which* world the client had just been launched for.

This release passes that along on the command line, as `--phvalheim-launch` followed by the
launch payload. On a 2.53 server the Companion reads it and offers a **Connect** button on
Valheim's main menu: the player picks their own character and joins, with nothing to copy and
nothing to type.

Two details worth recording, because both are places this could have gone wrong quietly:

- The payload handed over is the **original base64 the client was given**, not a re-encoding of
  the fields after parsing. Re-encoding would have been a second place to get the positional
  order wrong, and the two would have drifted the first time a field was added.
- Windows launches Valheim through Steam's `-applaunch`, which takes a single command string
  rather than an argument list, so it has its own append path. Every other platform passes
  separate argv entries.

**Nothing is appended when there is no payload.** A plain Steam launch, or this client started
without a world, produces exactly the command line it did in 2.0.13 — the argument is only
added when a launch payload is actually present, so this cannot make an ordinary launch look
like a PhValheim one.

## Compatibility

- **Against a 2.52 or older server:** harmless. Those servers do not send a launch payload, so
  nothing is appended and the client behaves exactly as 2.0.13 did.
- **Against a 2.53 server:** the Companion offers Connect on modded worlds.
- **Vanilla (unmodded) worlds are unaffected and always will be.** A vanilla world has no
  BepInEx, so it has no Companion, so there is nothing to hand the payload to. Those worlds are
  joined with their join code, as before. This is by design, not a gap.

## What has been verified

Against a 2.53 server, on a real client: **Connect joins the world**, the Connect dialog is
correct, **joining by IP:PORT works**, and disconnecting returns to the menu cleanly.

## What has not been verified

- **Only the Linux Flatpak has been exercised.** The `.msi`, `.deb`, `.rpm`, the universal
  tarball and the macOS package are the same code through the same builders, but none of them
  has been run against this release. Of those, only the `.msi` and the Flatpak have any
  automated verification at all; the other four have none.
