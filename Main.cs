using System.Reflection;

namespace PhValheim
{
    public class PhValheim
    {

        static void Main(string[] args)
        {
            // A crash must not take its own explanation with it.
            //
            // This client is normally started by a phvalheim:// URL handler, which gives it a
            // terminal with NO stdin -- so Console.ReadLine() returns instantly and the window
            // closes the moment the process ends. An unhandled exception therefore printed its
            // stack trace and vanished in the same instant, which is exactly how a modded
            // launch broke with nothing to show for it. The trace was there; nobody could read
            // it fast enough.
            //
            // Rethrow is deliberately NOT done: there is no outer handler to benefit, and the
            // non-zero exit would be just as invisible.
            try
            {
                Run(args);
            }
            catch (Exception e)
            {
                Ui.Error("PhValheim hit an unexpected problem and could not finish.",
                         e.GetType().Name + ": " + e.Message);
                Ui.Blank();
                Ui.Line("The technical detail below is what to send if you report this:");
                Ui.Blank();
                Console.WriteLine(e.ToString());
                Ui.PressEnterToExit();
                // Hold the window even when there is no stdin for Enter to arrive on.
                Thread.Sleep(30000);
            }
        }

        static void Run(string[] args)
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


                // Stay up for as long as the game does.
                //
                // This used to print "This window closes on its own in 10 seconds" and sleep,
                // which put the window's lifetime on a timer unrelated to anything the player
                // was doing -- it vanished ten seconds into a session, taking the launch log
                // with it, so a crash two minutes later had nothing left on screen to explain
                // it. Now it closes when Valheim does, and says so.
                //
                // The notice matters as much as the wait: a window that sits there with no
                // explanation reads as "still working, do not touch". It is not -- the game is
                // already independent of this process on all three platforms (Steam starts it
                // on Windows, setsid on Linux, and an exec with SIGHUP ignored on macOS).
                Ui.Blank();
                Ui.Section("Valheim is running");
                Ui.Line("You can close this window at any time -- the game keeps running.");
                Ui.Line("Leave it open and it closes by itself when you quit Valheim.");
                Ui.Blank();

                if (Game.WaitForExit())
                {
                    Ui.Line("Valheim has closed. See you next time.");
                    Thread.Sleep(2000);
                }
                else
                {
                    // Never saw the game in the process table. Either the launch failed, or it
                    // is running somewhere this process cannot see -- a Flatpak Steam runs
                    // Valheim on the host, outside our sandbox's process namespace. Both of
                    // those make "the game has closed" a claim we have not earned, so the
                    // window waits for the player instead of asserting anything.
                    Ui.Note("This window could not tell when Valheim closed, so it is staying open.");
                    Ui.PressEnterToExit();
                }
                Environment.Exit(0);


            }
        }
    }
}
