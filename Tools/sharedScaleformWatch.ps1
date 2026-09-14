$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-BuildWatchRemovalPatch {
  param(
    [Parameter(Mandatory = $true)][string]$PatchPath,
    [AllowEmptyString()][string]$DisplayMode
  )

  $resolvedPatchPath = Resolve-BuildRequiredFile -Path $PatchPath -Description 'Watch removal patch'
  if (![string]::IsNullOrWhiteSpace($DisplayMode)) {
    throw "Watch removal patch '$resolvedPatchPath' does not support DisplayMode configuration."
  }

  [xml]$document = Get-Content -LiteralPath $resolvedPatchPath -Raw
  $removal = $document.watchRemoval
  if ($null -eq $removal -or
      [string]$removal.schema -cne 'VWCANVAS_WATCH_REMOVAL/1' -or
      [string]$removal.instanceName -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z' -or
      [string]$removal.className -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z' -or
      [string]$removal.placeTagType -cnotmatch '\APlaceObject[234]?Tag\z') {
    throw "Invalid Watch removal patch: $resolvedPatchPath"
  }

  $rootDepth = 0
  if (![int]::TryParse([string]$removal.rootDepth, [ref]$rootDepth) -or $rootDepth -le 0) {
    throw "Invalid Watch removal root depth in patch: $resolvedPatchPath"
  }

  return [pscustomobject]@{
    Kind = 'WatchRemoval'
    Path = $resolvedPatchPath
    InstanceName = [string]$removal.instanceName
    ClassName = [string]$removal.className
    PlaceTagType = [string]$removal.placeTagType
    RootDepth = $rootDepth
    DisplayMode = $null
  }
}

function Get-BuildWatchReferenceRewrite {
  param([Parameter(Mandatory = $true)][string]$RewritePath)

  $resolvedRewritePath = Resolve-BuildRequiredFile -Path $RewritePath -Description 'Watch reference rewrite'
  [xml]$document = Get-Content -LiteralPath $resolvedRewritePath -Raw
  $rewrite = $document.watchReferenceRewrite
  if ($null -eq $rewrite) {
    throw "Invalid Watch reference rewrite: $resolvedRewritePath"
  }

  $structuralRemoval = $rewrite.structuralRemoval
  $exactRemovals = @($rewrite.SelectNodes('exactRemovals/removal') | ForEach-Object { [string]$_.InnerText })
  $rangeReplacements = @($rewrite.SelectNodes('rangeReplacements/replacement') | ForEach-Object {
    [pscustomobject]@{
      StartAnchor = [string]$_.startAnchor.InnerText
      EndAnchor = [string]$_.endAnchor.InnerText
      Content = [string]$_.content.InnerText
      ExpectedSpanSha256 = @($_.SelectNodes('expectedSpanSha256/hash') | ForEach-Object { [string]$_.InnerText })
    }
  })
  $forbiddenInspectionTokens = @($rewrite.SelectNodes('validation/forbiddenInspectionTokens/token') | ForEach-Object { [string]$_.InnerText })
  if ([string]$rewrite.schema -cne 'VWCANVAS_WATCH_REFERENCE_REWRITE/1' -or
      [string]$rewrite.script -cnotmatch '\A[A-Za-z_][A-Za-z0-9_.]*\z' -or
      $null -eq $structuralRemoval -or
      [string]$structuralRemoval.instanceName -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z' -or
      [string]$structuralRemoval.className -cnotmatch '\A[A-Za-z_][A-Za-z0-9_]*\z' -or
      [string]$structuralRemoval.placeTagType -cnotmatch '\APlaceObject[234]?Tag\z' -or
      $exactRemovals.Count -eq 0 -or
      $rangeReplacements.Count -eq 0 -or
      $forbiddenInspectionTokens.Count -eq 0 -or
      @($exactRemovals | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0 -or
      @($rangeReplacements | Where-Object {
        [string]::IsNullOrWhiteSpace($_.StartAnchor) -or
        [string]::IsNullOrWhiteSpace($_.EndAnchor) -or
        @($_.ExpectedSpanSha256).Count -eq 0 -or
        @($_.ExpectedSpanSha256 | Where-Object { $_ -cnotmatch '\A[A-F0-9]{64}\z' }).Count -ne 0 -or
        @($_.ExpectedSpanSha256 | Sort-Object -Unique).Count -ne @($_.ExpectedSpanSha256).Count
      }).Count -ne 0 -or
      @($forbiddenInspectionTokens | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw "Invalid Watch reference rewrite: $resolvedRewritePath"
  }
  $rootDepth = 0
  if (![int]::TryParse([string]$structuralRemoval.rootDepth, [ref]$rootDepth) -or $rootDepth -le 0) {
    throw "Invalid Watch reference structural-removal depth: $resolvedRewritePath"
  }
  return [pscustomobject]@{
    Path = $resolvedRewritePath
    Script = [string]$rewrite.script
    ExactRemovals = $exactRemovals
    RangeReplacements = $rangeReplacements
    ForbiddenInspectionTokens = $forbiddenInspectionTokens
    StructuralRemoval = [pscustomobject]@{
      InstanceName = [string]$structuralRemoval.instanceName
      ClassName = [string]$structuralRemoval.className
      PlaceTagType = [string]$structuralRemoval.placeTagType
      RootDepth = $rootDepth
    }
  }
}

function Get-BuildStringSha256 {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    return ([System.BitConverter]::ToString($hash)).Replace('-', '')
  }
  finally {
    $sha256.Dispose()
  }
}

function Assert-BuildWatchReferenceTokensAbsent {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][pscustomobject]$Rewrite,
    [Parameter(Mandatory = $true)][string]$Description
  )

  foreach ($token in @($Rewrite.ForbiddenInspectionTokens)) {
    if ($Source.Contains($token)) {
      throw "$Description still contains forbidden native Watch token '$token'."
    }
  }
}

