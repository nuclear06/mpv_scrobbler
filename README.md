# Last.fm Scrobbler for MPV Player

Forked from `https://github.com/MugoSquero/mpv_scrobbler` with significant robustness and feature improvements.

## Key Improvements in this Fork
- **Improved Robustness**: Fixed multiple bugs that caused the script to crash (e.g., missing album metadata, subprocess failures, undefined error handlers).
- **Loop/Repeat Support**: Fully supports scrobbling when a track is set to loop (`--loop-file` or `--loop-playlist`).
- **Ghost Scrobble Prevention**: Improved state management ensures metadata from a previous track never "leaks" into the next scrobble if metadata is missing.
- **Case-Insensitive Metadata**: Metadata keys are now normalized, ensuring tags like `artist` and `Artist` are both recognized.
- **Configurable Binary Path**: Supports custom paths for the `scrobbler` executable via `scrobbler_path` (with `~/` expansion support).

## Installation
1. **Download the Repository**: Clone or download this repository.
2. **Copy Files**:
   - **For Unix/Linux**: 
     - Copy the `scrobble` folder to `~/.config/mpv/scripts/`
     - Copy `lastfm.conf` to `~/.config/mpv/script-opts/`
   - **For Windows**: 
     - Copy the `scrobble` folder to `C:\Users\<YourUsername>\AppData\Roaming\mpv\scripts\`
     - Copy `lastfm.conf` to `C:\Users\<YourUsername>\AppData\Roaming\mpv\script-opts\`
3. **Dependency**: Ensure you have [hauzer/scrobbler](https://github.com/hauzer/scrobbler) installed and available in your PATH (or configure its path in `lastfm.conf`).
4. **Authenticate**: Run the following command to link your Last.fm account:
   ```bash
   scrobbler add-user
   ```

## Configuration
The scrobbler is configured using `script-opts/lastfm.conf`. Key options include:

- **username**: Your Last.fm username.
- **scrobble_paths**: Comma-separated list of folders/paths to whitelist for scrobbling.
- **scrobble_threshold**: Percentage of track to play before scrobbling (default: 50).
- **scrobbler_path**: Path to the `scrobbler` executable. Supports `~/` (e.g., `~/.local/bin/scrobbler`).
- **fuzzy_metadata_search**: Try to extract artist/album from filename if tags are missing.
- **only_album_artist**: Whether to prioritize Album Artist tags.

Refer to the documented [lastfm.conf](lastfm.conf) for all options.

## Usage
Once installed and authenticated, the script runs automatically in the background when you play music in mpv.

### Metadata Overrides
To manually correct metadata for a specific file, you can use the override feature. Add this to your `input.conf`:
```
O script-binding scrobble/create-override
```
Pressing `O` will create a `.override` JSON template next to the current file.

## License
MIT
