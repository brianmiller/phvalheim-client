using Microsoft.Win32;


namespace PhValheim.Steam
{
    public class PhValheim
    {
        //get our local Valheim installation directory and execuatable
        public static bool ValheimGetter()
        {
            foreach (var line in File.ReadAllLines(Path.Combine(Platform.State.SteamDir , "steamapps","libraryfolders.vdf")))
            {
                if (line.Contains("path")) 
                {      
                    string[] library = line.Split('"');
                    foreach (var libraryPath in library) 
                    {
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


