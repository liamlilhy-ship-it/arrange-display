#!/bin/bash
# One-time setup for the update channel: the signing key and the feed URL.
# Safe to re-run — it only fills in whatever is still missing, and never
# replaces a key you already have.
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Resources/Info.plist"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

if [ ! -x "$TOOLS/generate_keys" ]; then
    echo "Sparkle's tools aren't downloaded yet. Run ./build.sh once, then re-run this."
    exit 1
fi

echo "════════════════════════════════════════════════════════════"
echo " Arrange Display — update channel setup"
echo "════════════════════════════════════════════════════════════"
echo

# ── Step 1: signing key ────────────────────────────────────────────────
current_key=$(plutil -extract SUPublicEDKey raw "$PLIST")

if [ "$current_key" != "PUBLIC_ED_KEY_NOT_SET" ]; then
    echo "① Signing key — already set up."
    echo "   Public key in $PLIST: ${current_key:0:16}…"
    echo
else
    echo "① Signing key"
    echo
    echo "   This creates a key pair that proves updates come from you."
    echo "   The private half goes into your login keychain and never leaves"
    echo "   this Mac. The public half goes into the app so it can check."
    echo
    echo "   You only ever do this once. macOS may ask permission to save to"
    echo "   the keychain — allow it, or the key can't be stored."
    echo
    read -r -p "   Create the signing key now? [y/N] " reply
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        echo
        echo "   Skipped. Nothing was changed. Re-run this script when ready."
        exit 0
    fi
    echo

    # Reuse an existing keychain key if there is one; only generate otherwise.
    if pub=$("$TOOLS/generate_keys" -p 2>/dev/null) && [ -n "$pub" ]; then
        echo "   Found an existing Sparkle key in your keychain — reusing it."
    else
        "$TOOLS/generate_keys" >/dev/null
        pub=$("$TOOLS/generate_keys" -p)
        echo "   Key created."
    fi

    plutil -replace SUPublicEDKey -string "$pub" "$PLIST"
    echo "   Public key written to $PLIST."
    echo
    echo "   ⚠  BACK IT UP NOW — outside this repo, e.g. your password manager:"
    echo
    echo "        $TOOLS/generate_keys -x ~/Desktop/sparkle-private-key.txt"
    echo
    echo "   That file IS the private key. Store it safely, then delete it from"
    echo "   the Desktop. Lose it and you can never update installed copies"
    echo "   again — every user would have to re-download by hand."
    echo
fi

# ── Step 2: feed URL ───────────────────────────────────────────────────
current_feed=$(plutil -extract SUFeedURL raw "$PLIST")

if [ "$current_feed" != "APPCAST_URL_NOT_SET" ]; then
    echo "② Feed URL — already set up."
    echo "   $current_feed"
    echo
    echo "   This is permanent. Changing it strands every copy already installed."
    echo
else
    echo "② Feed URL"
    echo
    echo "   The address installed copies check for updates. It is baked into"
    echo "   every app you ship and CAN NEVER MOVE — apps already out there"
    echo "   keep asking this exact address forever."
    echo
    echo "   Two supported layouts (docs/RELEASING.md has the detail):"
    echo
    echo "     website   your host, feed at /appcast.xml, archives in /downloads/"
    echo "     github    a public repo's releases/latest/download/appcast.xml"
    echo
    echo "   A domain you own is the only address you can ever move. A"
    echo "   vercel.app or github.com URL ties you to that project or repo"
    echo "   name — workable, just know it is permanent."
    echo
    read -r -p "   Feed URL, or a bare domain, or blank to skip: " domain
    if [ -z "$domain" ]; then
        echo
        echo "   Skipped. Set it here once your domain is attached."
        exit 0
    fi

    # Accept either a full feed URL or a bare hostname.
    if [[ "$domain" == *appcast.xml ]]; then
        feed_url="$domain"
        [[ "$feed_url" == http* ]] || feed_url="https://$feed_url"
    else
        domain="${domain#https://}"; domain="${domain#http://}"; domain="${domain%/}"
        domain=$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')
        feed_url="https://$domain/appcast.xml"
    fi

    plutil -replace SUFeedURL -string "$feed_url" "$PLIST"
    echo
    echo "   Feed URL set to $feed_url"
    if [[ "$feed_url" == *github.com* ]]; then
        echo
        echo "   GitHub layout: upload appcast.xml as an asset on EVERY release,"
        echo "   and pass the archive location when releasing —"
        echo "   DOWNLOAD_URL_PREFIX=\".../releases/download/v<version>/\" ./release.sh"
    else
        echo "   Archives will be served from $(dirname "$feed_url")/downloads/"
    fi
    echo
fi

echo "────────────────────────────────────────────────────────────"
echo " Setup complete. Before announcing the first release:"
echo
echo "   • Test the update end to end, including the Gatekeeper step"
echo "     (docs/RELEASING.md — \"Testing the update flow locally\")"
echo "   • Then: ./release.sh"
echo
echo " Ongoing release steps: docs/RELEASING.md"
echo "────────────────────────────────────────────────────────────"
