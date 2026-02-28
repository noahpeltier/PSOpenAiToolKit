function ConvertTo-OpenAiQueryString {
    param(
        [hashtable]$Query
    )

    if ($null -eq $Query -or $Query.Count -eq 0) {
        return ""
    }

    $pairs = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value) {
            continue
        }

        $escapedKey = [System.Uri]::EscapeDataString([string]$key)
        $isCollection = ($value -is [System.Collections.IEnumerable]) -and ($value -isnot [string]) -and ($value -isnot [System.Collections.IDictionary])
        if ($isCollection) {
            foreach ($item in $value) {
                if ($null -eq $item) {
                    continue
                }

                $pairs.Add("$escapedKey=$([System.Uri]::EscapeDataString([string]$item))") | Out-Null
            }

            continue
        }

        $pairs.Add("$escapedKey=$([System.Uri]::EscapeDataString([string]$value))") | Out-Null
    }

    if ($pairs.Count -eq 0) {
        return ""
    }

    return "?" + ($pairs -join "&")
}
