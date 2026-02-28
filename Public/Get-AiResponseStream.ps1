function Get-AiResponseStream {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Message,
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
        if ($PSBoundParameters.ContainsKey("Message")) {
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
