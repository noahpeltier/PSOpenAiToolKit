function New-OpenAiUserContentParts {
    [CmdletBinding()]
    param(
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ImagePath,

        [ValidateSet("auto", "low", "high")]
        [string]$ImageDetail = "auto"
    )

    if ($ImagePath.Count -gt 500) {
        throw "A maximum of 500 images is allowed per request."
    }

    $content = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $content.Add([ordered]@{
                type = "input_text"
                text = $Message
            }) | Out-Null
    }

    $totalBytes = [int64]0
    foreach ($path in $ImagePath) {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($item.PSIsContainer) {
            throw "Image path '$path' is a directory. Provide a file path."
        }

        $totalBytes += [int64]$item.Length
        if ($totalBytes -gt 52428800) {
            throw "Total image file size exceeds 50 MB limit for a single request."
        }

        $part = [ordered]@{
            type = "input_image"
            image_url = ConvertTo-OpenAiImageDataUrl -Path $item.FullName
        }

        if ($ImageDetail -ne "auto") {
            $part.detail = $ImageDetail
        }

        $content.Add($part) | Out-Null
    }

    return @($content)
}
