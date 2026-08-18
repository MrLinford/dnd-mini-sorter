#!/bin/bash

# Enable case-insensitive matching and prevent errors if no files match a keyword
shopt -s nocaseglob
shopt -s nullglob

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# --- LOGGING FUNCTIONS ---
# Uses ISO timestamps and explicit level names for easier parsing and readability.

_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
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

# --- SET YOUR FULL PATHS HERE ---
SOURCE_DIR="/mnt/user/nas/3D Models/MZ4250 3D Miniature Models Aug 2026"
TARGET_DIR="$SOURCE_DIR/Sorted_Monsters"

# --- PARSE COMMAND LINE ARGUMENTS ---
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        -d|--dry-run)
            DRY_RUN=true
            ;;
        *)
            log_warn "Unknown argument: $arg"
            ;;
    esac
done

# --- VALIDATE SOURCE DIRECTORY ---
if [[ ! -d "$SOURCE_DIR" ]]; then
    log_fatal "Source directory not found: $SOURCE_DIR"
fi

# --- INITIALIZE STATISTICS ---
declare -i total_moved=0
declare -i total_unsorted=0
declare -A category_counts

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN INITIATED: No files will be moved."
    log_info "Would create directory structure in: $TARGET_DIR"
else
    log_info "LIVE RUN: Moving files..."
    # Generate the directory tree with D&D 5e Official Creature Type classification
    # 14 Primary Types + Official Sub-categories (Tags) + Universal Modifiers
    if ! mkdir -p "$TARGET_DIR"/{Aberration,Beast,Celestial,Construct,Dragon/{Chromatic,Metallic,Gem},Elemental,Fey,Fiend/{Demon,Devil,Yugoloth},Giant/{Hill,Stone,Frost,Fire,Cloud,Storm},Humanoid/{Elf,Dwarf,Halfling,Human,Goblinoid,Orc,Aarakocra,Aasimar,Dragonborn,Kenku,Lizardfolk,Tabaxi,Tortle,Triton,Yuan-ti,Sahuagin,Thri-kreen,Kobold,Gnome,Lycanthrope},Monstrosity,Ooze,Plant,Undead,Shapechanger,Swarm,Titan,Unsorted}; then
        log_fatal "Failed to create directory structure at $TARGET_DIR"
    fi
fi

log_info "Scanning directory: $SOURCE_DIR"
log_info "======================================================================"

# Create an associative array to track which files have been processed
declare -A matched_files

# Helper function: sorts files into their target folder (recursively searches subdirectories)
sort_category() {
    local dest=$1
    shift
    local category_moved=0
    
    for keyword in "$@"; do
        # Use find to recursively search all subdirectories for keyword matches
        while IFS= read -r -d '' filepath; do
            file=$(basename "$filepath")
            
            # Track by full path so duplicate basenames in different directories are not skipped.
            if [[ ! -v matched_files["$filepath"] ]]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "Would move: $file → $dest/"
                else
                    if mv -n "$filepath" "$TARGET_DIR/$dest/" 2>/dev/null; then
                        log_info "Moving: $file → $dest/"
                        ((category_moved++))
                    else
                        log_warn "Failed to move $file to $dest/"
                    fi
                fi
                matched_files["$filepath"]=1
            fi
        done < <(find "$SOURCE_DIR" -path "$TARGET_DIR" -prune -o -type f \( -iname "*$keyword*.stl" -o -iname "*$keyword*.obj" -o -iname "*$keyword*.ctb" -o -iname "*$keyword*.lys" -o -iname "*$keyword*.zip" \) -print0)
    done
    
    category_counts["$dest"]=$category_moved
}

# --- D&D 5e OFFICIAL CREATURE TYPE CLASSIFICATION ---
# Based on D&D 5th Edition with 14 Primary Types, Official Tags, and Universal Modifiers
# Reference: Player's Handbook, Monster Manual

# PRIMARY TYPES (1-14)

# (1) Aberrations - Alien entities and bizarre creatures, often from Far Realm or Underdark
sort_category "Aberration" "beholder" "mind flayer" "illithid" "aboleth" "chuul" "gibbering" "otyugh" "spectator" "yuan-ti" "yuan ti"

# (2) Beasts - Non-humanoid animals, both mundane and giant variants
sort_category "Beast" "bear" "wolf" "panther" "horse" "boar" "lion" "tiger" "leopard" "puma" "eagle" "raven" "crow" "hawk" "owl" "bird" "stirge" "velociraptor" "reptile" "snake" "lizard" "alligator" "crocodile" "turtle" "tortoise" "spider" "rat" "scorpion" "swarm"

