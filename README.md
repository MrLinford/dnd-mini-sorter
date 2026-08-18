# D&D 5e Miniature STL Auto-Sorter 🐉

A robust, fail-safe Bash script designed to automatically organize massive, chaotic directories of 3D printable miniatures into a clean directory structure based on the official Dungeons & Dragons 5th Edition creature taxonomy.

Perfect for Dungeon Masters and 3D printing hobbyists managing massive creator collections (like the MZ4250 Patreon archives) who want to find the right monster for their tabletop session in seconds.

## ✨ Features

* **Official 5e Taxonomy:** Automatically sorts files into the 14 Primary Creature Types (Aberration, Beast, Celestial, Construct, Dragon, Elemental, Fey, Fiend, Giant, Humanoid, Monstrosity, Ooze, Plant, Undead) plus Universal Modifiers (Shapechanger, Swarm, Titan).
* **Deep Sub-Categorization:** Drills down into specific sub-races and variants (e.g., separating `Fiend/Demon` from `Fiend/Devil`, or pulling out specific humanoids like `Humanoid/Goblinoid` and `Humanoid/Tabaxi`).
* **Slicer File Support:** Looks beyond just raw `.stl` and `.obj` files to capture pre-supported slicer files and archives (`.ctb`, `.lys`, `.zip`) so your Chitubox or Lychee scenes stay with the raw models.
* **Recursive Searching:** Digs through nested folders to find files buried deep in your directories.
* **Fail-Safe Operations:**
  * Uses `-n` to prevent overwriting files with identical names.
  * Uses `-prune` to ignore the target directory, preventing infinite loops or double-sorting if run multiple times.
* **Dry Run Mode:** Preview exactly where files will go without actually moving a single byte.
* **Detailed Logging:** Outputs ISO-timestamped logs and a final statistical summary of moved files.

## ⚙️ Configuration

Before running the script, you **must** configure it to point to your specific models directory. There are two ways to do this:

### Option 1: Environment Variable (Recommended)

The easiest way is to pass the `SOURCE_DIR` environment variable when running the script:

```bash
# Dry run with custom directory
SOURCE_DIR="/path/to/your/minis" ./sort_minis.sh --dry-run

# Live run with custom directory
SOURCE_DIR="/path/to/your/minis" ./sort_minis.sh
```

### Option 2: Edit the Script

Alternatively, edit the default path in the script:

1. Open `sort_minis.sh` in a text editor.
2. Locate the `CONFIGURATION` section near the top:
   ```bash
   # --- CONFIGURATION ---
   SOURCE_DIR="${SOURCE_DIR:-/path/to/your/minis}"
   ```
3. Replace the default path with your actual directory path (keep the `${SOURCE_DIR:-...}` syntax).

### Finding Your Directory Path

If you're unsure of your directory's full path:

**On Linux/macOS:**
```bash
# Navigate to your minis folder in terminal, then run:
pwd
# This prints the full path. Copy and use it in the SOURCE_DIR variable.
```

**Example paths:**
- `/home/username/3d-models/minis`
- `/mnt/nas/shared/3D Models/MZ4250 3D Miniature Models Aug 2026`
- `/Volumes/ExternalDrive/3D Prints/Minis`

## 🚀 Usage

Make sure the script is executable before trying to run it:

```bash
chmod +x sort_minis.sh
```

### 1. Perform a Dry Run (Highly Recommended)

Always perform a dry run first. This scans your files and prints the planned moves to the console without actually altering your file system.

```bash
./sort_minis.sh --dry-run
# or
./sort_minis.sh -d

# With custom directory:
SOURCE_DIR="/path/to/minis" ./sort_minis.sh --dry-run
```

### 2. Execute the Live Sort

Once you are satisfied with the dry run preview, run the script normally to execute the file moves:

```bash
./sort_minis.sh

# With custom directory:
SOURCE_DIR="/path/to/minis" ./sort_minis.sh
```

### 3. Review Results

After completion, check the `Sorted_Monsters/` folder created in your source directory:

```bash
# List the top-level categories created
ls -la Sorted_Monsters/

# Check what's in the Unsorted folder (files needing manual review)
ls Sorted_Monsters/Unsorted/
```

## 📁 Output Structure Example

After a successful run, your target directory will look like this:

```text
Sorted_Monsters/
├── Aberration/
│   ├── Beholder_supported.lys
│   └── Mind_Flayer_v2.stl
├── Dragon/
│   ├── Chromatic/
│   │   └── Young_Red_Dragon.ctb
│   └── Metallic/
│       └── Ancient_Gold_Dragon.stl
├── Humanoid/
│   ├── Elf/
│   ├── Goblinoid/
│   │   └── Bugbear_Chief.stl
│   └── Tabaxi/
├── Undead/
│   └── Zombie_Horde.zip
└── Unsorted/
    └── [Files that did not match any 5e keyword]
```

