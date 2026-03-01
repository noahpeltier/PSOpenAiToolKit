function Add-InternalAiContentParts {
    param(
        [Parameter(Mandatory)]
        [object]$Ai,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$ContentParts
    )

    if ($null -eq $Ai) {
        throw "Ai instance is required."
    }

    if ($ContentParts.Count -eq 0) {
        throw "At least one content part is required."
    }

    $content = @($ContentParts | Where-Object { $null -ne $_ })
    if ($content.Count -eq 0) {
        throw "At least one non-null content part is required."
    }

    $message = [ordered]@{
        role = "user"
        content = $content
    }

    if ($Ai.PSObject.Properties["Body"] -and $Ai.Body -and $Ai.Body.PSObject.Properties["input"]) {
        $null = $Ai.Body.input.Add($message)
        return
    }

    throw "Could not append content parts to the current Ai instance."
}
