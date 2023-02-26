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
            if (!inputDirExists)
            {
                Console.WriteLine(desc + " directory is missing, creating: " + inputDir);

                try
                {
                    Directory.CreateDirectory(inputDir);
                    return true;
                }
                catch
                {
                    Console.WriteLine(desc + " directory could not be created, exiting...");
                    return false;
                }

            }
            else
            {
                Console.WriteLine(desc + " directory was found: " + inputDir);
                return true;
            }
        }
           
        
        //ensure PhValheim's root dir exists, else create it.
        public static bool PhValheimPrep()
        {
            if (!MakeDir(Platform.State.PhValheimDir, "PhValheim root"))
            {
                return false;
            }

            if (!MakeDir(Platform.State.PhValheimServerRoot, "World root"))
            {
                return false;
            }

            return true;
        }


        // write backenfile to bepinex directory. phvalheim-companion uses this file to send "Player" scene data to phvalheim-server's backend (e.g., world progression (boss heads hung at spawn point)
        public static bool WriteBackendFile(string worldName, string phvalheimHostNoPort, string phvalheimURL)
        {
            string bepInExRoot;
            string backendFile;

            OSPlatform osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows : OSPlatform.Linux;

            if (osPlatform == OSPlatform.Windows)
            {
                bepInExRoot = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim\\worlds\\" + phvalheimHostNoPort + "\\" + worldName + "\\" + worldName + "\\BepInEx\\");
                backendFile = Environment.ExpandEnvironmentVariables(bepInExRoot + "phvalheim.backend" );

                // ensure the bepinex directory exists
                if (!Directory.Exists(bepInExRoot))
                {
                    Directory.CreateDirectory(bepInExRoot);
                }

                // if backendFile already exists, delete it so we write current information
                //if (!File.Exists(backendFile))
                //{
                //    File.Delete(backendFile);
                //}

                // write new backend file
                using (StreamWriter outputFile = new StreamWriter(backendFile))
                {
                    outputFile.Write(phvalheimURL);
                }
                return true;
            }
            return true; 
        }

    }
}


