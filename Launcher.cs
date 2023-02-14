using System.Diagnostics;
using System.Runtime;
using System.Runtime.InteropServices;

namespace PhValheim.Launcher
{
    public class PhValheim
    {
        public static void Launch(ref string worldPassword, ref string worldHost, ref string worldPort)
        {
            string BepInEx_Preloader = Path.Combine(Platform.State.PhValheimServerRoot, Platform.State.WorldName, "BepInEx","core","BepInEx.Preloader.dll");
            string steamExe = Platform.State.SteamExe;
            string steamDir = Platform.State.SteamDir;
            string valheimDir = Platform.State.ValheimDir;
            string worldName = Platform.State.WorldName;

            Console.WriteLine("  Launching Valheim with '" + worldName + "' context...");
            Console.WriteLine("");
            Console.WriteLine("  Steam root: " + steamDir);
            Console.WriteLine("  Name: " + worldName);
            Console.WriteLine("  Password: " + worldPassword);
            Console.WriteLine("  Host: " + worldHost);
            Console.WriteLine("  Port: " + worldPort + "/udp");
            Console.WriteLine("");

            // if running in windows
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                Process.Start(@steamExe, "-applaunch 892970 --doorstop-enable true --doorstop-target \"" + BepInEx_Preloader + "\" -console");
            } 
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {

                Console.WriteLine("  Linux launch detected...");

                // Check if steam is already running
                // If its not, we need to launch steam, otherwise velheim will crash on startup
                string[] pids = Process.GetProcessesByName("steam").Select(p => p.Id.ToString()).ToArray();
                if (pids.Length == 0)
                {
                    Console.WriteLine("  Starting Steam...");
                    ProcessStartInfo steamStartInfo = new ProcessStartInfo(@steamExe);
                    steamStartInfo.RedirectStandardOutput = false;
                    steamStartInfo.Arguments = "> /dev/null 2>&1";
                    Process.Start(steamStartInfo);
                    Console.WriteLine("FOOOOOOOOOOOO: " + @steamExe);

                    // I honestly don't know a better way to do this, so we sleep
                    Thread.Sleep(10000);
                }
            {

                  // try to set gnome's check-alive-timeout to 0. This timeout is what causes the "not responding" warnings.
                  // IronGate needs to send a pong back to the different display managers to satisfy this timeout
                  try
                  {
                        string gsettingsExec = "/usr/bin/gsettings";
                        ProcessStartInfo gsettingsCmd = new ProcessStartInfo(gsettingsExec);
                        gsettingsCmd.UseShellExecute = true;
                        gsettingsCmd.CreateNoWindow = true;
                        gsettingsCmd.Arguments = "set org.gnome.mutter check-alive-timeout 0";
                        Process.Start(gsettingsCmd);
                   }
                   catch
                   {
                   }

                  // if running in linux
                  // valheim.x86_64 must be launched directly with BepInEx environment variables instead of through steam
                  // This is the same strategy that the BepInEx uses in their start_game_bepinex.sh script
                  string exec = Path.Combine(valheimDir, "valheim.x86_64");
                  string doorstep_libs = Path.Combine(valheimDir, "doorstop_libs");
                  string ld_library_path = doorstep_libs;
                  string ld_preload = $"libdoorstop_x64.so:{System.Environment.GetEnvironmentVariable("LD_PRELOAD")}";

                  ProcessStartInfo startInfo = new ProcessStartInfo(exec);

                  startInfo.UseShellExecute = true;
                  startInfo.CreateNoWindow = false;
                  startInfo.Arguments = "-console";
                  startInfo.WorkingDirectory = valheimDir;
                  startInfo.EnvironmentVariables["DOORSTOP_ENABLE"] =  "TRUE";
                  startInfo.EnvironmentVariables["DOORSTOP_INVOKE_DLL_PATH"] =  BepInEx_Preloader;
                  startInfo.EnvironmentVariables["DOORSTOP_CORLIB_OVERRIDE_PATH"] =  Path.Combine(valheimDir, "unstripped_corlib");
                  startInfo.EnvironmentVariables["LD_LIBRARY_PATH"] = ld_library_path;
                  startInfo.EnvironmentVariables["LD_PRELOAD"] = ld_preload;                 

                  //Console.WriteLine("  Executable: " + exec);
                  //Console.WriteLine("  Arguments: " + startInfo.Arguments);
                  //Console.WriteLine("  Working Directory: " + startInfo.WorkingDirectory);
                  //Console.WriteLine("  DOORSTOP_ENABLE: " + startInfo.EnvironmentVariables["DOORSTOP_ENABLE"]);
                  //Console.WriteLine("  DOORSTOP_INVOKE_DLL_PATH: " + startInfo.EnvironmentVariables["DOORSTOP_INVOKE_DLL_PATH"]);
                  //Console.WriteLine("  DOORSTOP_CORLIB_OVERRIDE_PATH: " + startInfo.EnvironmentVariables["DOORSTOP_CORLIB_OVERRIDE_PATH"]);
                  //Console.WriteLine("  LD_LIBRARY_PATH: " + startInfo.EnvironmentVariables["LD_LIBRARY_PATH"]);
                  //Console.WriteLine("  LD_PRELOAD: " + startInfo.EnvironmentVariables["LD_PRELOAD"]);

                  Process p = Process.Start(startInfo);
                  p.WaitForExit();
                }
            }
        }
    }
}