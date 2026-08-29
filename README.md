# D&D 5e Miniature Auto-Sorter 🐉

A Bash importer that reorganises an unstructured 3D miniature download into a [Manyfold](https://github.com/manyfold3d/manyfold) library, tagging every model with Dungeons & Dragons 5th Edition creature taxonomy along the way.

Built for Dungeon Masters and 3D printing hobbyists sitting on massive creator archives (like the MZ4250 Patreon drops) who want to find the right monster mid-session instead of trawling through folders named `G/Giants/OLD Giants`.

## 🧩 What counts as a model

A **model is a folder**, not a file. Any directory that directly contains at least one mesh becomes one Manyfold model, and every file sitting alongside it travels with it:

```text
Ancient Time Dragon/
├── Ancient Time Dragon.stl                     ← mesh
├── Ancient Time Dragon Body presupported.stl   ← part
├── Ancient Time Dragon Left Wing.stl           ← part
├── Ancient Time Dragon rigged.blend            ← source file
├── Ancient Time Dragon.JPG                     ← render
└── Gargantuan Creature Flying Size Marker.stl  ← accessory
```

That whole folder imports as a single model. Parts, `.blend` sources, renders, slicer projects and size markers stay together rather than being scattered across a dozen "models".

## ✨ Features

* **Manyfold library layout:** imports into `{creator}/{collections}/{tags}/{modelName}-{modelId}`, ready to scan.
* **Automatic collections:** each top-level folder of your download (`Monster Manual 2014`, `Kobold Press - Tome of Beasts`, `Terrain, Ships & Scatter Models`) becomes a collection. Override with `MANYFOLD_COLLECTION` if you want everything under one.
* **Official 5e taxonomy:** the 14 primary creature types (Aberration, Beast, Celestial, Construct, Dragon, Elemental, Fey, Fiend, Giant, Humanoid, Monstrosity, Ooze, Plant, Undead) plus Shapechanger, Swarm, Titan, Deity, Spell Effect and Terrain.
* **Hierarchical tags:** `Fiend/Demon` vs `Fiend/Devil`, `Giant/Hill` vs `Giant/Storm`, `Humanoid/Goblinoid` vs `Humanoid/Tabaxi`. Manyfold turns each path segment into its own tag.
* **~1,900 keywords tuned against a real archive:** roughly 89% of a 3,844-model MZ4250 collection classifies automatically. Longest match wins, so `hill giant` beats `giant`. Plurals match too, so `OLD Giants` and `Other Wizards` classify correctly.
* **Context-aware matching:** the model's own name is matched first, falling back to its parent folders. A collection called `Kobold Press - Tome of Beasts` therefore can't tag every model inside it as `Humanoid/Kobold`.
* **Variant folders preserved:** `Flumph`, `Flumph OLD` and `Flumph Updated` each import as their own model so you keep the version history.
* **Non-destructive by default:** copies rather than moves, leaving your download untouched.
* **Re-runnable:** a model already present in the library is detected and skipped, so you can re-run after adding keywords or downloading new releases.
* **Dry run mode:** preview every destination without touching a byte.
* **ISO-timestamped logging** and a per-tag summary at the end.

## ⚙️ Configuration

Everything is set through environment variables; only `SOURCE_DIR` and `MANYFOLD_LIBRARY_DIR` really matter.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SOURCE_DIR` | `/path/to/your/minis` | The downloaded archive to import |
| `MANYFOLD_LIBRARY_DIR` | `$SOURCE_DIR/Manyfold_Library` | Destination library root |
| `MANYFOLD_CREATOR` | `MZ4250` | Creator folder name |
| `MANYFOLD_COLLECTION` | *(auto)* | Force a single collection instead of one per top-level folder |

You can also edit the defaults directly in the `CONFIGURATION` section near the top of the script:

```bash
SOURCE_DIR="${SOURCE_DIR:-/path/to/your/minis}"
MANYFOLD_LIBRARY_DIR="${MANYFOLD_LIBRARY_DIR:-$SOURCE_DIR/Manyfold_Library}"
MANYFOLD_CREATOR="${MANYFOLD_CREATOR:-MZ4250}"
MANYFOLD_COLLECTION="${MANYFOLD_COLLECTION:-}"
```

Set your Manyfold library's folder template to `{creator}/{collections}/{tags}/{modelName}-{modelId}` so the scan lines up with what the script produces.

### Finding your directory path

```bash
# Navigate to your minis folder, then:
pwd
```

Example paths:

* `/home/username/3d-models/minis`
* `/mnt/user/nas/Downloads/MEGA/MZ4250 3D Miniature Models Aug 2026`
* `/Volumes/ExternalDrive/3D Prints/Minis`

## 🚀 Usage

```bash
chmod +x sort_minis.sh
```

### 1. Dry run first

Scans everything and prints the planned layout without creating, copying or moving anything.

```bash
SOURCE_DIR="/mnt/user/nas/Downloads/MEGA/MZ4250 3D Miniature Models Aug 2026" \
MANYFOLD_LIBRARY_DIR="/mnt/user/manyfold/library" \
  ./sort_minis.sh --dry-run 2>&1 | tee sort_preview.log
```

Then grep the log for anything that fell through:

```bash
grep Unsorted sort_preview.log
```

### 2. Import

Copies by default, so the original download is left intact.

```bash
SOURCE_DIR="/mnt/user/nas/Downloads/MEGA/MZ4250 3D Miniature Models Aug 2026" \
MANYFOLD_LIBRARY_DIR="/mnt/user/manyfold/library" \
  ./sort_minis.sh
```

Add `--move` if you'd rather relocate the files and reclaim the space. In move mode the emptied source directories are cleaned up afterwards.

```bash
./sort_minis.sh --move
```

### 3. Scan in Manyfold

Add the library root in Manyfold and run a scan.

```bash
find /mnt/user/manyfold/library -maxdepth 5 -type d
```

### Options

| Flag | Effect |
| --- | --- |
| `-d`, `--dry-run` | Preview only; nothing is written |
| `-m`, `--move` | Move instead of copy (empties `SOURCE_DIR`) |
| `-h`, `--help` | Show usage |

## 📁 Output structure example

```text
MZ4250/
├── Planescape - Adventures in the Multiverse/
│   └── Dragon/
│       └── Ancient Time Dragon-11/
│           ├── Ancient Time Dragon.stl
│           ├── Ancient Time Dragon Left Wing.stl
│           ├── Ancient Time Dragon rigged.blend
│           └── Ancient Time Dragon.JPG
├── Monster Manual 2014/
│   ├── Giant/
│   │   ├── Hill/
│   │   │   └── Hill Giant Updated-9/
│   │   └── Storm/
│   │       └── Storm Giant Updated-10/
│   └── Monstrosity/
│       ├── Flumph-6/
│       ├── Flumph OLD-7/
│       └── Flumph Updated-8/
├── Kobold Press - Tome of Beasts/
│   ├── Fiend/
│   │   └── Demon/
│   │       └── Demon - Kishi-1/
│   └── Unsorted/
│       └── Shadhavar-4/
└── Terrain, Ships & Scatter Models/
    └── Terrain/
        └── Vehicle/
            └── Viking Longship-13/
```

Model IDs continue above the highest existing `*-<number>` directory already in the library, so repeat imports never collide.

## 🔍 File types

A directory becomes a model if it contains any of: `.stl`, `.obj`, `.3mf`, `.ctb`, `.lys`, `.photon`.

Once a directory qualifies, **every** file in it is imported regardless of extension — `.blend`, `.jpg`, `.png`, `.mix`, `.pdf`, `.txt` and anything else comes along. Extend `MESH_EXTENSIONS` near the top of the script if your collection uses other mesh formats.

## 🛠️ Modifying the dictionary

Find the `--- D&D CLASSIFICATION MAPPINGS ---` section and append keywords to the relevant line:

```bash
register_category "Plant" "plant" "myconid" "shambling mound" "treant" "YOUR_NEW_KEYWORD"
```

Tips:

* Keywords are case-insensitive and punctuation-insensitive — `Mi-Go`, `mi go` and `MI_GO` all match the keyword `mi-go`.
* Matching is whole-word, so `rat` won't match `Pirate`. Simple plurals (`+s`, `+es`) match automatically, so don't add both `giant` and `giants`.
* The longest matching keyword wins across all categories, so specific beats generic regardless of ordering — `hill giant` will always beat `giant`.
* A tag containing `/` becomes nested folders and therefore multiple Manyfold tags.
* Adding a brand-new category is just another `register_category` line.
* Re-run with `--dry-run` to check the effect before importing.

## 📋 Advanced usage

### Run in the background

```bash
nohup ./sort_minis.sh > sort_results.log 2>&1 &
tail -f sort_results.log
```

### Import everything into one collection

```bash
MANYFOLD_COLLECTION="Patreon" ./sort_minis.sh
```

### Import a different creator's archive

```bash
MANYFOLD_CREATOR="Artisan Guild" SOURCE_DIR="/path/to/artisan" ./sort_minis.sh
```

## 🔧 Troubleshooting

### "Source directory not found" / "not readable"

Check the path and permissions:

```bash
ls -ld /path/to/your/minis
chmod u+r /path/to/your/minis
```

### "Source directory is not writable (required to move files)"

Only raised in `--move` mode. Either fix the permissions or drop the flag and copy instead.

### "Already imported, skipping"

The library already contains a directory matching `<tag>/<model name>-*`. This is normal on a re-run. To force a re-import, delete the existing model directory from the library first.

### Too many models land in `Unsorted`

Grep the dry-run log for `Unsorted`, note the creature names, and add them to the appropriate `register_category` line. Named NPCs (`Drizzt Do'Urden`, `Madam Eva`, `Ismark`) are expected to stay unsorted — there's no reliable signal in a personal name, and a wrong tag is more annoying to undo in Manyfold than an absent one.

### A model got the wrong tag

Longest-match usually resolves this, but a genuinely ambiguous name may need a more specific keyword adding. For example adding `shadow beast` to `Monstrosity` will beat the generic `shadow` keyword in `Undead`.

### Script permission error

```bash
chmod +x sort_minis.sh
```

## ❓ FAQ

**Q: Will this delete anything?**
A: No. The default mode copies. `--move` relocates files and then removes the directories it emptied, but no file is ever deleted.

**Q: Can I run it multiple times?**
A: Yes. The library is pruned from the scan, and already-imported models are detected and skipped. Re-running after adding keywords only imports what's new.

**Q: My source and destination are the same path via different mounts. Is that safe?**
A: The script resolves both to absolute paths and refuses to run if they match.

**Q: How long does it take?**
A: The scan is a single `find` pass; the bulk of the time is the actual copy. Expect a few minutes for ~40,000 files on local disk, considerably longer over NAS or SMB — use `--move` on the same filesystem for a near-instant import.

**Q: Does it work on macOS?**
A: With Bash 4 or newer. macOS ships Bash 3.2, so install a newer one (`brew install bash`) and invoke it explicitly: `$(brew --prefix)/bin/bash ./sort_minis.sh`. The timestamp helper already has a BSD `date` fallback. Note the script also relies on GNU `find` (`-printf`), so `brew install findutils` and put `gfind` on your `PATH` as `find`.

**Q: Why are `Flumph`, `Flumph OLD` and `Flumph Updated` three separate models?**
A: They're genuinely different sculpts. If you only want the current versions, delete the `OLD` folders from the source before importing.

## ⚠️ Disclaimer

The default copy mode is non-destructive, but always keep a backup before running automated organisation over a large archive, and always dry run first.
