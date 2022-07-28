namespace PhValheim.Arguments
{
    public class PhValheim
    {
        //get our local Steam installation directory and execuatable
        public static void Usage()
        {
            Console.WriteLine(
                    "\n" +
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
                    Console.WriteLine("0Launch URL provided: " + args[0]);
                    Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                    return false;
                }

                argumentsPassed = args[0].Split('?');
                if (argumentsPassed[0] == "phvalheim:///")
                {
                    if (argumentsPassed.Length < 2)
                    {
                        Console.WriteLine("1Launch URL provided: " + args[0]);
                        Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                        return false;
                    }
                    else
                    {
                        command = argumentsPassed[1];
                    }
                    if (command == "launch")
                    {
                        if (argumentsPassed.Length < 7)
                        {
                            Console.WriteLine("2Launch URL provided: " + args[0]);
                            Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                            return false;
                        }                     
                        else
                        {
                            worldName = argumentsPassed[2];
                            worldPassword = argumentsPassed[3];
                            worldHost = argumentsPassed[4];
                            worldPort = argumentsPassed[5];
                            phvalheimHost = argumentsPassed[6];
                            return true;
                        }                     
                    }
                    if (command == "textures")
                    {
                        if (argumentsPassed.Length < 4)
                        {
                            Console.WriteLine("3Launch URL provided: " + args[0]);
                            Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                            return false;
                        }
                        else
                        {
                            worldName = argumentsPassed[2];
                            texturePack = argumentsPassed[3];
                        }
                    }
                }
                else
                {
                    Console.WriteLine("4Launch URL provided: " + args[0]);
                    Console.WriteLine("ERROR: malformed phvalheim URL, exiting...");
                    return false;
                }
            return true;
            }
        }
    }
}


