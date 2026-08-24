# Releasing

How updates reach users, and what you do each time. Everything here assumes
`./setup-updates.sh` has been run once.

## The short version

```bash
# 1. bump the version in Resources/Info.plist
# 2.
./release.sh
# 3. copy the two files it names into the website repo, push
```

That's the whole loop. The rest of this file is detail and recovery.

---

## One-time setup

```bash
./build.sh          # downloads Sparkle's tools
./setup-updates.sh  # signing key + feed URL
```

Run it once and it's done forever. It's safe to re-run — it only fills in
what's missing and will never replace a key you already have.

**Back up the private key** the first time, somewhere outside this repo —
a password manager is ideal:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/sparkle-private-key.txt
```

Store it, then delete the file from your Desktop. See *If you lose the key*
below for why this matters.

---

## Cutting a release

**1. Bump the version** in `Resources/Info.plist`:

- `CFBundleShortVersionString` — what people see: `0.2.0`
- `CFBundleVersion` — a plain counter that must increase every single
  release: `1`, `2`, `3`… This is the one Sparkle compares. Forget to raise
  it and installed copies won't see the update.

**2. Build and sign:**

```bash
./release.sh
```

This builds the app, archives it, signs the archive with your key, and
regenerates `releases/appcast.xml` with the new entry alongside the old ones.
It refuses to run if setup hasn't been done.

### Where the files are served from

`release.sh` assumes archives sit at `/downloads/` next to the feed, matching
the website repo's layout. If you host archives on GitHub Releases instead, the
tag is part of the URL, so pass the prefix explicitly:

```bash
DOWNLOAD_URL_PREFIX="https://github.com/liamlilhy-ship-it/arrange-display/releases/download/v1.1.0/" ./release.sh
```

The two supported layouts:

| | Feed URL (`SUFeedURL`) | Archives |
|---|---|---|
| Website | `https://HOST/appcast.xml` | `public/downloads/` — default, no override needed |
| GitHub | `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml` | attached to each release, needs the override above |

With the GitHub layout, `appcast.xml` must be uploaded as an asset on **every**
release — `latest/download/` resolves to the newest release, so an older one
would go stale. Archive URLs use the specific tag, so entries for past versions
keep working.

**3. Publish** — copy the two files it names into the website repo:

| From | To |
|---|---|
| `releases/ArrangeDisplay-<version>.zip` | `public/downloads/` |
| `releases/appcast.xml` | `public/` |

Then update `downloadUrl`, `version` and `approxSizeMB` in `lib/config.ts`,
and push. Vercel deploys, and the update is live.

Also upload the DMG (`./package-dmg.sh`) wherever you point new users, so
first-time downloads get the new version too.

**4. Check it.** Open the app, gear → Check for Updates…. You should be
offered the version you just published. This is worth doing every time — it
is the only end-to-end test of the whole chain.

---

## Release notes (optional)

To make the update dialog show what's new, drop a file next to the zip with
the same name before running `release.sh`:

```
releases/ArrangeDisplay-0.2.0.zip
releases/ArrangeDisplay-0.2.0.html    <- shown in the update dialog
```

Plain HTML fragment, no `<html>` or `<body>` needed. Without one, users see
a version number and nothing else.

---

## Testing the update flow locally

Proves the whole chain — signing, fetching, verifying, installing, relaunching
— without a domain, a server, or shipping anything. Uses your real key, so
what passes here is what users get.

**Setup (once):**

```bash
./setup-updates.sh
```

Say `y` at step ①. At step ② just press Enter — the local test overrides the
feed URL at runtime, so no URL needs to go in `Info.plist` yet.

**1. Build v0.1.0 and "install" it.** Quit the app first if it's running.

```bash
./build.sh
mkdir -p ~/Applications && rm -rf ~/Applications/DisplayManager.app
cp -R build/DisplayManager.app ~/Applications/
```

**2. Build v0.2.0 as the update.** Both keys must change; `CFBundleVersion` is
the one Sparkle compares.