function Apply-BuildWatchReferenceRewrite {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][pscustomobject]$Rewrite
  )

  $resolvedSourcePath = Resolve-BuildRequiredFile -Path $SourcePath -Description "Exported ActionScript '$($Rewrite.Script)'"
  $source = [System.IO.File]::ReadAllText($resolvedSourcePath)
  foreach ($removal in @($Rewrite.ExactRemovals)) {
    $occurrenceCount = Get-BuildOrdinalOccurrenceCount -Source $source -Value $removal
    if ($occurrenceCount -ne 1) {
      throw "Watch reference rewrite '$($Rewrite.Path)' expected one '$($Rewrite.Script)' removal anchor but found $occurrenceCount."
    }
    $index = $source.IndexOf($removal, [System.StringComparison]::Ordinal)
    $source = $source.Remove($index, $removal.Length)
  }
  foreach ($replacement in @($Rewrite.RangeReplacements)) {
    $startCount = Get-BuildOrdinalOccurrenceCount -Source $source -Value $replacement.StartAnchor
    $endCount = Get-BuildOrdinalOccurrenceCount -Source $source -Value $replacement.EndAnchor
    if ($startCount -ne 1 -or $endCount -ne 1) {
      throw "Watch reference rewrite '$($Rewrite.Path)' expected one '$($Rewrite.Script)' range boundary but found start=$startCount end=$endCount."
    }
    $startIndex = $source.IndexOf($replacement.StartAnchor, [System.StringComparison]::Ordinal)
    $endIndex = $source.IndexOf($replacement.EndAnchor, [System.StringComparison]::Ordinal)
    if ($endIndex -le $startIndex) {
      throw "Watch reference rewrite '$($Rewrite.Path)' contains an invalid '$($Rewrite.Script)' range."
    }
    $spanLength = $endIndex - $startIndex
    $spanSha256 = Get-BuildStringSha256 -Value $source.Substring($startIndex, $spanLength)
    if (@($replacement.ExpectedSpanSha256) -cnotcontains $spanSha256) {
      throw "Watch reference rewrite '$($Rewrite.Path)' found an unexpected '$($Rewrite.Script)' span fingerprint '$spanSha256'."
    }
    $source = $source.Remove($startIndex, $spanLength).Insert($startIndex, $replacement.Content)
  }
  Assert-BuildWatchReferenceTokensAbsent -Source $source -Rewrite $Rewrite -Description "Rewritten ActionScript '$($Rewrite.Script)'"
  Write-BuildUtf8WithoutBom -Path $resolvedSourcePath -Text $source
}

