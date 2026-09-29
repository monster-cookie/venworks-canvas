function Get-CanvasGeneralBa2Entries {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $resolvedPath = [IO.Path]::GetFullPath($Path)
  $stream = [IO.File]::OpenRead($resolvedPath)
  $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::UTF8, $true)
  try {
    if ($stream.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'BTDX') {
      throw "Canvas runtime archive is missing the BTDX signature: $resolvedPath"
    }
    $version = $reader.ReadUInt32()
    $archiveType = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
    $fileCount = $reader.ReadUInt32()
    $nameTableOffset = $reader.ReadUInt64()
    if ($version -ne 2 -or $archiveType -cne 'GNRL' -or $fileCount -eq 0 -or
        $fileCount -gt 10000 -or $nameTableOffset -ge [uint64]$stream.Length) {
      throw "Canvas runtime archive is not a supported version 2 General BA2: $resolvedPath"
    }
    [void]$reader.ReadUInt64()

    $recordTableEnd = 32L + (36L * [long]$fileCount)
    if ($recordTableEnd -gt [long]$nameTableOffset) {
      throw "Canvas runtime archive has an invalid record table: $resolvedPath"
    }
    $records = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $fileCount; $index++) {
      [void]$reader.ReadUInt32()
      [void]$reader.ReadBytes(4)
      [void]$reader.ReadUInt32()
      [void]$reader.ReadUInt32()
      $offset = $reader.ReadUInt64()
      $packedSize = $reader.ReadUInt32()
      $unpackedSize = $reader.ReadUInt32()
      [void]$reader.ReadUInt32()
      $storedSize = if ($packedSize -eq 0) { $unpackedSize } else { $packedSize }
      if ($unpackedSize -eq 0 -or $unpackedSize -gt 67108864 -or $offset -lt $recordTableEnd -or
          $offset + $storedSize -gt $nameTableOffset) {
        throw "Canvas runtime archive contains an invalid file record at index ${index}: $resolvedPath"
      }
      $records.Add([pscustomobject]@{
        ArchivePath = $resolvedPath
        Offset = $offset
        PackedSize = $packedSize
        UnpackedSize = $unpackedSize
      })
    }

    $stream.Position = [int64]$nameTableOffset
    for ($index = 0; $index -lt $fileCount; $index++) {
      $nameLength = $reader.ReadUInt16()
      if ($nameLength -eq 0 -or $nameLength -gt 1024 -or $stream.Position + $nameLength -gt $stream.Length) {
        throw "Canvas runtime archive contains an invalid name record at index ${index}: $resolvedPath"
      }
      $name = [Text.Encoding]::UTF8.GetString($reader.ReadBytes($nameLength)).Replace('\', '/')
      if ($name -match '(^/|^[A-Za-z]:|(?:^|/)\.\.(?:/|$))') {
        throw "Canvas runtime archive contains an unsafe entry name: $name"
      }
      $records[$index] | Add-Member -NotePropertyName Name -NotePropertyValue $name
    }
    return @($records)
  }
  finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Read-CanvasGeneralBa2EntryBytes {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Entry
  )

  if ([uint32]$Entry.PackedSize -ne 0) {
    throw "Canvas runtime archive entry must be uncompressed: $($Entry.Name)"
  }
  $length = [uint32]$Entry.UnpackedSize
  if ($length -eq 0 -or $length -gt 67108864) {
    throw "Canvas runtime archive entry has an unsupported length: $($Entry.Name)"
  }
  $bytes = [byte[]]::new([int]$length)
  $stream = [IO.File]::OpenRead([string]$Entry.ArchivePath)
  try {
    $stream.Position = [int64]$Entry.Offset
    $read = 0
    while ($read -lt $bytes.Length) {
      $count = $stream.Read($bytes, $read, $bytes.Length - $read)
      if ($count -eq 0) { break }
      $read += $count
    }
    if ($read -ne $bytes.Length) {
      throw "Canvas runtime archive entry is truncated: $($Entry.Name)"
    }
  }
  finally {
    $stream.Dispose()
  }
  return $bytes
}

