function Invoke-OpenAiMethod {
    [CmdletBinding(DefaultParameterSetName = "CurrentAi")]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(ParameterSetName = "ApiKey", Mandatory)]
        [string]$ApiKey,

        [hashtable]$Query,
        [object]$Body,
        [string]$BodyJson,
        [hashtable]$Headers,
        [switch]$RawResponse,
        [int]$TimeoutSec = 100
    )

    if ($PSBoundParameters.ContainsKey("Body") -and $PSBoundParameters.ContainsKey("BodyJson")) {
        throw "Specify either -Body or -BodyJson, not both."
    }

    $session = $null
    if ($PSCmdlet.ParameterSetName -eq "ApiKey") {
        $session = [OpenAiWebSession]::new($ApiKey)
    }
    else {
        if (-not $script:CurrentAi) {
            throw "No OpenAi instance found. Run New-Ai first, or provide -ApiKey."
        }

        $session = $script:CurrentAi.Session
    }

    $cleanEndpoint = $Endpoint.Trim('/')
    if ([string]::IsNullOrWhiteSpace($cleanEndpoint)) {
        throw "Endpoint is required."
    }

    $queryString = ConvertTo-OpenAiQueryString -Query $Query
    $uri = "$([OpenAiWebSession]::BaseUri)/$cleanEndpoint$queryString"

    $requestParams = @{
        Method = $Method
        Uri = $uri
        WebSession = $session
        ErrorAction = "Stop"
        TimeoutSec = $TimeoutSec
    }

    if ($Headers) {
        $requestParams.Headers = $Headers
    }

    if ($PSBoundParameters.ContainsKey("BodyJson")) {
        $requestParams.Body = $BodyJson
        $requestParams.ContentType = "application/json"
    }
    elseif ($PSBoundParameters.ContainsKey("Body")) {
        if ($Body -is [string]) {
            $requestParams.Body = $Body
        }
        elseif ($Body -and $Body.PSObject.Methods.Match("ToJson").Count -gt 0) {
            $requestParams.Body = $Body.ToJson()
        }
        else {
            $requestParams.Body = ($Body | ConvertTo-Json -Depth 100)
        }

        $requestParams.ContentType = "application/json"
    }

    try {
        if ($RawResponse) {
            return Invoke-WebRequest @requestParams
        }

        return Invoke-RestMethod @requestParams
    }
    catch {
        $statusCode = $null
        $errorBody = $null

        if ($_.Exception.PSObject.Properties["Response"] -and $null -ne $_.Exception.Response) {
            try {
                if ($_.Exception.Response.PSObject.Properties["StatusCode"]) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {
            }

            try {
                if ($_.Exception.Response.PSObject.Properties["Content"] -and $null -ne $_.Exception.Response.Content) {
                    $errorBody = $_.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                }
            }
            catch {
            }
        }

        if ([string]::IsNullOrWhiteSpace($errorBody) -and $_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errorBody = $_.ErrorDetails.Message
        }

        if ($null -ne $statusCode) {
            if ([string]::IsNullOrWhiteSpace($errorBody)) {
                throw "OpenAI request failed ($Method $cleanEndpoint) with status code $statusCode."
            }

            throw "OpenAI request failed ($Method $cleanEndpoint) with status code ${statusCode}: $errorBody"
        }

        throw "OpenAI request failed ($Method $cleanEndpoint): $($_.Exception.Message)"
    }
}
