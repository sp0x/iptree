#!/bin/bash

set -e
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

echo "Syncing udgerdb..."
export $(cat .secrets)
basePath="$1"
key=$KEY_UDGER
dbname="udgerdb_v3.dat.gz"
distArchiveFile="$distDirectory/$dbname"
distDatacentersFile="$distDirectory/datacenters.csv"

curl -L "https://data.udger.com/$key/$dbname" -o "$distArchiveFile"
curl -L "https://data.udger.com/$key/datacenter.csv" -o "$distDatacentersFile"

gzip -f -d "$distArchiveFile"

# Optionally remove the archive file if not already removed by gzip
# (gzip -d deletes the .gz file by default)
