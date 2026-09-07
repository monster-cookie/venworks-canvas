<#
.SYNOPSIS
Exercises Canvas staging setup against disposable Windows junction fixtures.
#>
[CmdletBinding()]
param()

$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!$IsWindows) {
  Write-Output 'Setup junction tests skipped: Windows Junction behavior requires Windows.'
  return
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testWorkRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.work\canvas\authoring-remediation-tests'))
$fixtureRoot = Join-Path $testWorkRoot ('setup-' + [guid]::NewGuid().ToString('N'))
$powerShellPath = (Get-Process -Id $PID).Path
$createdCases = [System.Collections.Generic.List[object]]::new()

function Assert-TestCondition {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$Condition,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (!$Condition) { throw $Message }
}

function Write-TestText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $parent = Split-Path -Parent $Path
  if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function New-SetupCase {
  param([Parameter(Mandatory = $true)][string]$Name)

  $caseRoot = Join-Path $fixtureRoot $Name
  $caseRepository = Join-Path $caseRoot 'repository'
  $caseTools = Join-Path $caseRepository 'Tools'
  $targetRoot = Join-Path $caseRoot 'targets'
  New-Item -ItemType Directory -Force -Path $caseTools, $targetRoot | Out-Null
  foreach ($fileName in @('sharedConfig.ps1', 'sharedCanvas.ps1', 'sharedCanvasBuildEvidence.ps1', 'sharedCanvasPackaging.ps1', 'setupRepo.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination (Join-Path $caseTools $fileName)
  }
  $case = [pscustomobject]@{
    Root = $caseRoot
    Repository = $caseRepository
    SetupScript = (Join-Path $caseTools 'setupRepo.ps1')
    EnvironmentPath = (Join-Path $caseRepository '.env')
    CanvasTarget = (Join-Path $targetRoot 'canvas')
    ExampleTarget = (Join-Path $targetRoot 'example')
    ComponentTarget = (Join-Path $targetRoot 'component-gallery')
  }
  $environmentText = [string]::Join("`n", @(
    "MODULE_VARIANT_CANVAS_PATH=$($case.CanvasTarget)"
    "MODULE_VARIANT_EXAMPLE_PATH=$($case.ExampleTarget)"
    "MODULE_VARIANT_COMPONENT_GALLERY_PATH=$($case.ComponentTarget)"
  )) + "`n"
  Write-TestText -Path $case.EnvironmentPath -Text $environmentText
  $createdCases.Add($case)
  return $case
}

function Invoke-SetupCase {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Case,

    [string[]]$ArgumentList = @()
  )

  $output = @(& $powerShellPath -NoProfile -File $Case.SetupScript -EnvironmentPath $Case.EnvironmentPath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Assert-JunctionRoute {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Target
  )

  $item = Get-Item -LiteralPath $Path -Force
  Assert-TestCondition ($item.LinkType -eq 'Junction') "Expected a Junction at $Path."
  $targets = @($item.Target)
  Assert-TestCondition ($targets.Count -eq 1) "Expected one Junction target at $Path."
  $actual = [System.IO.Path]::GetFullPath([string]$targets[0]).TrimEnd('\')
  $expected = [System.IO.Path]::GetFullPath($Target).TrimEnd('\')
  Assert-TestCondition ([string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)) "Unexpected Junction target at $Path."
}

function Assert-SafeFixturePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $fullRoot = $testWorkRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if (!$fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing fixture cleanup outside the authoring test root: $fullPath"
  }
}

New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

try {
  $preflight = New-SetupCase -Name 'preflight-populated'
  $populatedPath = Join-Path $preflight.Repository 'Staging-Example'
  $sentinelPath = Join-Path $populatedPath 'keep.txt'
  Write-TestText -Path $sentinelPath -Text "keep populated staging`n"
  $sentinelHash = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
  $result = Invoke-SetupCase -Case $preflight
  Assert-TestCondition ($result.ExitCode -ne 0) 'Populated ordinary staging directory was accepted.'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match 'ordinary directory' }).Count -gt 0) 'Populated staging rejection was not actionable.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $preflight.Repository 'Staging-Canvas'))) 'Setup mutated an earlier variant before completing preflight.'
  Assert-TestCondition (!(Test-Path -LiteralPath $preflight.CanvasTarget)) 'Setup created a physical target before completing preflight.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash) -ceq $sentinelHash) 'Setup changed the populated staging directory it rejected.'

  $result = Invoke-SetupCase -Case $preflight -ArgumentList @('-MigrateExisting')
  Assert-TestCondition ($result.ExitCode -ne 0) 'Retired -MigrateExisting parameter was accepted.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash) -ceq $sentinelHash) 'Retired migration invocation changed populated staging.'

  $wrongJunction = New-SetupCase -Name 'wrong-junction'
  $wrongTarget = Join-Path $wrongJunction.Root 'wrong-target'
  New-Item -ItemType Directory -Force -Path $wrongTarget | Out-Null
  $wrongStaging = Join-Path $wrongJunction.Repository 'Staging-Canvas'
  New-Item -ItemType Junction -Path $wrongStaging -Value $wrongTarget | Out-Null
  $result = Invoke-SetupCase -Case $wrongJunction -ArgumentList @('-VariantKeys', 'CANVAS')
  Assert-TestCondition ($result.ExitCode -ne 0) 'Wrong-target staging Junction was accepted.'
  Assert-JunctionRoute -Path $wrongStaging -Target $wrongTarget
  Assert-TestCondition (!(Test-Path -LiteralPath $wrongJunction.CanvasTarget)) 'Wrong-target Junction rejection created the configured target.'

  $linkedTarget = New-SetupCase -Name 'linked-physical-target'
  $physicalDestination = Join-Path $linkedTarget.Root 'physical-destination'
  New-Item -ItemType Directory -Force -Path $physicalDestination | Out-Null
  New-Item -ItemType Junction -Path $linkedTarget.CanvasTarget -Value $physicalDestination | Out-Null
  $result = Invoke-SetupCase -Case $linkedTarget -ArgumentList @('-VariantKeys', 'CANVAS')
  Assert-TestCondition ($result.ExitCode -ne 0) 'Linked physical module target was accepted.'
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match 'ordinary directory, not a link' }).Count -gt 0) 'Linked physical target rejection was not actionable.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $linkedTarget.Repository 'Staging-Canvas'))) 'Linked physical target rejection created a staging path.'

  $fileTarget = New-SetupCase -Name 'file-target'
  Write-TestText -Path $fileTarget.CanvasTarget -Text "not a directory`n"
  $fileTargetHash = (Get-FileHash -LiteralPath $fileTarget.CanvasTarget -Algorithm SHA256).Hash
  $result = Invoke-SetupCase -Case $fileTarget -ArgumentList @('-VariantKeys', 'CANVAS')
  Assert-TestCondition ($result.ExitCode -ne 0) 'Physical module file was accepted as a target directory.'
  Assert-TestCondition (((Get-FileHash -LiteralPath $fileTarget.CanvasTarget -Algorithm SHA256).Hash) -ceq $fileTargetHash) 'Rejected physical module file was changed.'
  Assert-TestCondition (!(Test-Path -LiteralPath (Join-Path $fileTarget.Repository 'Staging-Canvas'))) 'Physical module file rejection created a staging path.'

  $valid = New-SetupCase -Name 'valid-and-repeat'
  $existingTargetSentinel = Join-Path $valid.CanvasTarget 'keep.txt'
  Write-TestText -Path $existingTargetSentinel -Text "keep target contents`n"
  $existingTargetHash = (Get-FileHash -LiteralPath $existingTargetSentinel -Algorithm SHA256).Hash
  $result = Invoke-SetupCase -Case $valid
  Assert-TestCondition ($result.ExitCode -eq 0) "Valid setup failed: $([string]::Join([Environment]::NewLine, $result.Output))"
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-Canvas') -Target $valid.CanvasTarget
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-Example') -Target $valid.ExampleTarget
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-ComponentGallery') -Target $valid.ComponentTarget
  Assert-TestCondition (((Get-FileHash -LiteralPath $existingTargetSentinel -Algorithm SHA256).Hash) -ceq $existingTargetHash) 'Setup changed an existing physical target file.'

  $result = Invoke-SetupCase -Case $valid
  Assert-TestCondition ($result.ExitCode -eq 0) "Repeated valid setup failed: $([string]::Join([Environment]::NewLine, $result.Output))"
  Assert-TestCondition (@($result.Output | Where-Object { $_ -match 'already configured' }).Count -eq 3) 'Repeated setup did not report all existing Junctions as configured.'
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-Canvas') -Target $valid.CanvasTarget
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-Example') -Target $valid.ExampleTarget
  Assert-JunctionRoute -Path (Join-Path $valid.Repository 'Staging-ComponentGallery') -Target $valid.ComponentTarget
  Assert-TestCondition (((Get-FileHash -LiteralPath $existingTargetSentinel -Algorithm SHA256).Hash) -ceq $existingTargetHash) 'Repeated setup changed existing target contents.'

  Write-Output 'Setup tests passed: complete preflight, populated-directory preservation, retired migration, invalid Junction and target rejection, three missing-path creations, and harmless repetition.'
}
finally {
  foreach ($case in $createdCases) {
    foreach ($stagingName in @('Staging-Canvas', 'Staging-Example', 'Staging-ComponentGallery')) {
      $stagingPath = Join-Path $case.Repository $stagingName
      if (Test-Path -LiteralPath $stagingPath) {
        $item = Get-Item -LiteralPath $stagingPath -Force
        if ($item.LinkType -eq 'Junction') { Remove-Item -LiteralPath $stagingPath -Force }
      }
    }
    foreach ($targetPath in @($case.CanvasTarget, $case.ExampleTarget, $case.ComponentTarget)) {
      if (Test-Path -LiteralPath $targetPath) {
        $item = Get-Item -LiteralPath $targetPath -Force
        if ($item.LinkType -eq 'Junction') { Remove-Item -LiteralPath $targetPath -Force }
      }
    }
  }
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-SafeFixturePath -Path $fixtureRoot
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}
