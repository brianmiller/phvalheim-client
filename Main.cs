using System;
using System.Data;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Configuration;
using System.Collections.Specialized;
using Microsoft.Win32;
using System.Security.Cryptography.X509Certificates;

namespace PhValheim
{
    public class PhValheim
    {
        static void Main(string[] args)
        {
            string phvalheimDir = @"%appdata%\PhValheim2.0";
            string[] argumentsPassed = Array.Empty<string>();
            string command = "";
            string worldName = "";
            string worldPassword = "";
            string worldHost = "";
            string worldPort = "";
            string texturePack = "";
            string steamDir = "";
            string steamExe = "";
            
            //take in and process all arguments from our URL handler
            if(!Arguments.PhValheim.argHandler(ref args,ref argumentsPassed, ref command, ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref texturePack))
            {
                return;
            }

            //we're launching
            if (command == "launch")
            {
                //run through the PhValheim prep logic, exit if fails         
                if (!Prep.PhValheim.PhValheimPrep(phvalheimDir, worldName))
                {              
                    Console.WriteLine("\n");
                    Console.WriteLine("Press any key to exit.");
                    Console.ReadLine();
                    return;
                }

                //get our Steam installation directory, exit if fails
                if (!Steam.PhValheim.SteamGetter(ref steamDir, ref steamExe))
                {                  
                    Console.WriteLine("\n");
                    Console.WriteLine("Press any key to exit.");
                    Console.ReadLine();
                    return;
                }

                //sync world to local disk
                if (!Syncer.PhValheim.Sync(phvalheimDir, worldName))
                {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press any key to exit.");
                    Console.ReadLine();
                    return;
                }

                //launch the game in the world context
                //Launcher.PhValheim.Launch(ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref steamDir, ref steamExe);

            }
        }
    }
}