function Add-AiTool {
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param(
        [Parameter(ParameterSetName = "Path", Mandatory, ValueFromPipeline)]
        [Alias("Tool")]
        [string]$Path,

        [Parameter(ParameterSetName = "Command", Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateScript({ (Get-Command $_ -ErrorAction Ignore) -is [System.Management.Automation.CommandInfo] })]
        [Alias("Name")]
        [string[]]$Command,

        [Parameter(ParameterSetName = "Command")]
        [string]$Description,

        [Parameter(ParameterSetName = "Command")]
        [ValidateNotNullOrEmpty()]
        [string[]]$IncludeParameters,

        [Parameter(ParameterSetName = "Command")]
        [ValidateNotNullOrEmpty()]
        [string[]]$ExcludeParameters,

        [Parameter(ParameterSetName = "Command")]
        [string]$ParameterSetName,

        [Parameter(ParameterSetName = "Command")]
        [switch]$Strict
    )

    process {
        if (-not $script:CurrentAi) {
            throw "No OpenAi instance found. Run New-Ai first."
        }

        switch ($PSCmdlet.ParameterSetName) {
            "Path" {
                $script:CurrentAi.AddToolFromPath($Path)
            }
            "Command" {
                Ensure-AiToolBuilderLoaded

                foreach ($currentCommand in $Command) {
                    $builderParams = @{ Command = $currentCommand }
                    foreach ($name in @("Description", "IncludeParameters", "ExcludeParameters", "ParameterSetName")) {
                        if ($PSBoundParameters.ContainsKey($name)) {
                            $builderParams[$name] = $PSBoundParameters[$name]
                        }
                    }

                    if ($Strict.IsPresent) {
                        $builderParams.Strict = $true
                    }

                    $functionDefinition = New-ChatCompletionFunction @builderParams
                    if ($null -eq $functionDefinition) {
                        throw "No function definition was created for command '$currentCommand'."
                    }

                    $toolPayload = @{
                        type = "function"
                        name = [string]$functionDefinition.name
                        parameters = $functionDefinition.parameters
                    }

                    if (-not [string]::IsNullOrWhiteSpace([string]$functionDefinition.description)) {
                        $toolPayload.description = [string]$functionDefinition.description
                    }

                    if ($functionDefinition.Contains("strict") -and $functionDefinition.strict) {
                        $toolPayload.strict = $true
                    }

                    $script:CurrentAi.AddTool($toolPayload)
                }
            }
        }
    }
}
