#!/bin/bash
# Cuts a release: builds the app, archives it, and regenerates the appcast
# that installed copies poll for automatic updates.
#
# Publishing = copying two things into the website repo:
#   releases/ArrangeDisplay-<version>.zip  ->  public/downloads/
#   releases/appcast.xml                   ->  public/
set -euo pipefail
cd "$(dirname "$0")"

PLIST="Resources/Info.plist"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
RELEASES="releases"

version=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
build_number=$(plutil -extract CFBundleVersion raw "$PLIST")
feed=$(plutil -extract SUFeedURL raw "$PLIST")
ed_key=$(plutil -extract SUPublicEDKey raw "$PLIST")

if [ "$ed_key" = "PUBLIC_ED_KEY_NOT_SET" ]; then
    cat >&2 <<'MSG'
No update-signing key yet. Run the one-time setup:

    ./setup-updates.sh

It creates the key, stores it in your login keychain, writes the public half
into Resources/Info.plist, and tells you how to back it up.

Details and recovery steps: docs/RELEASING.md
MSG
    exit 1
fi

if [ "$feed" = "APPCAST_URL_NOT_SET" ]; then
    cat >&2 <<'MSG'
No appcast URL yet. Run the one-time setup:

    ./setup-updates.sh

It asks for your domain and writes the feed URL. Have the domain attached
first — this URL is baked into every copy you ship and can never move, so
apps already installed keep asking this exact address forever.

Details: docs/RELEASING.md
MSG
    exit 1
fi

# Where the archives will be served from. Defaults to /downloads/ next to the
# feed, which is how the website repo is laid out. GitHub Releases puts the tag
# in the path instead, so override it there — export it in your shell or prefix
# the command:
#
#   DOWNLOAD_URL_PREFIX="https://github.com/OWNER/REPO/releases/download/v$version/" ./release.sh
#
download_prefix="${DOWNLOAD_URL_PREFIX:-$(dirname "$feed")/downloads/}"
echo "Archives will be linked from: $download_prefix"

./build.sh

mkdir -p "$RELEASES"
archive="$RELEASES/ArrangeDisplay-$version.zip"
rm -f "$archive"
# ditto, not zip: the app bundle contains a framework whose symlinks and
# code signature a plain zip would mangle.
ditto -c -k --sequesterRsrc --keepParent build/DisplayManager.app "$archive"

# -o is not optional: without it generate_appcast names the output after the
# last path component of SUFeedURL, which silently produces a stray file.
"$TOOLS/generate_appcast" -o "$RELEASES/appcast.xml" \
    --download-url-prefix "$download_prefix" "$RELEASES"

echo
echo "Release $version (build $build_number) ready."
echo
echo "  $archive"
echo "  $RELEASES/appcast.xml"
echo

if [[ "$feed" == *github.com* ]]; then
    repo=$(printf '%s' "$feed" | sed -E 's|https://github.com/([^/]+/[^/]+)/.*|\1|')
    cat <<MSG
To publish, attach BOTH files to a release tagged v$version:

  gh release create v$version --repo $repo --title "Arrange Display $version" \\
      "$archive" "$RELEASES/appcast.xml"

appcast.xml must be attached to every release — the feed URL resolves to the
newest one, so an older copy would go stale and updates would stop appearing.
MSG
else
    cat <<MSG
To publish, serve both files from your host:

  $archive         -> $(dirname "$feed")/downloads/
  $RELEASES/appcast.xml  -> $(dirname "$feed")/
MSG
fi

cat <<'MSG'

Automatic checks are off, so nothing reaches users on its own: they see the
update when they click "Check for Updates…".
MSG
