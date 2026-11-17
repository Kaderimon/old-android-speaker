# Ask the LAN who offers a service (legacy unicast mDNS query) and print the names that answer.
param([string]$Service = '_spotify-connect._tcp.local', [int]$WaitMs = 3000)
$q = New-Object System.Collections.Generic.List[byte]
$q.AddRange([byte[]](0,0, 0,0, 0,1, 0,0, 0,0, 0,0))          # header: 1 question
foreach ($label in $Service.Split('.')) { $b = [Text.Encoding]::ASCII.GetBytes($label); $q.Add([byte]$b.Length); $q.AddRange($b) }
$q.AddRange([byte[]](0, 0,12, 0,1))                            # PTR, IN
$u = New-Object Net.Sockets.UdpClient(0)
$u.Client.ReceiveTimeout = 500
[void]$u.Send($q.ToArray(), $q.Count, '224.0.0.251', 5353)
$deadline = (Get-Date).AddMilliseconds($WaitMs); $seen = @{}
while ((Get-Date) -lt $deadline) {
    try {
        $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $data = $u.Receive([ref]$ep)
        $txt = -join ($data | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { '.' } })
        $key = "$($ep.Address)"
        if (-not $seen[$key]) { $seen[$key] = 1; "{0} answered: {1}" -f $ep.Address, ($txt -replace '\.{2,}', ' | ') }
    } catch { }
}
$u.Close()
if ($seen.Count -eq 0) { "No answers for $Service" }
