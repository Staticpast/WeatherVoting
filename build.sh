#!/bin/bash

# WeatherVoting Plugin Build and Deploy Script
# This script detects changes, increments versions, builds the plugin, and deploys it to the server

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

# --- Logging Functions ---
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# --- Utility Functions ---
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v mvn >/dev/null 2>&1; then
        missing_deps+=("maven")
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if ! command -v gh >/dev/null 2>&1; then
        log_warning "GitHub CLI (gh) not found. Installing via Homebrew..."
        if command -v brew >/dev/null 2>&1; then
            brew install gh
        else
            missing_deps+=("gh (GitHub CLI)")
        fi
    fi
    
    if ! command -v xmlstarlet >/dev/null 2>&1; then
        log_warning "xmlstarlet not found. Installing via Homebrew..."
        if command -v brew >/dev/null 2>&1; then
            brew install xmlstarlet
        else
            missing_deps+=("xmlstarlet")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    log_info "Dependencies check passed."
}

get_current_version() {
    xmlstarlet sel -t -v "//*[local-name()='project']/*[local-name()='version']" "$POM_FILE" 2>/dev/null || {
        grep -o '<version>[^<]*</version>' "$POM_FILE" | head -1 | sed 's/<version>\(.*\)<\/version>/\1/' || {
            log_error "Failed to read version from $POM_FILE"
            exit 1
        }
    }
}

increment_version() {
    local current_version="$1"
    local version_type="${2:-patch}"
    
    if [[ $current_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local patch="${BASH_REMATCH[3]}"
        
        case "$version_type" in
            major)
                major=$((major + 1))
                minor=0
                patch=0
                ;;
            minor)
                minor=$((minor + 1))
                patch=0
                ;;
            patch|*)
                patch=$((patch + 1))
                ;;
        esac
        
        echo "${major}.${minor}.${patch}"
    else
        log_error "Invalid version format: $current_version (expected: major.minor.patch)"
        exit 1
    fi
}

update_version() {
    local new_version="$1"
    
    log_info "Updating plugin version to $new_version using Maven versions plugin..."
    
    # Use Maven versions plugin to update version
    mvn versions:set -DnewVersion="$new_version" -DgenerateBackupPoms=false -q || {
        log_error "Failed to update version using Maven versions plugin"
        exit 1
    }
    
    log_info "Successfully updated version to $new_version"
}

calculate_project_hash() {
    # Calculate hash of all source files and configuration
    find "$PROJECT_DIR/src" "$PROJECT_DIR/pom.xml" -type f \( -name "*.java" -o -name "*.yml" -o -name "*.xml" \) 2>/dev/null | \
        sort | xargs cat | sha256sum | cut -d' ' -f1
}

detect_changes() {
    log_info "Detecting changes in project..."
    
    local current_hash
    current_hash=$(calculate_project_hash)
    
    local previous_hash=""
    if [[ -f "$CHANGE_CACHE_FILE" ]]; then
        previous_hash=$(cat "$CHANGE_CACHE_FILE")
    fi
    
    # Save current hash
    echo "$current_hash" > "$CHANGE_CACHE_FILE"
    
    if [[ "$current_hash" != "$previous_hash" ]]; then
        log_info "Changes detected in project"
        return 0
    else
        log_info "No changes detected"
        return 1
    fi
}

build_plugin() {
    log_info "Building plugin with Maven..."
    
    cd "$PROJECT_DIR"
    
    # Clean and build the plugin
    mvn clean package -q || {
        log_error "Maven build failed"
        exit 1
    }
    
    log_success "Plugin built successfully"
}

remove_old_plugin() {
    log_info "Removing old plugin versions from $PLUGINS_DIR..."
    
    if [[ ! -d "$PLUGINS_DIR" ]]; then
        log_warning "Plugins directory does not exist: $PLUGINS_DIR"
        log_info "Creating plugins directory..."
        mkdir -p "$PLUGINS_DIR"
        return
    fi
    
    local removed_count=0
    for file in "$PLUGINS_DIR"/${PLUGIN_NAME}*.jar; do
        if [[ -f "$file" ]]; then
            log_info "Removing old plugin: $(basename "$file")"
            rm -f "$file"
            removed_count=$((removed_count + 1))
        fi
    done
    
    if [[ $removed_count -eq 0 ]]; then
        log_info "No old plugin versions found to remove"
    else
        log_info "Removed $removed_count old plugin file(s)"
    fi
}

