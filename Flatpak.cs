using System.Diagnostics;

namespace PhValheim.Sandbox
{
    /// <summary>
    /// Everything the client has to do differently when it is running inside a
    /// Flatpak sandbox.
    ///
    /// The client is not really an application in its own right -- it is an
    /// orchestrator. It finds Steam, syncs a mod payload to disk and then execs
    /// Valheim with a doorstop environment. Every one of those steps is about
    /// the HOST: the host's Steam, the host's game files, the host's GPU
    /// drivers and the host's Steam Runtime. Running Valheim inside our sandbox
    /// would give it our runtime's libraries and no Steam client to talk to, so
    /// the sandbox is something to step out of, not something to work within.
    ///
    /// `flatpak-spawn --host` is the supported way out. It needs
    /// `--talk-name=org.freedesktop.Flatpak` in the manifest; without that
    /// permission every call here fails with a D-Bus access error rather than
    /// silently doing the wrong thing, which is the failure mode we want.
    ///
    /// OUTSIDE a sandbox every method here is a pass-through, so the .deb,
    /// .rpm and .tar.gz builds execute exactly the same code they always did.
    /// That is deliberate: one code path, so the Flatpak cannot drift away from
    /// the packages that are already known to work.
    /// </summary>
    public static class Flatpak
    {
        /// <summary>
        /// /.flatpak-info is written into every Flatpak sandbox by flatpak
        /// itself and cannot exist outside one. The FLATPAK_ID env var looks
        /// like an easier test but is inherited by child processes, so anything
        /// the client spawns would also believe it was sandboxed.
        /// </summary>
        private static readonly Lazy<bool> inSandbox = new Lazy<bool>(() => File.Exists("/.flatpak-info"));

        public static bool InSandbox => inSandbox.Value;

        private const string SpawnExe = "flatpak-spawn";

        // ON THE ENVIRONMENT OF HOST COMMANDS -- measured, because it is easy
        // to get backwards and the wrong guess is costly either way.
        //
        // A command run with `flatpak-spawn --host` does NOT inherit our
        // environment. It inherits the environment of the host's flatpak
        // session helper -- the user's real session -- plus whatever we pass
        // with --env. Verified directly: inside the sandbox FLATPAK_ID and
        // XDG_CONFIG_HOME are set (the latter to ~/.var/app/<id>/config), and
        // a host command spawned from that same process sees neither, not
        // even a variable passed in with `flatpak run --env=`.
        //
        // So the obvious worry does not apply. Valheim stores characters and
        // worlds under XDG_CONFIG_HOME, and if our per-app value reached the
        // game the player's saves would land inside our app directory and
        // vanish on uninstall -- but it cannot reach it.
        //
        // An earlier version of this file "fixed" that non-problem by forcing
        // XDG_CONFIG_HOME, XDG_DATA_HOME, PATH and friends to stock values.
        // That was strictly worse than doing nothing: it would have
        // OVERWRITTEN the settings of anyone who deliberately relocates
        // XDG_DATA_HOME to another disk, silently moving where Valheim keeps
        // its data. Inheriting the session's own values is already correct.
        //
        // Pass only what the game actually needs, and leave the rest alone.

        /// <summary>
        /// A ProcessStartInfo that will run <paramref name="exe"/> on the host
        /// when sandboxed, and directly when not.
        /// </summary>
        public static ProcessStartInfo HostCommand(string exe,
                                                   IEnumerable<string>? args = null,
                                                   IDictionary<string, string>? env = null,
                                                   string? workingDirectory = null)
        {
            ProcessStartInfo psi;

            if (!InSandbox)
            {
                psi = new ProcessStartInfo(exe);
                if (args != null)
                {
                    foreach (string a in args) psi.ArgumentList.Add(a);
                }
                if (env != null)
                {
                    foreach (var kv in env) psi.EnvironmentVariables[kv.Key] = kv.Value;
                }
                if (!string.IsNullOrEmpty(workingDirectory)) psi.WorkingDirectory = workingDirectory;
                psi.UseShellExecute = false;
                return psi;
            }

            psi = new ProcessStartInfo(SpawnExe);
            psi.ArgumentList.Add("--host");

            if (!string.IsNullOrEmpty(workingDirectory))
            {
                // --directory is what makes the host process start in the game
                // directory. Setting psi.WorkingDirectory instead would only
                // change the directory of flatpak-spawn itself, inside the
                // sandbox, where the path usually does not even exist.
                psi.ArgumentList.Add("--directory=" + workingDirectory);
            }

            if (env != null)
            {
                foreach (var kv in env) psi.ArgumentList.Add("--env=" + kv.Key + "=" + kv.Value);
            }

            // End of options. flatpak-spawn parses with GOption, which permutes
            // arguments, so without this a game argument like "-console" is
            // read as a flatpak-spawn flag and the spawn fails.
            psi.ArgumentList.Add("--");

            psi.ArgumentList.Add(exe);
            if (args != null)
            {
                foreach (string a in args) psi.ArgumentList.Add(a);
            }

            psi.UseShellExecute = false;
            return psi;
        }

        /// <summary>
        /// Run a short shell snippet on the host and collect its output. Used
        /// for the questions that only the host can answer -- where Steam is,
        /// whether it is already running.
        /// </summary>
        public static (int exitCode, string stdout) HostShell(string script, int timeoutMs = 20000)
        {
            try
            {
                ProcessStartInfo psi = HostCommand("/bin/sh", new[] { "-c", script });
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;

                using Process? p = Process.Start(psi);
                if (p == null) return (-1, "");

                string output = p.StandardOutput.ReadToEnd();
                if (!p.WaitForExit(timeoutMs))
                {
                    try { p.Kill(true); } catch { }
                    return (-1, "");
                }
                return (p.ExitCode, output.Trim());
            }
            catch (Exception)
            {
                return (-1, "");
            }
        }

        /// <summary>
        /// Is a process with this name running on the host?
        ///
        /// Process.GetProcessesByName cannot answer this from inside a sandbox.
        /// Flatpak unshares the PID namespace, so /proc shows only our own
        /// processes and the answer is always "no". The client used that answer
        /// to decide whether to start Steam, so in a Flatpak it would start a
        /// second Steam and then sleep ten seconds, every single launch.
        /// </summary>
        public static bool HostProcessRunning(string name)
        {
            if (!InSandbox)
            {
                return Process.GetProcessesByName(name).Length > 0;
            }

            // pgrep -x matches the executable name exactly, the same thing
            // GetProcessesByName does. Exit 0 means at least one match.
            var (exitCode, _) = HostShell("pgrep -x " + name + " >/dev/null 2>&1");
            return exitCode == 0;
        }
    }
}
