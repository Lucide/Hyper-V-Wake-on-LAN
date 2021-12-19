<#
.SYNOPSIS
Hyper-V Wake-on-LAN listener
.DESCRIPTION
Listens for Wake On Lan packets, and starts all the Hyper-V VMs with the matching MAC address.
.PARAMETER Port
The UDP port to listen on, defaults to 7.
.PARAMETER Loop
Keep processing WOL packets indefinitely.
.PARAMETER All
Include non-external virtual switches. By default, the script ignores virtual adapters connected to Private or Internal switches,
since they aren't supposed to be reachable outside.
.PARAMETER RegisterJob
Register a scheduled startup job, with the provided arguments. If the job already exists, it will be replaced.
The scheduled job will be self-contained, you can then delete this file safely.
.PARAMETER UnregisterJob
Remove the scheduled job, equivalent to "Unregister-ScheduledJob -Name 'Hyper-V WOL'"".
If '-RegisterJob' is also provided, it will take precedence.
.INPUTS
None. You cannot pipe objects to psHyper-V_WoL.ps1
.OUTPUTS
None. psHyper-V_WoL.ps1 does not generate any output
.EXAMPLE
PS> psHyper-V_WoL.ps1
Listens on port 7 for a WOL packet, starts the matching VMs and terminates.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -Port 9 -Loop
Listens on port 9 for incoming WOL packets and starts the matching VMs.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -Port 9 -Loop -All -RegisterJob
Registers a startup job with the provided parameters. Does not perform any additional operation.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -UnregisterJob
Removes the startup job. Additional parameters are unnecessary.
.NOTES
History:
v0.1 - Daniel Oxley - Initial version
V0.2 - Daniel Oxley - Tidy up messages in console window and added Time/Date information
V1.0 - Lucide - see https://github.com/Lucide/Hyper-V-Wake-on-LAN

Please maintain this header and provide credit to author.
You are free to use this code for non-commercial reasons.  No support is provided whatsoever and you use it at your own risk.
No responsibility by the author is accepted.

(c) 2016 - Daniel Oxley
.LINK
https://github.com/Lucide/Hyper-V-Wake-on-LAN
.LINK
https://deploymentpros.wordpress.com/2016/11/28/wake-on-lan-for-hyper-v-guests
#>

param([parameter(HelpMessage = 'The UDP port to listen on, defaults to 7')]
    [PSDefaultValue(Help = '7')]
    [Int]$Port = 7,
    [parameter(HelpMessage = 'Keep processing WOL packets indefinitely')]
    [switch]$Loop,
    [parameter(HelpMessage = 'Include non-external virtual switches')]
    [switch]$All,
    [parameter(HelpMessage = 'Register a scheduled startup job, with the provided arguments')]
    [switch]$RegisterJob,
    [parameter(HelpMessage = 'Remove the scheduled job')]
    [switch]$UnregisterJob
)
    
$argList = $Port, $Loop, $All

