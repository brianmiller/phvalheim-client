using System.Net;
using System.IO.Compression;
using Microsoft.VisualBasic.FileIO;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        public static bool Sync(string phvalheimDir, string worldName, string phvalheimURL)
        {

            phvalheimDir = Environment.ExpandEnvironmentVariables(phvalheimDir);

            var localWorldMD5 = "";
            var remoteWorldMD5 = "";
            bool inSync = false;
            bool readyToExtract = false;
            bool remoteMissing;
            bool localMissing;
            string remoteWorldURL = phvalheimURL + "/" + worldName;
            string localWorldVersionFile = phvalheimDir + "\\" + "worlds" + "\\" + worldName + "\\" + "version.txt";
            string localWorldFile = phvalheimDir + "\\" + "worlds" + "\\" + worldName + "\\" + worldName + ".zip";
            string localWorldDir = phvalheimDir + "\\worlds" + "\\" + worldName + "\\" + worldName;
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
            bool oldDirExists = Directory.Exists(phvalheimDir + "\\" + worldName);
            try
            {
                if (oldDirExists)
                {
                    Directory.Delete(phvalheimDir + "\\" + worldName, true);
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
                    Directory.Delete(phvalheimDir + "\\worlds" + "\\" + worldName + "\\" + worldName, true);  
                }
                
                //extract new world files to local directory
                ZipFile.ExtractToDirectory(localWorldFile, localWorldDir);
            }


            return true;
        }
    }
}