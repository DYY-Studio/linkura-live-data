#!/bin/bash

# Archive task script for linkura-cli
# This script downloads linkura-cli, runs the archive command, and processes the results

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/data"
ARCHIVE_JSON="$DATA_DIR/archive.json"
TEMP_ARCHIVE="/tmp/archive.json"

# Tool URL and configuration
TOOL_URL="https://github.com/ChocoLZS/linkura-cli/releases/download/linkura-cli-v0.0.2/linkura-cli-x86_64-unknown-linux-gnu.tar.gz"
TOOL_NAME="linkura-cli"

echo "Starting archive task..."

# Create temporary directory for tool
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading linkura-cli..."
curl -L "$TOOL_URL" -o linkura-cli.tar.gz

echo "Extracting linkura-cli..."
tar -xzf linkura-cli.tar.gz

# Make the tool executable
chmod +x ./$TOOL_NAME

echo "Running archive command..."
./$TOOL_NAME --player-id "$PLAYER_ID" --password "$PASSWORD" archive -l 6 -s "$TEMP_ARCHIVE"

# Check if temp archive was created
if [ ! -f "$TEMP_ARCHIVE" ]; then
    echo "Error: Archive command did not create output file"
    exit 1
fi

echo "Processing archive data..."

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# If archive.json doesn't exist, create it with empty array
if [ ! -f "$ARCHIVE_JSON" ]; then
    echo "[]" > "$ARCHIVE_JSON"
fi

# Use Python to process the JSON files
python3 << 'EOF'
import json
import sys
import os

def load_json(file_path):
    """Load JSON from file, return empty list if file doesn't exist or is invalid"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []

def save_json(data, file_path):
    """Save JSON data to file"""
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def normalize_archive_entry(entry):
    """Normalize archive entry to match the expected format"""
    # Define expected fields based on the backup data
    expected_fields = [
        "archives_id", "description", "external_link", "live_end_time",
        "live_id", "live_start_time", "live_type", "name", 
        "thumbnail_image_url", "video_url"
    ]
    
    # Create normalized entry with only expected fields
    normalized = {}
    for field in expected_fields:
        normalized[field] = entry.get(field, "")
    
    return normalized

def find_new_data(temp_data, existing_data):
    """Find entries with new video_url or external_link data"""
    existing_dict = {entry['archives_id']: entry for entry in existing_data if 'archives_id' in entry}
    new_entries = []
    updated_entries = []
    
    for temp_entry in temp_data:
        if 'archives_id' not in temp_entry:
            continue
            
        archives_id = temp_entry['archives_id']
        normalized_temp = normalize_archive_entry(temp_entry)
        
        if archives_id in existing_dict:
            existing_entry = existing_dict[archives_id]
            has_updates = False
            
            # Check video_url
            if (existing_entry.get('video_url', '') == '' and 
                normalized_temp.get('video_url', '') != ''):
                has_updates = True
                
            # Check external_link
            if (existing_entry.get('external_link', '') == '' and 
                normalized_temp.get('external_link', '') != ''):
                has_updates = True
                
            if has_updates:
                # Update existing entry with new data
                for key, value in normalized_temp.items():
                    if value != '' or existing_entry.get(key, '') == '':
                        existing_entry[key] = value
                updated_entries.append(archives_id)
        else:
            # New entry
            new_entries.append(normalized_temp)
    
    return new_entries, updated_entries

# Main processing
temp_archive = '/tmp/archive.json'
archive_json = os.environ.get('ARCHIVE_JSON', 'data/archive.json')

print(f"Loading temp archive from: {temp_archive}")
print(f"Loading existing archive from: {archive_json}")

temp_data = load_json(temp_archive)
existing_data = load_json(archive_json)

print(f"Temp data entries: {len(temp_data)}")
print(f"Existing data entries: {len(existing_data)}")

new_entries, updated_entries = find_new_data(temp_data, existing_data)

if new_entries or updated_entries:
    print(f"Found {len(new_entries)} new entries and {len(updated_entries)} updated entries")
    
    # Add new entries to existing data
    existing_data.extend(new_entries)
    
    # Save updated data
    save_json(existing_data, archive_json)
    
    # Set flag for git operations
    with open('/tmp/has_updates', 'w') as f:
        f.write('true')
    
    print("Archive data updated successfully")
else:
    print("No new data found")
    with open('/tmp/has_updates', 'w') as f:
        f.write('false')
EOF

# Check if there were updates
HAS_UPDATES=$(cat /tmp/has_updates)

if [ "$HAS_UPDATES" = "true" ]; then
    echo "Changes detected, committing to git..."
    
    cd "$PROJECT_ROOT"
    
    # Configure git (in case it's not configured in CI)
    git config --local user.email "action@github.com"
    git config --local user.name "GitHub Action"
    
    # Add and commit changes
    git add data/archive.json
    
    # Create commit message with current date
    COMMIT_DATE=$(date '+%y-%m-%d')
    git commit -m "auto($COMMIT_DATE): update archive.json

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    # Push changes
    git push
    
    echo "Changes committed and pushed successfully"
else
    echo "No changes to commit"
fi

# Cleanup
rm -rf "$TEMP_DIR"
rm -f /tmp/has_updates

echo "Archive task completed successfully"