$script = {
    param(
        [Parameter(Mandatory)]
        [Int]$Port,
        [Parameter(Mandatory)]
        [bool]$Loop,
        [Parameter(Mandatory)]
        [bool]$All
    )
    function Receive-UDPMessage{    
        param([parameter(Mandatory)]
            [Int]$Port,
            [parameter(Mandatory)]
            [bool]$Loop
        )
    
        try{
            $endpoint = new-object System.Net.IPEndPoint ([IPAddress]::Any, $port)
            $udpClient = new-Object System.Net.Sockets.UdpClient $port
    
            do{
                Write-Host
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Waiting for message on UDP port $Port..."
                Write-Host
            
                $content = $udpClient.Receive([ref]$endpoint)
                # $strContent = $([Text.Encoding]::ASCII.GetString($content))
    
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Message received from: $($endpoint.address.toString()):$($endpoint.Port)"
    
                $tmpVal = ''
                $receivedMac = ''
    
                for($i = 6; $i -lt 12; $i++){
                    $tmpVal = [convert]::tostring($content[$i], 16)
                    if($tmpVal.Length -lt 2){
                        $tmpVal = '0' + $tmpVal 
                    }
                    $receivedMac = $receivedMac + $tmpVal.ToUpper()
                }
    
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "WoL MAC address received: $(FormatMac $receivedMac )"
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Searching MAC addresses on Hyper-V host $myFQDN"
    
                if($arrMacs.ContainsKey($receivedMac)){
                    $arrVMs = $arrMacs.$receivedMac
                    Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Matched MAC address: $(FormatMac $receivedMac )"
                    StartVMs($arrVMs)
                } else{
                    Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') 'No VM found on host that matches the MAC address received.'
                }
    
                Write-Host
                Write-Host '-------------------------------------------------------------------------------'
            }while($Loop)
        } catch [system.exception]{
            throw $error[0]
        } finally{
            Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') 'Closing connection.'
            $udpClient.Close()
        }
    }
    function StartVMs{
        param(
            [parameter(Mandatory)]
            [Microsoft.HyperV.PowerShell.VirtualMachine[]]$VMs
        )
    
        foreach($VM in $VMs){
            Write-Host "Starting VM: $($VM.Name)"
            Start-VM $VM
        }
    }
    function FormatMac{
        param(
            [parameter(Mandatory)]
            [string]$MacToFormat
        )
    
        $MacToFormat = $MacToFormat.Insert(2, ':')
        $MacToFormat = $MacToFormat.Insert(5, ':')
        $MacToFormat = $MacToFormat.Insert(8, ':')
        $MacToFormat = $MacToFormat.Insert(11, ':')
        $MacToFormat = $MacToFormat.Insert(14, ':')
    
        return $MacToFormat
    }

    $myFQDN = (Get-WmiObject win32_ComputerSystem).DNSHostName + '.' + (Get-WmiObject win32_ComputerSystem).Domain
    $objVMs = Get-VM

    if($objVMs.Count -gt 0){
        Write-Host
        Write-Host "The following Virtual Machines have been found on Hyper-V host $($myFQDN):"
        Write-Host
        Write-Host 'MAC Address        ¦ VM Name'
        Write-Host '-------------------¦-------------------'

        $arrMacs = @{}
    
        forEach($VM in $objVMs){
            forEach($objAdapter in $VM.NetworkAdapters){
                if((Get-VMSwitch -Id ($objAdapter.SwitchId)).SwitchType -eq 'External' -or $All){
                    $strMac = $objAdapter.MacAddress.Trim()
                    if($arrMacs.ContainsKey($strMac)){
                        $arrMacs.$strMac += $VM
                    } else{
                        $arrMacs.Add($strMac, $VM)
                    }
                    Write-Host "$(FormatMac $strMac)  ¦ $($VM.Name)"
                }
            }
        }

        Write-Host '-------------------¦-------------------'
        Write-Host
        Write-Host
        Write-Host '*******************************************************************************'

        Receive-UDPMessage $Port $Loop
    } else{
        Write-Host 'ERROR: No virtual machines found on host! (Is Hyper-V even enabled?)'
    }
    exit(0)
}

if($RegisterJob -or $UnregisterJob){
    $name = 'Hyper-V WOL'
    Unregister-ScheduledJob $name -ErrorAction SilentlyContinue

    if($RegisterJob){
        $trigger = New-JobTrigger -AtStartup
        $options = New-ScheduledJobOption -RunElevated -IdleDuration 0 
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0
        Register-ScheduledJob -ScriptBlock $script -Name $name -Trigger $trigger -ScheduledJobOption $options -ArgumentList $argList
        # disable three days execution limit
        Set-ScheduledTask -TaskName $name -TaskPath '\Microsoft\Windows\PowerShell\ScheduledJobs' -Settings $settings

        Write-Host 'A startup job has been created, it''s self-contained, so you can now delete this script.'
        Write-Host "To removed it, run with -UnregisterJob or use ""Unregister-ScheduledJob -Name '$name'"" in a Powershell shell."
    }
} else{
    Invoke-Command -ScriptBlock $script -ArgumentList $argList
}
exit(0)
