# Update your tux

Simple Bash script to update a Debian-based Linux system.

## Requirements

- `bash`
- `nala`
- `sudo` when running as a regular user

Optional package managers:

- `flatpak`
- `snap`

Optional safety tools:

- `btrfs` and a Btrfs root filesystem for a read-only pre-update snapshot

## Behavior

- Updates `.deb` packages with `nala`
- Detects `flatpak` and `snap` automatically
- Skips optional managers that are not installed
- Creates a best-effort Btrfs snapshot before changing the system when available; keeps only the 3 most recent snapshots
- Accepts repository `Label` release-info changes during `nala update`
- Waits up to 5 minutes for APT/dpkg locks (e.g. `apt-daily` at boot) before every `nala`/`apt-get`/`dpkg` call
- Retries `.deb` updates once after running `dpkg --configure -a` and `apt-get -f install -y`
- Runs Flatpak updates noninteractively and retries once after 5 seconds on failure; interruptions are not retried
- When a user systemd session is active, the Flatpak retry uses IPv4 in a transient service to work around slow or broken IPv6 routes without changing system network settings
- Archives old `.bak.*` source-list backups outside `/etc/apt/sources.list.d` to avoid apt warnings
- Stops on the first real update failure
- Does not fall back to `apt` when `nala` is missing

## Usage

```bash
chmod +x update-tux.sh
./update-tux.sh
```

## Notes

- If `nala` is not installed, the script exits with an error message.
- If you run the script as root, it does not use `sudo`.
- Flatpak end-of-life runtime notices require an app update from its maintainer; they are not download failures.
- Run the regression checks with `bash tests/flatpak.sh && bash tests/apt-lock.sh && bash tests/snapshot.sh` (no real package updates).
