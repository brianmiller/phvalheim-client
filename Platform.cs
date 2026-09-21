using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace PhValheim.Platform
{
  public class State
  {
    private static State _instance;

    private string worldName;
    private string steamDir;
    private string steamExe;
    private string valheimDir;
    private string phvalheimHostNoPort;
    private string phvalheimDir;
    private static OSPlatform osPlatform;

    protected State() { }

    public static State Instance
    {
      get
      {
        if (_instance == null)
        {
          throw new Exception("State not initialized");
        }
        return _instance;
      }
    }

    public static bool init(string worldName, string phvalheimHostNoPort)
    {
      _instance = new State();
      osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows :
                   RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? OSPlatform.OSX : OSPlatform.Linux;
      if (osPlatform == OSPlatform.Windows)
      {
        RegistryKey steamKey = Registry.CurrentUser.OpenSubKey("Software\\Valve\\Steam");

        if (steamKey != null)
        {
          Instance.steamDir = (steamKey.GetValue("SteamPath") as string).Replace('/', '\\');
          Instance.steamExe = (steamKey.GetValue("SteamExe") as string).Replace('/', '\\');
          Console.WriteLine("Steam root directory was found: " + Instance.steamDir);
        }
        else
        {
          Console.WriteLine("ERROR: Steam isn't installed, exiting...");
          return false;
        }

        Instance.phvalheimDir = Environment.ExpandEnvironmentVariables("%appdata%\\PhValheim");
      }
      else if (osPlatform == OSPlatform.Linux)
      {
        try
        {
          // Sandbox.Flatpak.HostShell runs this on the host when we are inside
          // a Flatpak and locally when we are not. It matters here: our sandbox
          // has its own PATH and its own /usr, so "command -v steam" answered
          // from inside it is always "no" no matter what the user has
          // installed.
          var (exitCode, steamPath) = Sandbox.Flatpak.HostShell("command -v steam");

          if (exitCode < 0)
          {
            Console.WriteLine("ERROR: Unable to query for steam executable, exiting...");
            if (Sandbox.Flatpak.InSandbox)
            {
              Console.WriteLine("       Running as a Flatpak but could not reach the host.");
              Console.WriteLine("       This build needs --talk-name=org.freedesktop.Flatpak.");
            }
            return false;
          }

          Instance.steamExe = steamPath;

          //   if the output is empty, steam isn't installed
          if (Instance.steamExe == "")
          {
              Console.WriteLine("ERROR: Steam isn't installed, exiting...");

              // A very likely case on Bazzite and other immutable distros, and
              // one worth naming precisely rather than letting the user hunt.
              // We cannot drive a Flatpak Steam from here: its game files live
              // inside its own sandbox and Valheim would have to be launched
              // within that sandbox to get the Steam Runtime and a reachable
              // Steam client.
              if (Sandbox.Flatpak.HostShell("flatpak info com.valvesoftware.Steam >/dev/null 2>&1").exitCode == 0)
              {
                Console.WriteLine("");
                Console.WriteLine("       Steam is installed as a Flatpak (com.valvesoftware.Steam).");
                Console.WriteLine("       The PhValheim client cannot drive a Flatpak Steam -- it needs a");
                Console.WriteLine("       system Steam it can launch Valheim from. Install Steam from your");
                Console.WriteLine("       distribution instead. On SteamOS and Bazzite it is already there.");
              }
              return false;
          }
          Instance.steamDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.steam/steam";
        } catch (Exception)
        {
          Console.WriteLine("ERROR: Steam isn't installed, exiting...");
          return false;
        }

        Instance.phvalheimDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.config/PhValheim";
      }
      else if (osPlatform == OSPlatform.OSX)
      {
        Instance.steamExe = "/Applications/Steam.app/Contents/MacOS/steam_osx";
        if (!File.Exists(Instance.steamExe))
        {
          Console.WriteLine("ERROR: Steam isn't installed, exiting...");
          return false;
        }
        Instance.steamDir = Path.Combine(
          Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
          "Library", "Application Support", "Steam");
        Instance.phvalheimDir = Path.Combine(
          Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
          "Library", "Application Support", "PhValheim");
      }
      else
      {
        Console.WriteLine("ERROR: Unsupported operating system, exiting...");
        return false;
      }

      Instance.phvalheimHostNoPort = phvalheimHostNoPort;
      Instance.worldName = worldName;
      return true;
    }

    // Steam Path Accessors
    public static string SteamDir => Instance.steamDir;
    public static string SteamExe => Instance.steamExe;
    public static string ValheimDir {
      get {
        return Instance.valheimDir;
      }
      set {
        Instance.valheimDir = value;
      }
    }

    // Convienence Accessors
    public static string PhvalheimHostNoPort => Instance.phvalheimHostNoPort;
    public static string WorldName => Instance.worldName;

    // PhValheim Path Accessors
    public static string PhValheimDir => Instance.phvalheimDir;
    public static string PhValheimServerRoot => Path.Combine(Instance.phvalheimDir, "worlds", Instance.phvalheimHostNoPort, Instance.worldName);
    public static string PhValheimServerWorld => Path.Combine(PhValheimServerRoot, WorldName);
        
  }
}
