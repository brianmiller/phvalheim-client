using System.Diagnostics;
using System.Runtime;
using System.Runtime.InteropServices;

namespace PhValheim.Launcher
{
    public class PhValheim
    {
        /// <summary>
        /// Launch a vanilla (zero-mod) world.
        ///
        /// Nothing about the modded path applies here: there is no BepInEx to inject, so
        /// no doorstop arguments, and no quickconnect mod to read a server list. We use
        /// Valheim's own +connect argument instead, routed through Steam on every
        /// platform so it works the same way everywhere.
        ///
        /// Vanilla Valheim has NO client-side argument to pre-fill the server password --
        /// the player is dropped at the password prompt and types it themselves. That is
        /// why we print it here and why the public UI shows it on the world card.
        /// </summary>
        /// <summary>
        /// The Companion launch argument, as separate argv entries.
        ///
        /// Returns nothing at all when there is no payload. That is load-bearing on the
        /// Companion side: it treats the ARGUMENT'S PRESENCE as proof the game was started by
        /// PhValheim, and shows no dialog without it. Passing the flag with an empty value
        /// would make a plain Steam launch look like a PhValheim one.
        ///
        /// Separate entries rather than one string so a payload is never re-split on
        /// whitespace. Base64 contains no spaces today, but '+' and '/' and '=' have all
        /// surprised someone before.
        /// </summary>
        private static IEnumerable<string> CompanionArgList()
        {
            if (!Arguments.PhValheim.HaveLaunchPayload)
                return Array.Empty<string>();

            // Not null: HaveLaunchPayload is exactly the check that it is set and non-empty.
            return new[] { Arguments.PhValheim.CompanionArgName, Arguments.PhValheim.RawLaunchPayload! };
        }

        /// <summary>
        /// The same thing for the one launch path that takes a single command string rather
        /// than an argument list: Windows, via Steam's -applaunch. Leads with a space so it
        /// can be concatenated onto an existing argument string, and is empty when there is
        /// no payload so nothing is appended.
        /// </summary>
        private static string CompanionArg()
        {
            if (!Arguments.PhValheim.HaveLaunchPayload) return "";

            // No quoting: base64's alphabet is A-Z a-z 0-9 + / = and none of those need it.
            // Quoting would be the safer habit, but Steam passes -applaunch arguments through
            // its own parsing and adding quotes here has a real chance of delivering them
            // literally to the game.
            return " " + Arguments.PhValheim.CompanionArgName + " " + Arguments.PhValheim.RawLaunchPayload;
        }

        private static void LaunchVanilla(string steamExe, string worldPassword, string worldHost, string worldPort)
        {
            string connect = worldHost + ":" + worldPort;

            // THE PASSWORD IS NEVER PRINTED, on any path. Brian's call: "no need to display
            // the password."
            //
            // A vanilla world has no Companion mod, so Valheim's own prompt does appear and the
            // player does have to type something -- but the password is already on the world
            // card and in the world's Settings modal on the server's web page, which is the
            // page they just pressed Launch on. Printing it into a window that gets
            // screenshotted into Discord added an exposure without adding an answer.
            if (!string.IsNullOrEmpty(worldPassword))
            {
                Ui.Blank();
                Ui.Line("Valheim will ask for the server password. It is shown on this "
                        + "world's card on the PhValheim web page you launched from.");
                Ui.Blank();
            }

            // Valheim needs Steam up before it starts; on Windows -applaunch handles that
            // itself, but on Linux/macOS we start it the same way the modded path does.
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                string steamProcess = RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "steam_osx" : "steam";

                // Sandbox-aware: inside a Flatpak our PID namespace contains
                // nothing but us, so asking the local process list whether
                // Steam is up always answers "no".
                if (!Sandbox.Flatpak.HostProcessRunning(steamProcess))
                {
                    Ui.Line("Starting Steam...");
                    Process.Start(Sandbox.Flatpak.HostCommand(steamExe,
                        Platform.State.SteamArgs("-nofriendsui", "-console")));
                    Thread.Sleep(10000);
                }
            }