deploy_plugin() {
    local version="$1"
    
    log_info "Deploying plugin to $PLUGINS_DIR..."
    
    mkdir -p "$PLUGINS_DIR"
    
    local jar_file="$PROJECT_DIR/target/${PLUGIN_ARTIFACT_ID}-${version}.jar"
    
    if [[ -f "$jar_file" ]]; then
        cp "$jar_file" "$PLUGINS_DIR/" || {
            log_error "Failed to copy plugin to $PLUGINS_DIR"
            exit 1
        }
        log_info "Deployed: ${PLUGIN_ARTIFACT_ID}-${version}.jar"
        log_success "Successfully deployed plugin to $PLUGINS_DIR"
    else
        log_error "JAR file not found: $jar_file"
        exit 1
    fi
}

save_version_cache() {
    local version="$1"
    echo "$version" > "$VERSION_CACHE_FILE"
    log_info "Saved version $version to cache"
}

load_version_cache() {
    if [[ -f "$VERSION_CACHE_FILE" ]]; then
        cat "$VERSION_CACHE_FILE"
    else
        echo ""
    fi
}

get_git_tag_for_version() {
    local version="$1"
    echo "v$version"
}

get_previous_version_tag() {
    git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo ""
}

generate_release_notes() {
    local version="$1"
    local previous_tag="$2"
    
    cat > "$RELEASE_NOTES_FILE" << EOF
## What's New
*Add your release notes here*

## Requirements
- Spigot/Paper 1.21.6+
- Java 21+

## Full Changelog
https://github.com/$GITHUB_REPO/compare/$previous_tag...v$version
EOF
}

create_github_release() {
    local version="$1"
    local jar_file="$2"
    local force_release="${3:-false}"
    local tag="v$version"
    local release_title="$PLUGIN_NAME $tag"
    
    log_info "Creating GitHub release: $release_title"
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a git repository. Cannot create GitHub release."
        return 1
    fi
    
    # Check if user is authenticated with GitHub CLI
    if ! gh auth status >/dev/null 2>&1; then
        log_error "Not authenticated with GitHub CLI. Run 'gh auth login' first."
        return 1
    fi
    
    # Check if release already exists (unless force release is enabled)
    if gh release view "$tag" >/dev/null 2>&1; then
        if [[ "$force_release" == true ]]; then
            log_info "GitHub release $tag already exists, but force release is enabled - deleting it"
            if gh release delete "$tag" --yes; then
                log_info "Deleted existing GitHub release: $tag"
            else
                log_error "Failed to delete existing GitHub release: $tag"
                return 1
            fi
        else
            log_warning "GitHub release $tag already exists"
            log_info "You can view it at: https://github.com/$GITHUB_REPO/releases/tag/$tag"
            log_info "Use --force-release to recreate it"
            return 0
        fi
    fi
    
    # Get previous version for changelog
    local previous_tag
    previous_tag=$(get_previous_version_tag)
    
    # Generate release notes
    generate_release_notes "$version" "$previous_tag"
    
    # Open release notes in editor for user to edit
    if [[ -n "${EDITOR:-}" ]]; then
        log_info "Opening release notes in $EDITOR for editing..."
        $EDITOR "$RELEASE_NOTES_FILE"
    elif command -v nano >/dev/null 2>&1; then
        log_info "Opening release notes in nano for editing..."
        nano "$RELEASE_NOTES_FILE"
    else
        log_warning "No editor found. Using generated release notes as-is."
        log_info "You can edit the release notes manually at: $RELEASE_NOTES_FILE"
    fi
    
    # Determine target commit - use existing tag if it exists, otherwise current HEAD
    local target_commit
    if git tag -l "$tag" | grep -q "^$tag$"; then
        target_commit=$(git rev-list -n 1 "$tag")
        log_info "Using existing tag $tag (commit: ${target_commit:0:7})"
    else
        target_commit=$(git rev-parse HEAD)
        log_info "Using current HEAD (commit: ${target_commit:0:7})"
    fi
    
    # Create the release
    if gh release create "$tag" \
        --title "$release_title" \
        --notes-file "$RELEASE_NOTES_FILE" \
        --target "$target_commit" \
        "$jar_file"; then
        
        log_success "GitHub release created successfully: $release_title"
        log_info "Release URL: https://github.com/$GITHUB_REPO/releases/tag/$tag"
        
        # Clean up temporary file
        rm -f "$RELEASE_NOTES_FILE"
        
        return 0
    else
        log_error "Failed to create GitHub release"
        return 1
    fi
}

