function Register-AiToolHandler {
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [Parameter(Mandatory)]
        [scriptblock]$Handler
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    $script:CurrentAi.RegisterToolHandler($ToolName, $Handler)
}
