using Microsoft.Win32;


namespace PhValheim.Steam
{
    public class PhValheim
    {
        //get our local Steam installation directory and execuatable
        public static bool SteamGetter(ref string steamDir, ref string steamExe)
        {
            //get steam info from registry, exit if Steam is missing.
            RegistryKey steamKey = Registry.CurrentUser.OpenSubKey("Software\\Valve\\Steam");

            if (steamKey != null)
            {
                steamDir = (steamKey.GetValue("SteamPath") as string).Replace('/', '\\');
                steamExe = (steamKey.GetValue("SteamExe") as string).Replace('/', '\\');
                Console.WriteLine("Steam root directory was found: " + steamDir);
                return true;
            }
            else
            {
                Console.WriteLine("ERROR: Steam isn't installed, exiting...");
                return false;
            }
        }

        //get our local Valheim installation directory and execuatable
        public static bool ValheimGetter(string steamDir, ref string valheimDir)
        {
            foreach (var line in File.ReadAllLines(steamDir + "\\steamapps\\libraryfolders.vdf"))
            {
                if (line.Contains("path")) 
                {      
                    string[] library = line.Split('"');
                    foreach (var libraryPath in library) 
                    {
                        bool valheimExists = File.Exists(libraryPath + "\\steamapps\\appmanifest_892970.acf");
                        if (valheimExists)
                        {
                            valheimDir = libraryPath + "\\steamapps\\common\\Valheim";
                            valheimDir = valheimDir.Replace(@"\\", @"\");
                            Console.WriteLine("Valheim root directory was found: " + valheimDir);
                            return true;
                        }
                    }                   
                } 
            }
            Console.WriteLine("Valheim not found, exiting...");
            return false;
        }
    }
}


