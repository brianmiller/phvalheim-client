using System;
using System.Diagnostics;
using System.Runtime.ExceptionServices;

namespace PhValheim.Launcher
{
    public class PhValheim
    {
        public static void Launch(ref string worldName, ref string worldPassword, ref string worldHost, ref string worldPort, ref string steamDir, ref string steamExe)
        {

            Console.WriteLine("");
            Console.WriteLine("World Launch Detected");
            Console.WriteLine("");


            Console.WriteLine(" Steam root: " + steamDir);
            Console.WriteLine(" Name: " + worldName);
            Console.WriteLine(" Password: " + worldPassword);
            Console.WriteLine(" Host: " + worldHost);
            Console.WriteLine(" Port: " + worldPort);

            //Console.WriteLine("Second Argument: " + secondArg);

            //Process.Start(@"c:\windows\system32\notepad.exe", firstArg);
            //&"$STEAM_DIR\steam.exe" - applaunch 892970--doorstop - enable true--doorstop - target "$DATA_DIR/$WORLD/$WORLD/BepInEx/core/BepInEx.Preloader.dll" - console
            //Process.Start(@"C:\Program Files (x86)\Steam\steam.exe", "-applaunch 892970 -console");
            //Process.Start(@"C:\Program Files (x86)\Steam\steam.exe", "-applaunch 892970 -console");
        }
    }
}