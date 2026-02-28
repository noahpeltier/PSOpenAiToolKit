function Remove-AiTool {
    [CmdletBinding(DefaultParameterSetName = "ByName", SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName = "ByName", Mandatory, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                if ($null -eq $script:CurrentAi) {
                    return
                }

                $typeFilter = ""
                if ($fakeBoundParameters.ContainsKey("Type") -and $fakeBoundParameters["Type"]) {
                    $typeFilter = [string]$fakeBoundParameters["Type"]
                }

                $candidates = $script:CurrentAi.GetTools()
                if (-not [string]::IsNullOrWhiteSpace($typeFilter)) {
                    $candidates = @($candidates | Where-Object { $_.Type -eq $typeFilter })
                }

                $names = $candidates |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } |
                    Select-Object -ExpandProperty Name -Unique |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    Sort-Object

                foreach ($name in $names) {
                    [System.Management.Automation.CompletionResult]::new($name, $name, "ParameterValue", $name)
                }
            })]
        [string[]]$Name,

        [Parameter(ParameterSetName = "ByName")]
        [string]$Type,

        [Parameter(ParameterSetName = "ByIndex", Mandatory, ValueFromPipelineByPropertyName)]
        [int[]]$Index,

        [switch]$KeepHandler,
        [switch]$PassThru
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    $targetDescription = if ($PSCmdlet.ParameterSetName -eq "ByIndex") {
        "index: $($Index -join ', ')"
    }
    else {
        "name: $($Name -join ', ')"
    }

    if (-not $PSCmdlet.ShouldProcess("OpenAi tools", "Remove tool(s) by $targetDescription")) {
        return
    }

    $removedTools = switch ($PSCmdlet.ParameterSetName) {
        "ByIndex" { $script:CurrentAi.RemoveToolsByIndex($Index, $KeepHandler.IsPresent) }
        default { $script:CurrentAi.RemoveToolsByName($Name, $Type, $KeepHandler.IsPresent) }
    }

    if ($PassThru) {
        return $removedTools
    }

    return $removedTools.Count
}
