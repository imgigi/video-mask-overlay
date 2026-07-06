$ErrorActionPreference = "Stop"

$project = Join-Path $PSScriptRoot "..\WindowsMaskOverlay\WindowsMaskOverlay.csproj"
$publish = Join-Path $PSScriptRoot "..\WindowsMaskOverlay\bin\Release\net8.0-windows\win-x64\publish"
$dist = Join-Path $PSScriptRoot "..\dist"

dotnet publish $project `
  -c Release `
  -r win-x64 `
  --self-contained true `
  /p:PublishSingleFile=true `
  /p:IncludeNativeLibrariesForSelfExtract=true `
  /p:EnableCompressionInSingleFile=true `
  /p:DebugType=None `
  /p:DebugSymbols=false

New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item (Join-Path $PSScriptRoot "..\WindowsMaskOverlay\README.md") (Join-Path $publish "README.txt") -Force
Compress-Archive -Path (Join-Path $publish "*") -DestinationPath (Join-Path $dist "WindowsMaskOverlay-win-x64.zip") -Force

Write-Host "Created dist\WindowsMaskOverlay-win-x64.zip"
