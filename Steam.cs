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
    }
}


