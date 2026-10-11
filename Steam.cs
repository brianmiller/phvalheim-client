using Microsoft.Win32;


namespace PhValheim.Steam
{
    public class PhValheim
    {
        //get our local Valheim installation directory and execuatable
        public static bool ValheimGetter()
        {
            Ui.Step("Valheim install");

            string libraryFolders = Path.Combine(Platform.State.SteamDir, "steamapps", "libraryfolders.vdf");

            // ReadAllLines throws if the file is absent, so without this check a machine
            // with no Steam install (or Steam in a non-default location) gets an unhandled
            // DirectoryNotFoundException stack trace instead of the message below.
            if (!File.Exists(libraryFolders))
            {
                Ui.Fail("not found");
                Ui.Error("PhValheim could not find Steam's library list, so it cannot tell where Valheim is installed.",
                         "Is Steam installed, and has it been run at least once?",
                         "If Steam lives somewhere unusual, PhValheim cannot find it there.");
                Ui.Detail("libraryfolders.vdf", libraryFolders);
                return false;
            }

            string[] lines;
            try
            {
                lines = File.ReadAllLines(libraryFolders);
            }
            catch (Exception e)
            {
                Ui.Fail("unreadable");
                Ui.Error("PhValheim found Steam's library list but could not read it.", e.Message);
                Ui.Detail("libraryfolders.vdf", libraryFolders);
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
                            // The absolute path is developer detail. A player needs to know
                            // it was FOUND; the old line made them read a path to learn that.
                            Ui.Done("found");
                            Ui.Detail("Valheim", Platform.State.ValheimDir);
                            return true;
                        }
                    }
                }
            }
            Ui.Fail("not found");
            Ui.Error("Valheim is not installed in any of your Steam libraries.",
                     "Install Valheim in Steam, run it once, then launch from PhValheim again.");
            return false;
        }
    }
}


