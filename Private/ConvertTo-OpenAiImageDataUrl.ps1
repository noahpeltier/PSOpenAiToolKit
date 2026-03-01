function ConvertTo-OpenAiImageDataUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "Image path '$Path' is a directory. Provide a file path."
    }

    $mimeType = switch ($item.Extension.ToLowerInvariant()) {
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".webp" { "image/webp" }
        ".gif" { "image/gif" }
        default {
            throw "Unsupported image file extension '$($item.Extension)'. Supported types: .png, .jpg, .jpeg, .webp, .gif"
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
    $base64 = [System.Convert]::ToBase64String($bytes)
    return "data:$mimeType;base64,$base64"
}
