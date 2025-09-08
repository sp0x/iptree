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

echo "Syncing maxmind..."
export $(cat .secrets)
basePath="$1"
key=$KEY_MAXMIND
maxMindApiBase="https://db-ip.com/account"
dbType="ip-to-location-isp" # To get a list of types, just send a request to the URL
format="mmdb"
fullUrl="$maxMindApiBase/$key/db/$dbType/$format"

# Parse JSON response from API
resp=$(curl -s -H "Accept: application/json" -X GET "$fullUrl" -H "Content-Type: application/json")
size=$(jq -r '.size' <<< "$resp")
mmdb_file="$distDirectory/mmdb"
mmdb_arch="$distDirectory/mmdb.gz"

# Get the current file size, if it exists
currentSize=0
if [ -f $mmdb_file ]; then
    currentSize=$(stat -c%s $mmdb_file)
fi

# Download the gz only if the size is different
if [ "$currentSize" -eq "$size" ]; then
    echo "MaxMind database is up to date, skipping download"
    exit 0
else
    downloadUrl=$(jq -r '.url' <<< "$resp")
    echo "Downloading MaxMind database from $downloadUrl to $mmdb_arch"
    # Download the database
    curl -s -L "$downloadUrl" -o $mmdb_arch 
fi

# Unzip the database using gzip
gzip -d -q -f $mmdb_arch

echo "Syncing maxmind... Done!"
