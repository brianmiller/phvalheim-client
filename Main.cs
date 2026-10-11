using System.Reflection;

namespace PhValheim
{
    public class PhValheim
    {

        static void Main(string[] args)
        {

            System.Reflection.Assembly assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var phvalheimLauncherVersion = Assembly.GetEntryAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute> ().InformationalVersion;
            phvalheimLauncherVersion = phvalheimLauncherVersion?.Split('+')[0]; // take only before '+'

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
            bool isVanilla = false;


            //take in and process all arguments from our URL handler
            if (!Arguments.PhValheim.argHandler(ref args, ref argumentsPassed, ref command, ref worldName, ref worldPassword, ref worldHost, ref worldPort, ref texturePack, ref phvalheimHost, ref httpScheme, ref isVanilla))
            {
                Ui.PressEnterToExit();
                return;
            }
            else
            {
                phvalheimURL = httpScheme + "://" + phvalheimHost;
                string[] phvalheimHostNoPortArr = phvalheimHost.Split(':', StringSplitOptions.TrimEntries);
                phvalheimHostNoPort = phvalheimHostNoPortArr[0];

                // The header answers the three questions a player has before anything happens:
                // which client is this, which server is it talking to, and which world. The old
                // banner said "PhValheim Launcher" while the update check said "PhValheim
                // Client"; it is one product and now has one name.
                Ui.Banner(phvalheimLauncherVersion);
                Ui.Field("Server", phvalheimURL);
                Ui.Field("World", worldName + (isVanilla ? "  (vanilla - no mods)" : "  (modded)"));
                Ui.Blank();

                if (!Platform.State.init(worldName, phvalheimHostNoPort)) {
                    Ui.PressEnterToExit();
                    return;
                }
            }


            //we're launching
            if (command == "launch")
            {

                //check client version
                Ver.PhValheim.VersionCheck(phvalheimLauncherVersion);


                //run through the PhValheim prep logic, exit if fails
                if (!Prep.PhValheim.PhValheimPrep())
                {
                    Ui.PressEnterToExit();
                    return;
                }


                //get our Valheim installation directory, exit if fails
                if (!Steam.PhValheim.ValheimGetter())
                {
                    Ui.PressEnterToExit();
                    return;
                }


                // A vanilla world has no BepInEx, no mods and no client payload, so
                // there is nothing to sync and no backend file for a companion mod that
                // will not be running. Players join it with Valheim's own +connect.
                if (!isVanilla)
                {
                    //sync world to local disk
                    if (!Syncer.PhValheim.Sync(phvalheimURL))
                    {
                        Ui.PressEnterToExit();
                        return;
                    }


                    //write backend info to local file
                    Prep.PhValheim.WriteBackendFile(worldName, phvalheimHostNoPort, phvalheimURL);
                }
                else
                {
                    // Said once, in the header, rather than repeated here: the World field
                    // already reads "(vanilla - no mods)".
                    Ui.Step("Mod files");
                    Ui.Done("not needed on a vanilla world");
                }


                //launch the game in the world context
                Launcher.PhValheim.Launch(ref worldPassword, ref worldHost, ref worldPort, isVanilla);


                //keep everything on the screen allowing you to read what just happend
                Ui.Blank();
                Ui.Line("This window closes on its own in 10 seconds.");
                Thread.Sleep(10000);
                Environment.Exit(0);


            }
        }
    }
}
