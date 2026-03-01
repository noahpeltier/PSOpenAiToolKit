function Invoke-InternalAiVisionTextResponse {
    param(
        [Parameter(Mandatory)]
        [object]$Ai,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$ContentParts
    )

    if ($Ai.PSObject.Methods.Match("GetTextResponseFromContentParts").Count -gt 0) {
        return $Ai.GetTextResponseFromContentParts([object[]]$ContentParts)
    }

    $objectArrayOverload = $Ai.GetType().GetMethod("GetTextResponse", [type[]]@([object[]]))
    if ($objectArrayOverload) {
        return [string]$objectArrayOverload.Invoke($Ai, @([object[]]$ContentParts))
    }

    Add-InternalAiContentParts -Ai $Ai -ContentParts $ContentParts
    $response = $Ai.GetRawResponse()
    return Get-InternalAiOutputText -Response $response
}