            // -applaunch works identically through `flatpak run com.valvesoftware.Steam`,
            // because it is Steam itself that starts the game -- inside its own
            // sandbox, with its own runtime, exactly as a Library click would.
            Process.Start(Sandbox.Flatpak.HostCommand(steamExe,
                Platform.State.SteamArgs("-applaunch", "892970", "+connect", connect)));
        }

        public static void Launch(ref string worldPassword, ref string worldHost, ref string worldPort, bool isVanilla = false)
        {
            string BepInEx_Preloader = Path.Combine(Platform.State.PhValheimServerRoot, Platform.State.WorldName, "BepInEx","core","BepInEx.Preloader.dll");
            string steamExe = Platform.State.SteamExe;
            string steamDir = Platform.State.SteamDir;
            string valheimDir = Platform.State.ValheimDir;
            string worldName = Platform.State.WorldName;

            // THE PASSWORD IS NOT PRINTED HERE, and that is the point of this block.
            //
            // It used to be, on every launch -- and on a vanilla one it was printed again a few
            // lines later by LaunchVanilla, so the same credential appeared twice. On a modded
            // world the Companion mod fills the prompt in, so the player never reads it and has
            // no use for it; it was on screen purely because it happened to be in a variable.
            // These windows get screenshotted into Discord when somebody asks for help, so it
            // is shown ONLY where the player has to type it, which is the vanilla path below.
            //
            // The remaining lines are the ones that answer "did it understand what I clicked":
            // the world, and where it is connecting. The Steam root is a path, which is
            // developer detail.
            Ui.Section("Starting Valheim");
            Ui.Field("World", worldName);
            Ui.Field("Address", worldHost + ":" + worldPort + "  (udp)");
            Ui.Detail("steam root", steamDir);
            // (worldPassword ?? "") for the same reason as the DOORSTOP block below: this
            // argument is evaluated whether or not verbose is on, so a null here would be an
            // NRE on every launch rather than a missing debug line.
            Ui.Detail("password", Ui.Mask(worldPassword) + "  ("
                                  + (worldPassword ?? "").Length + " chars)");

            if (isVanilla)
            {
                LaunchVanilla(steamExe, worldPassword, worldHost, worldPort);
                return;
            }

            // if running in windows
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                // The Companion payload rides on argv rather than an environment variable
                // because of this line specifically: -applaunch hands off to Steam, which
                // starts the game itself, and our environment does not survive that. argv
                // does. The other three platforms could use env, but one mechanism that works
                // everywhere beats three that each work somewhere.
                Process.Start(@steamExe, "-applaunch 892970 --doorstop-enabled true --doorstop-target-assembly \"" + BepInEx_Preloader + "\" -console" + CompanionArg());
            } 
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {

                Ui.Detail("platform", "linux");

                if (Sandbox.Flatpak.InSandbox)
                {
                    Ui.Detail("sandbox", "flatpak -- Steam and Valheim start on the host");
                }

                // Check if steam is already running
                // If its not, we need to launch steam, otherwise velheim will crash on startup
                //
                // Sandbox-aware: see the note in Flatpak.HostProcessRunning.
                // Asking our own process list from inside the sandbox always
                // answers "not running", so a Flatpak would start a second
                // Steam and then sleep ten seconds on every single launch.
                if (Platform.State.SteamIsFlatpak)
                {
                    Ui.Detail("sandbox", "Steam is a Flatpak -- Valheim starts inside its sandbox");
                }

                if (!Sandbox.Flatpak.HostProcessRunning("steam"))
                {
                    Ui.Line("Starting Steam...");
                    Process.Start(Sandbox.Flatpak.HostCommand(@steamExe,
                        Platform.State.SteamArgs("-nofriendsui", "-console")));

                    // I honestly don't know a better way to do this, so we sleep
                    Thread.Sleep(10000);
                }
            {

                  // try to set gnome's check-alive-timeout to 0. This timeout is what causes the "not responding" warnings.
                  // IronGate needs to send a pong back to the different display managers to satisfy this timeout
                  try
                  {
                        // Must run on the host: the sandbox has its own dconf
                        // and setting mutter's timeout in here would change
                        // nothing the user's compositor ever reads.
                        ProcessStartInfo gsettingsCmd = Sandbox.Flatpak.HostCommand("/usr/bin/gsettings",
                            new[] { "set", "org.gnome.mutter", "check-alive-timeout", "0" });
                        gsettingsCmd.CreateNoWindow = true;
                        Process.Start(gsettingsCmd);
                   }
                   catch
                   {
                   }

                  // if running in linux
                  // valheim.x86_64 must be launched directly with BepInEx environment variables instead of through steam
                  // This is the same strategy that the BepInEx uses in their start_game_bepinex.sh script
                  string exec = Path.Combine(valheimDir, "valheim.x86_64");
                  string setsid = "/usr/bin/setsid";
                  string worldDir = Path.Combine(Platform.State.PhValheimServerRoot, Platform.State.WorldName);
                  string doorstep_libs = Path.Combine(valheimDir, "doorstop_libs");
                  string ld_library_path = doorstep_libs;
                  string existingLdPreload = System.Environment.GetEnvironmentVariable("LD_PRELOAD");
                  string ld_preload = string.IsNullOrEmpty(existingLdPreload)
                      ? "libdoorstop_x64.so"
                      : $"libdoorstop_x64.so:{existingLdPreload}";

                  // The doorstop environment. Passing it as a dictionary rather
                  // than mutating psi.EnvironmentVariables is what lets the
                  // same call work in both worlds: outside a sandbox these
                  // become process environment variables exactly as before,
                  // inside one they become --env= arguments to flatpak-spawn.
                  var doorstopEnv = new Dictionary<string, string>
                  {
                      ["DOORSTOP_ENABLED"] = "1",
                      ["DOORSTOP_TARGET_ASSEMBLY"] = BepInEx_Preloader,
                      ["DOORSTOP_MONO_LIB_PATH"] = Path.Combine(valheimDir, "valheim_Data", "MonoBleedingEdge", "x86_64", "libmonobdwgc-2.0.so"),
                      //["DOORSTOP_CORLIB_OVERRIDE_PATH"] = Path.Combine(valheimDir, "unstripped_corlib"),
                      ["LD_LIBRARY_PATH"] = ld_library_path,
                      ["LD_PRELOAD"] = ld_preload,
                  };

                  ProcessStartInfo startInfo;

                  if (Platform.State.SteamIsFlatpak)
                  {
                      // A Flatpak Steam cannot be driven the way a system one
                      // can. Exec'ing valheim.x86_64 on the host would give it
                      // the host's libraries instead of the Steam Runtime, and
                      // -- the part that actually decides it -- no route to the
                      // Steam client, whose IPC pipe lives inside Steam's
                      // sandbox under ~/.var/app/com.valvesoftware.Steam. A
                      // Steamworks game with no client to talk to exits at
                      // startup.
                      //
                      // So we run the game inside Steam's own sandbox instead,
                      // where the runtime and the pipe both already are. The
                      // doorstop variables go in as `flatpak run --env=`
                      // rather than through HostCommand's env dictionary:
                      // HostCommand's would set them on the host, one layer
                      // out from the process that has to read them.
                      //
                      // setsid still runs on the host, so the game outlives
                      // this client exactly as it does everywhere else.
                      var fpArgs = new List<string>
                      {
                          "flatpak", "run",
                          "--cwd=" + valheimDir,
                      };

                      foreach (var kv in doorstopEnv)
                          fpArgs.Add("--env=" + kv.Key + "=" + kv.Value);

                      // BepInEx and the mod payload live in our own directory,
                      // which Steam's sandbox has no reason to be able to see.
                      // Granted per-run, so nothing about the user's Steam
                      // install is permanently changed.
                      fpArgs.Add("--filesystem=" + Platform.State.PhValheimDir);

                      fpArgs.Add("--command=" + exec);
                      fpArgs.Add(Platform.State.SteamFlatpakId);
                      fpArgs.Add("-console");

                      // Everything after the Flatpak app id is passed through to the game, so
                      // this reaches Valheim's own argv. Added as separate list entries, not
                      // one joined string, so a payload is never re-split on whitespace.
                      foreach (var arg in CompanionArgList())
                          fpArgs.Add(arg);

                      startInfo = Sandbox.Flatpak.HostCommand(setsid, fpArgs);
                  }
                  else
                  {
                      // Native Linux: exec'd directly, so the payload goes straight onto the
                      // game's argv.
                      var nativeArgs = new List<string> { exec, "-console" };
                      nativeArgs.AddRange(CompanionArgList());

                      startInfo = Sandbox.Flatpak.HostCommand(
                          setsid,
                          nativeArgs.ToArray(),
                          doorstopEnv,
                          valheimDir);
                  }

                  startInfo.CreateNoWindow = false;

                  // Live again, behind PHVALHEIM_VERBOSE. This was the right set of things to
                  // print when a Linux launch goes wrong -- which is exactly why it had been
                  // commented out rather than deleted: it was too noisy to leave on and too
                  // useful to lose. A verbose gate is the thing it was missing.
                  //
                  // GUARDED BY if (Ui.Verbose), NOT by Ui.Detail's own check, and that is the
                  // whole point. Ui.Detail returns early when verbose is off -- but its
                  // ARGUMENTS are evaluated at the call site first, so a throwing argument
                  // crashes a non-verbose run too. The first cut of this block did exactly
                  // that and killed every modded launch:
                  //
                  //   startInfo.EnvironmentVariables[ev] ?? "(unset)"
                  //
                  // On .NET Core that indexer is backed by a Dictionary and THROWS
                  // KeyNotFoundException for a key that is not set; it does not return null, so
                  // the ?? could never fire. Inside a Flatpak the launch goes through
                  // HostCommand, which sets no DOORSTOP_* at all, so the very first key was
                  // missing -- an unhandled exception two statements before Process.Start.
                  // The game never started and the window vanished with the stack trace in it.
                  //
                  // ContainsKey first, and the loop only runs when someone asked for it.
                  if (Ui.Verbose)
                  {
                      Ui.Detail("exec", exec);
                      Ui.Detail("args", startInfo.Arguments);
                      Ui.Detail("cwd", startInfo.WorkingDirectory);
                      foreach (string ev in new[] { "DOORSTOP_ENABLE", "DOORSTOP_INVOKE_DLL_PATH",
                                                    "DOORSTOP_CORLIB_OVERRIDE_PATH",
                                                    "LD_LIBRARY_PATH", "LD_PRELOAD" })
                      {
                          Ui.Detail(ev, startInfo.EnvironmentVariables.ContainsKey(ev)
                                            ? startInfo.EnvironmentVariables[ev] : "(unset)");
                      }
                  }

                  Process.Start(startInfo);
                }
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Ui.Detail("platform", "macos");

                // Check if steam is already running; Valheim needs Steam online at launch
                string[] pids = Process.GetProcessesByName("steam_osx").Select(p => p.Id.ToString()).ToArray();
                if (pids.Length == 0)
                {
                    Ui.Line("Starting Steam...");
                    ProcessStartInfo steamStartInfo = new ProcessStartInfo(steamExe);
                    steamStartInfo.UseShellExecute = false;
                    steamStartInfo.Arguments = "-nofriendsui -console";
                    Process.Start(steamStartInfo);
                    Thread.Sleep(10000);
                }

                string exec = Path.Combine(valheimDir, "Valheim.app", "Contents", "MacOS", "Valheim");
                string worldDir = Path.Combine(Platform.State.PhValheimServerRoot, Platform.State.WorldName);
                string doorstopLibs = Path.Combine(worldDir, "doorstop_libs");
                string doorstopDylib = Path.Combine(doorstopLibs, "libdoorstop.dylib");

                // fall back to the copy bundled inside the .app if the server didn't ship one
                if (!File.Exists(doorstopDylib))
                {
                    string bundled = "/Applications/PhValheim Client.app/Contents/Resources/libdoorstop.dylib";
                    if (File.Exists(bundled))
                        doorstopDylib = bundled;
                    else
                        Ui.Warning("The mod loader for macOS (libdoorstop.dylib) could not be found.",
                           "Valheim will start WITHOUT mods, so you may not be able to join.");
                }

                // FIRST, undo the damage older versions did. This is a repair, and it has to
                // run before anything else looks at the bundle.
                //
                // 2.0.15 and earlier wrote the thinned x86_64 binary to
                // Valheim.app/Contents/MacOS/Valheim.x86_64 -- INSIDE Steam's signed app
                // bundle -- and then ran `codesign --force` on it. Both halves break the
                // bundle. A signed bundle carries a sealed manifest of its contents in
                // Contents/_CodeSignature/CodeResources, and files under Contents/MacOS that
                // are not the main executable are sealed as resources. An unlisted file there
                // makes the resource envelope invalid, and macOS reports that as:
                //
                //     "Valheim" is damaged and can't be opened. You should move it to the Trash.
                //
                // which is what a macOS user reported. It reads like a corrupt download, so
                // nobody looks at the mod launcher for it.
                //
                // Deleting the stray file is a COMPLETE repair, and that is worth being precise
                // about: CodeResources never listed the file, so its absence is the state the
                // seal was computed over. Iron Gate's original signature becomes valid again on
                // its own -- nothing needs re-signing, and we must not re-sign, because ad-hoc
                // signing over their identity is a second, different kind of damage.
                RepairValheimBundle(valheimDir);

                // On Apple Silicon, force Valheim to run under Rosetta 2 (x86_64).
                // MonoMod v22 (bundled with BepInEx 5.x) cannot write detour trampolines
                // on arm64 due to MAP_JIT W^X hardware enforcement. Running under Rosetta
                // uses the x86_64 MonoMod code path which works correctly.
                //
                // We still use lipo -thin, because /usr/bin/arch strips DYLD_ vars under SIP
                // and that kills doorstop injection. What changed is WHERE the output goes:
                // into a PhValheim-owned shadow bundle, never into Valheim.app.
                bool useRosetta = RuntimeInformation.ProcessArchitecture == Architecture.Arm64;
                string launchExec = exec;

                if (useRosetta)
                {
                    Ui.Line("Apple Silicon: preparing the x86_64 build for Rosetta 2...");
                    try
                    {
                        string shadowExec = PrepareRosettaBundle(valheimDir, worldDir, exec);
                        if (shadowExec == null)
                        {
                            useRosetta = false;
                        }
                        else
                        {
                            launchExec = shadowExec;
                            Ui.Line("Launching under Rosetta 2...");
                        }
                    }
                    catch (Exception ex)
                    {
                        Ui.Warning("Could not prepare the x86_64 build: " + ex.Message,
                                   "Valheim will run as native arm64 instead, and mods may not load.");
                        useRosetta = false;
                    }
                }

                string monoLibPath = Path.Combine(valheimDir, "Valheim.app", "Contents", "Frameworks", "libmonobdwgc-2.0.dylib");

                ProcessStartInfo startInfo = new ProcessStartInfo(launchExec);
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = false;
                startInfo.ArgumentList.Add("-console");

                // macOS execs the binary directly, like native Linux.
                foreach (var arg in CompanionArgList())
                    startInfo.ArgumentList.Add(arg);

                startInfo.WorkingDirectory = valheimDir;
                startInfo.EnvironmentVariables["DOORSTOP_ENABLED"] = "1";
                startInfo.EnvironmentVariables["DOORSTOP_TARGET_ASSEMBLY"] = BepInEx_Preloader;
                startInfo.EnvironmentVariables["DOORSTOP_MONO_LIB_PATH"] = monoLibPath;
                startInfo.EnvironmentVariables["DYLD_LIBRARY_PATH"] = doorstopLibs;
                startInfo.EnvironmentVariables["DYLD_INSERT_LIBRARIES"] = doorstopDylib;

                Process.Start(startInfo);
            }
        }

        /// <summary>
        /// Remove anything an older PhValheim wrote inside Steam's signed Valheim.app.
        /// </summary>
        /// <remarks>
        /// Up to and including 2.0.15 the Rosetta path put its thinned binary at
        /// Contents/MacOS/Valheim.x86_64 and codesigned it in place. A signed bundle seals its
        /// contents in Contents/_CodeSignature/CodeResources, and an unlisted file under
        /// Contents/MacOS invalidates that envelope -- which macOS surfaces as
        /// <c>"Valheim" is damaged and can't be opened</c>, a message that points the user at
        /// their download rather than at us.
        ///
        /// Deleting the file is the whole repair. The seal was computed over a tree that did
        /// not contain it, so removing it restores the original signature's validity exactly.
        /// We deliberately do NOT re-sign: replacing Iron Gate's identity with an ad-hoc one
        /// would be a second kind of damage, and would survive a Steam "verify integrity".
        ///
        /// Silent when there is nothing to do, which is the common case -- a user who never ran
        /// an affected version should see no mention of a problem they do not have.
        /// </remarks>
        private static void RepairValheimBundle(string valheimDir)
        {
            try
            {
                string macOsDir = Path.Combine(valheimDir, "Valheim.app", "Contents", "MacOS");
                if (!Directory.Exists(macOsDir)) { return; }

                // Only ever our own leavings. Anything else in here belongs to the game, and a
                // launcher that deletes files it does not recognise out of someone's Steam
                // install is worse than the bug it is fixing.
                foreach (string stray in Directory.GetFiles(macOsDir, "Valheim.x86_64"))
                {
                    File.Delete(stray);
                    Ui.Line("Repaired the Valheim app bundle (an older PhValheim left a file inside it,");
                    Ui.Line("which is what made macOS call Valheim \"damaged\").");
                }
            }
            catch (Exception ex)
            {
                // Not fatal: the launch below may still work, and on an unaffected install
                // there was nothing to repair anyway.
                Ui.Warning("Could not tidy up the Valheim app bundle: " + ex.Message,
                           "If macOS says Valheim is damaged, use Steam > Valheim > Properties > "
                           + "Installed Files > Verify integrity.");
            }
        }

        /// <summary>
        /// Build a PhValheim-owned app bundle whose executable is the x86_64 slice of Valheim,
        /// so Rosetta can be forced without touching Steam's bundle. Returns the path to launch,
        /// or null if the x86_64 build could not be prepared.
        /// </summary>
        /// <remarks>
        /// Why a bundle at all, rather than just a loose binary somewhere: Unity's macOS player
        /// locates its data through NSBundle.mainBundle, as
        /// <c>&lt;bundle&gt;/Contents/Resources/Data</c>. Run the executable from outside a
        /// bundle and mainBundle resolves somewhere else and the game finds no data. So the
        /// shadow has to have the shape of a bundle.
        ///
        /// Only two real files are created -- Info.plist and the thinned executable. Resources,
        /// Frameworks and PlugIns are SYMLINKS back into the real install, so this costs
        /// kilobytes rather than copying a multi-gigabyte game, and the game's own files are
        /// never duplicated or modified.
        ///
        /// No _CodeSignature is produced and none is wanted. The shadow is ad-hoc signed at the
        /// executable level only; it is a file we just created, so it carries no quarantine
        /// attribute and Gatekeeper is not consulted. Ad-hoc also keeps the binary
        /// non-platform, which is what preserves DYLD_INSERT_LIBRARIES for doorstop -- the
        /// reason /usr/bin/arch was rejected in the first place.
        /// </remarks>
        private static string PrepareRosettaBundle(string valheimDir, string worldDir, string exec)
        {
            string realContents = Path.Combine(valheimDir, "Valheim.app", "Contents");
            string shadowApp = Path.Combine(worldDir, "rosetta", "Valheim.app");
            string shadowContents = Path.Combine(shadowApp, "Contents");
            string shadowMacOs = Path.Combine(shadowContents, "MacOS");
            string shadowExec = Path.Combine(shadowMacOs, "Valheim");

            Directory.CreateDirectory(shadowMacOs);

            // Re-thin only when Steam's binary is newer than the slice we cached. A Valheim
            // update rewrites the universal binary, and a stale slice would quietly launch the
            // previous build against the current data files.
            bool stale = !File.Exists(shadowExec)
                         || File.GetLastWriteTimeUtc(exec) > File.GetLastWriteTimeUtc(shadowExec);

            if (stale)
            {
                if (File.Exists(shadowExec)) { File.Delete(shadowExec); }

                if (!Run("/usr/bin/lipo", new[] { "-thin", "x86_64", exec, "-output", shadowExec }))
                {
                    Ui.Warning("Could not extract the x86_64 build, so Valheim will run as native arm64.",
                               "Mods may not load. See the PhValheim docs for Apple Silicon.");
                    return null;
                }

                // lipo -thin drops the linker's per-slice ad-hoc signature. Re-sign so the
                // binary is a normal signed executable rather than an unsigned one.
                if (!Run("/usr/bin/codesign", new[] { "--force", "--sign", "-",
                                                      "--preserve-metadata=entitlements,flags",
                                                      shadowExec }))
                {
                    Ui.Warning("Could not re-sign the x86_64 build, so Valheim will run as native arm64.",
                               "Mods may not load. See the PhValheim docs for Apple Silicon.");
                    return null;
                }

                Ui.Detail("codesign", "re-signed the x86_64 slice (outside the game's bundle)");
            }

            // Info.plist is copied, not linked: it is the one file whose contents the shadow
            // bundle genuinely owns, and CFBundleExecutable must name OUR executable.
            string realPlist = Path.Combine(realContents, "Info.plist");
            string shadowPlist = Path.Combine(shadowContents, "Info.plist");
            if (File.Exists(realPlist)
                && (!File.Exists(shadowPlist)
                    || File.GetLastWriteTimeUtc(realPlist) > File.GetLastWriteTimeUtc(shadowPlist)))
            {
                File.Copy(realPlist, shadowPlist, true);
            }

            // Everything heavy is a symlink. Resources is the load-bearing one -- it is where
            // Unity's Data directory lives. Frameworks carries libmonobdwgc, PlugIns may be
            // absent on some builds, which is not an error.
            foreach (string dir in new[] { "Resources", "Frameworks", "PlugIns" })
            {
                string target = Path.Combine(realContents, dir);
                string link = Path.Combine(shadowContents, dir);
                if (!Directory.Exists(target)) { continue; }

                // A symlink whose target moved (Steam library relocated, world renamed) is
                // worse than no symlink: it resolves to nothing and the game starts with no
                // data. Recreate rather than trust an existing one.
                if (Directory.Exists(link) || File.Exists(link))
                {
                    try { Directory.Delete(link); } catch (IOException) { File.Delete(link); }
                }
                Directory.CreateSymbolicLink(link, target);
            }

            if (!Directory.Exists(Path.Combine(shadowContents, "Resources")))
            {
                Ui.Warning("Could not link the Valheim data files into the Rosetta bundle.",
                           "Valheim will run as native arm64 instead, and mods may not load.");
                return null;
            }

            Ui.Detail("rosetta bundle", shadowApp);
            return shadowExec;
        }

        /// <summary>Run a tool, wait, and report whether it exited 0.</summary>
        private static bool Run(string exe, string[] args)
        {
            var psi = new ProcessStartInfo(exe);
            foreach (string a in args) { psi.ArgumentList.Add(a); }
            psi.UseShellExecute = false;
            psi.RedirectStandardError = true;
            using var proc = Process.Start(psi);
            if (proc == null) { return false; }
            // A tool that hangs must not hang the launcher. 60s is generous for lipo on a
            // ~1 GB binary and for codesign on the slice it produces.
            if (!proc.WaitForExit(60000))
            {
                try { proc.Kill(true); } catch { }
                return false;
            }
            return proc.ExitCode == 0;
        }
    }
}