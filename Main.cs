namespace PhValheim
{
    public class PhValheim
    {
        static void Main(string[] args)
        {

            string phvalheimLauncherVersion = "2.0";
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
                if (!Syncer.PhValheim.Sync(phvalheimDir, worldName, phvalheimURL))
                {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press any key to exit.");
                    Console.ReadLine();
                    return;
                }


                //launch the game in the world context
                Launcher.PhValheim.Launch(ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref steamDir, ref steamExe, ref phvalheimDir);


                //keep everyone on the screen, allowing you to read what just happend
                Console.WriteLine("\n");
                Console.WriteLine("Press any key to safely close this window.");
                Console.ReadLine();
                return;

            }
        }
    }
}