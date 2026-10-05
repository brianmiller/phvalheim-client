using System.Net;
using System.IO.Compression;

namespace PhValheim.Syncer
{
    public class PhValheim
    {
        // What the server says this world's payloads currently hash to.
        //
        // ConfigMd5 is "" when the server publishes none -- a pre-2.55 server, or a world that
        // has not been packaged since the column existed. "" means UNKNOWN and must never be
        // compared as though it were a real value. A client that read an unknown as "matches
        // what I have" would skip a config change forever; a client that reads it as "differs"
        // costs itself one 80 KB download. Only one of those is recoverable.
        //
        // ModsMd5 is the identity of the payload's MOD CONTENT -- everything in it except
        // BepInEx/config. It is NOT the md5 of the zip, and it has to be separate from it:
        // re-zipping the same tree produces different bytes, so a repackage (which rebuilds the
        // payload so a NEW player still gets the current settings inside it) moves WorldMd5
        // every time. Deciding "do I need the 573 MB" on WorldMd5 therefore answers "yes" after
        // every config edit, and the config-only path below could never be reached.
        //
        // WorldMd5 keeps its original job: verifying a payload we just downloaded.
        private sealed class RemoteState
        {
            public string WorldMd5 = "";
            public string ModsMd5 = "";
            public string ConfigMd5 = "";
        }

        // Ask the server for BOTH checksums in ONE request.
        //
        // One request, deliberately. Fetched separately, an operator who repackages between the
        // two calls hands us a full-payload checksum from one generation of the server's tree
        // and a config checksum from the next -- so we either re-sync for nothing or believe we
        // are current when we are not, with no way to detect either from here.
        //
        // Falls back to the pre-2.55 getMD5 contract, which every server speaks. That keeps a
        // new client working against an old server: ConfigMd5 simply stays "" and the
        // config-only path is never taken.
        private static RemoteState FetchRemoteState(string phvalheimURL, string worldName)
        {
            var state = new RemoteState();
            string world = Uri.EscapeDataString(worldName);

            try
            {
                using (var client = new WebClient())
                using (var stream = client.OpenRead(phvalheimURL + "/api.php?mode=getSyncState&world=" + world))
                using (var reader = new StreamReader(stream))
                {
                    string? line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        // Split on the FIRST '=' only -- the same rule the client manifest in
                        // BepInEx/plugins/PhValheimCompanion/phvalheim-world.cfg uses.
                        int eq = line.IndexOf('=');
                        if (eq < 1) { continue; }

                        string key = line.Substring(0, eq).Trim();
                        string val = line.Substring(eq + 1).Trim();

                        if (key == "world") { state.WorldMd5 = val; }
                        else if (key == "mods") { state.ModsMd5 = val; }
                        else if (key == "config") { state.ConfigMd5 = val; }
                    }
                }
            }
            catch
            {
                // An older server has no such mode. Not an error worth reporting -- fall
                // through to the contract it does understand.
            }

            if (state.WorldMd5.Length > 0)
            {
                return state;
            }

            try
            {
                using (var client = new WebClient())
                using (var stream = client.OpenRead(phvalheimURL + "/api.php?mode=getMD5&world=" + world))
                using (var reader = new StreamReader(stream))
                {
                    state.WorldMd5 = (reader.ReadLine() ?? "").Trim();
                }
            }
            catch
            {
                state.WorldMd5 = "";
            }

            return state;
        }

