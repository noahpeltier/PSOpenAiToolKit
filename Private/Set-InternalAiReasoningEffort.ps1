function Set-InternalAiReasoningEffort {
    param(
        [Parameter(Mandatory)]
        [object]$Ai,
        [string]$Effort,
        [switch]$Clear
    )

    if ($null -eq $Ai) {
        throw "Ai instance is required."
    }

    if ($Clear) {
        if ($Ai.PSObject.Methods.Match("ClearReasoningEffort").Count -gt 0) {
            $Ai.ClearReasoningEffort()
            return
        }

        $model = ""
        if ($Ai.PSObject.Properties["Body"] -and $Ai.Body -and $Ai.Body.PSObject.Properties["model"] -and $Ai.Body.model) {
            $model = [string]$Ai.Body.model
        }

        if ($Ai.PSObject.Properties["Body"] -and $Ai.Body) {
            if ($model -match '^gpt-5') {
                $Ai.Body.reasoning = @{ effort = 'none' }
            }
            else {
                $Ai.Body.reasoning = $null
            }
        }

        return
    }

    if ([string]::IsNullOrWhiteSpace($Effort)) {
        throw "Effort is required."
    }

    $normalizedEffort = $Effort.ToLowerInvariant()
    if ($normalizedEffort -notin @("none", "low", "medium", "high")) {
        throw "Reasoning effort '$Effort' is invalid. Valid values are: none, low, medium, high."
    }

    if ($Ai.PSObject.Methods.Match("SetReasoningEffort").Count -gt 0) {
        $Ai.SetReasoningEffort($normalizedEffort)
        return
    }

    if ($Ai.PSObject.Properties["Body"] -and $Ai.Body) {
        $Ai.Body.reasoning = @{ effort = $normalizedEffort }
        return
    }

    throw "Could not apply reasoning effort to the current Ai instance."
}
