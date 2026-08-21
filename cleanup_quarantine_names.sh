#!/bin/bash

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-/path/to/your/minis}"
QUARANTINE_DIR="${QUARANTINE_DIR:-$SOURCE_DIR/Quarantine}"
DRY_RUN=false

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Rename old quarantine duplicate filenames so the suffix appears before the extension.

Options:
  -d, --dry-run    Preview renames without making changes
  -h, --help       Show this help message

Environment Variables:
  SOURCE_DIR       Source directory containing Quarantine/
  QUARANTINE_DIR   Override the quarantine directory path

Examples:
  SOURCE_DIR="/path/to/minis" $0 --dry-run
  SOURCE_DIR="/path/to/minis" $0
EOF
}

log_info() {
    printf 'INFO  %s\n' "$*"
}

log_warn() {
    printf 'WARNING  %s\n' "$*" >&2
}

for arg in "$@"; do
    case "$arg" in
        -d|--dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_warn "Unknown argument: $arg"
            print_usage
            exit 1
            ;;
    esac
done

if [[ ! -d "$QUARANTINE_DIR" ]]; then
    log_warn "Quarantine directory not found: $QUARANTINE_DIR"
    exit 1
fi

if [[ ! -r "$QUARANTINE_DIR" ]]; then
    log_warn "Quarantine directory is not readable: $QUARANTINE_DIR"
    exit 1
fi

if [[ "$DRY_RUN" == false && ! -w "$QUARANTINE_DIR" ]]; then
    log_warn "Quarantine directory is not writable: $QUARANTINE_DIR"
    exit 1
fi

declare -i renamed=0
declare -i skipped=0

while IFS= read -r -d '' filepath; do
    file="${filepath##*/}"

    if [[ "$file" =~ ^(.+)(\.[^.]+)\.duplicate\.([0-9]+)$ ]]; then
        stem="${BASH_REMATCH[1]}"
        extension="${BASH_REMATCH[2]}"
        suffix="${BASH_REMATCH[3]}"
        target="$QUARANTINE_DIR/${stem}.duplicate.${suffix}${extension}"
    elif [[ "$file" =~ ^(.+)\.duplicate\.([0-9]+)$ ]]; then
        stem="${BASH_REMATCH[1]}"
        suffix="${BASH_REMATCH[2]}"
        extension=""
        target="$QUARANTINE_DIR/${stem}.duplicate.${suffix}${extension}"
    else
        continue
    fi

    if [[ "$target" == "$filepath" ]]; then
        continue
    fi

    if [[ -e "$target" ]]; then
        log_warn "Skipped because target exists: $file -> ${target##*/}"
        ((skipped+=1))
    elif [[ "$DRY_RUN" == true ]]; then
        log_info "Would rename: $file -> ${target##*/}"
        ((renamed+=1))
    elif mv -- "$filepath" "$target"; then
        log_info "Renamed: $file -> ${target##*/}"
        ((renamed+=1))
    else
        log_warn "Failed to rename: $file"
        ((skipped+=1))
    fi
done < <(find "$QUARANTINE_DIR" -type f -print0)

log_info "Renamed: $renamed"
log_info "Skipped: $skipped"
