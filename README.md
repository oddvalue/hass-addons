# oddvalue add-ons

Home Assistant add-on repository. Add it in Settings > Add-ons > Add-on store > Repositories:

```
https://github.com/oddvalue/hass-addons
```

## Vaultwarden

Runs the official `vaultwarden/server` image, pinned by release tag and image digest. Set the `domain` option to the full URL clients use, for example `https://vault.example.com:7277`. The add-on won't start without it.

TLS comes from `/ssl/fullchain.pem` and `/ssl/privkey.pem`. Signups are off.

The add-on revision after the dash in `version` (`1.37.5-2`) is for changes to this repo that don't change the upstream tag. Bump it by hand for those.

### Updates

`.github/scripts/bump-vaultwarden.sh` runs every 6 hours. It bumps the pin to the latest upstream release once the GitHub release and the image push are both two days old. With auto-update on, Supervisor waits one more day, takes a backup, and installs it. A release reaches the vault three to four days after upstream ships it.

Each bump copies the upstream release notes into `vaultwarden/CHANGELOG.md`, which Home Assistant shows on the update screen. Add an entry by hand for revision bumps. Changelog edits alone don't need a new `version`, since Supervisor reads the file from the repo.

The delay is there so a bad or compromised release has time to be noticed and pulled first. The script also guards against:

- **Re-pushed tags.** The Dockerfile pins the digest, so pushing a different image under the same tag changes nothing here. The script won't adopt a tag it has seen before at another digest.
- **Pulled releases.** Each run checks that the pinned release still exists and its tag still points at the pinned digest. If not, and the bump is under 24 hours old, it rolls back to the previous pin before Supervisor can install it. An older bump may already be installed, and rolling back then would make Supervisor downgrade the vault, so it only fails the run. Either way the failure emails the repo owner.
- **Moved action tags.** `actions/checkout` is pinned to a commit.

It can't catch a backdoor that nobody spots within those few days.

To test it locally without committing:

```
DRY_RUN=1 GITHUB_TOKEN=$(gh auth token) .github/scripts/bump-vaultwarden.sh
```

### Moving data in

If `/data` has no database at startup, the add-on copies one from `/share/vaultwarden`, checks the md5, and refuses to start if either step fails. It never starts on an empty vault.

The `share` mapping is off once the vault has moved in. To migrate again, add it back to `map` in `config.yaml`, put the data in `/share/vaultwarden` without `options.json` (the copy would overwrite the add-on's own), start the add-on, then remove the mapping and the staged copy.