```bash
plutil -replace CFBundleShortVersionString -string "0.2.0" Resources/Info.plist
plutil -replace CFBundleVersion -string "2" Resources/Info.plist
./build.sh
mkdir -p /tmp/arrange-feed
ditto -c -k --sequesterRsrc --keepParent build/DisplayManager.app \
    /tmp/arrange-feed/ArrangeDisplay-0.2.0.zip
```

**3. Sign it into an appcast** (uses the key in your keychain):

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    -o /tmp/arrange-feed/appcast.xml \
    --download-url-prefix "http://localhost:8000/" \
    /tmp/arrange-feed
```

**4. Serve it.** Leave this running:

```bash
cd /tmp/arrange-feed && python3 -m http.server 8000
```

**5. Point the app at the local feed** (new terminal). User defaults override
`Info.plist`, which is Sparkle's documented way to test:

```bash
defaults write com.liam.display-manager SUFeedURL "http://localhost:8000/appcast.xml"
```

**6. Run it and check:**

```bash
open ~/Applications/DisplayManager.app
```

Menu bar → gear → **Check for Updates…**. You should be offered 0.2.0. Install
it, and `~/Applications/DisplayManager.app` becomes 0.2.0 with your presets and
settings intact.

**Clean up:**

```bash
defaults delete com.liam.display-manager SUFeedURL
plutil -replace CFBundleShortVersionString -string "0.1.0" Resources/Info.plist
plutil -replace CFBundleVersion -string "1" Resources/Info.plist
rm -rf /tmp/arrange-feed
```

### Also testing the Gatekeeper behaviour

The steps above don't prove the most important claim — that an update skips the
first-launch prompt — because an app you built locally was never quarantined.
To test that part, mark the v0.1.0 copy as if a browser had downloaded it,
before step 6:

```bash
xattr -w com.apple.quarantine "0083;00000000;Safari;$(uuidgen)" \
    ~/Applications/DisplayManager.app
```

Now launching it gives the real first-launch block, and you approve it through
System Settings exactly as a user would. Then run the update. If it installs
and relaunches without a second trip through Settings, the whole premise of
this setup is confirmed on your own machine.

---

## Things that must never change

**The feed URL** (`SUFeedURL`). Every copy ever shipped asks this exact
address forever. If you move it, those copies go silent — no error the user
would understand, they simply stop being offered updates. Recovering means
asking everyone to download by hand.

**The signing key.** Same story: installed copies trust one key and only one.

If you ever genuinely have to change either, the only path is shipping a new
version by hand and telling existing users to download it.

---

## Maintenance situations

### New Mac, or reinstalling

The private key lives in the login keychain, so it doesn't travel with the
repo. Restore it from your backup:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -f ~/path/to/sparkle-private-key.txt
```

Then `./release.sh` works as before. Don't run `setup-updates.sh` expecting
it to recreate the key — a *new* key would be useless to everyone who
already has the app.

### If you lose the key

There is no recovery. Installed copies only trust the original key, so a new
one can't reach them. You would have to ship a new version with a new key and
get every existing user to download and install it manually, first-launch
steps and all. This is the single worst failure mode in the whole setup,
which is why the backup is worth doing properly today.

### If the key leaks

Anyone holding it can sign something your users' apps will install and run.
Generate a new key, ship a new version with it, and treat existing installs
as compromised — you'd need to tell users directly. Keep it out of the repo,
out of screenshots, out of chat.

### Checking mainland-China reachability

You can't test this from your own Mac. Free services run pings and fetches
from mainland nodes — `itdog.cn`, or the various 站长工具 ping tools. Point
one at your feed URL and your download URL. Worth checking before the first
release, since the URL is the part you can't take back, and again if users
report updates never appearing.

---

## Why updates work this way

The app is self-signed rather than notarized by Apple, so macOS asks the user
to approve it on first launch. That approval is tied to that exact build — a
freshly downloaded version is, to macOS, an unrelated unknown app, and gets
the same treatment again.

Updating through the app avoids this entirely: the running app installs the
new version itself, so macOS never re-quarantines it. That is the whole
reason the updater exists, and why "just download the new DMG" is a worse
experience for users even though it works.

The signature on each update is what replaces Apple's check. Without it, the
app would install whatever it was handed.
