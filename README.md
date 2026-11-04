# oddvalue add-ons

Home Assistant add-on repository. Add it in Settings > Add-ons > Add-on store > Repositories:

```
https://github.com/oddvalue/hass-addons
```

## Vaultwarden

Runs the official `vaultwarden/server` image, pinned to a release tag. A daily workflow checks upstream releases and bumps the tag and add-on version once a release is two days old and its image is on Docker Hub. With auto-update on, Supervisor installs it a day later, after taking a backup.

Set the `domain` option to the full URL clients use, for example `https://vault.example.com:7277`. The add-on won't start without it.

TLS comes from `/ssl/fullchain.pem` and `/ssl/privkey.pem`. Signups are off.

The add-on revision after the dash in `version` (`1.37.4-1`) is for changes to this repo that don't change the upstream tag. Bump it by hand for those.

### Moving data in

If `/data` has no database at startup, the add-on copies one from `/share/vaultwarden`, checks the md5, and refuses to start if either step fails. It never starts on an empty vault.
