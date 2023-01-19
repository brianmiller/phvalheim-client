using System.Net;
using System.IO.Compression;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        public static bool Sync(string phvalheimURL)
        {
            string phvalheimDir = Platform.State.PhValheimDir;
            string worldName = Platform.State.WorldName;
            string valheimDir = Platform.State.ValheimDir;

            var localWorldMD5 = "";
            var remoteWorldMD5 = "";
            bool inSync = false;
            bool readyToExtract = false;
            bool remoteMissing;
            bool localMissing;
            string remoteWorldURL = phvalheimURL + "/" + worldName;
            string localWorldVersionFile = Path.Combine(Platform.State.PhValheimDir, "worlds","version.txt");
            string localWorldFile = Path.Combine(Platform.State.PhValheimServerRoot, $"{Platform.State.WorldName}.zip");
            string localWorldDir = Platform.State.PhValheimServerWorld;
            Uri remoteWorldFile = new Uri(phvalheimURL + "/stateful/valheim/worlds/" + worldName + "/" + worldName + ".zip");


            Console.WriteLine("");
            Console.WriteLine("Checking to see if local and remote world contexts match for '" + worldName + "'...");
            Console.WriteLine("");


            //setup a web client
            var client = new WebClient();


            //is PhValheim up and ready to use?
            try
            {
                using (var stream = client.OpenRead(phvalheimURL + "/api.php"))
                using (var reader = new StreamReader(stream))
                remoteWorldMD5 = reader.ReadLine();
            }
            catch
            {
                Console.WriteLine("ERROR: Could not connect to the remote PhValheim server '" + phvalheimURL + "'.");
                return false;
            }


            //get current md5 of local world payload file
            try
            {
                localWorldMD5 = Tooling.PhValheim.getMD5(localWorldFile);
                localMissing = false; //likely not needed
            }
            catch
            {
                localMissing = true; //likely not needed
            }


            //get current md5 of remote world
            try
            {
                using (var stream = client.OpenRead(phvalheimURL + "/api.php?mode=getMD5&world=" + worldName))
                using (var reader = new StreamReader(stream))
                remoteWorldMD5 = reader.ReadLine();
            }
            catch
            {
                Console.WriteLine("  ERROR: Remote world '" + worldName + "' does not exist, exiting...");
                return false;
            }


            //if remoteWorldMD5 is empty, the remote world doesn't exist
            if (remoteWorldMD5 == null || remoteWorldMD5.Count() == 0)
            {

                Console.WriteLine("  ERROR: Remote world '" + worldName + "' does not exist, exiting...");
                return false;
            }


            //if localWorldMD5 is empty, we'll need to download it
            if (localWorldMD5 == null || localWorldMD5.Count() == 0)
            {
                Console.WriteLine("  Local MD5: local world not found, marked for download.");
            }
            else
            {
                Console.WriteLine("  Local MD5: " + localWorldMD5);
            }
        

            Console.WriteLine("  Remote MD5: " + remoteWorldMD5);


            //if localWorldMD5 does not match remoteWorldMD5, re-download
            if (localWorldMD5 != remoteWorldMD5)
            {
                Console.WriteLine("");
                Console.WriteLine("  Local world version doesn't match remote world verison, synchronizing... \n");

                Downloader.PhValheim.Go(remoteWorldFile, localWorldFile, worldName);
                Console.WriteLine("  DEBUG: localWorldFile: " + localWorldFile);
                
                readyToExtract = true;
            } 
            else
            {
                Console.WriteLine("");
                Console.WriteLine("  Local and remote world verisons match for '" + worldName + "'.\n");
                inSync = true;

                //corner case: if the local world zip matches remote, but the local world directory was deleted for some reason, extract it
                bool directoryExists = Directory.Exists(localWorldDir);
                if (!directoryExists)
                {
                    readyToExtract = true;
                }

            }


            //check for the directory strucure from PhValheim 1.0.  If we see this old directory be nice and remove it.  We don't use this anymore.
            bool oldDirExists = Directory.Exists(Path.Combine(Platform.State.PhValheimDir, Platform.State.WorldName));
            try
            {
                if (oldDirExists)
                {
                    Directory.Delete(Path.Combine(Platform.State.PhValheimDir, Platform.State.WorldName), true);
                }
            }
            catch
            {
                Console.WriteLine("  WARNING: An old directory structure from PhValheim 1.0 was detected and could not be deleted. This isn't fatal, but you shouldn't see this message.");
            }


            //extract world files
            if (readyToExtract)
            {

                Console.WriteLine("  Extracting world files...\n");

                //delete world directory, just in case
                bool directoryExists = Directory.Exists(localWorldDir);
                if (directoryExists)
                { 
                    Directory.Delete(localWorldDir, true);  
                }

                //extract new world files to local directory
                try
                {
                    ZipFile.ExtractToDirectory(localWorldFile, localWorldDir);
                } 
                catch
                {
                    Console.WriteLine("  ERROR: Extracting world files failed!\n");
                    return false;
                }

            }


            // are doorstop_libs installed?
            bool doorstopExists = File.Exists(Path.Combine(Platform.State.ValheimDir, "doorstop_config.ini"));
            if (!doorstopExists)
            {
                Console.WriteLine("  Root level doorstop_libs missing, installing...\n");
                try
                { 
                    Tooling.PhValheim.CloneDirectory(Path.Combine(localWorldDir ,"doorstop_libs"), Path.Combine(valheimDir ,"doorstop_libs"));
                    Tooling.PhValheim.CloneDirectory(Path.Combine(localWorldDir ,"unstripped_corlib"), Path.Combine(valheimDir ,"unstripped_corlib"));
                    File.Copy(Path.Combine(localWorldDir ,"doorstop_config.ini"), Path.Combine(valheimDir ,"doorstop_config.ini"), true);
                    File.Copy(Path.Combine(localWorldDir ,"winhttp.dll"), Path.Combine(valheimDir ,"winhttp.dll"), true);
                }
                catch
                {
                    Console.WriteLine("  ERROR: Installation of doorstop files to Valheim root directory failed!\n");
                    return false;
                }

            }
            else
            {
                Console.WriteLine("  Root level doorstop_libs detected, continuing...\n");
            }


            // are doorstop_libs installed, double check?
            doorstopExists = File.Exists(Path.Combine(valheimDir, "doorstop_config.ini"));
            if (!doorstopExists)
            {
                Console.WriteLine("  ERROR: Installation of doorstop files to Valheim root directory failed!\n");
                return false;
            }
        return true;
        }
    }
}