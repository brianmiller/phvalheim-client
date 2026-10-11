#!/bin/sh
# Render the client's terminal output without needing Steam, Valheim or a server.
#
# WHAT THIS IS, precisely: a LAYOUT preview. It compiles the real Ui.cs and replays the call
# sequences the program makes, so the shape of the window can be read and reviewed. It is NOT
# proof that the program calls them in this order -- only the program can show that, and the
# error paths are exercised for real by running the client with no arguments.
#
# It exists because the output is the feature here. Judging "is this easy to read" from source
# diffs does not work; you have to look at it.
#
# Usage:  sh dev_tools/preview-console.sh            (player's view)
#         PHVALHEIM_VERBOSE=1 sh dev_tools/preview-console.sh   (with developer detail)

REPO=$(cd "$(dirname "$0")/.." && pwd)
SDK=mcr.microsoft.com/dotnet/sdk:9.0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/preview"
cp "$REPO/Ui.cs" "$WORK/preview/Ui.cs"

cat > "$WORK/preview/preview.csproj" <<'PROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>PhValheim</RootNamespace>
    <AssemblyName>preview</AssemblyName>
  </PropertyGroup>
</Project>
PROJ

cat > "$WORK/preview/Program.cs" <<'PROG'
using PhValheim;

class Preview
{
    static void Scene(string name)
    {
        Console.WriteLine();
        Console.WriteLine("================ " + name + " ================");
    }

    static void Main()
    {
        // ---- the ordinary case: nothing to do but launch ------------------------------
        Scene("already up to date");
        Ui.Banner("2.0.15");
        Ui.Field("Server", "https://valheim.example.com");
        Ui.Field("World", "VikingOutlaws  (modded)");
        Ui.Blank();
        Ui.Step("Client version");       Ui.Done("2.0.15  (up to date)");
        Ui.Step("PhValheim folders");    Ui.Done("ready");
        Ui.Step("Valheim install");      Ui.Done("found");
        Ui.Step("PhValheim server");     Ui.Done("up to date");
        Ui.Step("Mod loader");           Ui.Done("ready");
        Ui.Section("Starting Valheim");
        Ui.Field("World", "VikingOutlaws");
        Ui.Field("Address", "play.example.com:25000  (udp)");
        Ui.Blank();
        Ui.Line("This window closes on its own in 10 seconds.");

        // ---- a real update, with the download ----------------------------------------
        Scene("mod list changed - full download");
        Ui.Banner("2.0.15");
        Ui.Field("Server", "https://valheim.example.com");
        Ui.Field("World", "VikingOutlaws  (modded)");
        Ui.Blank();
        Ui.Step("Client version");       Ui.Done("2.0.15  (up to date)");
        Ui.Step("PhValheim folders");    Ui.Done("ready");
        Ui.Step("Valheim install");      Ui.Done("found");
        Ui.Step("PhValheim server");     Ui.Done("the mod list changed");
        Ui.Blank();
        foreach (int pct in new[] { 0, 17, 46, 78, 100 })
        {
            long total = 600_981_504;
            long got = total * pct / 100;
            const int bw = 24;
            int filled = pct * bw / 100;
            Ui.Progress("Downloading  [" + new string('#', filled) + new string('.', bw - filled)
                        + "] " + pct.ToString().PadLeft(3) + "%   "
                        + Ui.Bytes(got) + " of " + Ui.Bytes(total));
            Thread.Sleep(120);
        }
        Ui.ProgressDone("downloaded 573 MB");
        Ui.Step("Installing world files"); Ui.Done("done");
        Ui.Step("Mod loader");             Ui.Done("ready");
        Ui.Section("Starting Valheim");
        Ui.Field("World", "VikingOutlaws");
        Ui.Field("Address", "play.example.com:25000  (udp)");

        // ---- the 80 KB config-only path ----------------------------------------------
        Scene("only the mod settings changed");
        Ui.Step("PhValheim server");  Ui.Done("up to date");
        Ui.Step("Mod settings");      Ui.Done("updated");
        Ui.Step("Mod loader");        Ui.Done("ready");

        // ---- a client update is available --------------------------------------------
        Scene("a newer client exists");
        Ui.Step("Client version");  Ui.Done("2.0.14  ->  2.0.15 available");
        Ui.Warning("A newer PhValheim Client (2.0.15) is available.",
                   "Your launch will carry on with 2.0.14.",
                   "Updating is strongly recommended -- get it from your server's web page.");
        Ui.Step("PhValheim folders"); Ui.Done("ready");

        // ---- failures -----------------------------------------------------------------
        Scene("server unreachable");
        Ui.Step("PhValheim server");
        Ui.Fail("unreachable");
        Ui.Error("Could not reach your PhValheim server at https://valheim.example.com.",
                 "Check your internet connection, then try launching again.",
                 "If it keeps happening, the server may be down -- ask whoever runs it.");

        Scene("damaged download");
        Ui.Error("The download arrived damaged, so it has been discarded.",
                 "Your current install has been left alone and still works.",
                 "Launch again -- this is usually a one-off.");

        Scene("vanilla world, password shown because the player must type it");
        Ui.Banner("2.0.15");
        Ui.Field("Server", "https://valheim.example.com");
        Ui.Field("World", "SmallWorld  (vanilla - no mods)");
        Ui.Blank();
        Ui.Step("Client version");    Ui.Done("2.0.15  (up to date)");
        Ui.Step("Valheim install");   Ui.Done("found");
        Ui.Step("Mod files");         Ui.Done("not needed on a vanilla world");
        Ui.Section("Starting Valheim");
        Ui.Field("World", "SmallWorld");
        Ui.Field("Address", "play.example.com:25001  (udp)");
        Ui.Blank();
        Ui.Line("Valheim will ask for the server password. It is:");
        Ui.Blank();
        Ui.Note("Rh9kmTqw4vXzPLm2");
        Ui.Blank();

        Scene("the flatpak remedy, which has to be copyable");
        Ui.Error("Steam's folder exists but is not readable from inside this Flatpak.",
                 "Grant access by running this, then launch again:");
        Ui.Command("flatpak override --user --filesystem=~/.var/app/com.valvesoftware.Steam com.phvalheim.Client");

        Console.WriteLine();
        Console.WriteLine("verbose mode: " + (Ui.Verbose ? "ON" : "off (set PHVALHEIM_VERBOSE=1)"));
        if (Ui.Verbose)
        {
            Ui.Detail("local payload", "9f2c7a1e4b8d6f30a5c9e7b2d4f6a8c0  (from sync record)");
            Ui.Detail("server payload", "9f2c7a1e4b8d6f30a5c9e7b2d4f6a8c0");
            Ui.Detail("password", Ui.Mask("Rh9kmTqw4vXzPLm2") + "  (16 chars)");
        }
    }
}
PROG

# --user, so the obj/ and bin/ the SDK writes into the temp dir belong to the caller and the
# EXIT trap can actually remove them. That in turn needs HOME and DOTNET_CLI_HOME pointed
# somewhere writable: as a non-root user the SDK's first-run configuration tries to create
# /.dotnet and dies.
docker run --rm --user "$(id -u):$(id -g)" -v "$WORK":/w -w /w/preview \
  -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
  -e HOME=/tmp -e DOTNET_CLI_HOME=/tmp -e XDG_DATA_HOME=/tmp \
  -e PHVALHEIM_VERBOSE="${PHVALHEIM_VERBOSE:-}" \
  "$SDK" sh -c 'dotnet run -v q --nologo 2>&1' || {
    echo "preview build failed"
    exit 1
}
