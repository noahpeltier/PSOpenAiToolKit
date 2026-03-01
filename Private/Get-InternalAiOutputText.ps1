function Get-InternalAiOutputText {
    param(
        [Parameter(Mandatory)]
        [object]$Response
    )

    $message = @($Response.output) | Where-Object { $_.type -eq "message" } | Select-Object -Last 1
    if (-not $message) {
        return ""
    }

    $textParts = @($message.content) | ForEach-Object {
        if ($_.type -in @("output_text", "text")) {
            if ($_.text -is [string]) {
                $_.text
            }
            elseif ($_.text -and $_.text.value) {
                $_.text.value
            }
        }
    }

    return ($textParts -join "")
}
