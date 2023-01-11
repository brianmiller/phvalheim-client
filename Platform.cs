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
      osPlatform = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? OSPlatform.Windows : OSPlatform.Linux;
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
          var psi = new ProcessStartInfo();
          psi.FileName = "/bin/bash";
          psi.Arguments = "-c \"which steam\"";
          psi.RedirectStandardOutput = true;
          psi.UseShellExecute = false;
          psi.CreateNoWindow = true;

          using var process = Process.Start(psi);

          if (process == null)
          {
            Console.WriteLine("ERROR: Unable to query for steam executable, exiting...");
            return false;
          }
          process.WaitForExit();

          Instance.steamExe = process.StandardOutput.ReadToEnd();
          Instance.steamDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.steam/steam";
        } catch (Exception)
        {
          Console.WriteLine("ERROR: Steam isn't installed, exiting...");
          return false;
        }

        Instance.phvalheimDir = $"{Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}/.config/PhValheim";
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
