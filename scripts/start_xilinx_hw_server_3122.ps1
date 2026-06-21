param(
    [string]$VivadoBin = "Z:\Softwares\Xilinx\Vivado\2024.2\bin",
    [int]$Port = 3122,
    [string]$HostName = "127.0.0.1"
)

$ErrorActionPreference = "Stop"

$hwServerBat = Join-Path $VivadoBin "hw_server.bat"
if (!(Test-Path -LiteralPath $hwServerBat)) {
    throw "hw_server.bat not found: $hwServerBat"
}

$existing = Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet
if ($existing) {
    Write-Host "hw_server already listening on ${HostName}:${Port}"
    exit 0
}

$title = "xilinx_hw_server_$Port"
$cmd = "/c start `"$title`" /min `"$hwServerBat`" -stcp::$Port"
Start-Process -FilePath "cmd.exe" -ArgumentList $cmd | Out-Null

for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-NetConnection -ComputerName $HostName -Port $Port -InformationLevel Quiet) {
        Write-Host "hw_server started on ${HostName}:${Port}"
        exit 0
    }
}

throw "Timed out waiting for hw_server on ${HostName}:${Port}"
