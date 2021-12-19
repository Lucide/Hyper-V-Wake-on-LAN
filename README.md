# Hyper-V Wake-on-LAN listener

Listens for Wake On Lan packets, and starts all the Hyper-V VMs with the matching MAC address.

* `-Port`\
The UDP port to listen on, defaults to 7.
* `-Loop`\
Keep processing WOL packets indefinitely.
* `-All`\
Include non-external virtual switches. By default, the script ignores virtual adapters connected to *Private* or *Internal* switches, since they aren't supposed to be reachable outside.
* `-RegisterJob`\
Register a startup job, with the provided arguments. If the job already exists, it will be replaced.
The scheduled job will be self-contained, you can then delete this file safely.
* `-UnregisterJob`\
Remove the scheduled job, equivalent to `Unregister-ScheduledJob -Name 'Hyper-V WOL'`.\
If `-RegisterJob` is also provided, it will take precedence.

## Examples

* `PS> psHyper-V_WoL.ps1`\
Listens on port 7 for a WOL packet, starts the matching VMs and terminates.
* `PS> psHyper-V_WoL.ps1 -Port 9 -Loop`\
Listens on port 9 for incoming WOL packets and starts the matching VMs.
* `PS> psHyper-V_WoL.ps1 -Port 9 -Loop -All -RegisterJob`\
Registers a startup job with the provided parameters. Does not perform any additional operation.
* `PS> psHyper-V_WoL.ps1 -UnregisterJob`\
Removes the startup job. Additional parameters are unnecessary.

### Originally written by:

```txt
v0.1 - Daniel Oxley - Initial version
V0.2 - Daniel Oxley - Tidy up messages in console window and added Time/Date information

(c) 2016 - Daniel Oxley https://deploymentpros.wordpress.com/2016/11/28/wake-on-lan-for-hyper-v-guests
