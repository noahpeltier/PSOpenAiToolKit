function Set-AiReasoningEffort {
    [CmdletBinding(DefaultParameterSetName = "Set")]
    param(
        [Parameter(ParameterSetName = "Set", Mandatory)]
        [ValidateSet("none", "low", "medium", "high")]
        [string]$Effort,

        [Parameter(ParameterSetName = "Clear", Mandatory)]
        [switch]$Clear
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    if ($PSCmdlet.ParameterSetName -eq "Clear") {
        Set-InternalAiReasoningEffort -Ai $script:CurrentAi -Clear
        return
    }

    Set-InternalAiReasoningEffort -Ai $script:CurrentAi -Effort $Effort
}
