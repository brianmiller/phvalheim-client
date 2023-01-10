using System.Runtime.InteropServices;
using Microsoft.Win32;

// Static Class: Paths.cs
// Provides static getter for
// steamDir
// phvalheimDir

namespace PhValheim.Paths
{
  public static class PhValheim
  {
    private static OSPlatform osPlatform;
    private static string phvalheimDir;
    public static char slash = Path.DirectorySeparatorChar;

    // constructor detects OS and sets paths accordingly
    static PhValheim()
    {
      osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows : OSPlatform.Linux;
      // write os platforms string to stdout
      Console.WriteLine("OS Platform is: " + osPlatform.ToString());
      if (osPlatform == OSPlatform.Windows)
      {
        // Windows
        phvalheimDir = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim");
      }
      else if (osPlatform == OSPlatform.Linux)
      {
        // Linux
        phvalheimDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.config/PhValheim";
      } else {
        throw new Exception("Unsupported OS");
      }
    }

    public static string GetPhValheimDir()
    {
      return phvalheimDir;
    }

    public static bool SteamGetter(ref string steamDir, ref string steamExe)
    {
      if (osPlatform == OSPlatform.Windows)
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
      else if (osPlatform == OSPlatform.Linux)
      {
        steamExe = "/usr/bin/steam";
        steamDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.steam/steam";
        return true;
      }
      throw new Exception("Unsupported OS");
    }

    public static string getLocalWorldVersionFile()
    {
      return $"{phvalheimDir}{slash}worlds{slash}version.txt";
    }

    public static string getLocalWorldFile(string phvalheimHostNoPort, string worldName)
    {
      return $"{phvalheimDir}{slash}worlds{slash}{phvalheimHostNoPort}{slash}{worldName}{slash}world.zip";
    }

    public static string getLocalWorldDir(string phvalheimHostNoPort, string worldName)
    {
      return $"{phvalheimDir}{slash}worlds{slash}{phvalheimHostNoPort}{slash}{worldName}{slash}{worldName}";
    }

    public static string getBepInExPreloader(string phvalheimHostNoPort, string worldName) {
      return $"{getLocalWorldDir(phvalheimHostNoPort, worldName)}{Paths.PhValheim.slash}BepInEx{Paths.PhValheim.slash}core{Paths.PhValheim.slash}BepInEx.Preloader.dll";
    }
  }
}


// namespace PhValheim.Paths
// {
//   public class PhValheim
//   {
//     private string phvalheimDir;
//     private string steamDir;

//     // constructor detects OS and sets paths accordingly
//     public PhValheim()
//     {
//       if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
//       {
//         // Windows
//         steamDir = Environment.ExpandEnvironmentVariables("%ProgramFiles(x86)%\\Steam");
//         phvalheimDir = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim");
//       }
//       else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
//       {
//         // Linux
//         steamDir = Environment.ExpandEnvironmentVariables("~/.steam/steam");
//         phvalheimDir = Environment.ExpandEnvironmentVariables("~/.config/PhValheim");
//       }
//       else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
//       {
//         // OSX
//         throw new Exception("OSX is not supported");
//       }
//     }

//     public string GetPhValheimDir()
//     {
//       return phvalheimDir;
//     }
//   }
// }
