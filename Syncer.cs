using System;
using System.Runtime.ExceptionServices;
using System.IO;
using System.Net;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        public static bool Sync(string phvalheimDir, string worldName, string phvalheimHost)
        {


            string remoteWorldVersion;
            string localWorldVersion;
            bool outOfSync = true;
            string worldURL = phvalheimHost + "/" + worldName;
            string worldVersionURL = phvalheimHost + "/" + worldName + "/version.txt";
            string localWorldVersionFile = phvalheimDir + "\\" + "worlds" + "\\" + worldName + "\\" + "version.txt";
            localWorldVersionFile = Environment.ExpandEnvironmentVariables(localWorldVersionFile);


            Console.WriteLine("");
            Console.WriteLine("Syncer Logic Begins");
            Console.WriteLine("");
            Console.WriteLine("  PhValheim Remote World URL: " + worldURL);
            Console.WriteLine("  PhValheim Remote World Version URL: " + worldVersionURL);
            Console.WriteLine("  PhValheim Local World Version File: " + localWorldVersionFile);


            //setup a web client
            var client = new WebClient();

            //get current remote version of world
            using (var stream = client.OpenRead(worldVersionURL))
            using (var reader = new StreamReader(stream))
                remoteWorldVersion = reader.ReadLine();

            //get current local version of world
            try
            {
                localWorldVersion = File.ReadLines(localWorldVersionFile).First();
                outOfSync = false;
            }
            catch
            { 
                outOfSync = true;
            }


            if(outOfSync)
            {
                Console.WriteLine("Local world doesn't exist, downloading...");
            }
            


            Console.WriteLine("foo");


            //Console.Write(remoteWorldVersion);

            //Console.WriteLine("Sync for world '" + worldName + "' was successful.");
            return true;


        }
    }
}