function Get-BuildWatchSymbolMappings {
  param([Parameter(Mandatory = $true)][xml]$Movie)

  $mappings = [System.Collections.Generic.List[object]]::new()
  foreach ($symbolClass in @($Movie.SelectNodes('/swf/tags/item[@type="SymbolClassTag"]'))) {
    $tagNodes = @($symbolClass.SelectNodes('tags/item'))
    $nameNodes = @($symbolClass.SelectNodes('names/item'))
    if ($tagNodes.Count -ne $nameNodes.Count) {
      throw 'Scaleform SymbolClass tag and name counts differ.'
    }
    for ($index = 0; $index -lt $tagNodes.Count; $index++) {
      $tagId = 0
      if (![int]::TryParse([string]$tagNodes[$index].InnerText, [ref]$tagId) -or $tagId -lt 0) {
        throw 'Scaleform SymbolClass contains an invalid character id.'
      }
      $mappings.Add([pscustomobject]@{
        Container = $symbolClass
        TagNode = $tagNodes[$index]
        NameNode = $nameNodes[$index]
        TagId = $tagId
        Name = [string]$nameNodes[$index].InnerText
      })
    }
  }
  return @($mappings)
}

function Write-BuildWatchScaleformXml {
  param(
    [Parameter(Mandatory = $true)][xml]$Movie,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $settings = [System.Xml.XmlWriterSettings]::new()
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $settings.Indent = $true
  $settings.NewLineChars = "`n"
  $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
  $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
  try { $Movie.Save($writer) } finally { $writer.Dispose() }
}

function Assert-BuildWatchClassPlacementAbsent {
  param(
    [Parameter(Mandatory = $true)][xml]$Movie,
    [Parameter(Mandatory = $true)][pscustomobject]$Removal,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if (@($Movie.SelectNodes('/swf/tags')).Count -ne 1) {
    throw "$Description does not contain exactly one root tag collection."
  }
  $placeObjects = @($Movie.SelectNodes('//*[starts-with(@type,"PlaceObject")]'))
  if (@($placeObjects | Where-Object { $_.GetAttribute('name') -ceq $Removal.InstanceName }).Count -ne 0) {
    throw "$Description still contains native Watch placement name '$($Removal.InstanceName)'."
  }
  if (@($placeObjects | Where-Object { $_.GetAttribute('className') -ceq $Removal.ClassName }).Count -ne 0) {
    throw "$Description still contains native Watch placement class '$($Removal.ClassName)'."
  }
  $classMappings = @(Get-BuildWatchSymbolMappings -Movie $Movie | Where-Object { $_.Name -ceq $Removal.ClassName })
  if ($classMappings.Count -ne 0) {
    throw "$Description still contains native Watch class binding '$($Removal.ClassName)'."
  }
}

function Remove-BuildWatchClassPlacementFromScaleformXml {
  param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][pscustomobject]$Removal
  )

  $resolvedInputPath = Resolve-BuildRequiredFile -Path $InputPath -Description 'JPEXS HUDMenu structural-removal XML export'
  $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
  if (Test-Path -LiteralPath $resolvedOutputPath) {
    throw "HUDMenu structural-removal XML output path is not fresh: $resolvedOutputPath"
  }

  [xml]$movie = Get-Content -LiteralPath $resolvedInputPath -Raw
  if (@($movie.SelectNodes('/swf/tags')).Count -ne 1) {
    throw 'JPEXS HUDMenu structural-removal XML does not contain exactly one root tag collection.'
  }
  $placeObjects = @($movie.SelectNodes('//*[starts-with(@type,"PlaceObject")]'))
  $namePlacements = @($placeObjects | Where-Object { $_.GetAttribute('name') -ceq $Removal.InstanceName })
  $classPlacements = @($placeObjects | Where-Object { $_.GetAttribute('className') -ceq $Removal.ClassName })
  if ($namePlacements.Count -ne 1 -or
      $classPlacements.Count -ne 1 -or
      $namePlacements[0] -ne $classPlacements[0] -or
      $namePlacements[0].ParentNode -ne $movie.swf.tags) {
    throw "HUDMenu structural removal expected one root '$($Removal.InstanceName)' placement for class '$($Removal.ClassName)'."
  }
  if (@(Get-BuildWatchSymbolMappings -Movie $movie | Where-Object { $_.Name -ceq $Removal.ClassName }).Count -ne 0) {
    throw "HUDMenu structural removal found an unexpected '$($Removal.ClassName)' character binding."
  }

  $placement = $namePlacements[0]
  if ([string]$placement.type -cne $Removal.PlaceTagType -or
      [string]$placement.depth -cne [string]$Removal.RootDepth -or
      [string]$placement.placeFlagHasCharacter -cne 'false' -or
      [string]$placement.placeFlagHasClassName -cne 'true' -or
      [string]$placement.placeFlagHasName -cne 'true' -or
      [string]$placement.placeFlagMove -cne 'false' -or
      $placement.HasAttribute('characterId')) {
    throw "HUDMenu structural placement '$($Removal.InstanceName)' does not match the required type, depth, class, and construction flags."
  }

  [void]$movie.swf.tags.RemoveChild($placement)
  Assert-BuildWatchClassPlacementAbsent -Movie $movie -Removal $Removal -Description 'Transformed HUDMenu movie'
  Write-BuildWatchScaleformXml -Movie $movie -Path $resolvedOutputPath
}