commit_and_tag_version() {
    local version="$1"
    local tag="v$version"
    
    log_info "Committing version changes and creating git tag..."
    
    # Check if there are changes to commit
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes to commit"
    else
        # Add version-related files
        git add pom.xml
        git add src/main/resources/plugin.yml 2>/dev/null || true
        
        # Commit with conventional commit format
        git commit -m "chore(release): bump version to $version" || {
            log_warning "Failed to commit version changes"
        }
    fi
    
    # Check if tag already exists
    if git tag -l "$tag" | grep -q "^$tag$"; then
        log_warning "Git tag $tag already exists"
        
        # Check if GitHub release exists
        if gh release view "$tag" >/dev/null 2>&1; then
            log_info "GitHub release $tag already exists, skipping"
            return 0
        else
            log_info "Git tag exists but GitHub release doesn't - will create release using existing tag"
            return 0
        fi
    fi
    
    # Create and push tag
    if git tag -a "$tag" -m "$PLUGIN_NAME $tag"; then
        log_info "Created git tag: $tag"
        
        # Push tag to remote
        if git push origin "$tag" 2>/dev/null; then
            log_info "Pushed tag to remote: $tag"
        else
            log_warning "Failed to push tag to remote (this is okay if working locally)"
        fi
    else
        log_error "Failed to create git tag: $tag"
        return 1
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build and deploy the WeatherVoting plugin with intelligent change detection.

 OPTIONS:
     -t, --type TYPE     Version increment type: major, minor, patch (default: patch)
     -v, --version VER   Set specific version instead of incrementing
     -n, --no-increment  Build and deploy without incrementing version
     -f, --force         Force build even if no changes detected
     -c, --check-only    Only check for changes, don't build or deploy
     -b, --build-only    Build plugin but don't deploy to server
     -r, --release       Create GitHub release after successful build
     -g, --git-only      Only commit and tag version, don't create GitHub release
     --force-release     Force recreate GitHub release even if it exists
     --clean-tag VER     Delete existing git tag and recreate it
     -h, --help          Show this help message

 EXAMPLES:
     $0                  # Auto-detect changes and increment patch version if needed
     $0 -t minor         # Force minor version increment and build
     $0 -v 2.1.0         # Set version to 2.1.0 and build
     $0 -f               # Force build even without changes
     $0 -c               # Check for changes only
     $0 -b               # Build plugin but don't deploy
     $0 -r               # Build, deploy, and create GitHub release
     $0 -g               # Build, deploy, and create git tag (no GitHub release)
     $0 --clean-tag v1.1.5 -r  # Delete existing tag and recreate release
     $0 --force-release -r      # Force recreate GitHub release
     $0 -b -f            # Force build without deployment

CONFIGURATION:
    Plugin name: $PLUGIN_NAME
    Plugins directory: $PLUGINS_DIR
    Project directory: $PROJECT_DIR

CHANGE DETECTION:
    The script automatically detects changes in source files and configurations.
    Only builds and increments version when changes are detected (unless forced).
EOF
}

