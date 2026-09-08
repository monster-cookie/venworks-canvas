$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedBuild.ps1')

# Product-specific reference parsers and source-test configuration.
function ConvertTo-CanvasUuid {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $hex = '[0-9a-fA-F]'
  $dashed = "$hex{8}-$hex{4}-$hex{4}-$hex{4}-$hex{12}"
  $format = if ($Value -cmatch "\A$dashed\z") { 'D' }
    elseif ($Value -cmatch "\A\{$dashed\}\z") { 'B' }
    elseif ($Value -cmatch "\A$hex{32}\z") { 'N' }
    else { throw 'Invalid consumer UUID shape.' }
  $parsed = [guid]::Empty
  if (![guid]::TryParseExact($Value, $format, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
    throw 'Invalid or nil consumer UUID.'
  }
  return $parsed.ToString('D').ToLowerInvariant()
}

function ConvertFrom-CanvasUiLoadPacket {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Packet)
  $prefix = 'VWC_EVT/1|canvas.ui.load|'
  if ($Packet.Length -gt 512 -or $Packet -cnotmatch '\A[\x20-\x7e]+\z' -or !$Packet.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid UI load envelope.'
  }
  $cursor = $prefix.Length
  $values = @()
  foreach ($maximum in @(1, 38, 4, 180, 180)) {
    $delimiter = $Packet.IndexOf(':', $cursor)
    if ($delimiter -le $cursor -or $delimiter - $cursor -gt 6) { throw 'Invalid UI load frame.' }
    $lengthText = $Packet.Substring($cursor, $delimiter - $cursor)
    if ($lengthText -cnotmatch '\A[0-9]+\z') { throw 'Invalid UI load frame length.' }
    $length = [int]$lengthText
    $cursor = $delimiter + 1
    if ($length -gt $maximum -or $cursor + $length -gt $Packet.Length) { throw 'Truncated or oversized UI load frame.' }
    $values += $Packet.Substring($cursor, $length)
    $cursor += $length
  }
  if ($cursor -ne $Packet.Length -or $values[0] -cne '1' -or $values[2] -cnotmatch '\A[0-9]{1,4}\z' -or [int]$values[2] -lt 1) {
    throw 'Invalid UI load protocol, version or trailing data.'
  }
  $id = ConvertTo-CanvasUuid -Value $values[1]
  $normal = [regex]::Match($values[3], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/normal\.swf\z', 'IgnoreCase')
  $large = [regex]::Match($values[4], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/large\.swf\z', 'IgnoreCase')
  if (!$normal.Success -or !$large.Success -or $normal.Groups[1].Value.Contains('..') -or $normal.Groups[1].Value -ine $large.Groups[1].Value) {
    throw 'UI load paths must share one safe local namespace.'
  }
  $root = 'VenworksCanvas/Consumers/' + $normal.Groups[1].Value.ToLowerInvariant() + '/'
  return [pscustomobject]@{ ConsumerId = $id; Version = [int]$values[2]; NormalPath = $root + 'normal.swf'; LargePath = $root + 'large.swf' }
}

function Get-CanvasMatrix {
  param(
    [string]$RepositoryRoot = ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
  )

  $matrixPath = Resolve-BuildRequiredFile `
    -Path (Join-Path $RepositoryRoot 'Scaleform\canvas\canvas-matrix.psd1') `
    -Description 'Canvas matrix'
  return Import-PowerShellDataFile -LiteralPath $matrixPath
}