function Get-CanvasRuntimeMovieText {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Bytes,

    [Parameter(Mandatory = $true)]
    [string]$Context
  )

  if ($Bytes.Length -lt 8) {
    throw "$Context is too short to be a Scaleform movie."
  }
  $signature = [Text.Encoding]::ASCII.GetString($Bytes, 0, 3)
  $declaredLength = [BitConverter]::ToUInt32($Bytes, 4)
  if ($declaredLength -lt 8 -or $declaredLength -gt 67108864) {
    throw "$Context has an invalid declared length."
  }
  if ($signature -ceq 'CWS') {
    $compressed = [IO.MemoryStream]::new($Bytes, 8, $Bytes.Length - 8, $false)
    $expanded = [IO.MemoryStream]::new()
    try {
      $zlib = [IO.Compression.ZLibStream]::new($compressed, [IO.Compression.CompressionMode]::Decompress)
      try { $zlib.CopyTo($expanded) }
      finally { $zlib.Dispose() }
      $payload = $expanded.ToArray()
    }
    finally {
      $expanded.Dispose()
      $compressed.Dispose()
    }
    if ($payload.Length + 8 -ne $declaredLength) {
      throw "$Context decompressed length differs from its header."
    }
    $uncompressed = [byte[]]::new([int]$declaredLength)
    [Array]::Copy($Bytes, 0, $uncompressed, 0, 8)
    [Array]::Copy($payload, 0, $uncompressed, 8, $payload.Length)
    return [Text.Encoding]::UTF8.GetString($uncompressed)
  }
  if ($signature -ceq 'FWS' -or $signature -ceq 'GFX') {
    if ($Bytes.Length -ne $declaredLength) {
      throw "$Context length differs from its header."
    }
    return [Text.Encoding]::UTF8.GetString($Bytes)
  }
  throw "$Context has unsupported Scaleform signature '$signature'."
}

