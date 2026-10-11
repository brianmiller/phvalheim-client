using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace PhValheim.Prep
{
    public class PhValheim
    {
        public static bool MakeDir(string inputDir, string desc)
        {
            inputDir = Environment.ExpandEnvironmentVariables(inputDir);
            bool inputDirExists = System.IO.Directory.Exists(inputDir);
            // Silent on success, both ways. "PhValheim root directory was found: C:\Users\..."
            // told a player nothing they could act on and cost two of the first four lines on
            // screen; whether our own folder exists is our problem, not theirs. The path is
            // still one PHVALHEIM_VERBOSE away.
            if (!inputDirExists)
            {
                Ui.Detail(desc + " (creating)", inputDir);

                try
                {
                    Directory.CreateDirectory(inputDir);
                    return true;
                }
                catch (Exception e)
                {
                    // Named the directory and the reason. The old message said neither, so a
                    // permissions problem and a full disk produced the same unactionable line.
                    Ui.Fail("failed");
                    Ui.Error("PhValheim could not create its " + desc + " folder.", e.Message,
                             inputDir);
                    return false;
                }

            }
            else
            {
                Ui.Detail(desc, inputDir);
                return true;
            }
        }


        //ensure PhValheim's root dir exists, else create it.
        public static bool PhValheimPrep()
        {
            // One step for both folders. They are one concern to the player and they fail for
            // the same handful of reasons.
            Ui.Step("PhValheim folders");

            if (!MakeDir(Platform.State.PhValheimDir, "PhValheim root"))
            {
                return false;
            }

            if (!MakeDir(Platform.State.PhValheimServerRoot, "World root"))
            {
                return false;
            }

            Ui.Done("ready");
            return true;
        }


        // write backenfile to bepinex directory. phvalheim-companion uses this file to send "Player" scene data to phvalheim-server's backend (e.g., world progression (boss heads hung at spawn point)
        public static bool WriteBackendFile(string worldName, string phvalheimHostNoPort, string phvalheimURL)
        {
            string bepInExRoot = "";
            string backendFile;

            OSPlatform osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows : OSPlatform.Linux;

            if (osPlatform == OSPlatform.Windows)
            {
                bepInExRoot = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim\\worlds\\" + phvalheimHostNoPort + "\\" + worldName + "\\" + worldName + "\\BepInEx\\");
            }

            else if (osPlatform == OSPlatform.Linux)
            {
                bepInExRoot = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.config/PhValheim/worlds/" + phvalheimHostNoPort + "/" + worldName + "/" + worldName + "/BepInEx/";
            }

            else
            {
                Ui.Error("This operating system is not supported.");
                return false;
            }

            // set bepinex root directory
            backendFile = Environment.ExpandEnvironmentVariables(bepInExRoot + "phvalheim.backend" );
            
            // ensure the bepinex directory exists
            if (!Directory.Exists(bepInExRoot))
            {
                Directory.CreateDirectory(bepInExRoot);
            }

            // write new backend file
            using (StreamWriter outputFile = new StreamWriter(backendFile))
            {
                outputFile.Write(phvalheimURL);
            }
            return true;
        }
    }
}


