<#
.SYNOPSIS
Exercises pinned Canvas pipeline tooling setup with small local fixture archives.
.DESCRIPTION
Verifies cache integrity, offline behavior, Adobe license gating, safe ZIP extraction, valid-install reuse, and staged replacement rollback. The fixture does not download or execute Java, JPEXS, Adobe Flex, or Apache Flex; real binary readiness is covered separately by VerifyPipelineTooling.ps1.
#>
#Requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedPipelineTooling.ps1')

function Assert-TestCondition {
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (!$Condition) { throw $Message }
}

function Assert-TestRejected {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$ExpectedMessage,
    [ref]$CapturedOutput
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  try {
    & $Action 6>&1 | ForEach-Object { $lines.Add([string]$_) }
  }
  catch {
    $lines.Add($_.Exception.Message)
    if (!$_.Exception.Message.Contains($ExpectedMessage)) {
      throw "$Description returned an unexpected error: $($_.Exception.Message)"
    }
    if ($null -ne $CapturedOutput) { $CapturedOutput.Value = @($lines) }
    return
  }
  throw "$Description was accepted unexpectedly."
}

function Write-TestByteFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Bytes)
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path)) | Out-Null
  [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Write-TestText {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  Write-TestByteFile -Path $Path -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-TestFileContract {
  param([Parameter(Mandatory = $true)][string]$Path, [string]$RelativePath)
  $file = Get-Item -LiteralPath $Path
  return [pscustomobject]@{
    RelativePath = $RelativePath
    Length = [int64]$file.Length
    Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Initialize-TestZipFromDirectory {
  param([Parameter(Mandatory = $true)][string]$SourcePath, [Parameter(Mandatory = $true)][string]$ArchivePath)
  if (Test-Path -LiteralPath $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ArchivePath, [System.IO.Compression.CompressionLevel]::NoCompression, $false)
}

function Initialize-TestPipelineFixture {
  param([Parameter(Mandatory = $true)][string]$Root)

  $sources = Join-Path $Root 'sources'
  $cache = Join-Path $Root 'cache'
  New-Item -ItemType Directory -Path $sources, $cache | Out-Null

  $playerSource = Join-Path $sources 'playerglobal'
  Write-TestText -Path (Join-Path $playerSource 'catalog.xml') -Text '<catalog />'
  Write-TestByteFile -Path (Join-Path $playerSource 'library.swf') -Bytes ([byte[]](0x43, 0x57, 0x53, 0x09, 0x01, 0x02, 0x03, 0x04))
  $playerGlobalPath = Join-Path $sources 'playerglobal.swc'
  Initialize-TestZipFromDirectory -SourcePath $playerSource -ArchivePath $playerGlobalPath

  $javaSource = Join-Path $sources 'java'
  Write-TestText -Path (Join-Path $javaSource 'fixture-jdk\release') -Text 'fixture-temurin-release'
  Write-TestText -Path (Join-Path $javaSource 'fixture-jdk\bin\java.exe') -Text 'fixture-java'
  $javaArchive = Join-Path $cache 'fixture-java.zip'
  Initialize-TestZipFromDirectory -SourcePath $javaSource -ArchivePath $javaArchive

  $jpexsSource = Join-Path $sources 'jpexs'
  Write-TestText -Path (Join-Path $jpexsSource 'ffdec.jar') -Text 'fixture-jpexs'
  $jpexsArchive = Join-Path $cache 'fixture-jpexs.zip'
  Initialize-TestZipFromDirectory -SourcePath $jpexsSource -ArchivePath $jpexsArchive

  $flexSource = Join-Path $sources 'flex'
  Write-TestText -Path (Join-Path $flexSource 'flex-sdk-description.xml') -Text '<flex>fixture</flex>'
  Write-TestText -Path (Join-Path $flexSource 'lib\mxmlc.jar') -Text 'fixture-mxmlc'
  Write-TestText -Path (Join-Path $flexSource 'lib\compc.jar') -Text 'fixture-compc'
  Write-TestText -Path (Join-Path $flexSource 'frameworks\flex-config.xml') -Text '<flex-config />'
  $flexArchive = Join-Path $cache 'fixture-flex.zip'
  Initialize-TestZipFromDirectory -SourcePath $flexSource -ArchivePath $flexArchive

  $adobeSource = Join-Path $sources 'adobe'
  $adobePlayerPath = Join-Path $adobeSource 'frameworks\libs\player\11.1\playerglobal.swc'
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($adobePlayerPath)) | Out-Null
  Copy-Item -LiteralPath $playerGlobalPath -Destination $adobePlayerPath
  $adobeArchive = Join-Path $cache 'fixture-adobe.zip'
  Initialize-TestZipFromDirectory -SourcePath $adobeSource -ArchivePath $adobeArchive

  $contract = [pscustomobject]@{
    Versions = [pscustomobject]@{ Java = 'fixture'; Jpexs = 'fixture'; ApacheFlex = 'fixture'; AdobeFlex = 'fixture'; PlayerGlobal = '11.1' }
    Artifacts = [ordered]@{
      Java = (Get-TestFileContract -Path $javaArchive)
      Jpexs = (Get-TestFileContract -Path $jpexsArchive)
      ApacheFlex = (Get-TestFileContract -Path $flexArchive)
      AdobeFlex = (Get-TestFileContract -Path $adobeArchive)
    }
    Installed = [pscustomobject]@{
      JavaRelease = (Get-TestFileContract -Path (Join-Path $javaSource 'fixture-jdk\release') -RelativePath 'release')
      JavaExecutable = (Get-TestFileContract -Path (Join-Path $javaSource 'fixture-jdk\bin\java.exe') -RelativePath 'bin\java.exe')
      JpexsJar = (Get-TestFileContract -Path (Join-Path $jpexsSource 'ffdec.jar') -RelativePath 'ffdec.jar')
      FlexDescription = (Get-TestFileContract -Path (Join-Path $flexSource 'flex-sdk-description.xml') -RelativePath 'flex-sdk-description.xml')
      FlexConfig = (Get-TestFileContract -Path (Join-Path $flexSource 'frameworks\flex-config.xml') -RelativePath 'frameworks\flex-config.xml')
      MxmlcJar = (Get-TestFileContract -Path (Join-Path $flexSource 'lib\mxmlc.jar') -RelativePath 'lib\mxmlc.jar')
      CompcJar = (Get-TestFileContract -Path (Join-Path $flexSource 'lib\compc.jar') -RelativePath 'lib\compc.jar')
      PlayerGlobal = (Get-TestFileContract -Path $playerGlobalPath -RelativePath 'frameworks\libs\player\11.1\playerglobal.swc')
    }
  }
  foreach ($artifactName in $contract.Artifacts.Keys) {
    $contract.Artifacts[$artifactName] | Add-Member -NotePropertyName FileName -NotePropertyValue ([System.IO.Path]::GetFileName(@{
      Java = $javaArchive; Jpexs = $jpexsArchive; ApacheFlex = $flexArchive; AdobeFlex = $adobeArchive
    }[$artifactName]))
    $contract.Artifacts[$artifactName] | Add-Member -NotePropertyName Uri -NotePropertyValue "https://invalid.example/$artifactName"
  }
  return [pscustomobject]@{ Contract = $contract; Cache = $cache; PlayerGlobal = $playerGlobalPath }
}

function Get-TestTreeState {
  param([Parameter(Mandatory = $true)][string]$Path)
  return @(
    Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object {
      $relative = [System.IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/')
      "$relative|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    } | Sort-Object
  )
}

$production = Get-PipelineToolingContract
Assert-TestCondition ($production.Versions.Java -ceq '21.0.12.1+1') 'Production Java pin changed unexpectedly.'
Assert-TestCondition ($production.Artifacts.Java.FileName -ceq 'OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip') 'Production Java archive no longer pins Windows x64 HotSpot Temurin.'
Assert-TestCondition ($production.Installed.JavaExecutable.Length -eq 50304) 'Production Temurin java.exe length changed unexpectedly.'
Assert-TestCondition ($production.Installed.JavaExecutable.Sha256 -ceq '82051fdab26319d77d20cc0065045d05ec00b3e3d05f44935d7c06b96b621d55') 'Production Temurin java.exe SHA-256 changed unexpectedly.'
Assert-TestCondition ($production.Versions.Jpexs -ceq '26.2.1') 'Production JPEXS pin changed unexpectedly.'
Assert-TestCondition ($production.Versions.ApacheFlex -ceq '4.16.1') 'Production Apache Flex pin changed unexpectedly.'
Assert-TestCondition ($production.Installed.FlexConfig.Length -eq 19529) 'Production Apache Flex configuration length changed unexpectedly.'
Assert-TestCondition ($production.Installed.FlexConfig.Sha256 -ceq '08cc21404b146d3f623f4176a8e19734d35e81ea852d802283748708511d4fca') 'Production Apache Flex configuration SHA-256 changed unexpectedly.'
Assert-TestCondition ($production.Versions.AdobeFlex -ceq '4.6.0.23201B') 'Production Adobe Flex pin changed unexpectedly.'
Assert-TestCondition ($production.Artifacts.AdobeFlex.Length -eq 343973963) 'Production Adobe Flex archive length changed unexpectedly.'
Assert-TestCondition ($production.Artifacts.AdobeFlex.Sha256 -ceq '622b63f29de44600ff8d4231174a70fcb3085812c0e146a42e91877ca8b46798') 'Production Adobe Flex archive SHA-256 changed unexpectedly.'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureParent = Join-Path $repositoryRoot '.work\tasks\vwcanvas-8-11-ec3680f3\toolchain-tests'
New-Item -ItemType Directory -Force -Path $fixtureParent | Out-Null
$fixtureRoot = Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  $fixture = Initialize-TestPipelineFixture -Root (Join-Path $fixtureRoot 'valid')
  $toolRoot = Join-Path $fixtureRoot 'installed'
  $workspaceRoot = Join-Path $fixtureRoot 'workspace'
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $toolRoot `
    -WorkspaceRoot $workspaceRoot -ArtifactCachePath $fixture.Cache -Offline -AcceptAdobeLicense 6>&1 | Out-Null
  Assert-TestCondition (Test-PipelineJavaInstallation -Root (Join-Path $toolRoot 'java') -Contract $fixture.Contract) 'Fixture Java was not installed.'
  Assert-TestCondition (Test-PipelineJpexsInstallation -Root (Join-Path $toolRoot 'jpexs') -Contract $fixture.Contract) 'Fixture JPEXS was not installed.'
  Assert-TestCondition (Test-PipelineFlexInstallation -Root (Join-Path $toolRoot 'flex') -Contract $fixture.Contract) 'Fixture Apache Flex was not installed.'
  Assert-TestCondition (Test-PipelinePlayerGlobalInstallation -Path (Join-Path $toolRoot 'flex\frameworks\libs\player\11.1\playerglobal.swc') -Contract $fixture.Contract) 'Fixture playerglobal.swc was not installed.'

  $beforeReuse = @(Get-TestTreeState -Path $toolRoot)
  Start-Sleep -Milliseconds 25
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $toolRoot `
    -WorkspaceRoot $workspaceRoot -ArtifactCachePath (Join-Path $fixtureRoot 'missing-cache') -Offline 6>&1 | Out-Null
  $afterReuse = @(Get-TestTreeState -Path $toolRoot)
  Assert-TestCondition ([string]::Join("`n", $beforeReuse) -ceq [string]::Join("`n", $afterReuse)) 'An already-valid installation was rewritten.'

  $installedJavaPath = Join-Path $toolRoot 'java\bin\java.exe'
  [System.IO.File]::WriteAllBytes($installedJavaPath, [byte[]]::new(0))
  Assert-TestCondition (Test-PipelineFileContract -Path (Join-Path $toolRoot 'java\release') -FileContract $fixture.Contract.Installed.JavaRelease) 'Java corruption fixture changed the pinned release metadata.'
  Assert-TestCondition (!(Test-PipelineJavaInstallation -Root (Join-Path $toolRoot 'java') -Contract $fixture.Contract)) 'A zero-byte java.exe was incorrectly reusable.'
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $toolRoot `
    -WorkspaceRoot $workspaceRoot -ArtifactCachePath $fixture.Cache -Offline 6>&1 | Out-Null
  Assert-TestCondition (Test-PipelineFileContract -Path $installedJavaPath -FileContract $fixture.Contract.Installed.JavaExecutable) 'Setup did not repair a zero-byte java.exe from the pinned archive.'

  $installedFlexConfigPath = Join-Path $toolRoot 'flex\frameworks\flex-config.xml'
  [System.IO.File]::WriteAllText($installedFlexConfigPath, '<corrupt />')
  Assert-TestCondition (!(Test-PipelineFlexInstallation -Root (Join-Path $toolRoot 'flex') -Contract $fixture.Contract)) 'A corrupt flex-config.xml was incorrectly reusable.'
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $toolRoot `
    -WorkspaceRoot $workspaceRoot -ArtifactCachePath $fixture.Cache -Offline 6>&1 | Out-Null
  Assert-TestCondition (Test-PipelineFileContract -Path $installedFlexConfigPath -FileContract $fixture.Contract.Installed.FlexConfig) 'Setup did not repair flex-config.xml from the pinned Apache Flex archive.'

  $downloadTools = Join-Path $fixtureRoot 'download-tools'
  $downloadWorkspace = Join-Path $fixtureRoot 'download-workspace'
  $downloadSources = @{}
  foreach ($artifactName in $fixture.Contract.Artifacts.Keys) {
    $downloadSources[[string]$fixture.Contract.Artifacts[$artifactName].Uri] = Join-Path $fixture.Cache $fixture.Contract.Artifacts[$artifactName].FileName
  }
  $downloadState = [pscustomobject]@{ Count = 0 }
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $downloadTools `
    -WorkspaceRoot $downloadWorkspace -AcceptAdobeLicense -DownloadAction {
      param($uri, $outFile)
      $downloadState.Count++
      Copy-Item -LiteralPath $downloadSources[[string]$uri] -Destination $outFile
    } 6>&1 | Out-Null
  Assert-TestCondition ($downloadState.Count -eq 4) 'Online fallback did not retrieve each missing pinned artifact exactly once.'
  foreach ($artifactName in $fixture.Contract.Artifacts.Keys) {
    $cachedPath = Join-Path $downloadWorkspace "cache\$($fixture.Contract.Artifacts[$artifactName].FileName)"
    Assert-TestCondition (Test-PipelineFileContract -Path $cachedPath -FileContract $fixture.Contract.Artifacts[$artifactName]) "Downloaded $artifactName fixture was not validated into the repository-local cache."
  }

  $duplicatePlayerGlobal = Join-Path $toolRoot 'flex\frameworks\libs\player\12.0\playerglobal.swc'
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($duplicatePlayerGlobal)) | Out-Null
  Copy-Item -LiteralPath (Join-Path $toolRoot 'flex\frameworks\libs\player\11.1\playerglobal.swc') -Destination $duplicatePlayerGlobal
  Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $toolRoot `
    -WorkspaceRoot $workspaceRoot -ArtifactCachePath $fixture.Cache -Offline 6>&1 | Out-Null
  Assert-TestCondition (Test-PipelinePlayerGlobalSet -FlexRoot (Join-Path $toolRoot 'flex') -Contract $fixture.Contract) 'Setup did not remove an unexpected duplicate playerglobal by safely replacing Flex.'

  $licenseTools = Join-Path $fixtureRoot 'license-tools'
  $licenseOutput = $null
  Assert-TestRejected -Description 'Adobe license gate' -ExpectedMessage '-AcceptAdobeLicense' -CapturedOutput ([ref]$licenseOutput) -Action {
    Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot $licenseTools `
      -WorkspaceRoot (Join-Path $fixtureRoot 'license-work') -ArtifactCachePath $fixture.Cache -Offline
  }
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $licenseTools 'java'))) 'License rejection installed Java before failing.'
  Assert-TestCondition (@($licenseOutput | Where-Object { $_ -match 'Pinned pipeline tooling files are installed' }).Count -eq 0) 'License rejection claimed successful installation.'

  $offlineOutput = $null
  Assert-TestRejected -Description 'Offline missing cache' -ExpectedMessage $fixture.Contract.Artifacts.Java.FileName -CapturedOutput ([ref]$offlineOutput) -Action {
    Invoke-PipelineToolingInstall -Contract $fixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot (Join-Path $fixtureRoot 'offline-tools') `
      -WorkspaceRoot (Join-Path $fixtureRoot 'offline-work') -ArtifactCachePath (Join-Path $fixtureRoot 'empty-cache') -Offline -AcceptAdobeLicense
  }
  Assert-TestCondition (@($offlineOutput | Where-Object { $_ -match 'Offline mode prevents download' }).Count -gt 0) 'Offline failure did not explain that downloads were prohibited.'
  Assert-TestCondition (@($offlineOutput | Where-Object { $_ -match 'Pinned pipeline tooling files are installed' }).Count -eq 0) 'Offline failure claimed successful installation.'

  foreach ($corruption in @('Truncated', 'SameLengthMismatch')) {
    $caseRoot = Join-Path $fixtureRoot $corruption
    $caseFixture = Initialize-TestPipelineFixture -Root $caseRoot
    $javaArchivePath = Join-Path $caseFixture.Cache $caseFixture.Contract.Artifacts.Java.FileName
    $bytes = [System.IO.File]::ReadAllBytes($javaArchivePath)
    if ($corruption -ceq 'Truncated') {
      [System.IO.File]::WriteAllBytes($javaArchivePath, $bytes[0..($bytes.Length - 2)])
    }
    else {
      $bytes[0] = $bytes[0] -bxor 0xFF
      [System.IO.File]::WriteAllBytes($javaArchivePath, $bytes)
    }
    Assert-TestRejected -Description "$corruption cached archive" -ExpectedMessage 'byte-length or SHA-256' -Action {
      Invoke-PipelineToolingInstall -Contract $caseFixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot (Join-Path $caseRoot 'tools') `
        -WorkspaceRoot (Join-Path $caseRoot 'work') -ArtifactCachePath $caseFixture.Cache -Offline -AcceptAdobeLicense
    }
    Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $caseRoot 'tools\java'))) "$corruption cached archive installed Java."
  }

  $handoffRoot = Join-Path $fixtureRoot 'external-cache-handoff'
  $handoffFixture = Initialize-TestPipelineFixture -Root $handoffRoot
  $replacementSource = Join-Path $handoffRoot 'replacement-java'
  Write-TestText -Path (Join-Path $replacementSource 'fixture-jdk\release') -Text 'fixture-temurin-release'
  Write-TestText -Path (Join-Path $replacementSource 'fixture-jdk\bin\java.exe') -Text 'replacement-java-outside-pin'
  $replacementArchive = Join-Path $handoffRoot 'replacement-java.zip'
  Initialize-TestZipFromDirectory -SourcePath $replacementSource -ArchivePath $replacementArchive
  $retainedOriginal = Join-Path $handoffRoot 'verified-original-java.zip'
  $handoffState = [pscustomobject]@{ Replacements = 0 }
  $handoffOutput = $null
  Assert-TestRejected -Description 'External cache replacement after selection' -ExpectedMessage 'Private copy of pinned artifact' -CapturedOutput ([ref]$handoffOutput) -Action {
    Invoke-PipelineToolingInstall -Contract $handoffFixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot (Join-Path $handoffRoot 'tools') `
      -WorkspaceRoot (Join-Path $handoffRoot 'work') -ArtifactCachePath $handoffFixture.Cache -Offline -AcceptAdobeLicense `
      -AfterArtifactSelectedAction {
        param($selectedPath, $artifact)
        if ($handoffState.Replacements -eq 0 -and $artifact.FileName -ceq $handoffFixture.Contract.Artifacts.Java.FileName) {
          Move-Item -LiteralPath $selectedPath -Destination $retainedOriginal
          Move-Item -LiteralPath $replacementArchive -Destination $selectedPath
          $handoffState.Replacements++
        }
      }
  }
  Assert-TestCondition ($handoffState.Replacements -eq 1) 'External cache handoff fixture did not replace Java after its initial validation.'
  Assert-TestCondition (Test-PipelineFileContract -Path $retainedOriginal -FileContract $handoffFixture.Contract.Artifacts.Java) 'External cache handoff did not retain the originally verified archive bytes.'
  Assert-TestCondition (!(Test-PipelineFileContract -Path (Join-Path $handoffFixture.Cache $handoffFixture.Contract.Artifacts.Java.FileName) -FileContract $handoffFixture.Contract.Artifacts.Java)) 'External cache handoff replacement unexpectedly matched the pin.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $handoffRoot 'tools\java'))) 'Changed external cache bytes reached the Java installation.'
  Assert-TestCondition (@($handoffOutput | Where-Object { $_ -match 'Pinned pipeline tooling files are installed' }).Count -eq 0) 'Rejected external cache replacement claimed successful installation.'

  $unsafeArchive = Join-Path $fixtureRoot 'unsafe-path.zip'
  $zip = [System.IO.Compression.ZipFile]::Open($unsafeArchive, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $entry = $zip.CreateEntry('../escape.txt')
    $writer = [System.IO.StreamWriter]::new($entry.Open())
    try { $writer.Write('escape') } finally { $writer.Dispose() }
  }
  finally { $zip.Dispose() }
  Assert-TestRejected -Description 'Archive traversal entry' -ExpectedMessage 'unsafe path or link entry' -Action {
    Expand-PipelinePinnedArchive -ArchivePath $unsafeArchive -DestinationPath (Join-Path $fixtureRoot 'unsafe-extract') -AllowedRoot $fixtureRoot
  }
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $fixtureRoot 'escape.txt'))) 'Archive traversal wrote outside the extraction root.'

  $linkArchive = Join-Path $fixtureRoot 'unsafe-link.zip'
  $zip = [System.IO.Compression.ZipFile]::Open($linkArchive, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $entry = $zip.CreateEntry('link')
    $entry.ExternalAttributes = -1577123840
    $writer = [System.IO.StreamWriter]::new($entry.Open())
    try { $writer.Write('target') } finally { $writer.Dispose() }
  }
  finally { $zip.Dispose() }
  Assert-TestRejected -Description 'Archive link entry' -ExpectedMessage 'unsafe path or link entry' -Action {
    Expand-PipelinePinnedArchive -ArchivePath $linkArchive -DestinationPath (Join-Path $fixtureRoot 'link-extract') -AllowedRoot $fixtureRoot
  }

  $rollbackRoot = Join-Path $fixtureRoot 'rollback'
  $candidateRoot = Join-Path $rollbackRoot 'candidates'
  $rollbackTools = Join-Path $rollbackRoot 'tools'
  $candidatePath = Join-Path $candidateRoot 'candidate'
  $destinationPath = Join-Path $rollbackTools 'java'
  Write-TestText -Path (Join-Path $candidatePath 'sentinel.txt') -Text 'new'
  Write-TestText -Path (Join-Path $destinationPath 'sentinel.txt') -Text 'old'
  $validatorState = [pscustomobject]@{ Calls = 0 }
  Assert-TestRejected -Description 'Post-replacement validation failure' -ExpectedMessage 'previous installation was restored' -Action {
    Publish-PipelineToolDirectory -CandidatePath $candidatePath -DestinationPath $destinationPath -CandidateRoot $candidateRoot -ToolRoot $rollbackTools `
      -Description 'Fixture tool' -Validator {
        param($path)
        $validatorState.Calls++
        return $validatorState.Calls -eq 1 -and (Test-Path -LiteralPath (Join-Path $path 'sentinel.txt') -PathType Leaf)
      }
  }
  Assert-TestCondition ([System.IO.File]::ReadAllText((Join-Path $destinationPath 'sentinel.txt')) -ceq 'old') 'Failed replacement did not restore the previous installation.'
  Assert-TestCondition (@(Get-ChildItem -LiteralPath $rollbackTools -Filter '*.backup-*' -Force).Count -eq 0) 'Successful rollback left an unexpected backup directory.'

  $badStageRoot = Join-Path $fixtureRoot 'bad-stage'
  $badFixture = Initialize-TestPipelineFixture -Root $badStageRoot
  $oldJavaRoot = Join-Path $badStageRoot 'tools\java'
  Write-TestText -Path (Join-Path $oldJavaRoot 'old.txt') -Text 'old-installation'
  $oldHash = (Get-FileHash -LiteralPath (Join-Path $oldJavaRoot 'old.txt') -Algorithm SHA256).Hash
  $badJavaSource = Join-Path $badStageRoot 'bad-java-source'
  Write-TestText -Path (Join-Path $badJavaSource 'fixture-jdk\release') -Text 'wrong-release'
  Write-TestText -Path (Join-Path $badJavaSource 'fixture-jdk\bin\java.exe') -Text 'fixture-java'
  $badJavaArchive = Join-Path $badFixture.Cache $badFixture.Contract.Artifacts.Java.FileName
  Initialize-TestZipFromDirectory -SourcePath $badJavaSource -ArchivePath $badJavaArchive
  $badFixture.Contract.Artifacts.Java.Length = (Get-Item -LiteralPath $badJavaArchive).Length
  $badFixture.Contract.Artifacts.Java.Sha256 = (Get-FileHash -LiteralPath $badJavaArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  $stageOutput = $null
  Assert-TestRejected -Description 'Invalid staged installation' -ExpectedMessage 'did not produce the expected' -CapturedOutput ([ref]$stageOutput) -Action {
    Invoke-PipelineToolingInstall -Contract $badFixture.Contract -RepositoryRoot $repositoryRoot -ToolRoot (Join-Path $badStageRoot 'tools') `
      -WorkspaceRoot (Join-Path $badStageRoot 'work') -ArtifactCachePath $badFixture.Cache -Offline -AcceptAdobeLicense
  }
  Assert-TestCondition ((Get-FileHash -LiteralPath (Join-Path $oldJavaRoot 'old.txt') -Algorithm SHA256).Hash -ceq $oldHash) 'Invalid staged Java changed the previous installation.'
  Assert-TestCondition (@($stageOutput | Where-Object { $_ -match 'Pinned pipeline tooling files are installed' }).Count -eq 0) 'Invalid staged installation claimed success.'

  Write-Information 'Verified pinned pipeline tooling setup fixtures.' -InformationAction Continue
}
finally {
  $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
  Assert-TestCondition (Test-PipelinePathWithinRoot -Path $resolvedFixture -Root $fixtureParent) 'Refusing to clean a toolchain fixture outside the expected task directory.'
  if (Test-Path -LiteralPath $resolvedFixture -PathType Container) { Invoke-PipelineTreeRemoval -Path $resolvedFixture -AllowedRoot $fixtureParent }
}