# --- Main Execution ---
main() {
    local version_type="patch"
    local specific_version=""
    local no_increment=false
    local force_build=false
    local check_only=false
    local build_only=false
    local create_release=false
    local git_only=false
    local force_release=false
    local clean_tag=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                version_type="$2"
                if [[ ! "$version_type" =~ ^(major|minor|patch)$ ]]; then
                    log_error "Invalid version type: $version_type (must be: major, minor, patch)"
                    exit 1
                fi
                shift 2
                ;;
            -v|--version)
                specific_version="$2"
                shift 2
                ;;
            -n|--no-increment)
                no_increment=true
                shift
                ;;
            -f|--force)
                force_build=true
                shift
                ;;
            -c|--check-only)
                check_only=true
                shift
                ;;
            -b|--build-only)
                build_only=true
                shift
                ;;
            -r|--release)
                create_release=true
                shift
                ;;
            -g|--git-only)
                git_only=true
                shift
                ;;
            --force-release)
                force_release=true
                shift
                ;;
            --clean-tag)
                clean_tag="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting WeatherVoting plugin build and deployment..."
    
    # Handle clean tag option first
    if [[ -n "$clean_tag" ]]; then
        log_info "Cleaning up existing tag: $clean_tag"
        
        # Delete local tag
        if git tag -d "$clean_tag" 2>/dev/null; then
            log_info "Deleted local tag: $clean_tag"
        else
            log_info "Local tag $clean_tag doesn't exist"
        fi
        
        # Delete remote tag
        if git push origin --delete "$clean_tag" 2>/dev/null; then
            log_info "Deleted remote tag: $clean_tag"
        else
            log_info "Remote tag $clean_tag doesn't exist or couldn't be deleted"
        fi
        
        # Delete GitHub release if it exists
        if gh release delete "$clean_tag" --yes 2>/dev/null; then
            log_info "Deleted GitHub release: $clean_tag"
        else
            log_info "GitHub release $clean_tag doesn't exist"
        fi
    fi
    
    # Check dependencies
    check_dependencies
    
    # Detect changes
    local changes_detected=false
    if detect_changes; then
        changes_detected=true
    fi
    
    # Check-only mode
    if [[ "$check_only" == true ]]; then
        if [[ "$changes_detected" == true ]]; then
            log_info "Changes detected in project"
            exit 0
        else
            log_info "No changes detected"
            exit 1
        fi
    fi
    
    # Determine if we should build
    local should_build=false
    if [[ "$force_build" == true ]]; then
        log_info "Force build requested"
        should_build=true
    elif [[ "$changes_detected" == true ]]; then
        log_info "Changes detected, build required"
        should_build=true
    elif [[ -n "$specific_version" ]]; then
        log_info "Specific version requested, build required"
        should_build=true
    elif [[ "$no_increment" == false ]]; then
        log_info "Version increment requested, build required"
        should_build=true
    else
        log_info "No changes detected and no build forced"
        log_info "Use -f/--force to build anyway"
        exit 0
    fi
    
    if [[ "$should_build" == false ]]; then
        log_info "No build required"
        exit 0
    fi
    
    # Get current version
    local current_version
    current_version=$(get_current_version)
    log_info "Current version: $current_version"
    
    # Determine new version
    local new_version="$current_version"
    if [[ -n "$specific_version" ]]; then
        new_version="$specific_version"
        log_info "Setting version to: $new_version"
    elif [[ "$no_increment" == false ]]; then
        new_version=$(increment_version "$current_version" "$version_type")
        log_info "Incrementing $version_type version: $current_version -> $new_version"
    else
        log_info "Using current version: $new_version"
    fi
    
    # Update version if changed
    if [[ "$new_version" != "$current_version" ]]; then
        update_version "$new_version"
    fi
    
    # Build the plugin
    build_plugin
    
    # Save version to cache
    save_version_cache "$new_version"
    
    if [[ "$build_only" == true ]]; then
        log_success "Build completed successfully!"
        log_success "Version: $new_version"
        
        # Show built file
        local jar_file="$PROJECT_DIR/target/${PLUGIN_ARTIFACT_ID}-${new_version}.jar"
        echo
        echo "Built file:"
        if [[ -f "$jar_file" ]]; then
            echo "  ✓ $(basename "$jar_file") ($(du -h "$jar_file" | cut -f1))"
        fi
        
        echo
        echo "Next steps:"
        echo "1. Run without -b/--build-only to deploy to server"
        echo "2. Or manually copy JAR file from target/ directory"
        
        if [[ "$changes_detected" == true ]]; then
            echo "3. Changes were detected in the project"
        fi
    else
        # Remove old plugin version
        remove_old_plugin
        
        # Deploy new plugin
        deploy_plugin "$new_version"
        
        log_success "Build and deployment completed successfully!"
        log_success "Version: $new_version"
        log_success "Location: $PLUGINS_DIR/"
        
        # Show deployed file
        echo
        echo "Deployed file:"
        local jar_file="$PLUGINS_DIR/${PLUGIN_ARTIFACT_ID}-${new_version}.jar"
        if [[ -f "$jar_file" ]]; then
            echo "  ✓ $(basename "$jar_file")"
        fi
        
        # Show next steps
        echo
        echo "Next steps:"
        echo "1. Restart your Minecraft server to load the new plugin version"
        echo "2. Test the /fdc command to verify the plugin is loaded"
        echo "3. Check server logs for any errors during plugin loading"
        
        if [[ "$changes_detected" == true ]]; then
            echo "4. Changes were detected and deployed"
        fi
        
        # Handle Git operations and GitHub release
        if [[ "$create_release" == true || "$git_only" == true ]]; then
            # Commit and tag version
            if commit_and_tag_version "$new_version"; then
                if [[ "$create_release" == true ]]; then
                    # Create GitHub release
                    local jar_file="$PLUGINS_DIR/${PLUGIN_ARTIFACT_ID}-${new_version}.jar"
                    if [[ -f "$jar_file" ]]; then
                        create_github_release "$new_version" "$jar_file" "$force_release"
                    else
                        log_error "JAR file not found for GitHub release: $jar_file"
                    fi
                fi
            fi
        fi
    fi
}

# Run main function with all arguments
main "$@" 