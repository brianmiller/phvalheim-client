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


        //
        public static bool WriteBackendFile(string worldName)
        {

            OSPlatform osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows : OSPlatform.Linux;

            if (osPlatform == OSPlatform.Windows)
            {
                string foo = worldName;
                return true;
                //backendFile = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim\\");
            }
            return true; 
        }

    }
}


