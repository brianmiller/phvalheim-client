using System.Diagnostics;

namespace PhValheim.Launcher
{
    public class PhValheim
    {
        public static void Launch(ref string worldName, ref string worldPassword, ref string worldHost, ref string worldPort, ref string steamDir, ref string steamExe, ref string phvalheimDir)
        {
            phvalheimDir = Environment.ExpandEnvironmentVariables(phvalheimDir);
            string BepInEx_Preloader = phvalheimDir + "\\worlds" + "\\" + worldName + "\\" + worldName + "\\BepInEx\\core\\BepInEx.Preloader.dll";

            Console.WriteLine("  Launching Valheim with '" + worldName + "' context...");
            Console.WriteLine("");
            Console.WriteLine("  Steam root: " + steamDir);
            Console.WriteLine("  Name: " + worldName);
            Console.WriteLine("  Password: " + worldPassword);
            Console.WriteLine("  Host: " + worldHost);
            Console.WriteLine("  Port: " + worldPort + "/udp");
            Console.WriteLine("");

            //Process.Start(@steamExe, "-applaunch 892970 --doorstop-enable true --doorstop-target \"" + BepInEx_Preloader + "\" -console");
        }
    }
}