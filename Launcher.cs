using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PhValheim.Launcher
{
    public class PhValheim
    {
        public static void Launch(ref string worldName, ref string worldPassword, ref string worldHost, ref string worldPort, ref string steamDir, ref string steamExe, ref string phvalheimDir, ref string phvalheimHostNoPort, string valheimDir)
        {
            string BepInEx_Preloader = Paths.PhValheim.getBepInExPreloader(phvalheimHostNoPort, worldName);

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
                // Log start command
                Console.WriteLine("  Command  : " + steamExe + " -applaunch 892970 --doorstop-enable true --doorstop-target \"" + BepInEx_Preloader + "\" -console");
                Process.Start(@steamExe, "-applaunch 892970 --doorstop-enable true --doorstop-target \"" + BepInEx_Preloader + "\" -console");
            } else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                // if linux then run steamcmd with additional environment variables
                Console.WriteLine("Launching Valheim with environment variables (Linux)...");
                {
                  string exec = $"{valheimDir}/valheim.x86_64";
                  string ld_library_path = $"{valheimDir}/doorstop_libs:{System.Environment.GetEnvironmentVariable("LD_LIBRARY_PATH")}";
                  string ld_preload = $"libdoorstop_x64.so:{System.Environment.GetEnvironmentVariable("LD_PRELOAD")}";

                  ProcessStartInfo startInfo = new ProcessStartInfo(exec);

                  startInfo.UseShellExecute = true;
                  startInfo.Arguments = "-console";
                  startInfo.EnvironmentVariables["DOORSTOP_ENABLE"] =  "TRUE";
                  startInfo.EnvironmentVariables["DOORSTOP_INVOKE_DLL_PATH"] =  BepInEx_Preloader;
                  startInfo.EnvironmentVariables["DOORSTOP_CORLIB_OVERRIDE_PATH"] =  Path.Combine(valheimDir, "unstripped_corlib");
                  startInfo.EnvironmentVariables["LD_LIBRARY_PATH"] = ld_library_path;
                  startInfo.EnvironmentVariables["LD_PRELOAD"] = ld_preload;
                  Process.Start(startInfo);
              }
            }
        }
    }
}