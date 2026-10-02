using System.Text;
using System.Reflection;

namespace PhValheim.Arguments
{
    public class PhValheim
    {
        /// <summary>
        /// The argument the Companion mod reads the launch payload back out of, and the raw
        /// base64 to pass with it.
        ///
        /// The Companion needs the same world details this client was given: the address, and
        /// for a crossplay world the join code, which is reissued every time the world
        /// restarts. Handing over the ORIGINAL base64 rather than re-encoding the parsed
        /// fields is deliberate -- re-encoding would be a second place to get the positional
        /// order wrong, and the two would drift the first time a field was added.
        ///
        /// This lives here rather than on Platform.State because State is constructed after
        /// argument parsing. A static on the parser has no initialisation order to get wrong.
        /// </summary>
        public const string CompanionArgName = "--phvalheim-launch";

        // Nullable: there is no payload at all for a "textures" run, or before parsing. Absent
        // is a real state here, not a missing value to be defaulted away.
        public static string? RawLaunchPayload { get; private set; }

        public static bool HaveLaunchPayload => !string.IsNullOrEmpty(RawLaunchPayload);

        //get our local Steam installation directory and execuatable
        public static void Usage()
        {
            var phvalheimLauncherVersion = Assembly.GetEntryAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute> ().InformationalVersion;
            phvalheimLauncherVersion = phvalheimLauncherVersion?.Split('+')[0]; // take only before '+'

            Console.WriteLine(
                    "\n" +
                    "PhValheim Client Version " + phvalheimLauncherVersion +
                    "\n\n" +
                    "Usage: phvalheim-client.exe [OPTION...] [OPTION]...\n" +
                    "'phvalheim-client' syncs and launches Valheim client contexts with remote server contexts.\n" +
                    "\n" +
                    "Examples:\n" +
                    "\n" +
                    "  phvalheim-client.exe 'mode' 'worldname' 'hostname' 'password' 'port'\n" +
                    "  phvalheim-client.exe 'textures' 'worldname' 'texture_pack'\n" +
                    "  phvalheim-client.exe 'launch' 'Valhalla' 'valheim.mydomain.com' 'myValhallaPassword' 'port'\n" +
                    "  phvalheim-client.exe 'textures' 'Valhalla' 'coco'\n" +
                    "  phvalheim-client.exe 'textures' 'Valhalla' 'willybach'\n" +
                    "\n" +
                    "");
        }

        public static bool argHandler(ref string[] args, ref string[] argumentsPassed, ref string command, ref string worldName, ref string worldPassword, ref string worldHost, ref string worldPort, ref string texturePack, ref string phvalheimHost, ref string httpScheme, ref bool isVanilla)
        {

            //all arguments missing, print usage and exit
            if (args.Length == 0)
            {
                Arguments.PhValheim.Usage();
                Console.Write("ERROR: No arguments passed.");
                return false;
            }
            else
            {

                if (args[0] == "phvalheim:///?")
                {
                    Console.WriteLine("Launch URL provided: " + args[0]);
                    Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                    return false;
                }

                argumentsPassed = args[0].Split('?');

                string decodedLaunchString;

                // Kept before argumentsPassed is reassigned below, which is the only point the
                // original encoded payload still exists.
                string rawLaunchPayload = argumentsPassed.Length > 1 ? argumentsPassed[1] : null;

                try
                {
                    byte[] data = Convert.FromBase64String(argumentsPassed[1]);
                    decodedLaunchString = Encoding.UTF8.GetString(data);
                }
                catch
                {
                    Console.WriteLine("Launch URL provided: " + args[0]);
                    Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                    return false;
                }
                
                argumentsPassed = decodedLaunchString.Split('?');

                    if (argumentsPassed.Length < 2)
                    {
                        Console.WriteLine("Launch URL provided: " + decodedLaunchString);
                        Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                        return false;
                    }
                    else
                    {
                        command = argumentsPassed[0];
                    }
                    if (command == "launch")
                    {
                        if (argumentsPassed.Length < 7)
                        {
                            Console.WriteLine("Launch URL provided: " + decodedLaunchString);
                            Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                            return false;
                        }                     
                        else
                        {
                            worldName = argumentsPassed[1];
                            worldPassword = argumentsPassed[2];
                            worldHost = argumentsPassed[3];
                            worldPort = argumentsPassed[4];
                            phvalheimHost = argumentsPassed[5];
                            httpScheme = argumentsPassed[6];

                            // Field 7 (vanilla) was added in server 2.40. It is optional
                            // on purpose: a 2.40 client must still work against an older
                            // server, which sends only 7 fields. Absent means modded,
                            // which is what every pre-2.40 world is.
                            if (argumentsPassed.Length >= 8)
                            {
                                isVanilla = argumentsPassed[7] == "1";
                            }
                            else
                            {
                                isVanilla = false;
                            }

                            // Only set for a launch. A "textures" run starts no game, so there
                            // is nothing to hand a payload to.
                            RawLaunchPayload = rawLaunchPayload;

                            return true;
                        }                     
                    }
                    if (command == "textures")
                    {
                        if (argumentsPassed.Length < 3)
                        {
                            Console.WriteLine("Launch URL provided: " + decodedLaunchString);
                            Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                            return false;
                        }
                        else
                        {
                            worldName = argumentsPassed[1];
                            texturePack = argumentsPassed[2];
                        }
                    }
            return true;
            }
        }
    }
}


