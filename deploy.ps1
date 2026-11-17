# Push the W200 speaker files to the phone and (re)start the receivers.
param(
    [switch]$NoRestart,
    [string]$Adb = (Join-Path $env:USERPROFILE 'platform-tools\adb.exe')   # or just 'adb' if it's on PATH
)
$ErrorActionPreference = 'Continue'   # adb prints progress on stderr
$adb  = $Adb
$root = $PSScriptRoot
$D    = '/data/local/tmp/w200'

& $adb shell "mkdir -p $D/dalvik-cache $D/cache"
if (& $adb shell "ls $D/w200ctl.sh 2>/dev/null") { & $adb shell "sh $D/w200ctl.sh stop" }

# phone scripts: force LF line endings
foreach ($f in @(Get-ChildItem "$root\phone\*" -Include *.sh, *.conf) + @(Get-Item "$root\phone\system\install-recovery.sh")) {
    $tmp = Join-Path $env:TEMP $f.Name
    [IO.File]::WriteAllText($tmp, ([IO.File]::ReadAllText($f.FullName) -replace "`r", ''), (New-Object Text.UTF8Encoding($false)))
    & $adb push $tmp "$D/$($f.Name)" | Out-Null
    Remove-Item $tmp
}
foreach ($b in 'librespot', 'shairport-sync', 'daemonize', 'asshell', 'mdnsq', 'w200pcm.jar') {
    $p = Join-Path "$root\out" $b
    if (Test-Path $p) { & $adb push $p "$D/$b" | Out-Null }
}
# Spotify Soloist (official client) + glibc runtime + w200pulse; only pushed when present
if (Test-Path "$root\out\soloist\soloist") {
    & $adb push "$root\out\soloist" "$D/" | Select-Object -Last 1
    & $adb shell "chmod 755 $D/soloist/soloist $D/soloist/lib/*"
}
# Soloist API key: kept in soloist-api-key.txt next to this script (never printed)
$keyFile = Join-Path $root 'soloist-api-key.txt'
if (Test-Path $keyFile) {
    $key = (Get-Content $keyFile -Raw).Trim()
    if ($key) {
        $tmpKey = Join-Path $env:TEMP 'w200-soloist.key'
        [IO.File]::WriteAllText($tmpKey, $key, (New-Object Text.UTF8Encoding($false)))
        & $adb push $tmpKey "$D/soloist.key" | Out-Null
        Remove-Item $tmpKey
        & $adb shell "chmod 600 $D/soloist.key"
        'Soloist API key installed'
    }
}
& $adb shell "chmod 755 $D/*.sh $D/daemonize $D/asshell $D/mdnsq $D/librespot $D/shairport-sync 2>/dev/null; ls -l $D"
Start-Sleep 1
if (-not $NoRestart) { & $adb shell "sh $D/w200ctl.sh start"; Start-Sleep 5; & $adb shell "sh $D/w200ctl.sh status" }
