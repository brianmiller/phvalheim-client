using System.Text;
using System.Diagnostics;

namespace PhValheim.Arguments
{
    public class PhValheim
    {
        //get our local Steam installation directory and execuatable
        public static void Usage()
        {

            System.Reflection.Assembly assembly = System.Reflection.Assembly.GetExecutingAssembly();
            var phvalheimLauncherVersion = FileVersionInfo.GetVersionInfo(assembly.Location).ProductVersion;

            Console.WriteLine(
                    "\n" +
                    "PhValheim Version " + phvalheimLauncherVersion +
                    "\n\n" +
                    "Usage: phvalheim_launcher.exe [OPTION...] [OPTION]...\n" +
                    "'phvalheim_launcher' syncs and launches Valheim client contexts with remote server contexts.\n" +
                    "\n" +
                    "Examples:\n" +
                    "\n" +
                    "  phvalheim_launcher.exe 'mode' 'worldname' 'hostname' 'password' 'port'\n" +
                    "  phvalheim_launcher.exe 'textures' 'worldname' 'texture_pack'\n" +
                    "  phvalheim_launcher.exe 'launch' 'Valhalla' 'valheim.mydomain.com' 'myValhallaPassword' 'port'\n" +
                    "  phvalheim_launcher.exe 'textures' 'Valhalla' 'coco'\n" +
                    "  phvalheim_launcher.exe 'textures' 'Valhalla' 'willybach'\n" +
                    "\n" +
                    "");
        }

        public static bool argHandler(ref string[] args, ref string[] argumentsPassed, ref string command, ref string worldName, ref string worldPassword, ref string worldHost, ref string worldPort, ref string texturePack, ref string phvalheimHost)
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
                        if (argumentsPassed.Length < 6)
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


