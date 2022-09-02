using System.Diagnostics;

namespace PhValheim
{
    public class PhValheim
    {
        static void Main(string[] args)
        {

            System.Reflection.Assembly assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var phvalheimLauncherVersion = FileVersionInfo.GetVersionInfo(assembly.Location).ProductVersion;            
            string phvalheimDir = @"%appdata%\PhValheim";
            string[] argumentsPassed = Array.Empty<string>();
            string command = "";
            string worldName = "";
            string worldPassword = "";
            string worldHost = "";
            string worldPort = "";
            
            string texturePack = "";
            string steamDir = "";
            string steamExe = "";
            string phvalheimHost = "";
            string phvalheimURL = "";


            //take in and process all arguments from our URL handler
            if (!Arguments.PhValheim.argHandler(ref args, ref argumentsPassed, ref command, ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref texturePack, ref phvalheimHost))
            {
                Console.WriteLine("\n");
                Console.WriteLine("Press any key to exit.");
                Console.ReadLine();
                return;
            }
            else
            {
                phvalheimURL = @"http://" + phvalheimHost;
                Console.WriteLine("\n## PhValheim Launcher " + phvalheimLauncherVersion + " ##\n");
                Console.WriteLine("PhValheim Remote Server: " + phvalheimURL);
            }



            //we're launching
            if (command == "launch")
            {
                //run through the PhValheim prep logic, exit if fails         
                if (!Prep.PhValheim.PhValheimPrep(phvalheimDir, worldName))
                {              
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the enter key to exit.");
                    Console.ReadLine();
                    return;
                }


                //get our Steam installation directory, exit if fails
                if (!Steam.PhValheim.SteamGetter(ref steamDir, ref steamExe))
                {                  
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the enter key to exit.");
                    Console.ReadLine();
                    return;
                }


                //sync world to local disk
                if (!Syncer.PhValheim.Sync(phvalheimDir, worldName, phvalheimURL, steamDir))
                {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the enter key to exit.");
                    Console.ReadLine();
                    return;
                }


                //launch the game in the world context
                Launcher.PhValheim.Launch(ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref steamDir, ref steamExe, ref phvalheimDir);


                //keep everything on the screen allowing you to read what just happend
                Console.WriteLine("\n");
                Console.WriteLine("This window will automatically close in 10 seconds...");
                Thread.Sleep(10000);
                return;

            }
        }
    }
}