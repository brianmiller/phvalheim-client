using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace PhValheim.Platform
{
  public class State
  {
    private static State _instance;

    /// <summary>
    /// The Flatpak application id of Valve's official Steam package. Used on
    /// immutable distros (Bazzite, Silverblue) where there is no system Steam.
    /// </summary>
    public const string SteamFlatpakId = "com.valvesoftware.Steam";

    private string worldName;
    private string steamDir;
    private string steamExe;
    private bool steamIsFlatpak;
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

          string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

          //   if the output is empty, there is no system steam -- but there
          //   may still be a Flatpak one, which is the normal arrangement on
          //   Bazzite, Silverblue and other immutable distros.
          if (Instance.steamExe == "")
          {
              if (Sandbox.Flatpak.HostShell($"flatpak info {SteamFlatpakId} >/dev/null 2>&1").exitCode != 0)
              {
                Console.WriteLine("ERROR: Steam isn't installed, exiting...");
                return false;
              }

              // A Flatpak Steam keeps its whole Steam root under its per-app
              // data directory. That is an ordinary path on the host -- not,
              // as this code used to claim, something sealed inside the
              // sandbox -- so libraryfolders.vdf and the game files are
              // readable with no special handling beyond pointing at them.
              //
              // Launching is the part that genuinely differs, and is handled
              // in Launcher: the game has to run INSIDE Steam's sandbox to
              // get the Steam Runtime and reach the Steam client's IPC pipe.
              Instance.steamIsFlatpak = true;
              Instance.steamExe = "flatpak";
              Instance.steamDir = $"{home}/.var/app/{SteamFlatpakId}/.local/share/Steam";

              Console.WriteLine("Steam is installed as a Flatpak (" + SteamFlatpakId + ").");
              Console.WriteLine("Steam root directory was found: " + Instance.steamDir);

              if (!Directory.Exists(Instance.steamDir))
              {
                Console.WriteLine("");
                Console.WriteLine("WARNING: that directory is not readable from here.");
                if (Sandbox.Flatpak.InSandbox)
                {
                  Console.WriteLine("         Grant this client access to it with:");
                  Console.WriteLine("           flatpak override --user \\");
                  Console.WriteLine("             --filesystem=~/.var/app/" + SteamFlatpakId + " \\");
                  Console.WriteLine("             com.phvalheim.Client");
                }
                else
                {
                  Console.WriteLine("         Has Steam been run at least once?");
                }
                return false;
              }
          }
          else
          {
              Instance.steamDir = $"{home}/.steam/steam";
          }
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

    /// <summary>
    /// True when the Steam we are driving is com.valvesoftware.Steam rather
    /// than a distribution package. Changes how Steam is invoked, not where
    /// its files are: SteamExe is "flatpak" and every Steam argument has to be
    /// prefixed with "run com.valvesoftware.Steam".
    /// </summary>
    public static bool SteamIsFlatpak => Instance.steamIsFlatpak;

    /// <summary>
    /// Wrap a Steam argument list so it reaches Steam however Steam is
    /// installed. For a system Steam this is the identity function.
    /// </summary>
    public static string[] SteamArgs(params string[] args)
    {
      if (!Instance.steamIsFlatpak) return args;
      return new[] { "run", SteamFlatpakId }.Concat(args).ToArray();
    }
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
