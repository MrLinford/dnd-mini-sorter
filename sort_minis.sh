#!/bin/bash

# Import a MZ4250 miniature download into a Manyfold library laid out as
#   {creator}/{collections}/{tags}/{modelName}-{modelId}
#
# A "model" is a directory that directly contains at least one 3D file. Every
# file sitting alongside it (meshes, .blend sources, renders, slicer projects)
# travels with it so Manyfold sees one model with many files.

set -euo pipefail
shopt -s nullglob

if (( BASH_VERSINFO[0] < 4 )); then
    printf 'FATAL  Bash 4 or newer is required; found %s\n' "${BASH_VERSION}" >&2
    exit 1
fi

# --- LOGGING ---

_iso_timestamp() {
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%N" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000")
    printf '%s' "${ts:0:23}Z"
}

log_info()  { printf '%s INFO  %s\n' "$(_iso_timestamp)" "$*"; }
log_warn()  { printf '%s WARNING  %s\n' "$(_iso_timestamp)" "$*" >&2; }
log_error() { printf '%s ERROR  %s\n' "$(_iso_timestamp)" "$*" >&2; }
log_fatal() { printf '%s FATAL  %s\n' "$(_iso_timestamp)" "$*" >&2; exit 1; }

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -d, --dry-run    Preview the import without touching any files
  -m, --move       Move models instead of copying them (empties SOURCE_DIR)
  -h, --help       Show this help message

Environment Variables:
  SOURCE_DIR             Directory containing the downloaded models
                         (default: /path/to/your/minis)
  MANYFOLD_LIBRARY_DIR   Destination Manyfold library root
                         (default: SOURCE_DIR/Manyfold_Library)
  MANYFOLD_CREATOR       Creator folder name (default: MZ4250)
  MANYFOLD_COLLECTION    Force a single collection name. By default each
                         top-level folder of SOURCE_DIR becomes a collection.

Examples:
  # Preview first - always recommended
  SOURCE_DIR="/mnt/user/nas/Downloads/MEGA/MZ4250 3D Miniature Models Aug 2026" \\
  MANYFOLD_LIBRARY_DIR="/mnt/user/manyfold/library" \\
      $0 --dry-run 2>&1 | tee sort_preview.log

  # Import for real; the download is left intact
  SOURCE_DIR="/mnt/user/nas/Downloads/MEGA/MZ4250 3D Miniature Models Aug 2026" \\
  MANYFOLD_LIBRARY_DIR="/mnt/user/manyfold/library" \\
      $0
EOF
}

# --- CONFIGURATION ---

SOURCE_DIR="${SOURCE_DIR:-/path/to/your/minis}"
MANYFOLD_LIBRARY_DIR="${MANYFOLD_LIBRARY_DIR:-$SOURCE_DIR/Manyfold_Library}"
MANYFOLD_CREATOR="${MANYFOLD_CREATOR:-MZ4250}"
MANYFOLD_COLLECTION="${MANYFOLD_COLLECTION:-}"

# Extensions that mark a directory as a model.
MESH_EXTENSIONS=(stl obj 3mf ctb lys photon)

DRY_RUN=false
TRANSFER_MODE=copy

for arg in "$@"; do
    case $arg in
        -d|--dry-run) DRY_RUN=true ;;
        -m|--move)    TRANSFER_MODE=move ;;
        -h|--help)    print_usage; exit 0 ;;
        *)            log_error "Unknown argument: $arg"; print_usage; exit 1 ;;
    esac
done

# --- VALIDATION ---

[[ -d "$SOURCE_DIR" ]] || log_fatal "Source directory not found: $SOURCE_DIR"
[[ -r "$SOURCE_DIR" ]] || log_fatal "Source directory is not readable: $SOURCE_DIR"
[[ -n "$MANYFOLD_CREATOR" ]] || log_fatal "MANYFOLD_CREATOR must not be empty"