function Assert-CanvasRuntimeArchive {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$ContractPath,

    [switch]$RequireRegistry
  )

  $entries = @(Get-CanvasGeneralBa2Entries -Path $Path)
  $entriesByName = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $entries) {
    if ($entriesByName.ContainsKey([string]$entry.Name)) {
      throw "Canvas runtime archive contains a duplicate entry: $($entry.Name)"
    }
    $entriesByName.Add([string]$entry.Name, $entry)
  }

  $contract = Import-PowerShellDataFile -LiteralPath $ContractPath
  if ([string]$contract.Schema -cne 'VWCANVAS_RUNTIME_PACKAGE/1' -or
      [string]::IsNullOrWhiteSpace([string]$contract.HostEntry) -or
      [string]::IsNullOrWhiteSpace([string]$contract.RegistryEntry) -or
      @($contract.HostRequiredTokens).Count -eq 0 -or
      @($contract.RegistryRequiredTokens).Count -eq 0) {
    throw "Canvas runtime package contract is invalid: $ContractPath"
  }

  $hostName = [string]$contract.HostEntry
  if (!$entriesByName.ContainsKey($hostName)) {
    throw "Canvas runtime archive is missing ${hostName}: $Path"
  }
  $hostBytes = [byte[]](Read-CanvasGeneralBa2EntryBytes -Entry $entriesByName[$hostName])
  $hostText = Get-CanvasRuntimeMovieText -Bytes $hostBytes -Context "Canvas host in $Path"
  foreach ($token in @($contract.HostRequiredTokens)) {
    if ([string]::IsNullOrWhiteSpace([string]$token)) {
      throw "Canvas runtime package contract contains an empty host token: $ContractPath"
    }
    if (!$hostText.Contains([string]$token)) {
      throw "Canvas runtime archive host is missing current required token '${token}': $Path"
    }
  }
  $hostHash = Get-CanvasSha256Hex -Bytes $hostBytes
  $expectedHostHash = [string]$contract.HostSha256
  if ($expectedHostHash -cnotmatch '\A[A-F0-9]{64}\z' -or $hostHash -cne $expectedHostHash) {
    throw "Canvas runtime archive host hash $hostHash does not match the packaged source build '$expectedHostHash': $Path"
  }
  $sourceHash = Get-CanvasHostSourceSha256 -ContractPath $ContractPath
  $expectedSourceHash = [string]$contract.HostSourceSha256
  if ($expectedSourceHash -cnotmatch '\A[A-F0-9]{64}\z' -or $sourceHash -cne $expectedSourceHash) {
    throw "Canvas host source hash $sourceHash does not match the packaged source build '$expectedSourceHash': $ContractPath"
  }
  foreach ($token in @($contract.HostForbiddenTokens)) {
    if ([string]::IsNullOrWhiteSpace([string]$token)) {
      throw "Canvas runtime package contract contains an empty forbidden token: $ContractPath"
    }
    if ($hostText.Contains([string]$token)) {
      throw "Canvas runtime archive host contains forbidden token '${token}': $Path"
    }
  }

  if ($RequireRegistry) {
    $registryName = [string]$contract.RegistryEntry
    if (!$entriesByName.ContainsKey($registryName)) {
      throw "Canvas runtime archive is missing ${registryName}: $Path"
    }
    $registryBytes = [byte[]](Read-CanvasGeneralBa2EntryBytes -Entry $entriesByName[$registryName])
    $registryText = [Text.Encoding]::UTF8.GetString($registryBytes)
    foreach ($token in @($contract.RegistryRequiredTokens)) {
      if ([string]::IsNullOrWhiteSpace([string]$token)) {
        throw "Canvas runtime package contract contains an empty Registry token: $ContractPath"
      }
      if (!$registryText.Contains($token)) {
        throw "Canvas runtime archive Registry.pex is missing current API '${token}': $Path"
      }
    }
    $registryHash = Get-CanvasSha256Hex -Bytes $registryBytes
    $expectedRegistryHash = [string]$contract.RegistrySha256
    if ($expectedRegistryHash -cnotmatch '\A[A-F0-9]{64}\z' -or $registryHash -cne $expectedRegistryHash) {
      throw "Canvas runtime archive Registry.pex hash $registryHash does not match the packaged source build '$expectedRegistryHash': $Path"
    }
  }

  Write-Host -ForegroundColor Green "Verified Canvas runtime contract in $([IO.Path]::GetFileName($Path))."
}

function Get-CanvasSha256Hex {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
  finally { $sha.Dispose() }
}

function Get-CanvasHostSourceSha256 {
  param([Parameter(Mandatory = $true)][string]$ContractPath)
  $sourceRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent (Split-Path -Parent $ContractPath)) 'actionscript'))
  if (!(Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Canvas host source root does not exist: $sourceRoot"
  }
  $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.as' | Sort-Object { $_.FullName.Replace('\','/') })
  if ($files.Count -eq 0) { throw "Canvas host source root contains no ActionScript: $sourceRoot" }
  $sha = [Security.Cryptography.SHA256]::Create()
  $utf8 = [Text.UTF8Encoding]::new($false)
  try {
    foreach ($file in $files) {
      $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\','/').Replace('\','/') + "`n"
      $prefix = $utf8.GetBytes($relative)
      [void]$sha.TransformBlock($prefix, 0, $prefix.Length, $null, 0)
      $content = [IO.File]::ReadAllBytes($file.FullName)
      [void]$sha.TransformBlock($content, 0, $content.Length, $null, 0)
    }
    [void]$sha.TransformFinalBlock(@(), 0, 0)
    return ([BitConverter]::ToString($sha.Hash)).Replace('-','')
  }
  finally { $sha.Dispose() }
}
