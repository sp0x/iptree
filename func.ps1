#------------------------------------------------------------------------------
# Subroutine ip_range_to_prefix
# Purpose           : Return all prefixes between two IPs
function Get-IpSubnetsBetween {

    param(
        [ipaddress]$StartIp,

        [ipaddress]$EndIp
    )


    if ($StartIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
          $EndIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {

        Write-Error -Message 'Function only works for IPv4 addresses'
    }


    # Get the IPs in 32-bit unsigned integers (big-endian)
    # The .Address property is little-endian, or host-endian, so avoid that.

    [uint32[]]$octets = $StartIp.GetAddressBytes()
    [uint32]$startIpAddress = ($octets[0] -shl 24) + ($octets[1] -shl 16) + ($octets[2] -shl 8) + $octets[3]

    [uint32[]]$octets = $EndIp.GetAddressBytes()
    [uint32]$EndIpAddress   = ($octets[0] -shl 24) + ($octets[1] -shl 16) + ($octets[2] -shl 8) + $octets[3]
    Remove-Variable -Name octets -ErrorAction SilentlyContinue


    while ($startIpAddress -le $endIPAddress -and $startIpAddress -ne [uint32]::MaxValue) {


        # Bitwise shift-right in a loop,
        # to find how many trailing 0 bits there are
        $numTrailingZeros = 0
        while ([uint32]($startIpAddress -shr $numTrailingZeros) % 2 -eq 0) {
            $numTrailingZeros++
        }
    
        # switch all those bits to 1, 
        # see if that takes us past the end IP address. 
        # Try one fewer in a loop until it doesn't pass the end.
        do {
            [uint32]$current = $startIpAddress -bor ([math]::Pow(2, $numTrailingZeros)-1)
            $numTrailingZeros--
        } while ($current -gt $endIpAddress)
    

        # Now compare this new address with the original,
        # and handwave idk what this is for
        $prefixLen = 0
        while (([uint32]($current -band [math]::Pow(2, $prefixLen))) -ne ([uint32]($startIpAddress -band [math]::Pow(2, $prefixLen)))) {
            $prefixLen++
        }
        $prefixLen = 32 - $prefixLen

    
        # add this subnet to the output
        [byte[]]$bytes = @(
            (($startIpAddress -band [uint32]4278190080) -shr 24),
            (($startIpAddress -band [uint32]16711680) -shr 16),
            (($startIpAddress -band [uint32]65280) -shr 8),
             ($startIpAddress -band [uint32]255)
        )

        [ipaddress]::new($bytes).IpAddressToString + "/$prefixLen"
    
        # Add 1 to current IP
        [uint32]$startIpAddress = [uint32]($current + 1)

    }
}