        // The local record of what we last successfully synced.
        //
        // This exists to avoid re-hashing the payload on every single launch. The payload is
        // 573 MB on a real modpack, and hashing it means reading all of it -- seconds of disk
        // on a cold start, every start, to answer a question we already knew the answer to.
        //
        // worldMd5 here is always the md5 of the payload THIS MACHINE HOLDS, never what the
        // server happens to report. After a config-only sync the server's payload has been
        // rebuilt and ours has not, so copying the server's value in would be a false claim
        // about our own file -- and that value is what the integrity check compares against.
        private static void ReadSyncRecord(string path, out string worldMd5, out string modsMd5,
                                           out string configMd5)
        {
            worldMd5 = "";
            modsMd5 = "";
            configMd5 = "";

            try
            {
                foreach (var line in File.ReadAllLines(path))
                {
                    int eq = line.IndexOf('=');
                    if (eq < 1) { continue; }

                    string key = line.Substring(0, eq).Trim();
                    string val = line.Substring(eq + 1).Trim();

                    if (key == "worldMd5") { worldMd5 = val; }
                    else if (key == "modsMd5") { modsMd5 = val; }
                    else if (key == "configMd5") { configMd5 = val; }
                }
            }
            catch
            {
                // Missing or unreadable. All stay "", which the caller treats as "I know
                // nothing" -- it hashes the payload instead. Never as "I am up to date".
                worldMd5 = "";
                modsMd5 = "";
                configMd5 = "";
            }
        }

        private static void WriteSyncRecord(string path, string worldMd5, string modsMd5,
                                            string configMd5)
        {
            try
            {
                File.WriteAllText(path, "worldMd5=" + worldMd5 + "\nmodsMd5=" + modsMd5
                                      + "\nconfigMd5=" + configMd5 + "\n");
            }
            catch (Exception e)
            {
                // Explicitly not fatal. Losing this file costs one hash of the payload on the
                // next launch -- the very cost it exists to avoid -- and nothing on disk is
                // wrong. Failing a successful sync over it would be worse than being slow once.
                Console.WriteLine("  WARNING: Could not write the sync record (" + e.Message + ").");
                Console.WriteLine("  This is not fatal; the next launch re-checks the payload the slow way.");
            }
        }