function Assert-BuildWatchRemovedScaleformXml {
  param(
    [Parameter(Mandatory = $true)][xml]$Movie,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch,
    [Parameter(Mandatory = $true)][int]$CharacterId,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if (@($Movie.SelectNodes('/swf/tags')).Count -ne 1) {
    throw "$Description does not contain exactly one root tag collection."
  }
  $instanceXPath = '//*[@name="{0}"]' -f $Patch.InstanceName
  if (@($Movie.SelectNodes($instanceXPath)).Count -ne 0) {
    throw "$Description still contains the native Watch instance '$($Patch.InstanceName)'."
  }
  $placementXPath = '//*[starts-with(@type,"PlaceObject") and @characterId="{0}"]' -f $CharacterId
  if (@($Movie.SelectNodes($placementXPath)).Count -ne 0) {
    throw "$Description still contains a placement for native Watch character $CharacterId."
  }

  $mappings = @(Get-BuildWatchSymbolMappings -Movie $Movie)
  if (@($mappings | Where-Object { $_.Name -ceq $Patch.ClassName }).Count -ne 0) {
    throw "$Description still binds native Watch class '$($Patch.ClassName)'."
  }
  if (@($mappings | Where-Object { $_.TagId -eq $CharacterId }).Count -ne 0) {
    throw "$Description still binds native Watch character $CharacterId."
  }

  $definitionXPath = '/swf/tags/item[@type="DefineSpriteTag" and @spriteId="{0}"]' -f $CharacterId
  $definitions = @($Movie.SelectNodes($definitionXPath))
  if ($definitions.Count -gt 1) {
    throw "$Description contains duplicate retained native Watch definitions for character $CharacterId."
  }
}

function Remove-BuildWatchFromScaleformXml {
  param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch
  )

  $resolvedInputPath = Resolve-BuildRequiredFile -Path $InputPath -Description 'JPEXS Watch removal XML export'
  $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
  if (Test-Path -LiteralPath $resolvedOutputPath) {
    throw "Watch removal XML output path is not fresh: $resolvedOutputPath"
  }

  [xml]$movie = Get-Content -LiteralPath $resolvedInputPath -Raw
  $rootTags = @($movie.SelectNodes('/swf/tags'))
  if ($rootTags.Count -ne 1) {
    throw 'JPEXS Watch removal XML does not contain exactly one root tag collection.'
  }

  $rootPlacementXPath = '/swf/tags/item[@name="{0}"]' -f $Patch.InstanceName
  $placements = @($movie.SelectNodes($rootPlacementXPath))
  if ($placements.Count -ne 1) {
    throw "Watch removal expected exactly one root '$($Patch.InstanceName)' placement but found $($placements.Count)."
  }
  $placement = $placements[0]
  if ([string]$placement.type -cne $Patch.PlaceTagType -or
      [string]$placement.depth -cne [string]$Patch.RootDepth -or
      [string]$placement.placeFlagHasCharacter -cne 'true' -or
      [string]$placement.placeFlagHasName -cne 'true' -or
      [string]$placement.placeFlagMove -cne 'false') {
    throw "Watch removal root placement '$($Patch.InstanceName)' does not match the required type, depth, and construction flags."
  }
  $characterId = 0
  if (![int]::TryParse([string]$placement.characterId, [ref]$characterId) -or $characterId -le 0) {
    throw "Watch removal root placement '$($Patch.InstanceName)' has an invalid character id."
  }

  $characterPlacementXPath = '//*[starts-with(@type,"PlaceObject") and @characterId="{0}"]' -f $characterId
  $characterPlacements = @($movie.SelectNodes($characterPlacementXPath))
  if ($characterPlacements.Count -ne 1 -or $characterPlacements[0] -ne $placement) {
    throw "Watch removal requires character $characterId to have exactly one placement, at '$($Patch.InstanceName)'."
  }
  $definitionXPath = '/swf/tags/item[@type="DefineSpriteTag" and @spriteId="{0}"]' -f $characterId
  if (@($movie.SelectNodes($definitionXPath)).Count -ne 1) {
    throw "Watch removal expected exactly one native Watch definition for character $characterId."
  }

  $mappings = @(Get-BuildWatchSymbolMappings -Movie $movie)
  $classMappings = @($mappings | Where-Object { $_.Name -ceq $Patch.ClassName })
  $characterMappings = @($mappings | Where-Object { $_.TagId -eq $characterId })
  if ($classMappings.Count -ne 1 -or
      $characterMappings.Count -ne 1 -or
      $classMappings[0].TagId -ne $characterId -or
      $classMappings[0].TagNode -ne $characterMappings[0].TagNode) {
    throw "Watch removal expected one '$($Patch.ClassName)' SymbolClass binding to character $characterId."
  }

  [void]$rootTags[0].RemoveChild($placement)
  [void]$classMappings[0].TagNode.ParentNode.RemoveChild($classMappings[0].TagNode)
  [void]$classMappings[0].NameNode.ParentNode.RemoveChild($classMappings[0].NameNode)
  Assert-BuildWatchRemovedScaleformXml -Movie $movie -Patch $Patch -CharacterId $characterId -Description 'Transformed Scaleform movie'

  Write-BuildWatchScaleformXml -Movie $movie -Path $resolvedOutputPath
  return $characterId
}

