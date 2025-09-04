#!/bin/sh

# Base path passed as the first argument
basePath="$1"
# Check if basePath is provided
if [ -z "$basePath" ]; then
    basePath=$(pwd)
fi

# Define the distribution directory
distDirectory="$basePath"
# If basePath is "data", distDirectory shouuld be "data" as well.

if [ ! -d "$distDirectory" ]; then
    mkdir -p "$distDirectory"
fi

echo "Downloading ASN data to $distDirectory..." >&2
# Here we assume that you've activated the virtual environment and also installed all deps in the pyproject.toml file, probably using UV or poetry.

# Get the directory of the current script
scriptDirectory="$(dirname "$(realpath "$0")")"
srcFile="$distDirectory/rib.bz2"
datFile="$distDirectory/rib.dat"

# Call the pyasn_util_download.py script
python3 "$scriptDirectory/pyasn_util_download.py" --latestv4 --filename "$srcFile"
python3 "$scriptDirectory/pyasn_util_convert.py" --single "$srcFile" "$datFile"

# Remove header part
sed -i '1,6d' "$datFile"

rm -f "$srcFile"
echo "Fetching ASN database ... Done!" >&2

