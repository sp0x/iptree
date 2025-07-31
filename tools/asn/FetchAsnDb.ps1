Write-Host "Fetching ASN database ..."
$basePath = $args[0]
# Call the pyasn_util_download.py script
# The pyasn_util_download.py script is a Python script that downloads the latest routing table view
# from the RIRs and converts it into the format expected by pyasn. The script is available at

$distDirectory = Join-Path -Path $basePath -ChildPath "data/networks"
if (!(Test-Path -Path $distDirectory)) {
    New-Item -ItemType Directory -Path $distDirectory
}


# Check if the pyasn pip module is installed and install it if it's not
if (!(python3 -m pip show pyasn)) {
    Write-Host "pyasn pip module not found. Can't continue forward..."
    exit 1
}

$powershellScriptDirectory=Split-Path -Parent $MyInvocation.MyCommand.Definition
$srcFile="$distDirectory/rib.bz2"
$datFile="$distDirectory/rib.dat"
python3 $powershellScriptDirectory/pyasn_util_download.py --latestv4 --filename $srcFile
python3 $powershellScriptDirectory/pyasn_util_convert.py --single $srcFile $datFile
# Remove header part
sed -i '1,6d' "$datFile"

Write-Host "Removing source archive $srcFile"
Remove-Item $srcFile -Force

python3 -c "import pyasn
asndb2 = pyasn.pyasn('$datFile')
res = asndb2.lookup('167.253.18.199')
print(res)"

Write-Host "Fetching ASN database ... Done!"