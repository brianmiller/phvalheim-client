using System.Reflection;

namespace PhValheim
{
    public class PhValheim
    {

        static void Main(string[] args)
        {

            System.Reflection.Assembly assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var phvalheimLauncherVersion = Assembly.GetEntryAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute> ().InformationalVersion;

            string[] argumentsPassed = Array.Empty<string>();
            string command = "";
            string worldName = "";
            string worldPassword = "";
            string worldHost = "";
            string worldPort = "";
            
            string texturePack = "";
            string phvalheimHost = "";
            string phvalheimURL = "";
            string httpScheme = "";
            string phvalheimHostNoPort;


            //take in and process all arguments from our URL handler
            if (!Arguments.PhValheim.argHandler(ref args, ref argumentsPassed, ref command, ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref texturePack, ref phvalheimHost, ref httpScheme))
            {
                Console.WriteLine("\n");
                Console.WriteLine("Press Enter key to exit.");
                Console.ReadLine();
                return;
            }
            else
            {
                phvalheimURL = httpScheme + "://" + phvalheimHost;
                string[] phvalheimHostNoPortArr = phvalheimHost.Split(':', StringSplitOptions.TrimEntries);
                phvalheimHostNoPort = phvalheimHostNoPortArr[0];

                Console.WriteLine("\n## PhValheim Launcher " + phvalheimLauncherVersion + " ##\n");
                Console.WriteLine("PhValheim Remote Server: " + phvalheimURL);

                if (!Platform.State.init(worldName, phvalheimHostNoPort)) {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press Enter key to exit.");
                    Console.ReadLine();
                    return;
                }
            }

            //we're launching
            if (command == "launch")
            {
                //write backend info to local file
                Prep.PhValheim.WriteBackendFile(worldName);


                //check client version
                Ver.PhValheim.VersionCheck(phvalheimLauncherVersion);


                //run through the PhValheim prep logic, exit if fails         
                if (!Prep.PhValheim.PhValheimPrep())
                {              
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the Enter key to exit.");
                    Console.ReadLine();
                    return;
                }

                //get our Valheim installation directory, exit if fails
                if (!Steam.PhValheim.ValheimGetter())
                {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the Enter key to exit.");
                    Console.ReadLine();
                    return;
                }

                //sync world to local disk
                if (!Syncer.PhValheim.Sync(phvalheimURL))
                {
                    Console.WriteLine("\n");
                    Console.WriteLine("Press the Enter key to exit.");
                    Console.ReadLine();
                    return;
                }



                //launch the game in the world context
                Launcher.PhValheim.Launch(ref worldPassword, ref worldHost, ref worldPort);


                //keep everything on the screen allowing you to read what just happend
                Console.WriteLine("\n");
                Console.WriteLine("This window will automatically close in 10 seconds...");
                Thread.Sleep(10000);
                return;

            }
        }
    }
}