# (3) Celestials - Holy or good-aligned beings native to Upper Planes
sort_category "Celestial" "angel" "deva" "planetar" "solar" "pegasus" "unicorn" "empyrean" "couatl" "goodly"

# (4) Constructs - Artificially created or animated beings
sort_category "Construct" "golem" "animated" "stone golem" "iron golem" "clay golem" "modron" "monodrone" "duodrone" "tridrone" "quadrone" "pentadrone" "homunculus" "shield guardian" "warforged" "retriever" "nimblewright"

# (5) Dragons - Powerful, highly intelligent reptilian creatures
# Chromatic Dragons - Chaotic evil (Red, Blue, Green, Black, White)
sort_category "Dragon/Chromatic" "red dragon" "blue dragon" "green dragon" "black dragon" "white dragon" "chromatic" "tiamat"
# Metallic Dragons - Good-aligned (Gold, Silver, Bronze, Copper, Brass)
sort_category "Dragon/Metallic" "gold dragon" "silver dragon" "bronze dragon" "copper dragon" "brass dragon" "metallic" "bahamut"
# Gem Dragons - Rare (Amethyst, Crystal, Emerald, Sapphire, Topaz)
sort_category "Dragon/Gem" "amethyst dragon" "crystal dragon" "emerald dragon" "sapphire dragon" "topaz dragon" "gem dragon"
# Dragon variants
sort_category "Dragon" "wyrmling" "drake" "wyvern" "pseudodragon" "dragon" "dragon-kin"

# (6) Elementals - Beings composed of fundamental forces
sort_category "Elemental" "elemental" "mephit" "azer" "gargoyle" "djinn" "efreeti" "water weird" "water elemental" "fire elemental" "earth elemental" "air elemental" "xorn"

# (7) Fey - Creatures of magic and nature, tied to Feywild
sort_category "Fey" "dryad" "pixie" "sprite" "hag" "satyr" "blink dog" "eladrin" "fey" "sylph" "nymph"

# (8) Fiends - Evil beings native to Lower Planes
# Demons - Chaotic evil fiends
sort_category "Fiend/Demon" "demon" "balor" "vrock" "quasit" "succubus" "glabrezu" "nalfeshnee" "demonic" "chaotic evil fiend"
# Devils - Lawful evil fiends
sort_category "Fiend/Devil" "devil" "pit fiend" "imp" "barbed devil" "horned devil" "narzugon" "erinyes" "devilish" "lawful evil fiend"
# Yugoloths - Neutral evil fiends
sort_category "Fiend/Yugoloth" "yugoloth" "ultroloth" "nycaloth" "arcanoloth" "neutral evil fiend"

# (9) Giants - Massive humanoid-like beings
# True Giants hierarchy (Hill, Stone, Frost, Fire, Cloud, Storm)
sort_category "Giant/Hill" "hill giant"
sort_category "Giant/Stone" "stone giant"
sort_category "Giant/Frost" "frost giant"
sort_category "Giant/Fire" "fire giant"
sort_category "Giant/Cloud" "cloud giant"
sort_category "Giant/Storm" "storm giant"
# Other giant-like creatures
sort_category "Giant" "giant" "troll" "ogre" "cyclops" "ettin" "fomorian" "titan" "giant-kin"

