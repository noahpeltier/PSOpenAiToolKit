function Invoke-InternalAiVisionTextResponseStream {
    param(
        [Parameter(Mandatory)]
        [object]$Ai,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$ContentParts,

        [scriptblock]$OnDelta,
        [scriptblock]$OnEvent,

        [Parameter(Mandatory)]
        [bool]$IncludeObfuscation
    )

    if ($Ai.PSObject.Methods.Match("GetTextResponseStreamFromContentParts").Count -gt 0) {
        return $Ai.GetTextResponseStreamFromContentParts([object[]]$ContentParts, $OnDelta, $OnEvent, $IncludeObfuscation)
    }

    $objectArrayOverload = $Ai.GetType().GetMethod("GetTextResponseStream", [type[]]@([object[]], [scriptblock], [scriptblock], [bool]))
    if ($objectArrayOverload) {
        return [string]$objectArrayOverload.Invoke($Ai, @([object[]]$ContentParts, $OnDelta, $OnEvent, $IncludeObfuscation))
    }

    $deltaBuilder = [System.Text.StringBuilder]::new()
    $userOnDelta = $OnDelta

    $captureDelta = {
        param($delta, $eventObject)

        if (-not [string]::IsNullOrEmpty($delta)) {
            $null = $deltaBuilder.Append($delta)
        }

        if ($userOnDelta) {
            & $userOnDelta $delta $eventObject
        }
    }.GetNewClosure()

    Add-InternalAiContentParts -Ai $Ai -ContentParts $ContentParts
    $response = $Ai.GetRawResponseStream($captureDelta, $OnEvent, $IncludeObfuscation)

    $streamedText = $deltaBuilder.ToString()
    if (-not [string]::IsNullOrEmpty($streamedText)) {
        return $streamedText
    }

    return Get-InternalAiOutputText -Response $response
}
