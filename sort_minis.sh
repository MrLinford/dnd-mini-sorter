#!/bin/bash

# Enable case-insensitive matching and prevent errors if no files match a keyword
shopt -s nocaseglob
shopt -s nullglob

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# --- LOGGING FUNCTIONS ---
# Uses ISO timestamps and explicit level names for easier parsing and readability.

_iso_timestamp() {
    # Cross-platform ISO 8601 timestamp (handles Linux/macOS differences)
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%N" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000")
    # Truncate nanoseconds to milliseconds (take first 23 chars + 'Z')
    printf '%s' "${ts:0:23}Z"
}

log_info() {
    printf '%s INFO  %s\n' "$( _iso_timestamp )" "$*"
}

log_warn() {
    printf '%s WARNING  %s\n' "$( _iso_timestamp )" "$*" >&2
}

log_error() {
    printf '%s ERROR  %s\n' "$( _iso_timestamp )" "$*" >&2
}

log_fatal() {
    printf '%s FATAL  %s\n' "$( _iso_timestamp )" "$*" >&2
    exit 1
}

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -d, --dry-run    Preview file moves without making changes
  -h, --help       Show this help message

Environment Variables:
  SOURCE_DIR       Override the source directory path
                   (default: /path/to/your/minis)

Examples:
  # Perform a dry run (recommended first step)
  $0 --dry-run

  # Sort files using custom source directory
  SOURCE_DIR="/path/to/minis" $0

  # Dry run with custom directory and capture output to log
  SOURCE_DIR="/path/to/minis" $0 -d 2>&1 | tee sort_preview.log
EOF
}

# --- CONFIGURATION ---
# Set your default paths here, or override via SOURCE_DIR environment variable
SOURCE_DIR="${SOURCE_DIR:-/path/to/your/minis}"
TARGET_DIR="$SOURCE_DIR/Sorted_Monsters"

# --- PARSE COMMAND LINE ARGUMENTS ---
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        -d|--dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            print_usage
            exit 1
            ;;
    esac
done

# --- VALIDATE SOURCE AND TARGET DIRECTORIES ---
if [[ ! -d "$SOURCE_DIR" ]]; then
    log_fatal "Source directory not found: $SOURCE_DIR"
fi

if [[ ! -r "$SOURCE_DIR" ]]; then
    log_fatal "Source directory is not readable: $SOURCE_DIR"
fi

if [[ "$(cd "$SOURCE_DIR" && pwd)" == "$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo '')" ]]; then
    log_fatal "Source and target directories cannot be the same"
fi

if [[ ! "$DRY_RUN" == "true" ]] && [[ ! -w "$SOURCE_DIR" ]]; then
    log_fatal "Source directory is not writable (required for live mode): $SOURCE_DIR"
fi

# --- INITIALIZE STATISTICS ---
declare -i total_moved=0
declare -i total_unsorted=0
declare -i total_skipped=0
declare -A category_counts

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN INITIATED: No files will be moved."
    log_info "Would create directory structure in: $TARGET_DIR and $SOURCE_DIR/Utility/Size Markers"
else
    log_info "LIVE RUN: Moving files..."
    
    # Create the Utility Directory
    if ! mkdir -p "$SOURCE_DIR/Utility/Size Markers"; then
        log_fatal "Failed to create directory structure at $SOURCE_DIR/Utility/Size Markers"
    fi

    # Generate the directory tree with expanded D&D 5e categories and Reference/Docs folder
    if ! mkdir -p "$TARGET_DIR"/{Aberration,Beast,Celestial,Construct,Dragon/{Chromatic,Metallic,Gem},Elemental,Fey,Fiend/{Demon,Devil,Yugoloth},Giant/{Hill,Stone,Frost,Fire,Cloud,Storm},Humanoid/{Elf,Dwarf,Halfling,Human,Goblinoid,Orc,Aarakocra,Aasimar,Dragonborn,Kenku,Lizardfolk,Tabaxi,Tortle,Triton,Yuan-ti,Sahuagin,Thri-kreen,Kobold,Gnome,Lycanthrope},Monstrosity,Ooze,Plant,Undead,Shapechanger,Swarm,Titan,Reference_Docs,Unsorted}; then
        log_fatal "Failed to create directory structure at $TARGET_DIR"
    fi
