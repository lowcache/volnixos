#!/usr/bin/env fish

# priv-sync.sh: Safely sync live persistent data to priv.bkup
# Mandate: Never overwrite live data from the repo. Sync is ONE-WAY (Live -> Repo).

set REPO_DIR /persist/home/lowcache/.nix-config/priv.bkup
set LIVE_HOME /persist/home/lowcache

echo "Starting Safe Sync to priv.bkup..."

# List of directories to sync
set DIRS Documents Pictures CodeRep unDevel AppImage ZAP-Sessions fonts krita-master .bin crypto-bot

for dir in $DIRS
    if test -d $LIVE_HOME/$dir
        echo "Syncing $dir..."
        rsync -au --progress $LIVE_HOME/$dir/ $REPO_DIR/$dir/
    end
end

# Surgical .gemini sync
# We only backup the logic/config, not the volatile history or tmp files.
echo "Syncing .gemini configuration..."
mkdir -p $REPO_DIR/.gemini/skills
rsync -au --progress $LIVE_HOME/.gemini/analytical-agent.yaml $REPO_DIR/.gemini/
rsync -au --progress $LIVE_HOME/.gemini/nix-agent.yaml $REPO_DIR/.gemini/
rsync -au --progress $LIVE_HOME/.gemini/skills/ $REPO_DIR/.gemini/skills/

# SSH and GPG (Backup only)
echo "Backing up SSH and GPG keys..."
rsync -au --progress $LIVE_HOME/.ssh/ $REPO_DIR/.ssh/
rsync -au --progress $LIVE_HOME/.gnupg/ $REPO_DIR/.gnupg/

echo "Sync complete. You can now commit changes in $REPO_DIR."