function Assert-BuildWatchRemovedActionScript {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch
  )

  $scriptFiles = @(Get-ChildItem -LiteralPath $ScriptsDirectory -Recurse -File -Filter '*.as')
  $classFiles = @($scriptFiles | Where-Object { $_.BaseName -ceq $Patch.ClassName })
  if ($classFiles.Count -ne 1) {
    throw "Watch removal inspection expected one retained '$($Patch.ClassName)' class definition but found $($classFiles.Count)."
  }
  $classTokenPattern = '(?<![A-Za-z0-9_$])' + [regex]::Escape($Patch.ClassName) + '(?![A-Za-z0-9_$])'
  foreach ($scriptFile in $scriptFiles) {
    $source = [System.IO.File]::ReadAllText($scriptFile.FullName)
    if ($scriptFile.FullName -cne $classFiles[0].FullName -and [regex]::IsMatch($source, $classTokenPattern)) {
      throw "Watch removal inspection found a native Watch class reference in '$($scriptFile.FullName)'."
    }
    if ($source.Contains($Patch.InstanceName)) {
      throw "Watch removal inspection found native Watch instance reference '$($Patch.InstanceName)' in '$($scriptFile.FullName)'."
    }
  }
}

function Invoke-BuildWatchRemovalScaleformMovie {
  param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch,
    [switch]$KeepWork
  )

  $resolvedInputPath = Assert-BuildScaleformFile -Path $InputPath -Description 'Scaleform Watch removal input'
  $resolvedJavaPath = Resolve-BuildRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-BuildRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
  if (Test-Path -LiteralPath $resolvedOutputPath) {
    throw "Patched Scaleform output path is not fresh: $resolvedOutputPath"
  }

  $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
  New-Item -ItemType Directory -Force -Path $resolvedWorkDirectory | Out-Null
  $buildWorkDirectory = Join-Path $resolvedWorkDirectory ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $buildWorkDirectory | Out-Null
  $rawXmlPath = Join-Path $buildWorkDirectory 'source.xml'
  $removedXmlPath = Join-Path $buildWorkDirectory 'watch-removed.xml'
  $inspectionXmlPath = Join-Path $buildWorkDirectory 'inspection.xml'
  $inspectionScripts = Join-Path $buildWorkDirectory 'inspection-scripts'
  try {
    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-swf2xml', $resolvedInputPath, $rawXmlPath) -Description 'JPEXS Watch removal XML export'
    [void](Resolve-BuildRequiredFile -Path $rawXmlPath -Description 'JPEXS Watch removal XML export')
    $characterId = Remove-BuildWatchFromScaleformXml -InputPath $rawXmlPath -OutputPath $removedXmlPath -Patch $Patch

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputPath) | Out-Null
    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-xml2swf', $removedXmlPath, $resolvedOutputPath) -Description 'JPEXS Watch-removed movie rebuild'
    [void](Assert-BuildScaleformFile -Path $resolvedOutputPath -Description 'Watch-removed Scaleform movie')

    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-swf2xml', $resolvedOutputPath, $inspectionXmlPath) -Description 'JPEXS Watch-removed movie XML inspection'
    [xml]$inspectionMovie = Get-Content -LiteralPath (Resolve-BuildRequiredFile -Path $inspectionXmlPath -Description 'JPEXS Watch-removed movie XML inspection') -Raw
    Assert-BuildWatchRemovedScaleformXml -Movie $inspectionMovie -Patch $Patch -CharacterId $characterId -Description 'Rebuilt Scaleform movie'

    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-format', 'script:as', '-onerror', 'abort', '-export', 'script', $inspectionScripts, $resolvedOutputPath) -Description 'JPEXS Watch-removed ActionScript inspection'
    Assert-BuildWatchRemovedActionScript -ScriptsDirectory (Resolve-BuildRequiredDirectory -Path $inspectionScripts -Description 'JPEXS Watch-removed ActionScript inspection') -Patch $Patch
    return $resolvedOutputPath
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Scaleform Watch removal files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-BuildRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}