        public static bool Sync(string phvalheimURL)
        {
            string worldName = Platform.State.WorldName;
            string valheimDir = Platform.State.ValheimDir;
            string localWorldDir = Platform.State.PhValheimServerWorld;

            string localWorldFile = Path.Combine(Platform.State.PhValheimServerRoot, $"{worldName}.zip");
            string localConfigFile = Path.Combine(Platform.State.PhValheimServerRoot, $"{worldName}-config.zip");
            string syncRecordFile = Path.Combine(Platform.State.PhValheimServerRoot, $"{worldName}.sync");

            Uri remoteWorldFile = new Uri(phvalheimURL + "/stateful/valheim/worlds/" + worldName + "/" + worldName + ".zip");
            Uri remoteConfigFile = new Uri(phvalheimURL + "/stateful/valheim/worlds/" + worldName + "/" + worldName + "-config.zip");

            bool readyToExtract = false;

            Console.WriteLine("");
            Console.WriteLine("Checking to see if local and remote world contexts match for '" + worldName + "'...");
            Console.WriteLine("");

            // Is PhValheim up and ready to use? Asked of the API root, whose body we do not
            // care about -- only that it answered at all.
            try
            {
                using (var client = new WebClient())
                using (var stream = client.OpenRead(phvalheimURL + "/api.php"))
                using (var reader = new StreamReader(stream))
                {
                    reader.ReadLine();
                }
            }
            catch
            {
                Console.WriteLine("ERROR: Could not connect to the remote PhValheim server '" + phvalheimURL + "'.");
                return false;
            }

            RemoteState remote = FetchRemoteState(phvalheimURL, worldName);

            // An empty remote payload checksum means the world does not exist there, or is
            // vanilla and has no payload at all.
            if (remote.WorldMd5.Length == 0)
            {
                Console.WriteLine("  ERROR: Remote world '" + worldName + "' does not exist, exiting...");
                return false;
            }

            string localWorldMD5;
            string localModsMD5;
            string localConfigMD5;
            ReadSyncRecord(syncRecordFile, out localWorldMD5, out localModsMD5, out localConfigMD5);

            // Captured BEFORE the hash below overwrites localWorldMD5, so "I had no record" is
            // still answerable afterwards. Without it, an install that is already current never
            // gets a record written and re-hashes 573 MB on every single launch.
            bool hadRecord = (localWorldMD5.Length > 0);

            if (localWorldMD5.Length == 0)
            {
                // No record: a first run, or a client that just upgraded to a version that
                // keeps one. Hash the payload ONCE so an upgrade does not force a 573 MB
                // re-download of a payload we already have and which is already correct.
                //
                // localConfigMD5 stays "" here on purpose. We genuinely do not know which
                // config generation the extracted tree holds, and the honest consequence is an
                // 80 KB config fetch below -- not an assumption that it is current.
                try
                {
                    localWorldMD5 = Tooling.PhValheim.getMD5(localWorldFile);
                    Console.WriteLine("  Local MD5: " + localWorldMD5 + " (no sync record; hashed the payload once)");
                }
                catch
                {
                    localWorldMD5 = "";
                    Console.WriteLine("  Local MD5: local world not found, marked for download.");
                }
            }
            else
            {
                Console.WriteLine("  Local MD5: " + localWorldMD5 + " (from sync record)");
            }

            Console.WriteLine("  Remote MD5: " + remote.WorldMd5);

            // ---- Decide which of the three paths this is -------------------------------
            //
            // The order matters. A differing payload subsumes a differing config, because the
            // full payload CONTAINS the config generation the server reported alongside it --
            // both checksums came from one request describing one state of the server's tree.
            //
            // The question "do I need the 573 MB" is asked of the MOD IDENTITY, not of the
            // zip's md5. A repackage rebuilds the payload so a new player gets current settings
            // inside it, and a rebuilt zip is different bytes even when nothing in it changed --
            // so the zip's md5 moves on every config edit while its mod content does not.
            //
            // Both sides must be known to use it. An empty remote value is a pre-2.55 server;
            // an empty local value is a record written before this field existed, or no record
            // at all. Either way we fall back to the zip comparison, which costs one full
            // download if a repackage happened in the meantime -- the honest answer to "I do
            // not know what my payload contains", and self-correcting, because the record
            // written afterwards carries the mod identity.
            bool canCompareMods = (remote.ModsMd5.Length > 0 && localModsMD5.Length > 0);
            bool needFullSync = canCompareMods ? (localModsMD5 != remote.ModsMd5)
                                               : (localWorldMD5 != remote.WorldMd5);
            bool needConfigSync = false;

            if (canCompareMods)
            {
                Console.WriteLine("  Mods:       " + localModsMD5 + " -> " + remote.ModsMd5);
            }

            // What we will hold when the payload step below is done. Tracked separately from
            // what the server reports, because the two are no longer the same thing: with the
            // mod identity matching we may keep a payload whose bytes -- and whose config
            // generation -- differ from the server's. Recording the server's values for a file
            // we did not download is how a stale config becomes invisible.
            string heldWorldMD5 = localWorldMD5;
            string heldConfigMD5 = localConfigMD5;

            if (needFullSync)
            {
                Console.WriteLine("");
                Console.WriteLine("  Local world version doesn't match remote world verison, synchronizing... \n");

                Downloader.PhValheim.Go(remoteWorldFile, localWorldFile, worldName);

                // Verify what we just downloaded, BEFORE recording it as good.
                //
                // This check is not optional, it is what the sync record costs. The old client
                // re-hashed the payload on every launch, so a truncated or corrupt download was
                // caught on the next run by accident. Writing a record without verifying would
                // turn that accidental self-healing into a permanent lie: we would claim to
                // hold a payload we do not, and never fetch it again.
                string gotWorldMD5;
                try
                {
                    gotWorldMD5 = Tooling.PhValheim.getMD5(localWorldFile);
                }
                catch
                {
                    Console.WriteLine("  ERROR: The world payload did not download.\n");
                    return false;
                }

                if (gotWorldMD5 != remote.WorldMd5)
                {
                    Console.WriteLine("  ERROR: The downloaded world payload is corrupt (expected " +
                                      remote.WorldMd5 + ", got " + gotWorldMD5 + ").");
                    Console.WriteLine("  Discarding it and leaving your current install alone. Try launching again.\n");

                    // Remove both, so the next launch cannot pair a stale record with a bad
                    // payload. The extracted world directory is deliberately untouched: the
                    // player keeps a working, if outdated, install instead of a broken one.
                    try { File.Delete(localWorldFile); } catch { }
                    try { File.Delete(syncRecordFile); } catch { }
                    return false;
                }

                // Verified. Only now is the server's generation a true statement about our
                // disk -- payload bytes and the config inside them both.
                heldWorldMD5 = gotWorldMD5;
                heldConfigMD5 = remote.ConfigMd5;
                readyToExtract = true;
            }
            else
            {
                Console.WriteLine("");
                Console.WriteLine("  Local and remote world verisons match for '" + worldName + "'.\n");

                // Corner case: the payload matches but the extracted directory was deleted.
                // heldConfigMD5 deliberately stays at the LOCAL value here -- re-extracting our
                // own payload reinstates the config generation that payload contains, which is
                // not necessarily the server's current one. The config check after the extract
                // is what closes that gap.
                if (!Directory.Exists(localWorldDir))
                {
                    readyToExtract = true;
                }
            }

            // Check for the directory strucure from PhValheim 1.0.  If we see this old directory be nice and remove it.  We don't use this anymore.
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

            // ---- Full extract ----------------------------------------------------------
            if (readyToExtract)
            {
                Console.WriteLine("  Extracting world files...\n");

                //delete world directory, just in case
                if (Directory.Exists(localWorldDir))
                {
                    Directory.Delete(localWorldDir, true);
                }

                try
                {
                    ZipFile.ExtractToDirectory(localWorldFile, localWorldDir);
                }
                catch
                {
                    Console.WriteLine("  ERROR: Extracting world files failed!\n");

                    // Remove the half-written tree, then record the payload anyway.
                    //
                    // The payload on disk is correct -- it was either verified against the
                    // server's checksum moments ago, or it already matched before we got here.
                    // Only the extraction failed. Recording it, with the directory gone, means
                    // the next launch takes the "payload matches but the directory is missing"
                    // path and re-extracts from the copy we already hold.
                    //
                    // Without this the old behaviour is lost: the previous client re-hashed the
                    // payload on every launch, so it recovered from a failed extract without
                    // downloading anything. Returning here without recording would make the next
                    // launch re-download 573 MB to fix a unzip that failed. And leaving the
                    // partial directory in place would be worse than either -- Directory.Exists
                    // would be true and Valheim would be launched from an incomplete tree.
                    try { Directory.Delete(localWorldDir, true); } catch { }
                    WriteSyncRecord(syncRecordFile, heldWorldMD5, remote.ModsMd5, heldConfigMD5);
                    return false;
                }

                // Recorded as what we HOLD, not what the server has. After a download those are
                // the same thing; after re-extracting our own payload they are not, and the
                // config check below is what then fetches the difference.
                WriteSyncRecord(syncRecordFile, heldWorldMD5, remote.ModsMd5, heldConfigMD5);
            }

            // Does the config we now hold match the server's? Asked AFTER the payload step,
            // because both routes into it can leave us holding an older config generation: a
            // repackage leaves our payload current in mods but stale in config, and
            // re-extracting our own payload reinstates whatever config it was built with.
            //
            // An empty remote value means the server publishes none, so there is nothing to
            // compare. An empty held value means we do not know what we have -- which counts as
            // different, costing one 80 KB download rather than missing a change forever.
            needConfigSync = (remote.ConfigMd5.Length > 0 && heldConfigMD5 != remote.ConfigMd5);

            // ---- Config-only sync ------------------------------------------------------
            //
            // The whole point of this branch. A mod config change is ~80 KB of a 573 MB
            // payload; everything else in there is plugin DLLs and assets a config edit cannot
            // touch. Measured on a real world, the config archive is ~7,200x smaller.
            if (needConfigSync)
            {
                Console.WriteLine("  The mod configuration changed. Fetching just the config archive...\n");

                Downloader.PhValheim.Go(remoteConfigFile, localConfigFile, worldName);

                string gotConfigMD5;
                try
                {
                    gotConfigMD5 = Tooling.PhValheim.getMD5(localConfigFile);
                }
                catch
                {
                    Console.WriteLine("  WARNING: The config archive did not download. Keeping the configuration you have.\n");
                    return true;
                }

                if (gotConfigMD5 != remote.ConfigMd5)
                {
                    Console.WriteLine("  WARNING: The config archive is corrupt. Keeping the configuration you have.\n");
                    try { File.Delete(localConfigFile); } catch { }
                    return true;
                }

                try
                {
                    // Replaced WHOLESALE -- deleted, then extracted -- never merged file by
                    // file. Resetting a setting in the admin editor REMOVES a key, and can
                    // remove a whole file; a merge would leave the stale one behind and the
                    // reset would never reach the player.
                    //
                    // This is no more destructive than the full path above, which deletes the
                    // entire world directory. BepInEx re-adopts the server's values and
                    // re-expands each file at next boot, which is the same mechanism the
                    // server side relies on.
                    string configDir = Path.Combine(localWorldDir, "BepInEx", "config");
                    if (Directory.Exists(configDir))
                    {
                        Directory.Delete(configDir, true);
                    }

                    ZipFile.ExtractToDirectory(localConfigFile, localWorldDir, true);
                }
                catch (Exception e)
                {
                    // The config directory may now be missing, so this one IS fatal -- unlike
                    // a failed download, which leaves the old config intact. Clear the record
                    // so the next launch re-syncs from scratch rather than trusting a tree we
                    // half-rewrote.
                    Console.WriteLine("  ERROR: Applying the config archive failed (" + e.Message + ").\n");
                    try { File.Delete(syncRecordFile); } catch { }
                    return false;
                }

                Console.WriteLine("  Mod configuration updated.\n");
                WriteSyncRecord(syncRecordFile, heldWorldMD5, remote.ModsMd5, remote.ConfigMd5);
            }
            else if (!hadRecord
                     || localModsMD5 != remote.ModsMd5
                     || localConfigMD5 != heldConfigMD5)
            {
                // Nothing to download and nothing to extract, but the record is out of step
                // with what we now know -- the server stopped publishing a config checksum, or
                // this is the first launch of a client that records the mod identity.
                //
                // That second case is the one that matters: it is how an existing install picks
                // up a mod identity WITHOUT a download. Our payload matched the server's byte
                // for byte to get here, so the server's mod identity is a true statement about
                // our copy -- and from here on a config edit costs 80 KB instead of 573 MB.
                WriteSyncRecord(syncRecordFile, heldWorldMD5, remote.ModsMd5, heldConfigMD5);
            }

            // ---- doorstop into the Valheim directory -----------------------------------
            //
            // Unconditional, as before: the guard that used to wrap this was commented out and
            // the variable it tested was never read. Copying four small files is cheap and
            // being certain they match the payload is worth more than skipping them.
            try
            {
                Tooling.PhValheim.CloneDirectory(Path.Combine(localWorldDir, "doorstop_libs"), Path.Combine(valheimDir, "doorstop_libs"));
                File.Copy(Path.Combine(localWorldDir, "doorstop_config.ini"), Path.Combine(valheimDir, "doorstop_config.ini"), true);
                if (System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows))
                {
                    File.Copy(Path.Combine(localWorldDir, "winhttp.dll"), Path.Combine(valheimDir, "winhttp.dll"), true);
                }
            }
            catch
            {
                Console.WriteLine("  ERROR: Installation of doorstop files to Valheim root directory failed!\n");
                return false;
            }

            if (!File.Exists(Path.Combine(valheimDir, "doorstop_config.ini")))
            {
                Console.WriteLine("  ERROR: Installation of doorstop files to Valheim root directory failed!\n");
                return false;
            }

            return true;
        }
    }
}