fi

log_info "Scanning directory: $SOURCE_DIR"
log_info "======================================================================"

# Create an associative array to track which files have been processed
declare -A matched_files
declare -A category_keywords
declare -a category_order

# Helper function: registers keywords for a category (for single-pass sorting)
register_category() {
    local dest=$1
    shift
    category_keywords["$dest"]=$(printf '%s\036' "$@")
    category_order+=("$dest")
    category_counts["$dest"]=0
}

# Helper function: check if a filename matches any keyword in a category
matches_category() {
    local filename="$1"
    local keywords="$2"
    local filename_lower="${filename,,}"  # Convert to lowercase
    local -a keyword_list
    local keyword
    local keyword_lower
    local IFS=$'\036'
    read -r -a keyword_list <<< "$keywords"
    filename_lower=${filename_lower//[-_]/ }
    MATCH_LENGTH=0
    
    for keyword in "${keyword_list[@]}"; do
        keyword_lower=${keyword,,}
        keyword_lower=${keyword_lower//[-_]/ }
        if [[ "$filename_lower" == *"$keyword_lower"* ]]; then
            if (( ${#keyword} > MATCH_LENGTH )); then
                MATCH_LENGTH=${#keyword}
            fi
        fi
    done

    (( MATCH_LENGTH > 0 ))
}

# Helper function: move file to category
move_file_to_category() {
    local filepath="$1"
    local dest="$2"
    local file
    file=$(basename "$filepath")
    
    if [ "$DRY_RUN" = true ]; then
        ((category_counts["$dest"]+=1))
        log_info "Would move: $file → $dest/"
    else
        if [[ -e "$TARGET_DIR/$dest/$file" ]]; then
            log_warn "Skipped duplicate file: $file already exists in $dest/"
            ((total_skipped+=1))
        elif mv -n "$filepath" "$TARGET_DIR/$dest/" 2>/dev/null; then
            log_info "Moving: $file → $dest/"
            ((category_counts["$dest"]+=1))
        else
            log_warn "Failed to move $file to $dest/"
        fi
    fi
    matched_files["$filepath"]=1
}

# --- REFINED D&D CLASSIFICATION & UTILITY MAPPINGS ---

# (0) Utility - Expanded keyword variations for size markers
register_category "../Utility/Size Markers" "huge creature marker" "gargantuan creature marker" "size marker" "creature marker" "floating" "flying marker"

# DOCUMENTATION & REFERENCE FILES
register_category "Reference_Docs" ".pdf" ".txt" ".jfif" ".jpg" ".jpeg" ".png"

# PRIMARY TYPES (1-14)

# (1) Aberrations
register_category "Aberration" "beholder" "mind flayer" "illithid" "aboleth" "chuul" "gibbering" "otyugh" "spectator" "yuan-ti" "yuan ti" "gith" "amnizu" "nothic"

# (2) Beasts
register_category "Beast" "bear" "wolf" "panther" "horse" "boar" "lion" "tiger" "leopard" "puma" "eagle" "raven" "crow" "hawk" "owl" "bird" "stirge" "velociraptor" "reptile" "snake" "lizard" "alligator" "crocodile" "turtle" "tortoise" "spider" "rat" "scorpion" "swarm" "komondor" "doggo"

# (3) Celestials
register_category "Celestial" "angel" "deva" "planetar" "solar" "pegasus" "unicorn" "empyrean" "couatl" "goodly" "lulu"

# (4) Constructs
register_category "Construct" "golem" "animated" "stone golem" "iron golem" "clay golem" "modron" "monodrone" "duodrone" "tridrone" "quadrone" "pentadrone" "homunculus" "shield guardian" "warforged" "retriever" "nimblewright" "apparatus of kwalish"

# (5) Dragons (Added variations like dracohydra, abishai, drake spell keywords)
register_category "Dragon/Chromatic" "red dragon" "blue dragon" "green dragon" "black dragon" "white dragon" "chromatic" "tiamat"
register_category "Dragon/Metallic" "gold dragon" "silver dragon" "bronze dragon" "copper dragon" "brass dragon" "metallic" "bahamut"
register_category "Dragon/Gem" "amethyst dragon" "crystal dragon" "emerald dragon" "sapphire dragon" "topaz dragon" "gem dragon"
register_category "Dragon" "wyrmling" "drake" "wyvern" "pseudodragon" "dragon" "dracohydra" "abishai"

# (6) Elementals
register_category "Elemental" "elemental" "mephit" "azer" "gargoyle" "djinn" "efreeti" "water weird" "water elemental" "fire elemental" "earth elemental" "air elemental" "xorn" "merfolk" "leshy"

# (7) Fey
register_category "Fey" "dryad" "pixie" "sprite" "hag" "satyr" "blink dog" "eladrin" "fey" "sylph" "nymph" "eilistraee"

# (8) Fiends
register_category "Fiend/Demon" "demon" "balor" "vrock" "quasit" "succubus" "glabrezu" "nalfeshnee" "demonic" "chaotic evil fiend" "bulezau" "nupperibo" "strahd" "bucephalus"
register_category "Fiend/Devil" "devil" "pit fiend" "imp" "barbed devil" "horned devil" "narzugon" "erinyes" "devilish" "lawful evil fiend"
register_category "Fiend/Yugoloth" "yugoloth" "ultroloth" "nycaloth" "arcanoloth" "neutral evil fiend"
register_category "Fiend" "gnoll" "jackalwere"

# (9) Giants
register_category "Giant/Hill" "hill giant"
register_category "Giant/Stone" "stone giant"
register_category "Giant/Frost" "frost giant"
register_category "Giant/Fire" "fire giant"
register_category "Giant/Cloud" "cloud giant"
register_category "Giant/Storm" "storm giant"
register_category "Giant" "giant" "troll" "ogre" "cyclops" "ettin" "fomorian" "titan" "giant-kin"

# (10) Humanoids
register_category "Humanoid/Elf" "elf" "drow" "eladrin" "wood elf" "high elf" "dark elf"
register_category "Humanoid/Dwarf" "dwarf" "duergar" "mountain dwarf" "hill dwarf" "derro"
register_category "Humanoid/Halfling" "halfling" "lightfoot" "stout"
register_category "Humanoid/Human" "human" "bandit" "guard" "cultist" "knight" "mage" "warrior" "fighter" "rogue" "paladin" "ranger" "cleric" "druid" "bard" "wizard" "sorcerer" "warlock" "artificer" "commoner" "noble" "jimothy" "traxigor"
register_category "Humanoid/Orc" "orc" "half-orc" "half orc" "orcish"
register_category "Humanoid/Goblinoid" "goblin" "hobgoblin" "bugbear" "goblinoid"
register_category "Humanoid/Aarakocra" "aarakocra" "aeromancer" "skirmisher" "bird-folk"
register_category "Humanoid/Aasimar" "aasimar" "aasimar cleric" "aasimar druid" "celestial-touched"
register_category "Humanoid/Dragonborn" "dragonborn" "half-dragon" "half dragon" "dragon-kin"
register_category "Humanoid/Kenku" "kenku" "crow-folk" "raven-folk"
register_category "Humanoid/Lizardfolk" "lizardfolk" "lizard folk" "lizard-man"
register_category "Humanoid/Tabaxi" "tabaxi" "cat-folk" "feline" "brandysnap"
register_category "Humanoid/Tortle" "tortle" "turtle-folk"
register_category "Humanoid/Triton" "triton" "sea-born"
register_category "Humanoid/Yuan-ti" "yuan-ti" "yuan ti" "serpent-folk" "snake-people"
register_category "Humanoid/Sahuagin" "sahuagin" "sea-devils" "aquatic-humanoid"
register_category "Humanoid/Thri-kreen" "thri-kreen" "kreen" "insectoid" "mantis-folk"
register_category "Humanoid/Kobold" "kobold" "wyrmling-kin" "dragon-spawn"
register_category "Humanoid/Gnome" "gnome" "tinker" "forest gnome" "rock gnome"
register_category "Humanoid/Lycanthrope" "wereraven" "werewolf" "werebear" "weretiger" "lycanthrope" "shapeshifter" "hybrid"

# (11) Monstrosities
register_category "Monstrosity" "owlbear" "roper" "chimera" "behir" "minotaur" "centaur" "basilisk" "medusa" "bulette" "umber hulk" "peryton" "griffon" "hippogriff" "monstrosity" "harpy" "flumph"

# (12) Oozes
register_category "Ooze" "ooze" "gelatinous" "pudding" "jelly" "black pudding" "gray ooze" "amoeba"

# (13) Plants
register_category "Plant" "plant" "myconid" "shambling mound" "blight" "treant" "vegepygmy" "awakened" "fungal"

# (14) Undead
register_category "Undead" "undead" "zombie" "skeleton" "wight" "mummy" "ghast" "ghoul" "draugr" "jiangshi" "specter" "ghost" "phantom" "wraith" "shade" "spirit" "lich" "vampire" "vampire lord" "death knight" "mummy lord" "skull lord" "dullahan" "revenant" "night hag"

# UNIVERSAL MODIFIER TAGS
register_category "Shapechanger" "shapechanger" "shapeshift" "doppelganger" "wereraven" "werewolf" "werebear" "weretiger" "mimic" "disguise" "polymorphed"
register_category "Swarm" "swarm" "swarm of" "horde" "colony" "flock"
register_category "Titan" "titan" "kraken" "tarrasque" "empyrean" "god-like" "ancient"

# --- SINGLE-PASS SORTING LOOP ---
# Expanded `find` pattern to capture 3D files alongside documentation/images

while IFS= read -r -d '' filepath; do
    file=$(basename "$filepath")
    
    # Skip if already processed
    if [[ -v matched_files["$filepath"] ]]; then
        continue
    fi
    
    # Choose the most specific matching keyword so broad terms do not win first.
    found_match=false
    best_category=""
    best_match_length=0
    for category in "${category_order[@]}"; do
        if matches_category "$file" "${category_keywords[$category]}"; then
            if (( MATCH_LENGTH > best_match_length )); then
                best_category="$category"
                best_match_length=$MATCH_LENGTH
            fi
        fi
    done

    if [[ -n "$best_category" ]]; then
        move_file_to_category "$filepath" "$best_category"
        found_match=true
    fi
    
    # If no category matched, move to Unsorted
    if ! $found_match; then
        if [ "$DRY_RUN" = true ]; then
            log_info "Would move: $file → Unsorted/"
            ((category_counts["Unsorted"]+=1))
        else
            if [[ -e "$TARGET_DIR/Unsorted/$file" ]]; then
                log_warn "Skipped duplicate file: $file already exists in Unsorted/"
                ((total_skipped+=1))
            elif mv -n "$filepath" "$TARGET_DIR/Unsorted/" 2>/dev/null; then
                log_info "Moving: $file → Unsorted/"
                ((total_unsorted+=1))
            else
                log_warn "Failed to move $file to Unsorted/"
            fi
        fi
        matched_files["$filepath"]=1
    fi
done < <(find "$SOURCE_DIR" -path "$TARGET_DIR" -prune -o -type f \( -iname "*.stl" -o -iname "*.obj" -o -iname "*.ctb" -o -iname "*.lys" -o -iname "*.zip" -o -iname "*.pdf" -o -iname "*.txt" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.jfif" -o -iname "*.png" \) -print0)

# --- PRINT SUMMARY ---
log_info "======================================================================"

if [ "$DRY_RUN" = true ]; then
    log_info "Dry run complete! Run without the -d flag to execute these moves."
    log_info "Category Breakdown:"
    for category in "${!category_counts[@]}"; do
        printf '%s INFO  %-35s %4d files\n' "$( _iso_timestamp )" "$category" "${category_counts[$category]}"
    done | sort
else
    # Calculate total moved from all categories
    for count in "${category_counts[@]}"; do
        total_moved=$((total_moved + count))
    done
    
    log_info "Sorting complete!"
    log_info "Total files sorted into categories: $total_moved"
    log_info "Total files in Unsorted: $total_unsorted"
    log_info "Total duplicate files skipped: $total_skipped"
    log_info "Grand Total: $((total_moved + total_unsorted + total_skipped)) files"
    log_info "Category Breakdown:"
    for category in "${!category_counts[@]}"; do
        printf '%s INFO  %-35s %4d files\n' "$( _iso_timestamp )" "$category" "${category_counts[$category]}"
    done | sort
    log_info "Results saved to: $TARGET_DIR"
fi