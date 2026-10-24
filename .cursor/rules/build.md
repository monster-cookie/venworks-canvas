# Build and verification entry points

Run relevant entry points from the repository root in PowerShell 7, for example `pwsh -NoProfile -File .\Tools\compileScripts.ps1`. Use the configured inputs and tools; do not run every entry point as a generic validation checklist.

| Entry point | Purpose |
| --- | --- |
| [Tools/compileScripts.ps1](../../Tools/compileScripts.ps1) | Compile configured Papyrus sources using the installed compiler. |
| [Tools/buildScaleform.ps1](../../Tools/buildScaleform.ps1) | Build the Scaleform jobs configured for the selected Canvas variants. |
| [Tools/VerifyPipelineTooling.ps1](../../Tools/VerifyPipelineTooling.ps1) | Check the pinned JDK, JPEXS, Apache Flex, and Player 11.1 inputs before a native Scaleform build. |
| [Tools/createPackages.ps1](../../Tools/createPackages.ps1) | Build configured archives from the required inputs and publish packages beneath verified staging junctions. |
| [Tools/checkRepo.ps1](../../Tools/checkRepo.ps1) | Check configured metadata, artifacts, and staging paths. Its `-Committed` mode does not require destination values or junctions, but initial shared configuration still requires an environment file. |
| [Tools/setupRepo.ps1](../../Tools/setupRepo.ps1) | Prepare configured staging junctions; this is a maintainer operation, not a routine test. |

Spriggit dump/assembly scripts are optional authoring operations, not required checks for every change. CI's PowerShell analysis does not establish native Papyrus, Scaleform, package, game, or console acceptance. See the [build workflow](../../README.md#build-workflow) and [staging instructions](../../README.md#prepare-staging) for setup details. Downloads, installation, live staging, and authoring changes must be within the task's authorized scope.

PowerShell is the build interface, not a required test language. Invoking the actual compiler provides build evidence; recreating ActionScript behavior in PowerShell does not test the delivered Scaleform code. Missing native tools or game access are explicit validation limits. A compiled script or packaged archive still needs the relevant game/runtime scenario to establish its behavior; apply the shared [verification guidance](../../AGENTS.md#verification-and-communication).