for name in "$MANYFOLD_CREATOR" "$MANYFOLD_COLLECTION"; do
    [[ "$name" != /* && "$name" != *".."* ]] ||
        log_fatal "Creator and collection names must be relative and free of '..': $name"
done

SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
if [[ -d "$MANYFOLD_LIBRARY_DIR" ]]; then
    MANYFOLD_LIBRARY_DIR=$(cd "$MANYFOLD_LIBRARY_DIR" && pwd)
fi

[[ "$SOURCE_DIR" != "$MANYFOLD_LIBRARY_DIR" ]] ||
    log_fatal "Source and Manyfold library directories cannot be the same"

if [[ "$TRANSFER_MODE" == move && "$DRY_RUN" == false && ! -w "$SOURCE_DIR" ]]; then
    log_fatal "Source directory is not writable (required to move files): $SOURCE_DIR"
fi

# --- TEXT NORMALISATION & CLASSIFICATION ---

declare -A category_keywords
declare -A category_counts
declare -a category_order

# Lowercase, collapse punctuation to single spaces, trim. Result in NORMALIZED.
normalize_text() {
    local text=${1,,}
    text=${text//[![:alnum:]]/ }
    while [[ "$text" == *"  "* ]]; do text=${text//  / }; done
    text=${text# }
    NORMALIZED=${text% }
}

register_category() {
    local dest=$1
    shift
    local keyword joined=""
    for keyword in "$@"; do
        normalize_text "$keyword"
        [[ -n "$NORMALIZED" ]] && joined+="$NORMALIZED"$'\036'
    done
    category_keywords["$dest"]=$joined
    category_order+=("$dest")
    category_counts["$dest"]=0
}

# Longest whole-word keyword wins, so "hill giant" beats "giant".
# Simple plural forms match too, so "Giants" and "Sphinxes" still classify.
# Sets BEST_CATEGORY (empty when nothing matched).
best_category_for() {
    normalize_text "$1"
    local haystack=" $NORMALIZED "
    local category keyword best_length=0
    local -a keyword_list

    BEST_CATEGORY=""
    for category in "${category_order[@]}"; do
        IFS=$'\036' read -r -a keyword_list <<< "${category_keywords[$category]}"
        for keyword in "${keyword_list[@]}"; do
            [[ -n "$keyword" ]] || continue
            (( ${#keyword} > best_length )) || continue
            if [[ "$haystack" == *" $keyword "* ||
                  "$haystack" == *" ${keyword}s "* ||
                  "$haystack" == *" ${keyword}es "* ]]; then
                best_length=${#keyword}
                BEST_CATEGORY=$category
            fi
        done
    done
}

# Strip characters that are awkward in a Manyfold path segment.
sanitize_segment() {
    local text=$1
    text=${text//\//-}
    text=${text//[^[:alnum:] ._,\'\&()+-]/_}
    while [[ "$text" == *"  "* ]]; do text=${text//  / }; done
    text=${text# }
    text=${text% }
    text=${text%.}
    SANITIZED=${text:-Unnamed}
}

# --- D&D CLASSIFICATION MAPPINGS ---
# Tags are hierarchical; Manyfold turns each path segment into its own tag.

register_category "Aberration" "beholder" "death tyrant" "spectator" "beholdataur" "beerholder" "chonkholder" "pumpkinholder" "withholder" "originholder" "santa holder" "eye baller" "eyewing" "eye wyrm" "mind flayer" "mindflayer" "illithid" "owlflayer" "kangaroo flayer" "intellect devourer" "brain collector" "aboleth" "chuul" "gibbering" "gibberling" "otyugh" "gith" "githyanki" "githzerai" "amnizu" "nothic" "grell" "grick" "cloaker" "slaad" "kuo-toa" "kuo toa" "oblex" "phaerimm" "uvuudaum" "kaorti" "mooncalf" "far realm" "astral abomination" "father llymic" "decapus" "cthulhu" "star spawn" "mi-go" "shoggoth" "deep one" "leng" "voidling" "dorreq" "urochar" "gug" "voormi" "uchuulon" "wyste" "elasarian" "neothelid" "skyweaver" "nightspider" "alhoon" "ulitharid" "elder brain" "mindwitness" "brain in a jar" "gauth" "gazer" "death kiss" "xanathar" "eyedrake" "balhannoth" "choker" "chitine" "choldrith" "neogi" "morkoth" "psurlon" "quori" "overmind" "skulk" "sorrowsworn" "meazel" "gem stalker" "arcanaphage" "slithering tracker" "soulmonger" "unspeakable horror" "nyarlathotep" "azathoth" "hastur" "king in yellow" "ilvaash" "astral dreadnought" "nagpa" "anhkolox" "mozgriken" "phylaskia"

register_category "Beast" "bear" "wolf" "worg" "panther" "horse" "pony" "mule" "camel" "boar" "lion" "lioness" "tiger" "leopard" "puma" "lynx" "eagle" "raven" "crow" "hawk" "owl" "vulture" "ostrich" "stirge" "bat" "ape" "baboon" "monkey" "elephant" "mammoth" "rhinoceros" "rhino" "elk" "deer" "reindeer" "goat" "sheep" "ox" "auroch" "rothe" "pig" "swine" "badger" "weasel" "hyena" "jackel" "jackal" "armadillo" "beaver" "otter" "opossum" "raccoon" "squirrel" "porcupine" "red panda" "giraffe" "kangaroo" "moose" "walrus" "narwhal" "platypus" "chicken" "turkey" "goose" "parrot" "puffin" "crane" "snake" "viper" "adder" "lizard" "alligator" "crocodile" "gator" "turtle" "tortoise" "toad" "frog" "spider" "rat" "mouse" "scorpion" "centipede" "beetle" "wasp" "snail" "crab" "prawn" "octopus" "quipper" "shark" "whale" "seahorse" "dog" "hound" "corgi" "pug" "husky" "greyhound" "pitbull" "foxhound" "german shepard" "akita" "labradoodle" "komondor" "mastiff" "cat" "fox" "fennec fox" "rabbit" "hamster" "duck" "cow" "dolphin" "tressym" "steeder" "axe beak" "warhorse" "honse" "hippopotamus" "almiraj" "archelon" "bloodybeak" "zorbo" "felidar" "embercat" "tiacat" "kipine"
register_category "Beast/Dinosaur" "dinosaur" "velociraptor" "deinonychus" "allosaurus" "ankylosaurus" "brontosaurus" "triceratops" "stegosaurus" "tyrannosaurus" "plesiosaurus" "pteranodon" "mosasaurus" "hadrosaurus" "gallimimus" "spinosaurus" "quezalcoatlus" "dimetrodon" "deinosuchus" "anomalocaris" "trex" "t rex"

register_category "Celestial" "angel" "deva" "planetar" "solar" "pegasus" "unicorn" "alicorn" "empyrean" "couatl" "aasimar" "einherjar" "valkyrie" "buraq" "liosalfar" "ophanim" "seraphim" "shedu" "ki-rin" "phoenix" "hollyphant" "lulu" "firebird" "eidolon"

register_category "Construct" "golem" "animated" "modron" "monodrone" "duodrone" "tridrone" "quadrone" "pentadrone" "decaton" "nonaton" "octon" "septon" "hexton" "nordom" "homunculus" "shield guardian" "shambling guardian" "warforged" "gearforged" "fellforged" "helmed horror" "helmed overlord" "retriever" "nimblewright" "clockwork" "automaton" "automata" "ushabti" "living iron statue" "knight statue" "iron defender" "steel defender" "devastator" "algorith" "apparatus of kwalish" "mannequin" "snowman" "wickerman" "bombard" "colossus" "leuk-o" "sentinal" "sentinel" "marut" "myrmidon" "tin soldier" "ring servant" "iron consul" "juggernaut" "hellfire engine" "guardian portrait" "monolith" "pidlwick" "ornithopter" "siege orb" "tomb tapper" "stone cursed" "boilerdrak" "magen"

register_category "Dragon/Chromatic" "red dragon" "blue dragon" "green dragon" "black dragon" "white dragon" "chromatic" "tiamat"
register_category "Dragon/Metallic" "gold dragon" "silver dragon" "bronze dragon" "copper dragon" "brass dragon" "mithral dragon" "metallic" "bahamut"
register_category "Dragon/Gem" "amethyst" "crystal dragon" "emerald" "sapphire" "topaz" "moonstone" "gem dragon" "greatwyrm"
register_category "Dragon" "dragon" "wyrmling" "drake" "wyvern" "pseudodragon" "dracohydra" "abishai" "linnorm" "zmey" "drakon" "amphiptere" "jaculus" "lindwurm" "draconian" "draconic" "sea serpent" "serpentir" "piasa" "dragonnel" "wormling" "eyedrake dragon" "faerie dragon" "fairy dragon"

register_category "Elemental" "elemental" "mephit" "azer" "magmin" "thoqqua" "gargoyle" "djinn" "djinni" "efreeti" "marid" "dao" "genie" "water weird" "xorn" "galeb duhr" "invisible stalker" "salamander" "chronalmental" "firegeist" "sandman" "spark" "cryonax" "geonid" "pech" "eternal flame" "crushing wave" "howling hatred" "galvanice weird" "maegera" "elder tempest" "nereid" "water elemental" "bitter breath"

register_category "Fey" "dryad" "pixie" "sprite" "hag" "satyr" "blink dog" "eladrin" "fey" "sylph" "nymph" "korred" "redcap" "red cap" "clurichaun" "leprechaun" "leshy" "alseid" "bereginyas" "vila" "mavka" "boloti" "domovoi" "domovoy" "kikimora" "aridni" "shadow fey" "tooth fairy" "fairy queen" "curupira" "marshwiggle" "kitsune" "tanuki" "tengu" "kappa" "jackalope" "quickling" "darkling" "meenlock" "brigganock" "chwinga" "campestri" "wynling" "boggle" "puckwudgie" "nilbog" "siren" "mad cap" "coven" "will o wisp" "will of the feywild" "blightstraw" "nightshade" "moongrave" "pollenella" "garlicle" "witchlight" "feywild"

register_category "Fiend/Demon" "demon" "balor" "vrock" "quasit" "succubus" "glabrezu" "nalfeshnee" "hezrou" "marilith" "maralith" "dretch" "goristro" "chasme" "manes" "barlgura" "yochlol" "myrmyxicus" "bulezau" "nupperibo" "demon lord" "sap demon" "malakbel" "psoglav" "rubezahl" "berstuc" "kishi" "graz'zt" "orcus" "demogorgon" "zuggtmoy" "juiblex" "baphomet" "spyder fiend" "abyssal wretch" "alkilith" "armanite" "babau" "nabassu" "draegloth" "molydeus" "rutterkin" "sibriex" "wastrilith" "shoosuva" "maurezhi" "dybbuk" "yeenoghu" "fraz-urb" "kostchtchie" "zuggtmoy" "tanarukk" "cistern fiend" "master of cruelties" "larvae" "ygorl" "oublivae" "vargouille" "incubus" "sea spawn"
register_category "Fiend/Devil" "devil" "pit fiend" "imp" "lemure" "barbed devil" "horned devil" "narzugon" "erinyes" "chort" "koralk" "orobas" "zariel" "spinagon" "gelugon" "amnizu devil" "bael" "bel" "geryon" "hutijin" "moloch" "titivilus" "merregon" "orthon" "bane" "hellrider" "abishai devil"
register_category "Fiend/Yugoloth" "yugoloth" "ultroloth" "nycaloth" "arcanaloth" "mezzoloth" "shator" "volguloth" "daemon" "ceustodaemon" "canoloth" "dhergoloth" "hydroloth" "merrenoloth" "oinoloth" "yagnoloth"
register_category "Fiend" "gnoll" "jackalwere" "cambion" "hell hound" "barghest" "nightmare" "rakshasa" "stench kow" "lady of pain"

register_category "Giant/Hill" "hill giant"
register_category "Giant/Stone" "stone giant" "dodkong"
register_category "Giant/Frost" "frost giant" "snowmancer" "jotun" "juton" "thursir"
register_category "Giant/Fire" "fire giant"
register_category "Giant/Cloud" "cloud giant"
register_category "Giant/Storm" "storm giant"
register_category "Giant" "giant" "troll" "ogre" "oni" "cyclops" "ettin" "fomorian" "titan" "giant-kin" "hraesvelgr" "athach" "goliath" "verbeeg" "grolantor" "stronmaus" "shockstomper"

register_category "Humanoid/Elf" "elf" "elves" "elven" "elvish" "drow" "wood elf" "high elf" "dark elf" "shadar-kai" "shadar kai"
register_category "Humanoid/Dwarf" "dwarf" "dwarves" "dwarven" "duergar" "mountain dwarf" "hill dwarf" "derro"
register_category "Humanoid/Halfling" "halfling" "lightfoot" "stout"
register_category "Humanoid/Human" "human" "bandit" "guard" "cultist" "cult fanatic" "initiate" "knight" "mage" "warrior" "fighter" "rogue" "paladin" "ranger" "cleric" "druid" "archdruid" "bard" "wizard" "sorcerer" "warlock" "artificer" "abjurer" "conjurer" "diviner" "enchanter" "evoker" "illusionist" "necromancer" "transmuter" "spellcaster" "commoner" "noble" "monk" "barbarian" "assassin" "archer" "veteran" "berserker" "acolyte" "priest" "witch" "gladiator" "samurai" "ninja" "pirate" "thug" "spy" "scout" "sage" "expert" "champion" "executioner" "jester" "blacksmith" "barkeep" "barmaid" "baker" "chef" "adventurer" "plague doctor" "dungeon master" "gunslinger" "sidekick" "amazon" "ballerina" "martyr" "wayfarer" "mysterious merchant" "swashbuckler" "blackguard" "warlord" "apprentice" "shaman" "ruffian" "brigand" "sniper" "hoplite" "performer" "adept" "master thief" "abbot" "anchorite" "uthgardt" "redbrand" "lava child" "deep scion"
register_category "Humanoid/Tiefling" "tiefling" "dhampir"
register_category "Humanoid/Firbolg" "firbolg"
register_category "Humanoid/Orc" "orc" "orog" "half-orc" "half orc" "orcish"
register_category "Humanoid/Goblinoid" "goblin" "hobgoblin" "bugbear" "goblinoid" "fremlin" "gremlin" "meepo" "xvart" "flind" "gremishka"
register_category "Humanoid/Aarakocra" "aarakocra" "bird-folk" "batfolk" "mothfolk"
register_category "Humanoid/Dragonborn" "dragonborn" "half-dragon" "half dragon"
register_category "Humanoid/Kenku" "kenku" "ravenfolk" "crow-folk" "raven-folk"
register_category "Humanoid/Lizardfolk" "lizardfolk" "lizard folk" "croc folk" "xulgath" "aapoph"
register_category "Humanoid/Tabaxi" "tabaxi" "cat-folk" "nkosi"
register_category "Humanoid/Tortle" "tortle" "turtle-folk"
register_category "Humanoid/Triton" "triton" "locathah" "merfolk" "river siren"
register_category "Humanoid/Yuan-ti" "yuan-ti" "yuan ti" "serpent-folk" "snake-people"
register_category "Humanoid/Sahuagin" "sahuagin" "sea-devils"
register_category "Humanoid/Bullywug" "bullywug" "grung" "angulotl"
register_category "Humanoid/Thri-kreen" "thri-kreen" "kreen" "kruthik" "tosculi" "mantis-folk" "millitaur" "roachling" "girtablilu"
register_category "Humanoid/Kobold" "kobold"
register_category "Humanoid/Gnome" "gnome" "svirfneblin" "snirfneblin" "tinker" "forest gnome" "rock gnome"
register_category "Humanoid/Ratfolk" "ratfolk" "doppelrat" "lemurfolk" "erina" "bearfolk" "mousefolk" "pug folk" "octofolk" "prawnfolk" "snail folk" "gourd folk" "goatling" "harengon" "mongrelfolk" "pterafolk" "aldani" "lobsterfolk" "giff" "grung"
register_category "Humanoid/Lycanthrope" "werewolf" "werebear" "weretiger" "wereboar" "wererat" "wereraven" "wereshark" "werepanther" "werebuffalo" "werebulette" "werecapybara" "weresquirrel" "werereindeer" "wereturkery" "werepomeranian" "lycanthrope" "bouda" "loup garou" "nightgarm"
register_category "Humanoid/Grimlock" "grimlock" "troglodyte" "quaggoth" "cynidicean"
register_category "Humanoid/Plasmoid" "plasmoid"

register_category "Monstrosity" "owlbear" "roper" "chimera" "behir" "minotaur" "centaur" "taur" "basilisk" "medusa" "gorgon" "bulette" "umber hulk" "peryton" "griffon" "demigryph" "hippogriff" "hippocampus" "monstrosity" "harpy" "flumph" "piercer" "purple worm" "manticore" "anticore" "kraken" "hydra" "necrohydra" "yeti" "ankheg" "carrion crawler" "cockatrice" "cockitrice" "darkmantle" "displacer beast" "drider" "ettercap" "hook horror" "remorhaz" "roc" "rust monster" "sphinx" "androsphinx" "gynosphinx" "naga" "lamia" "merrow" "leucrotta" "serpopard" "sandwyrm" "angler worm" "rime worm" "sathaq worm" "amphisbaena" "amphibaena" "dogmole" "gbahali" "subek" "isonade" "mahoru" "titanoboa" "akhlut" "krampus" "cerberus" "sleipnir" "simurgh" "aurumvorax" "tarrasqling" "burrowshark" "carrion" "grim reaper" "afanc" "banderhobb" "catoblepas" "cave fisher" "chupacabra" "froghemoth" "girallon" "gray render" "hodag" "howler" "jabberwock" "kamadan" "kelpie" "leviathan" "mantrap" "mishipeshu" "su-monster" "thessalhydra" "tlincalli" "tromokratis" "trapper" "typhon" "zaratan" "steel predator" "woe strider" "krasis" "jaculi" "kalka-kylla" "sky swimmer" "bore worm" "ixitxachitl" "crocobear" "rhinobear" "sharkenbear" "liondrake" "liontaur" "mantaur" "omnitaur" "moosataur" "badgertaur" "centaurtaur" "manticorgi" "bearadactyl" "hawkfox" "pandalope" "beehemoth" "vermin behemoth" "eblis" "skeljaskrimsli" "raggadragga" "shago" "kython" "hellwasp" "aspis"

register_category "Ooze" "ooze" "gooze" "gelatinous" "pudding" "jelly" "slime" "amoeba" "oozasis" "treacle" "blob of annihilation" "sarcophagus"

register_category "Plant" "plant" "myconid" "shrieker" "gas spore" "violet fungus" "fungus" "fungal" "shambling mound" "blight" "treant" "vegepygmy" "awakened tree" "awakened shrub" "awakend shrub" "cactid" "ravenala" "vine lord" "duskthorn" "citrullus" "vesiculosa" "carniflower" "rot grub" "zurkhwood" "araumycos" "corpse flower" "singing tree" "stool" "wood woad" "thorn slinger" "yellow musk creeper" "spore servant" "lily pad" "frond" "mold" "twig blight" "needle blight" "vine blight"

register_category "Undead" "undead" "zombie" "skeleton" "wight" "mummy" "ghast" "ghoul" "darakhul" "draugr" "jiangshi" "specter" "spectre" "ghost" "phantom" "wraith" "shade" "shadow" "spirit" "lich" "dracolich" "demilich" "vampire" "strahd" "death knight" "skull lord" "dullahan" "headless horseman" "revenant" "flameskull" "crawling claw" "haunt" "banshee" "myling" "vaettir" "haugbui" "edimmu" "koschei" "fext" "shroud" "dissimortuum" "bone collective" "corpse mound" "mask wight" "bonedrinker" "penanggalan" "gashadokuro" "kyuss" "ulgurstasta" "atropal" "bone naga" "nightwing" "deathsnatcher" "allip" "bodak" "boneclaw" "boneless" "cadaver collector" "coldlight walker" "corpse bride" "corpse thief" "cyanwraith" "deathlock" "death s head" "duskwalker" "gallows speaker" "nightwalker" "nosferatu" "poltergeist" "stirgoi" "tomb guardian" "vampiric mist" "carrionette" "murder doll" "living doll" "returned" "yestabrod" "mormesk" "argynvost" "skeljaskr" "wight lord"

register_category "Deity" "deity" "diety" "god" "goddess" "demigod" "godslayer" "archdevil" "archduke" "arch fey" "archfey" "tharizdun" "vecna" "iuz" "lolth" "myrkul" "tyr" "malar" "loviatar" "eilistraee" "kukulkan" "wadjet" "sun wukong" "cronus" "blibdoolpoolp" "zargon" "celestial king" "aspect of atropus" "hyperion" "auril" "talos" "erebos" "ephara" "tecuziztecatl" "tzitzimitl" "rak tulkhesh" "sul khatesh" "dagon"

register_category "Terrain/Vehicle" "galleon" "longship" "canoe" "wagon" "carriage" "chariot" "ship" "spelljammer" "nautiloid" "catapult" "ballista" "landing craft" "sleigh" "hut" "taco truck"
register_category "Terrain/Scatter" "statue" "barrel" "tent" "bed" "couch" "armoire" "book shelf" "bookshelf" "fireplace" "toilet" "doorway" "door" "chest" "grave" "gazebo" "tree stump" "candles" "piano" "rug" "cake" "christmas tree" "jack o lantern" "scarecrow" "summoning circle" "tavern table" "pile of skulls" "scatter" "eggs" "teddy bear" "pot of gold" "cavern entrance" "gong" "coin" "crest" "weapons" "props" "body parts" "base bodies" "base rigged bodies" "ring of winter" "skelton key" "balloon" "oil can"

register_category "Spell Effect" "spiritual weapon" "flaming sphere" "floating disk" "wall of fire" "wind wall" "fireball radius" "bigby s hand" "flying carpet" "hurricane"

register_category "Utility/Size Markers" "size marker" "creature marker" "size markers" "dead size markers"

register_category "Shapechanger" "shapechanger" "shapeshifter" "doppelganger" "mimic" "polymorphed" "hulking whelp" "morphoi"
register_category "Swarm" "swarm" "horde" "colony" "flock" "cobbleswarm" "swarm of"
register_category "Titan" "tarrasque" "god-like"

# --- MODEL ID ALLOCATION ---

declare -i next_model_id=1

initialise_model_id() {
    local directory existing max_id=0
    [[ -d "$MANYFOLD_LIBRARY_DIR" ]] || return 0

    while IFS= read -r -d '' directory; do
        if [[ "$(basename "$directory")" =~ -([0-9]+)$ ]]; then
            existing=$((10#${BASH_REMATCH[1]}))
            (( existing > max_id )) && max_id=$existing
        fi
    done < <(find "$MANYFOLD_LIBRARY_DIR" -type d -print0)

    next_model_id=$((max_id + 1))
}

# --- IMPORT ---

declare -i total_models=0
declare -i total_files=0
declare -i total_skipped=0
declare -i total_failed=0

import_model_directory() {
    local model_dir=$1
    local relative collection subpath model_name tag destination destination_parent
    local -a existing files

    relative=""
    [[ "$model_dir" != "$SOURCE_DIR" ]] && relative=${model_dir#"$SOURCE_DIR"/}

    if [[ -z "$relative" ]]; then
        collection="Misc"
        subpath=""
    elif [[ "$relative" == */* ]]; then
        collection=${relative%%/*}
        subpath=${relative#*/}
    else
        collection=$relative
        subpath=""
    fi
    [[ -n "$MANYFOLD_COLLECTION" ]] && collection=$MANYFOLD_COLLECTION

    model_name=$(basename "$model_dir")

    # Prefer a match on the model's own name; only fall back to its ancestors so
    # a collection like "Kobold Press - Tome of Beasts" can't tag everything.
    best_category_for "$model_name"
    tag=$BEST_CATEGORY
    if [[ -z "$tag" && -n "$subpath" ]]; then
        best_category_for "${subpath//\// }"
        tag=$BEST_CATEGORY
    fi
    tag=${tag:-Unsorted}

    sanitize_segment "$collection"; collection=$SANITIZED
    sanitize_segment "$model_name"; model_name=$SANITIZED

    local tag_path="" segment saved_ifs=$IFS
    IFS='/'
    for segment in $tag; do
        IFS=$saved_ifs
        sanitize_segment "$segment"
        tag_path+="$SANITIZED/"
        IFS='/'
    done
    IFS=$saved_ifs
    tag_path=${tag_path%/}

    destination_parent="$MANYFOLD_LIBRARY_DIR/$MANYFOLD_CREATOR/$collection/$tag_path"

    existing=("$destination_parent/$model_name"-[0-9]*)
    if (( ${#existing[@]} > 0 )); then
        log_warn "Already imported, skipping: $collection/$tag_path/$model_name"
        ((total_skipped += 1))
        return 0
    fi

    files=()
    local entry
    for entry in "$model_dir"/*; do
        [[ -f "$entry" ]] && files+=("$entry")
    done
    (( ${#files[@]} > 0 )) || return 0

    destination="$destination_parent/$model_name-$next_model_id"
    ((next_model_id += 1))
    ((total_models += 1))
    category_counts["$tag"]=$(( ${category_counts["$tag"]:-0} + 1 ))
    ((total_files += ${#files[@]}))

    if [[ "$DRY_RUN" == true ]]; then
        log_info "Would import ${#files[@]} file(s): ${destination#"$MANYFOLD_LIBRARY_DIR"/}"
        return 0
    fi

    if ! mkdir -p "$destination"; then
        log_error "Failed to create $destination"
        ((total_failed += 1))
        return 0
    fi

    if [[ "$TRANSFER_MODE" == copy ]]; then
        if ! cp -n -- "${files[@]}" "$destination/"; then
            log_error "Failed to copy files into $destination"
            ((total_failed += 1))
            return 0
        fi
    elif ! mv -n -- "${files[@]}" "$destination/"; then
        log_error "Failed to move files into $destination"
        ((total_failed += 1))
        return 0
    fi

    log_info "Imported ${#files[@]} file(s): ${destination#"$MANYFOLD_LIBRARY_DIR"/}"
}

# --- MAIN ---

if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY RUN: nothing will be created, moved or copied."
else
    log_info "LIVE RUN: ${TRANSFER_MODE}ing models into the Manyfold library."
    mkdir -p "$MANYFOLD_LIBRARY_DIR" || log_fatal "Failed to create $MANYFOLD_LIBRARY_DIR"
fi

log_info "Source:  $SOURCE_DIR"
log_info "Library: $MANYFOLD_LIBRARY_DIR"
log_info "Layout:  $MANYFOLD_CREATOR/{collection}/{tags}/{modelName}-{modelId}"
log_info "======================================================================"

initialise_model_id

mesh_predicate=()
for extension in "${MESH_EXTENSIONS[@]}"; do
    (( ${#mesh_predicate[@]} > 0 )) && mesh_predicate+=(-o)
    mesh_predicate+=(-iname "*.$extension")
done

while IFS= read -r -d '' model_dir; do
    import_model_directory "$model_dir"
done < <(
    find "$SOURCE_DIR" -path "$MANYFOLD_LIBRARY_DIR" -prune -o \
        -type f \( "${mesh_predicate[@]}" \) -printf '%h\0' |
        sort -z -u
)

if [[ "$DRY_RUN" == false && "$TRANSFER_MODE" == move ]]; then
    find "$SOURCE_DIR" -path "$MANYFOLD_LIBRARY_DIR" -prune -o \
        -mindepth 1 -type d -empty -delete 2>/dev/null || true
fi

# --- SUMMARY ---

log_info "======================================================================"
if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry run complete. Re-run without -d to perform the import."
else
    log_info "Import complete."
fi
log_info "Models imported:        $total_models"
log_info "Files transferred:      $total_files"
log_info "Models already present: $total_skipped"
log_info "Models failed:          $total_failed"
log_info "Tag breakdown:"
for category in "${!category_counts[@]}"; do
    (( category_counts["$category"] > 0 )) || continue
    printf '%s INFO  %-35s %4d models\n' "$(_iso_timestamp)" "$category" "${category_counts[$category]}"
done | sort
