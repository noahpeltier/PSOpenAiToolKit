function Set-AiLegacyToolAutoInvoke {
    param(
        [Parameter(Mandatory)]
        [bool]$State
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    $script:CurrentAi.SetLegacyAutoToolInvocation($State)
}
