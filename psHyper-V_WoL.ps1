<#
.SYNOPSIS
Hyper-V Wake-on-LAN listener
.DESCRIPTION
Listens for Wake On Lan packets, and starts all the Hyper-V VMs with the matching MAC address.
.PARAMETER Port
The UDP port to listen on, defaults to 7.
.PARAMETER Once
Process a single WOL packet.
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
Listens on port 7 for incoming WOL packets and starts the matching VMs.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -Port 9 -Once
Listens on port 9 for a WOL packet, starts the matching VMs and terminates.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -Port 9 -Once -All -RegisterJob
Registers a startup job with the provided parameters. Does not perform any additional operation.
.EXAMPLE
PS> psHyper-V_WoL.ps1 -UnregisterJob
Removes the startup job. Additional parameters are unnecessary.
.NOTES
Originally written by:
Daniel Oxley

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
    [parameter(HelpMessage = 'Process a single WOL packet')]
    [switch]$Once,
    [parameter(HelpMessage = 'Include non-external virtual switches')]
    [switch]$All,
    [parameter(HelpMessage = 'Register a scheduled startup job, with the provided arguments')]
    [switch]$RegisterJob,
    [parameter(HelpMessage = 'Remove the scheduled job')]
    [switch]$UnregisterJob
)

$jobEnv = @{ Port = $Port; Once = $Once; All = $All }

$script = {
    function Open-Socket {
        param([parameter(Mandatory)]
            [Int]$Port
        )

        $socketAttempt = 1
        do {
            try {
                $endpoint = New-Object System.Net.IPEndPoint ([IPAddress]::Any, $port)
                $udpClient = New-Object System.Net.Sockets.UdpClient $port
                return $endpoint, $udpClient
            } catch [System.Net.Sockets.SocketException] {
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "attempt $socketAttempt/5: Failed to create socket. (another instance already running?)" -ForegroundColor Red
                Write-Error $_
                Start-Sleep -Seconds 10
                ++$socketAttempt
            }
        }while ($socketAttempt -le 5)
        return $null
    }


    function Receive-UDPMessage {    
        param([parameter(Mandatory)]
            [Int]$Port,
            [parameter(Mandatory)]
            [bool]$Once
        )
    
        $endpoint, $udpClient = Open-Socket $Port
        if (!$endpoint) {
            exit(-7)
        }
        do {
            try {
                Write-Host
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Waiting for message on UDP port $Port..."
                Write-Host
            
                do {
                    $content = $udpClient.Receive([ref]$endpoint)
                }while ($content.Length -lt 12)

                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "Message received from: $($endpoint.address.toString()):$($endpoint.Port)"
    
                $receivedMac = ''
                for ($i = 6; $i -lt 12; ++$i) {
                    $receivedMac = $receivedMac + ('{0:X2}' -f [int]$content[$i])
                }    
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') "WoL MAC address received: $(FormatMac $receivedMac )"
                if ($arrMacs.ContainsKey($receivedMac)) {
                    StartVMs($arrMacs.$receivedMac)
                } else {
                    Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') 'No VM found on host that matches the MAC address received.'
                }
                Write-Host
            } catch {
                Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') 'An error occurred while listening:' -ForegroundColor Red
                Write-Error $_
                $udpClient.Close()
                $endpoint, $udpClient = Open-Socket $Port
                if (!$endpoint) {
                    break
                }
            } 
        }while (!$Once)
        Write-Host (Get-Date).ToString('yyyy/MM/dd HH:MM:ss') 'Closing connection.'
        $udpClient.Close()
    }
    function StartVMs {
        param(
            [parameter(Mandatory)]
            [Microsoft.HyperV.PowerShell.VirtualMachine[]]$VMs
        )
    
        foreach ($VM in $VMs) {
            Write-Host "Starting VM: $($VM.Name)"
            if ($VM.State -eq 'off') {
                Start-VM $VM
            } elseif ($VM.State -eq 'paused') {
                Resume-VM $VM
            } else {
                Write-Host "$($VM.Name) already running."
            }
        }
    }
    function FormatMac {
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

    if ($objVMs.Count -le 0) {
        Write-Error 'ERROR: No virtual machines found on host! (Is Hyper-V even enabled?)'
        exit(1)
    }

    Write-Host
    Write-Host "The following Virtual Machines have been found on Hyper-V host $($myFQDN):"
    Write-Host
    Write-Host 'MAC Address        | VM Name'
    Write-Host '-------------------|-------------------'

    $arrMacs = @{}
    
    forEach ($VM in $objVMs) {
        forEach ($objAdapter in $VM.NetworkAdapters) {
            if ((Get-VMSwitch -Id ($objAdapter.SwitchId)).SwitchType -eq 'External' -or $All) {
                $strMac = $objAdapter.MacAddress.Trim()
                if ($arrMacs.ContainsKey($strMac)) {
                    $arrMacs.$strMac += $VM
                } else {
                    $arrMacs.Add($strMac, $VM)
                }
                Write-Host "$(FormatMac $strMac)  | $($VM.Name)"
            }
        }
    }
    Write-Host '-------------------|-------------------'
    Write-Host

    Receive-UDPMessage $Port $Once
    exit(0)
}

function createJobEnv {
    param(
        [parameter(Mandatory)]
        $jobEnv
    )
    $initScript = @('$env = @''')
    $initScript += [System.Management.Automation.PSSerializer]::Serialize($jobEnv)
    $initScript += '''@'
    $initScript += {
        $env = [System.Management.Automation.PSSerializer]::Deserialize($env)
        foreach ($var in $env.GetEnumerator()) {
            Set-Variable -Name $var.Key -Value $var.Value
        }
    }.toString()
    return [scriptblock]::Create(($initScript -join "`n"))
}

if ($RegisterJob -or $UnregisterJob) {
    $name = 'Hyper-V WOL'
    Unregister-ScheduledJob $name -ErrorAction SilentlyContinue
    if ($RegisterJob) {
        $trigger = New-JobTrigger -AtStartup -RandomDelay 00:00:30
        $options = New-ScheduledJobOption -RunElevated
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0
        Register-ScheduledJob -InitializationScript (createJobEnv $jobEnv) -ScriptBlock $script -Name $name -Trigger $trigger -ScheduledJobOption $options
        # disable three days execution limit
        Set-ScheduledTask -TaskName $name -TaskPath '\Microsoft\Windows\PowerShell\ScheduledJobs' -Settings $settings

        Write-Host 'A startup job has been created, it''s self-contained, so you can now delete this script.'
        Write-Host "To removed it, run with -UnregisterJob or use ""Unregister-ScheduledJob -Name '$name'"" in a Powershell shell."
    }
} else {
    Invoke-Command -NoNewScope -ScriptBlock $script
}
exit(0)
