using System;
using System.Runtime.ExceptionServices;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        public static bool Sync(string phvalheimDir, string worldName)
        {

            Console.WriteLine("");
            Console.WriteLine("Syncer Logic Begins");
            Console.WriteLine("");

            //Console.WriteLine("First Argument: " + firstArg);
            //Console.WriteLine("Second Argument: " + secondArg);
            
            
            
            
            
            
            if (phvalheimDir == null)
            {
                return false;
            }
            else
            {
                Console.WriteLine("Sync for world '" + worldName + "' was successful.");
                return true;
            }

        }

        

    }
}