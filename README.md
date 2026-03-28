# Update your tux

Simple Bash script to update a Debian-based Linux system.

## Requirements

- `bash`
- `nala`
- `sudo` when running as a regular user

Optional package managers:

- `flatpak`
- `snap`

## Behavior

- Updates `.deb` packages with `nala`
- Detects `flatpak` and `snap` automatically
- Skips optional managers that are not installed
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