# (10) Humanoids - Standard bipedal peoples of the multiverse (most diverse category)
sort_category "Humanoid/Elf" "elf" "drow" "eladrin" "wood elf" "high elf" "dark elf"
sort_category "Humanoid/Dwarf" "dwarf" "duergar" "mountain dwarf" "hill dwarf"
sort_category "Humanoid/Halfling" "halfling" "lightfoot" "stout"
sort_category "Humanoid/Human" "human" "bandit" "guard" "cultist" "knight" "mage" "warrior" "fighter" "rogue" "paladin" "ranger" "cleric" "druid" "bard" "wizard" "sorcerer" "warlock" "artificer" "commoner" "noble"
sort_category "Humanoid/Goblinoid" "goblin" "hobgoblin" "bugbear" "goblinoid"
sort_category "Humanoid/Orc" "orc" "half-orc" "half orc" "orcish"
sort_category "Humanoid/Aarakocra" "aarakocra" "aeromancer" "skirmisher" "bird-folk"
sort_category "Humanoid/Aasimar" "aasimar" "aasimar cleric" "aasimar druid" "celestial-touched"
sort_category "Humanoid/Dragonborn" "dragonborn" "half-dragon" "half dragon" "dragon-kin"
sort_category "Humanoid/Kenku" "kenku" "crow-folk" "raven-folk"
sort_category "Humanoid/Lizardfolk" "lizardfolk" "lizard folk" "lizard-man"
sort_category "Humanoid/Tabaxi" "tabaxi" "cat-folk" "feline"
sort_category "Humanoid/Tortle" "tortle" "turtle-folk"
sort_category "Humanoid/Triton" "triton" "sea-born"
sort_category "Humanoid/Yuan-ti" "yuan-ti" "yuan ti" "serpent-folk" "snake-people"
sort_category "Humanoid/Sahuagin" "sahuagin" "sea-devils" "aquatic-humanoid"
sort_category "Humanoid/Thri-kreen" "thri-kreen" "kreen" "insectoid" "mantis-folk"
sort_category "Humanoid/Kobold" "kobold" "wyrmling-kin" "dragon-spawn"
sort_category "Humanoid/Gnome" "gnome" "tinker" "forest gnome" "rock gnome"
sort_category "Humanoid/Lycanthrope" "wereraven" "werewolf" "werebear" "weretiger" "lycanthrope" "shapeshifter" "hybrid"

# (11) Monstrosities - Unnatural creatures defying normal biology
sort_category "Monstrosity" "mimic" "owlbear" "roper" "chimera" "behir" "minotaur" "centaur" "satyr" "basilisk" "medusa" "doppelganger" "bulette" "umber hulk" "nothic" "peryton" "griffon" "hippogriff" "monstrosity" "griffon"

# (12) Oozes - Shapeless gelatinous predators
sort_category "Ooze" "ooze" "gelatinous" "pudding" "jelly" "black pudding" "gray ooze" "amoeba"

# (13) Plants - Botanical or fungal creatures capable of movement
sort_category "Plant" "plant" "myconid" "shambling mound" "blight" "treant" "vegepygmy" "awakened" "fungal"

# (14) Undead - Once-living creatures brought back by necromantic magic
sort_category "Undead" "undead" "zombie" "skeleton" "wight" "mummy" "ghast" "ghoul" "draugr" "jiangshi" "specter" "ghost" "phantom" "wraith" "shade" "spirit" "lich" "vampire" "vampire lord" "death knight" "mummy lord" "skull lord" "dullahan" "revenant" "night hag"

# UNIVERSAL MODIFIER TAGS (Can be applied to any creature type)

# Shapechanger Tag - Any creature capable of altering physical form
sort_category "Shapechanger" "shapechanger" "shapeshift" "doppelganger" "wereraven" "werewolf" "werebear" "weretiger" "mimic" "disguise" "polymorphed"

# Swarm Tag - Many tiny creatures moving as one unit
sort_category "Swarm" "swarm" "swarm of" "horde" "colony" "flock"

# Titan Tag - God-like ancient powerful beings
sort_category "Titan" "titan" "kraken" "tarrasque" "empyrean" "god-like" "ancient"

# Process anything left over into an "Unsorted" folder (recursively searches subdirectories)
while IFS= read -r -d '' filepath; do
    file=$(basename "$filepath")
    if [[ ! -v matched_files["$filepath"] ]]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "Would move: $file → Unsorted/"
        else
            if mv -n "$filepath" "$TARGET_DIR/Unsorted/" 2>/dev/null; then
                log_info "Moving: $file → Unsorted/"
                ((total_unsorted++))
            else
                log_warn "Failed to move $file to Unsorted/"
            fi
        fi
        matched_files["$filepath"]=1
    fi
done < <(find "$SOURCE_DIR" -path "$TARGET_DIR" -prune -o -type f \( -iname "*.stl" -o -iname "*.obj" -o -iname "*.ctb" -o -iname "*.lys" -o -iname "*.zip" \) -print0)

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
    log_info "Grand Total: $((total_moved + total_unsorted)) files"
    log_info "Category Breakdown:"
    for category in "${!category_counts[@]}"; do
        printf '%s INFO  %-35s %4d files\n' "$( _iso_timestamp )" "$category" "${category_counts[$category]}"
    done | sort
    log_info "Results saved to: $TARGET_DIR"
fi