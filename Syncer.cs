using System;
using System.Runtime.ExceptionServices;
using System.IO;
using System.Net;
using System.Windows;
using System.Text.RegularExpressions;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        public static bool Sync(string phvalheimDir, string worldName, string phvalheimHost)
        {

            phvalheimDir = Environment.ExpandEnvironmentVariables(phvalheimDir);

            string remoteWorldVersion = "";
            string localWorldVersion = "";
            bool remoteMissing;
            bool localMissing;
            string remoteWorldURL = phvalheimHost + "/" + worldName;
            Uri remoteWorldVersionFile = new Uri(phvalheimHost + "/" + worldName + "/version.txt");
            Uri remoteWorldFile = new Uri(phvalheimHost + "/" + worldName + "/" + worldName + ".zip");
            //string remoteWorldVersionFile = phvalheimHost + "/" + worldName + "/version.txt";
            //string remoteWorldFile = phvalheimHost + "/" + worldName + "/" + worldName + ".zip";
            string localWorldVersionFile = phvalheimDir + "\\" + "worlds" + "\\" + worldName + "\\" + "version.txt";
            string localWorldFile = phvalheimDir + "\\" + "worlds" + "\\" + worldName + "\\" + worldName + ".zip";
            

            Console.WriteLine("");
            Console.WriteLine("Syncer Logic Begins");
            Console.WriteLine("");
            Console.WriteLine("  PhValheim Remote World URL: " + remoteWorldURL);
            Console.WriteLine("  PhValheim Remote World Version URL: " + remoteWorldVersionFile);
            Console.WriteLine("  PhValheim Local World Version File: " + localWorldVersionFile);


            //setup a web client
            var client = new WebClient();

            //get current local version of world
            try
            {
                localWorldVersion = File.ReadLines(localWorldVersionFile).First();
                localMissing = false;
            }
            catch
            { 
                localMissing = true;
            }

            //get current remote version of world
            try
            {
                //get current remote version of world
                using (var stream = client.OpenRead(remoteWorldVersionFile))
                using (var reader = new StreamReader(stream))
                remoteWorldVersion = reader.ReadLine();
                remoteMissing = false;
            }
            catch
            {
                remoteMissing = true;
            }


            if (remoteMissing)
            {
                Console.WriteLine("Remote world doesn't exist, exiting...");
                return false;
            }

            if (localWorldVersion != remoteWorldVersion)
            {
                Console.WriteLine("");
                Console.WriteLine("  Local world version doesn't match remote world verison, synchronizing... ");

                Downloader.PhValheim.Go(remoteWorldFile, localWorldFile, worldName);
                Downloader.PhValheim.Go(remoteWorldVersionFile, localWorldVersionFile, worldName);

            } 
            else
            {
                Console.WriteLine("");
                Console.WriteLine("  Local and remote world verisons match for '" + worldName + "'.");
            }

            return true;


        }
    }
}