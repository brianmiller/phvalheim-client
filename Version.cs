using Octokit;

namespace PhValheim.Ver
{
    public class PhValheim
    {

        // SYNCHRONOUS, BOUNDED and exception-safe, and all three were bugs.
        //
        // This was `async void` called without await, so the continuation ran on a thread pool
        // thread whenever GitHub happened to answer -- which meant its line could print in the
        // MIDDLE of the download progress or the launch summary. Ordering that depends on a
        // network round-trip is not ordering, and it is a good part of why this window looked
        // chaotic.
        //
        // Worse, there was no try/catch anywhere on the path. An exception from an `async void`
        // in a console app has no synchronization context to be posted back to, so it reaches
        // the thread pool unobserved and TAKES THE PROCESS WITH IT. Octokit is unauthenticated
        // here, which is 60 requests per hour per IP -- so a player behind a shared address, or
        // simply offline, could have the launcher die on them during an update check it did not
        // need to be doing. Now it is a step that can say "could not check" and move on.
        //
        // The timeout is what lets it be synchronous safely: the check is worth ~5 seconds of a
        // launch and not a second more.
        public static void VersionCheck(string phvalheimLauncherVersion)
        {
            Ui.Step("Client version");

            IReadOnlyList<Release> releases;
            try
            {
                //Source: https://octokitnet.readthedocs.io/en/latest/getting-started/
                GitHubClient client = new GitHubClient(new ProductHeaderValue("phvalheim-client"));
                var task = client.Repository.Release.GetAll("brianmiller", "phvalheim-client");
                if (!task.Wait(TimeSpan.FromSeconds(5)))
                {
                    Ui.Done(phvalheimLauncherVersion + "  (could not reach GitHub to check)");
                    return;
                }
                releases = task.Result;
            }
            catch (Exception e)
            {
                // Offline, rate-limited, DNS, TLS -- all the same answer to the player, and none
                // of them a reason to stop a launch that needs no network but their own server.
                Ui.Done(phvalheimLauncherVersion + "  (could not check for updates)");
                Ui.Detail("version check failed", e.GetBaseException().Message);
                return;
            }

            // This used to be releases[0], which was wrong twice over.
            //
            // GetAll() returns EVERY release, pre-releases and drafts included,
            // ordered by creation date rather than by version. So publishing a
            // pre-release told every stable user to upgrade to a build that was
            // explicitly not ready for them (phvalheim-client#14), and a patch
            // cut against an older branch could out-rank a newer one purely by
            // being published later.
            //
            // Take the highest STABLE version instead. Note that the
            // /releases/latest endpoint would also skip pre-releases, but it
            // returns the most RECENT stable rather than the highest, so it
            // only fixes half of this.
            Version? latestGitHubVersion = releases
                .Where(r => !r.Prerelease && !r.Draft)
                .Select(r => Version.TryParse(r.TagName, out Version? v) ? v : null)
                .Where(v => v != null)
                .Max();

            // No parseable stable release means we have nothing to compare
            // against. Saying nothing is correct; guessing is not.
            if (latestGitHubVersion == null)
            {
                // Still completes the step. The old code printed nothing at all here, which on
                // a page of labelled checks reads as a check that did not happen -- and the
                // player cannot tell that from one that passed.
                Ui.Done(phvalheimLauncherVersion + "  (no stable release to compare against)");
                return;
            }

            Version localVersion = new Version(phvalheimLauncherVersion); //Replace this with your local version.
                                                                          //Only tested with numeric values.

            //Compare the Versions
            int versionComparison = localVersion.CompareTo(latestGitHubVersion);
            if (versionComparison < 0)
            {
                //The version on GitHub is more up to date than this local release.
                Ui.Done(phvalheimLauncherVersion + "  ->  " + latestGitHubVersion + " available");
                Ui.Warning("A newer PhValheim Client (" + latestGitHubVersion + ") is available.",
                           "Your launch will carry on with " + phvalheimLauncherVersion + ".",
                           "Updating is strongly recommended -- get it from your server's web page.");
            }
            else if (versionComparison > 0)
            {
                // Ahead of the newest stable. Normally that means a pre-release,
                // which is a deliberate choice rather than a mistake -- now that
                // we compare against stables only, this branch is what every
                // pre-release tester sees on every launch, so it should not read
                // like a warning.
                Ui.Done(phvalheimLauncherVersion + "  (pre-release, ahead of stable "
                        + latestGitHubVersion + ")");
            }
            else
            {
                //This local Version and the Version on GitHub are equal.
                Ui.Done(phvalheimLauncherVersion + "  (up to date)");
            }


        }
    }
}


