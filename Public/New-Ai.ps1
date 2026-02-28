function New-Ai {
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey,
        [string]$Model = "gpt-5.2",
        [ValidateSet("none", "low", "medium", "high")]
        [string]$ReasoningEffort
    )

    $script:CurrentAi = [OpenAi]::new($ApiKey, $Model)

    if ($PSBoundParameters.ContainsKey("ReasoningEffort")) {
        Set-InternalAiReasoningEffort -Ai $script:CurrentAi -Effort $ReasoningEffort
    }

    return $script:CurrentAi
}
