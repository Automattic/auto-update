#!/bin/bash

function abort() {
    echo "Update script aborted."
    echo "Removing temporary directory..."
    rm -rf $tempdir
    echo "Removing tarball..."
    rm -rf "$tarball"
    echo "Relaunching bundle..."
    open "$destination"
    rm -f ~/.auto-update.lock
    exit 1
}

tarball=$1
destination=$2

echo "Update script initiated."
lockfile ~/.auto-update.lock

# Step 1. Wait until all processes from within the bundle are closed
echo -n "Waiting for bundled processes to close..."
while [ $(
    # List all processes, filtering out this process
    processes=$(echo "$(ps ax)" | grep -v "$0")

    # Escape the destination into a regexp that matches it
    regexp=$(echo "$destination" | sed 's/[^[:alnum:]_-]/\\&/g')

    # Filters entries matching the regexp, and do some magic to preserve the trailing newline
    matches=$(echo "$processes" | awk "/$regexp/ { print \$1 }"; echo .)
    matches=${matches%.}

    # Count matches
    printf "%s" "$matches" | wc -l
) -gt 0 ]
do
    echo -n .
    sleep 1
done
echo

# Step 2. Check if the downloaded tar is empty, if so abort
if [ ! -s "$tarball" ]
then
    abort
fi

# Step 3. Extract the new contents
echo "Creating temporary directory..."
tempdir=`mktemp -d /tmp/auto-update.XXXXX`
echo "Extracting new content from tarball..."
tar -xf "$tarball" -C "$tempdir"

# Step 4. Check if the extraction worked, if not abort
if [ $? -ne 0 ]
then
    abort
fi

# Step 5. Remove the old bundle directory
echo "Removing bundle..."
rm -rf "$destination"/*
echo "Moving new content into place..."
mv -f $tempdir'/'$(ls $tempdir | head -n 1)'/'* "$destination"'/'
echo "Make sure destination is not quarantined..."
xattr -d com.apple.quarantine "$destination"
echo "Removing temporary directory..."
rm -rf $tempdir
echo "Removing tarball..."
rm -rf "$tarball"

# Step 6. (Re)launch the destination bundle
echo "Relaunching bundle..."
open "$destination"

echo "Done."
rm -f ~/.auto-update.lock
