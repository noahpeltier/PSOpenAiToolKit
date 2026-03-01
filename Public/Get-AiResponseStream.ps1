function Get-AiResponseStream {
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
        [string]$ImageDetail = "auto",

        [scriptblock]$OnDelta,
        [scriptblock]$OnEvent,
        [switch]$NoLiveText,
        [switch]$IncludeObfuscation,
        [switch]$PassThru
    )

    process {
        if (-not $script:CurrentAi) {
            throw "No OpenAi instance found. Run New-Ai first."
        }

        $userOnDelta = $OnDelta
        $shouldWriteLiveText = -not $NoLiveText.IsPresent

        $forwardDelta = {
            param($delta, $eventObject)

            if ($shouldWriteLiveText -and -not [string]::IsNullOrEmpty($delta)) {
                Write-Host -NoNewline $delta
            }

            if ($userOnDelta) {
                & $userOnDelta $delta $eventObject
            }
        }.GetNewClosure()

        $includeObfuscation = $IncludeObfuscation.IsPresent

        $resultText = ""
        if ($PSCmdlet.ParameterSetName -eq "Vision") {
            $contentParts = New-OpenAiUserContentParts -Message $Message -ImagePath $ImagePath -ImageDetail $ImageDetail
            $resultText = Invoke-InternalAiVisionTextResponseStream -Ai $script:CurrentAi -ContentParts ([object[]]$contentParts) -OnDelta $forwardDelta -OnEvent $OnEvent -IncludeObfuscation $includeObfuscation
        }
        elseif ($PSBoundParameters.ContainsKey("Message")) {
            $resultText = $script:CurrentAi.GetTextResponseStream($Message, $forwardDelta, $OnEvent, $includeObfuscation)
        }
        else {
            $resultText = $script:CurrentAi.GetResponseStream($forwardDelta, $OnEvent, $includeObfuscation)
        }

        if (-not $NoLiveText) {
            Write-Host ""
        }

        if ($PassThru -or $NoLiveText) {
            return $resultText
        }
    }
}
