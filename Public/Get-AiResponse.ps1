function Get-AiResponse {
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Message
    )

    process {
        if (-not $script:CurrentAi) {
            throw "No OpenAi instance found. Run New-Ai first."
        }

        return $script:CurrentAi.GetTextResponse($Message)
    }
}
