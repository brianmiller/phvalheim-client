namespace PhValheim.Prep
{
    public class PhValheim
    {
     
        public static bool MakeDir(string inputDir, string desc)
        {
            inputDir = Environment.ExpandEnvironmentVariables(inputDir);
            bool inputDirExists = System.IO.Directory.Exists(inputDir);
            if (!inputDirExists)
            {
                Console.WriteLine(desc + " directory is missing, creating: " + inputDir);

                try
                {
                    Directory.CreateDirectory(inputDir);
                    return true;
                }
                catch
                {
                    Console.WriteLine(desc + " directory could not be created, exiting...");
                    return false;
                }

            }
            else
            {
                Console.WriteLine(desc + " directory was found: " + inputDir);
                return true;
            }
        }
        
        
        
        //ensure PhValheim's root dir exists, else create it.
        public static bool PhValheimPrep(string phvalheimDir,string worldName,string phvalheimHostNoPort)
        {

            string worldDir = phvalheimDir + "\\worlds\\" + phvalheimHostNoPort + "\\" + worldName;
            
            if (!MakeDir(phvalheimDir, "PhValheim root"))
            {
                return false;
            }

            if (!MakeDir(worldDir, "World root"))
            {
                return false;
            }

            return true;
        }
    }
}


