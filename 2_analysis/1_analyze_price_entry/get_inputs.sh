#!/bin/bash

# Define your input paths here
# Paths should be relative to the current module.
# Module directories are linked (not their output_local subfolders directly)
# because both would otherwise get the same link name. Reference data as
# ../input/<module>/output_local/<file> in source scripts.
INPUT_FILES=(
    ../../1_data/1_clean_prices
    ../../1_data/2_build_molecule_panel
)

# Path to current module
MAKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Remove existing input directory and recreate it.
# Windows note: input/ may contain junctions (symlink fallback below); Git
# Bash rm -rf TRAVERSES junctions and would delete the target contents, so
# unlink directory entries with rmdir first.
if [[ -d "${MAKE_SCRIPT_DIR}/input" ]]; then
    for p in "${MAKE_SCRIPT_DIR}/input"/* ; do
        [[ -e "$p" || -L "$p" ]] || continue
        if [[ -d "$p" ]]; then
            cmd //c "rmdir \"$(cygpath -w "$p")\"" 2>/dev/null || rm -rf "$p"
        else
            rm -f "$p"
        fi
    done
    rmdir "${MAKE_SCRIPT_DIR}/input" 2>/dev/null || rm -rf "${MAKE_SCRIPT_DIR}/input"
fi
mkdir -p "${MAKE_SCRIPT_DIR}/input"

# Variable to track if any links were created
links_created=false

# enable symbolic link
export MSYS=winsymlinks:nativestrict

# Loop through the input paths
for file_path in "${INPUT_FILES[@]}"; do
    resolved_path="$MAKE_SCRIPT_DIR/$file_path"

    if [[ -e "$resolved_path" ]]; then
        file_name=$(basename "$resolved_path")
        dest="$MAKE_SCRIPT_DIR/input/$file_name"
        if ! ln -sfn "../$file_path" "$dest" 2>/dev/null; then
            # Fallback for Windows without symlink privileges: junction for
            # directories (no elevation needed), copy for files.
            if [[ -d "$resolved_path" ]]; then
                cmd //c "mklink /J \"$(cygpath -w "$dest")\" \"$(cygpath -w "$resolved_path")\"" > /dev/null
            else
                cp -f "$resolved_path" "$dest"
            fi
        fi
        links_created=true
    else
        echo -e "\033[0;31mWarning\033[0m in \033[0;34mget_inputs.sh\033[0m: $file_path does not exist or is not a valid file path." >&2
    fi
done

# Output the result
if [[ "$links_created" == true ]]; then
    echo -e "\nAll input links were created!"
else
    echo -e "\n\033[0;34mNote:\033[0m There were no input links to create in \033[0;34mget_inputs.sh\033[0m."
fi
