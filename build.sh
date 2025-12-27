#!/bin/bash

# WeatherVoting Plugin Build and Deploy Script
# Java 21 / Spigot-Paper 1.21.11

set -e
set -o pipefail

# --- Configuration ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$SCRIPT_DIR"
readonly POM_FILE="$PROJECT_DIR/pom.xml"
readonly PLUGINS_DIR="$SCRIPT_DIR/../server/plugins"
readonly VERSION_CACHE_FILE="$PROJECT_DIR/.last_build_version"
readonly CHANGE_CACHE_FILE="$PROJECT_DIR/.last_build_hash"

# Plugin configuration
readonly PLUGIN_NAME="WeatherVoting"
readonly PLUGIN_ARTIFACT_ID="WeatherVoting"

# GitHub configuration
readonly GITHUB_REPO="Staticpast/WeatherVoting"
readonly RELEASE_NOTES_FILE="$PROJECT_DIR/.release_notes_temp"

# --- Logging ---
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }
log_warn()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"; }

# --- Dependency Checks ---
check_dependencies() {
    local missing=()

    command -v mvn >/dev/null 2>&1 || missing+=("maven")
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v gh  >/dev/null 2>&1 || missing+=("gh")
    command -v xmlstarlet >/dev/null 2>&1 || missing+=("xmlstarlet")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

check_java_version() {
    local version
    version=$(java -version 2>&1 | awk -F[\".] '/version/ {print $2}')

    if [[ "$version" -lt 21 ]]; then
        log_error "Java 21+ required. Detected Java $version"
        exit 1
    fi

    log_info "Java version OK: $version"
    mvn -v
}

# --- Version Handling ---
get_current_version() {
    xmlstarlet sel -t -v "//*[local-name()='project']/*[local-name()='version']" "$POM_FILE"
}

increment_version() {
    local v="$1" type="${2:-patch}"

    IFS=. read -r major minor patch <<< "$v"

    case "$type" in
        major) ((major++)); minor=0; patch=0 ;;
        minor) ((minor++)); patch=0 ;;
        patch) ((patch++)) ;;
    esac

    echo "$major.$minor.$patch"
}

update_version() {
    mvn versions:set -DnewVersion="$1" -DgenerateBackupPoms=false -q
}

# --- Change Detection ---
calculate_project_hash() {
    find "$PROJECT_DIR/src" \
         "$PROJECT_DIR/pom.xml" \
         "$PROJECT_DIR/.mvn" \
         "$PROJECT_DIR/mvnw"* \
         -type f \( -name "*.java" -o -name "*.yml" -o -name "*.xml" \) 2>/dev/null \
    | sort | xargs cat | sha256sum | cut -d' ' -f1
}

detect_changes() {
    local current
    current=$(calculate_project_hash)
    local previous=""
    [[ -f "$CHANGE_CACHE_FILE" ]] && previous=$(cat "$CHANGE_CACHE_FILE")

    echo "$current" > "$CHANGE_CACHE_FILE"

    [[ "$current" != "$previous" ]]
}

# --- Build ---
build_plugin() {
    log_info "Building plugin..."
    mvn clean package -q
    log_success "Build completed"
}

# --- Deploy ---
remove_old_plugin() {
    mkdir -p "$PLUGINS_DIR"
    rm -f "$PLUGINS_DIR/${PLUGIN_NAME}"*.jar || true
}

deploy_plugin() {
    local jar
    jar=$(ls "$PROJECT_DIR"/target/${PLUGIN_ARTIFACT_ID}-*.jar | head -1)

    [[ -f "$jar" ]] || { log_error "Built JAR not found"; exit 1; }

    cp "$jar" "$PLUGINS_DIR/"
    log_success "Deployed $(basename "$jar")"
}

# --- Release Notes ---
get_minecraft_version() {
    # Extract Minecraft version from Spigot API dependency in pom.xml
    xmlstarlet sel -t -v "//*[local-name()='dependency']/*[local-name()='artifactId'][text()='spigot-api']/../*[local-name()='version']" "$POM_FILE" | sed 's/-R0.1-SNAPSHOT//'
}

generate_release_notes() {
    local version="$1"
    local prev="$2"
    local whats_new="${3:-- Updated to support Minecraft $(get_minecraft_version)}"

    cat > "$RELEASE_NOTES_FILE" << EOF
## What's New
$whats_new

## Requirements
- Spigot/Paper $(get_minecraft_version)+
- Java 21+

## Full Changelog
https://github.com/$GITHUB_REPO/compare/$prev...v$version
EOF
}

# --- Git & GitHub ---
get_previous_tag() {
    git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo ""
}

commit_and_tag() {
    local v="$1"
    git add pom.xml src/main/resources/plugin.yml 2>/dev/null || true
    git commit -m "chore(release): v$v" || true
    git tag -a "v$v" -m "$PLUGIN_NAME v$v" || true
    git push origin "v$v" || true
}

create_github_release() {
    local v="$1"
    local jar="$2"
    local release_notes="$3"
    local prev
    prev=$(get_previous_tag)

    generate_release_notes "$v" "$prev" "$release_notes"

    gh release create "v$v" \
        --title "$PLUGIN_NAME v$v" \
        --notes-file "$RELEASE_NOTES_FILE" \
        "$jar"

    rm -f "$RELEASE_NOTES_FILE"
}

# --- Main ---
main() {
    check_dependencies
    check_java_version

    local force=false release=false type="patch" release_notes=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true ;;
            -r|--release) release=true ;;
            -t|--type) type="$2"; shift ;;
            -n|--notes) release_notes="$2"; shift ;;
        esac
        shift
    done

    if ! detect_changes && [[ "$force" != true ]]; then
        log_info "No changes detected. Use --force to override."
        exit 0
    fi

    local current new
    current=$(get_current_version)
    new=$(increment_version "$current" "$type")

    update_version "$new"
    build_plugin
    remove_old_plugin
    deploy_plugin

    if [[ "$release" == true ]]; then
        commit_and_tag "$new"
        local jar
        jar=$(ls "$PROJECT_DIR"/target/${PLUGIN_ARTIFACT_ID}-*.jar | head -1)
        create_github_release "$new" "$jar" "$release_notes"
    fi

    log_success "Done — $PLUGIN_NAME v$new"
}

main "$@"
