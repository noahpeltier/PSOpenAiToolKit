function Get-AiResponse {
    [CmdletBinding(DefaultParameterSetName = "Text")]
    param(
        [Parameter(ParameterSetName = "Text", ValueFromPipeline, Position = 0)]
        [Parameter(ParameterSetName = "Vision")]
        [string]$Message,

        [Parameter(ParameterSetName = "Vision", Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ImagePath,

        [Parameter(ParameterSetName = "Vision")]
        [ValidateSet("auto", "low", "high")]
        [string]$ImageDetail = "auto"
    )

    process {
        if (-not $script:CurrentAi) {
            throw "No OpenAi instance found. Run New-Ai first."
        }

        if ($PSCmdlet.ParameterSetName -eq "Vision") {
            $contentParts = New-OpenAiUserContentParts -Message $Message -ImagePath $ImagePath -ImageDetail $ImageDetail
            return Invoke-InternalAiVisionTextResponse -Ai $script:CurrentAi -ContentParts ([object[]]$contentParts)
        }

        return $script:CurrentAi.GetTextResponse($Message)
    }
}
