using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PhValheim
{
    public enum GameState { Stopped, Running, Unknown }

    public static class Game
    {
        // The host owns the game even when the launcher is a Flatpak. Match
        // exact executable names for this user; zombies cannot run or own a session.
        internal static GameState ParseLinuxProcesses(int exitCode, string output)
        {
            if (exitCode != 0) return GameState.Unknown;
            foreach (string line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var fields = line.Trim().Split((char[]?)null, 2, StringSplitOptions.RemoveEmptyEntries);
                if (fields.Length != 2) return GameState.Unknown;
                if (fields[0].StartsWith("Z")) continue;
                if (fields[1] is "valheim.x86_64" or "valheim") return GameState.Running;
            }
            return GameState.Stopped;
        }

        public static GameState GetState()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                var result = Sandbox.Flatpak.HostShell("ps -u \"$(id -u)\" -o stat= -o comm=", 5000);
                return ParseLinuxProcesses(result.exitCode, result.stdout);
            }
            try
            {
                foreach (string name in new[] { "valheim", "Valheim" })
                {
                    var processes = Process.GetProcessesByName(name);
                    bool running = processes.Length > 0;
                    foreach (var process in processes) process.Dispose();
                    if (running) return GameState.Running;
                }
                return GameState.Stopped;
            }
            catch { return GameState.Unknown; }
        }

        public static bool IsRunning() => GetState() == GameState.Running;

        // Two phases: allow Steam time to start the game, then observe it until
        // exit. Failed inspection is UNKNOWN, never evidence that the game quit.
        public static bool WaitForExit(int appearSeconds = 120, Action<int>? onWaiting = null)
        {
            var clock = Stopwatch.StartNew();
            bool seen = false;
            while (true)
            {
                var state = GetState();
                if (state == GameState.Unknown) return false;
                if (state == GameState.Running) seen = true;
                else if (seen) return true;
                else if (clock.Elapsed.TotalSeconds >= appearSeconds) return false;
                Thread.Sleep(1000);
                onWaiting?.Invoke(1);
            }
        }
    }
}
