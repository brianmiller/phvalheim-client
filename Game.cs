using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PhValheim
{
    /// <summary>
    /// Is Valheim running, and wait until it is not.
    ///
    /// WHY BY NAME AND NOT BY HANDLE. The obvious implementation is to keep the Process the
    /// launcher started and call WaitForExit() on it. That works on exactly none of the three
    /// platforms:
    ///
    ///   Windows -- we start steam.exe with "-applaunch 892970". Steam starts the game, so our
    ///              child is Steam, and when Steam is already running it signals the existing
    ///              instance and exits within a second. Waiting on it returns immediately.
    ///   Linux   -- we start /usr/bin/setsid, deliberately, so the game outlives this process.
    ///              setsid forks and exits; waiting on it returns immediately.
    ///   macOS   -- the game IS our direct child, so a handle would work here. One mechanism
    ///              that works on all three beats a handle that works on one.
    ///
    /// So the question "has the player quit Valheim" is answered from the process table, which
    /// is true regardless of who started the game or whether we are still its parent.
    /// </summary>
    public static class Game
    {
        /// <summary>
        /// Names to look for, per platform.
        ///
        /// Linux's is "valheim.x86_64" -- 14 characters. The kernel's comm field truncates at
        /// 15, so it survives intact; a longer name would be silently cut and never match, and
        /// "never matches" here reads as "the player quit instantly".
        /// </summary>
        private static string[] ProcessNames()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                return new[] { "valheim" };
            }
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                return new[] { "Valheim", "valheim" };
            }
            // Native Linux names the binary valheim.x86_64. Under a Flatpak Steam the game runs
            // on the host with the same name, which our process list cannot see -- see
            // IsRunning for what that costs.
            return new[] { "valheim.x86_64", "valheim" };
        }

        public static bool IsRunning()
        {
            foreach (string name in ProcessNames())
            {
                try
                {
                    if (Process.GetProcessesByName(name).Length > 0) { return true; }
                }
                catch
                {
                    // An unreadable process table is not worth crashing a launch for. Treated
                    // as "not running", which ends the wait rather than hanging on it.
                }
            }
            return false;
        }

        /// <summary>
        /// Block until Valheim appears and then exits.
        ///
        /// TWO PHASES, and the first one is the part that is easy to get wrong. The game takes
        /// a while to show up -- Steam has to hand off, BepInEx has to preload -- so polling
        /// "is it running" immediately after launch answers no, and a single-phase wait would
        /// return at once and close the window in the player's face. So: wait up to
        /// appearSeconds for it to appear, and only then wait for it to go.
        ///
        /// If it never appears we return false rather than waiting forever. That is the case
        /// where something went wrong with the launch, or where the game is running somewhere
        /// this process cannot see it (a Flatpak Steam puts Valheim on the host, outside our
        /// sandbox's process namespace), and in both of those the honest move is to stop
        /// claiming to know and let the caller say so.
        /// </summary>
        public static bool WaitForExit(int appearSeconds = 120, Action<int>? onWaiting = null)
        {
            int waited = 0;
            while (waited < appearSeconds)
            {
                if (IsRunning()) { break; }
                Thread.Sleep(1000);
                waited++;
            }
            if (!IsRunning()) { return false; }

            while (IsRunning())
            {
                Thread.Sleep(2000);
                onWaiting?.Invoke(2);
            }
            return true;
        }
    }
}
