param(
    [Parameter(Mandatory = $true)][string]$PublishPath,
    [Parameter(Mandatory = $true)][string]$ArchivePath
)
$ErrorActionPreference = 'Stop'
$packageRoot = $env:NUGET_PACKAGES
if (-not $packageRoot) { $packageRoot = Join-Path $HOME '.nuget/packages' }
$dependencies = Get-Content (Join-Path $PublishPath 'Lumine.deps.json') -Raw | ConvertFrom-Json
foreach ($library in $dependencies.libraries.PSObject.Properties.Name) {
    if (-not $library.StartsWith('runtimepack.')) { continue }
    $package = $library.Substring('runtimepack.'.Length)
    $source = Join-Path $packageRoot $package.ToLowerInvariant()
    $destination = Join-Path $PublishPath (Join-Path 'licenses' $package)
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Get-ChildItem -Path $source -File | Where-Object { $_.Name -match 'LICENSE|NOTICE' } |
        Copy-Item -Destination $destination
}
Compress-Archive -Path (Join-Path $PublishPath '*') -DestinationPath $ArchivePath -Force