*Any files that do not match the built-in keyword dictionary will be safely swept into the `Unsorted/` folder for manual review.*

## 🛠️ Modifying the Dictionary

You can easily add new monsters, specific character names, or custom tags to the sorting logic. Open the script and locate the `--- D&D 5e OFFICIAL CREATURE TYPE CLASSIFICATION ---` section. Simply append your new keywords (in lowercase) to the end of the relevant category line:

```bash
sort_category "Plant" "plant" "myconid" "shambling mound" "blight" "treant" "vegepygmy" "YOUR_NEW_KEYWORD"
```

**Tips for adding keywords:**
- Keywords are case-insensitive ("Dragon" matches "dragon", "DRAGON", etc.)
- Use partial words ("dragon" will match "dragon", "red_dragon", "young_dragon")
- More specific keywords should go first (e.g., "red dragon" before "dragon")
- Test your additions with a dry run before running live

## 📋 Advanced Usage

### Capture Output to a Log File

For larger collections, save the output to a log file for later review:

```bash
# Dry run with log capture
./sort_minis.sh --dry-run 2>&1 | tee sort_dry_run.log

# Live run with log capture
./sort_minis.sh 2>&1 | tee sort_results.log
```

### Run in Background

For very large collections, run the script in the background:

```bash
nohup ./sort_minis.sh > sort_results.log 2>&1 &

# Check progress:
tail -f sort_results.log
```

### Help and Options

View all available options:

```bash
./sort_minis.sh --help
```

## 🔧 Troubleshooting

### "Source directory not found"
**Cause:** The path doesn't exist or is wrong.

**Solution:**
1. Double-check the path: `ls /path/to/your/minis`
2. Verify it contains miniature files (`.stl`, `.obj`, `.ctb`, `.lys`, `.zip`)
3. Use `pwd` in your minis folder to get the exact path

### "Source directory is not readable"
**Cause:** Permission issues (folder is owned by another user).

**Solution:**
```bash
# Check permissions:
ls -ld /path/to/your/minis

# If needed, adjust permissions:
chmod u+r /path/to/your/minis
```

### "Source directory is not writable" (during live run)
**Cause:** The script can't move files because the directory lacks write permissions.

**Solution:**
```bash
# Check if you own the directory:
ls -ld /path/to/your/minis

# If you own it, fix permissions:
chmod u+w /path/to/your/minis

# If you don't own it, contact the owner or use:
sudo chmod u+w /path/to/your/minis
```

### Files are not being sorted (all end up in "Unsorted")
**Cause:** Filenames don't match any keywords in the dictionary.

**Solution:**
1. Check a filename from the Unsorted folder
2. Identify the monster type it should be
3. Add the keyword to the script's dictionary
4. Run again with the updated script

### Certain files failed to move
**Cause:** File move errors (usually due to `-n` flag preventing overwrites of existing files).

**Solution:**
- Check the log for warnings about duplicate filenames
- Either delete/rename the conflicting file or accept the duplicate in Unsorted
- The `-n` flag prevents data loss by refusing to overwrite

### Script permission error
**Cause:** Script is not executable.

**Solution:**
```bash
chmod +x sort_minis.sh
```

## ❓ FAQ

**Q: Will this delete any files?**
A: No. The script only moves files into organized folders. Nothing is deleted. If there's a conflict (duplicate filename), the file is skipped due to the `-n` flag.

**Q: Can I run this multiple times on the same directory?**
A: Yes! The script safely re-runs without double-sorting. Files already in the Sorted_Monsters folder are excluded from subsequent runs.

**Q: What if my source and target directories have different paths but are actually the same?**
A: The script detects this and prevents infinite loops. You're safe.

**Q: How long will this take?**
A: Speed depends on your collection size and storage speed. The script processes files recursively, so nested folders are handled. A dry run will show you the estimated count.

**Q: Can I use this on networked/NAS storage?**
A: Yes, but it may be slower. Consider running a dry run first to estimate time. The script works over SSH/SMB/NFS mounts.

**Q: Will this work on macOS?**
A: Yes, but the timestamp function includes a fallback for BSD's `date` command. Should work on recent macOS versions.

## ⚠️ Disclaimer

While this script is written to be non-destructive (no files are deleted, only moved), always ensure you have a backup of your files before running automated sorting operations on large directories. Test with a dry run first!