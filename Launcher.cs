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
                Process.Start(@steamExe, "-applaunch 892970 --doorstop-enabled true --doorstop-target-assembly \"" + BepInEx_Preloader + "\" -console");
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
                    steamStartInfo.RedirectStandardOutput = true;
                    steamStartInfo.RedirectStandardError = true;
                    steamStartInfo.UseShellExecute = false;
                    steamStartInfo.WindowStyle = ProcessWindowStyle.Minimized;
                    steamStartInfo.Arguments = "-nofriendsui -console";
                    Process.Start(steamStartInfo);

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
                  string setsid = "/usr/bin/setsid";
                  string worldDir = Path.Combine(Platform.State.PhValheimServerRoot, Platform.State.WorldName);
                  string doorstep_libs = Path.Combine(valheimDir, "doorstop_libs");
                  string ld_library_path = doorstep_libs;
                  string existingLdPreload = System.Environment.GetEnvironmentVariable("LD_PRELOAD");
                  string ld_preload = string.IsNullOrEmpty(existingLdPreload)
                      ? "libdoorstop_x64.so"
                      : $"libdoorstop_x64.so:{existingLdPreload}";

                  ProcessStartInfo startInfo = new ProcessStartInfo(setsid);

                  startInfo.UseShellExecute = false;
                  startInfo.CreateNoWindow = false;
                  startInfo.ArgumentList.Add(exec);
                  startInfo.ArgumentList.Add("-console");
                  startInfo.WorkingDirectory = valheimDir;
                  startInfo.EnvironmentVariables["DOORSTOP_ENABLED"] =  "1";
                  startInfo.EnvironmentVariables["DOORSTOP_TARGET_ASSEMBLY"] =  BepInEx_Preloader;
                  startInfo.EnvironmentVariables["DOORSTOP_MONO_LIB_PATH"] =  Path.Combine(valheimDir, "valheim_Data", "MonoBleedingEdge", "x86_64", "libmonobdwgc-2.0.so");
                  //startInfo.EnvironmentVariables["DOORSTOP_CORLIB_OVERRIDE_PATH"] =  Path.Combine(valheimDir, "unstripped_corlib");
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

                  Process.Start(startInfo);
                }
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Console.WriteLine("  macOS launch detected...");

                // Check if steam is already running; Valheim needs Steam online at launch
                string[] pids = Process.GetProcessesByName("steam_osx").Select(p => p.Id.ToString()).ToArray();
                if (pids.Length == 0)
                {
                    Console.WriteLine("  Starting Steam...");
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
                        Console.WriteLine("  WARNING: libdoorstop.dylib not found in world dir or app bundle");
                }

                string monoLibPath = Path.Combine(valheimDir, "Valheim.app", "Contents", "Frameworks", "libmonobdwgc-2.0.dylib");

                ProcessStartInfo startInfo = new ProcessStartInfo(exec);
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = false;
                startInfo.ArgumentList.Add("-console");
                startInfo.WorkingDirectory = valheimDir;
                startInfo.EnvironmentVariables["DOORSTOP_ENABLED"] = "1";
                startInfo.EnvironmentVariables["DOORSTOP_TARGET_ASSEMBLY"] = BepInEx_Preloader;
                startInfo.EnvironmentVariables["DOORSTOP_MONO_LIB_PATH"] = monoLibPath;
                startInfo.EnvironmentVariables["DYLD_LIBRARY_PATH"] = doorstopLibs;
                startInfo.EnvironmentVariables["DYLD_INSERT_LIBRARIES"] = doorstopDylib;

                Process.Start(startInfo);
            }
        }
    }
}