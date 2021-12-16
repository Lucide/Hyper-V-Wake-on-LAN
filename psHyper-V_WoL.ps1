# --------------------------------------------------------------------------------------------------------
# Hyper-V Wake-on-LAN Listener
# (c) 2016 - Daniel Oxley - https://deploymentpros.wordpress.com/2016/11/28/wake-on-lan-for-hyper-v-guests
#
# Please maintain this header and provide credit to author.
#
# You are free to use this code for non-commercial reasons.  No support is provided
# whatsoever and you use it at your own risk.  No responisibility by the author is
# accepted.
#
# History:
# v0.1 - Daniel Oxley - Initial version
# V0.2 - Daniel Oxley - Tidy up messages in console window and added Time/Date information
#
# Usage:
# psHyper-V_WoL.ps1 [UDP port number] [Loop until end]
# ex: psHyper-V_WoL.ps1 7 -Loop
# ex: psHyper-V_WoL.ps1 7
#
# Error codes:
#  0 - execution successful
#  1 - incorrect command line specified
# --------------------------------------------------------------------------------------------------------

param([parameter(Mandatory = $True, Position = 0, HelpMessage = 'The UDP port to listen on')]
    [Int]$Port,
    [parameter(HelpMessage = 'Boolean value to specify whether the code should continue listening after processing 1 message or quit')]
    [switch]$Loop
)

function Receive-UDPMessage {
    [CmdletBinding(DefaultparameterSetName = 'Relevance', SupportsShouldProcess = $False)]

    param([parameter(Mandatory = $True, Position = 0, HelpMessage = 'The UDP port to listen on')]
        [Int]$Port,
        [parameter(Mandatory = $True, Position = 1, HelpMessage = 'Boolean value to specify whether the code should continue listening after processing 1 message or quit')]
        [bool]$Loop
    )

    try {
        $endpoint = new-object System.Net.IPEndPoint ([IPAddress]::Any, $port)
        $udpclient = new-Object System.Net.Sockets.UdpClient $port

        do {
            Write-Host
            Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "Waiting for message on UDP port $Port..."
            Write-Host ""
        
            $content = $udpclient.Receive([ref]$endpoint)
            # $strContent = $([Text.Encoding]::ASCII.GetString($content))

            Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "Message received from: $($endpoint.address.toString()):$($endpoint.Port)"

            $tmpVal = ""
            $receivedMac = ""

            for ($i = 6; $i -lt 12; $i++) {
                $tmpVal = [convert]::tostring($content[$i], 16)
                if ($tmpVal.Length -lt 2) { $tmpVal = "0" + $tmpVal }
                $receivedMac = $receivedMac + $tmpVal.ToUpper()
            }

            Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "WoL MAC address received: $(FormatMac -MacToFormat $receivedMac)"
            Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "Searching MAC addresses on Hyper-V host $myFQDN"

            if ($arrMacs.ContainsKey($receivedMac)) {
                $arrVMs = $arrMacs.$receivedMac
                Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "Matched MAC address: $(FormatMac -MacToFormat $receivedMac)"
                StartVMs -VMs $arrVMs
            }
            else {
                Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "No VM found on host that matches the MAC address received."
            }

            Write-Host
            Write-Host "-------------------------------------------------------------------------------"
        }while ($Loop)
    }
    catch [system.exception] {
        throw $error[0]
    }
    finally {
        Write-Host (Get-Date).ToString("yyyy/MM/dd HH:MM:ss") "Closing connection."
        $udpclient.Close()
    }
}

function StartVMs {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [Microsoft.HyperV.PowerShell.VirtualMachine[]]$VMs
    )

    foreach ($VM in $VMs) {
        Write-Host "Starting VM: $($VM.Name)"
        Start-VM -VM $VM
    }
}

function FormatMac {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$MacToFormat
    )

    $MacToFormat = $MacToFormat.Insert(2, ":")
    $MacToFormat = $MacToFormat.Insert(5, ":")
    $MacToFormat = $MacToFormat.Insert(8, ":")
    $MacToFormat = $MacToFormat.Insert(11, ":")
    $MacToFormat = $MacToFormat.Insert(14, ":")

    return $MacToFormat

}

$myFQDN = (Get-WmiObject win32_ComputerSystem).DNSHostName + "." + (Get-WmiObject win32_ComputerSystem).Domain

$objVMs = Get-VM

if ($objVMs.Count -eq 0) {
    Write-Host "ERROR: No virtual machines found on host!"
}
else {
    Write-Host
    Write-Host "The following Virtual Machines have been found on Hyper-V host $($myFQDN):"
    Write-Host
    Write-Host "MAC Address        ¦ VM Name"
    Write-Host "-------------------¦-------------------"

    $arrMacs = @{}
    
    forEach ($VM in $objVMs) {
        forEach ($objMac in $VM.NetworkAdapters) {
            $strMac = $objMac.MacAddress.Trim()
            if ($arrMacs.ContainsKey($strMac)) {
                $arrMacs.$strMac += $VM
            }
            else {
                $arrMacs.Add($strMac, $VM)
            }
            Write-Host "$(FormatMac -MacToFormat $strMac)  ¦ $($VM.Name)"
        }
    }

    Write-Host "-------------------¦-------------------"
    Write-Host
    Write-Host
    Write-Host "*******************************************************************************"

    Receive-UDPMessage -Port $Port -Loop $Loop

    exit(0)
}