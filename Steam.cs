using Microsoft.Win32;


namespace PhValheim.Steam
{
    public class PhValheim
    {
        //get our local Valheim installation directory and execuatable
        public static bool ValheimGetter()
        {
            string libraryFolders = Path.Combine(Platform.State.SteamDir, "steamapps", "libraryfolders.vdf");

            // ReadAllLines throws if the file is absent, so without this check a machine
            // with no Steam install (or Steam in a non-default location) gets an unhandled
            // DirectoryNotFoundException stack trace instead of the message below.
            if (!File.Exists(libraryFolders))
            {
                Console.WriteLine("Steam library list not found at: " + libraryFolders);
                Console.WriteLine("Is Steam installed? If it lives somewhere unusual, PhValheim could not find it.");
                return false;
            }

            string[] lines;
            try
            {
                lines = File.ReadAllLines(libraryFolders);
            }
            catch (Exception e)
            {
                Console.WriteLine("Could not read Steam's library list at: " + libraryFolders);
                Console.WriteLine("  " + e.Message);
                return false;
            }

            foreach (var line in lines)
            {
                if (line.Contains("path"))
                {
                    string[] library = line.Split('"');
                    foreach (var libraryPath in library)
                    {
                        // A .vdf line splits into fragments that are not all paths ("path",
                        // whitespace, etc). Path.Combine throws on invalid characters, so
                        // skip anything that cannot be a directory rather than blowing up.
                        if (string.IsNullOrWhiteSpace(libraryPath) || libraryPath.IndexOfAny(Path.GetInvalidPathChars()) >= 0)
                        {
                            continue;
                        }

                        bool valheimExists = File.Exists(Path.Combine(libraryPath ,"steamapps","appmanifest_892970.acf"));
                        if (valheimExists)
                        {
                            Platform.State.ValheimDir = Path.Combine(libraryPath ,"steamapps","common","Valheim");
                            Console.WriteLine("Valheim root directory was found: " + Platform.State.ValheimDir);
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


