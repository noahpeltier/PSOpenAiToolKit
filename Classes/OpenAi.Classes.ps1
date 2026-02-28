class OpenAiWebSession : Microsoft.PowerShell.Commands.WebRequestSession {

    static [string] $BaseUri = "https://api.openai.com/v1"

    OpenAiWebSession([string]$ApiKey) {
        if ([string]::IsNullOrWhiteSpace($ApiKey)) {
            throw "ApiKey is required."
        }

        $this.Headers.Add("Authorization", "Bearer $ApiKey")
        $this.Headers.Add("Content-Type", "application/json")
    }

    hidden [string] BuildUri([string]$Endpoint) {
        if ([string]::IsNullOrWhiteSpace($Endpoint)) {
            throw "Endpoint is required."
        }

        $cleanEndpoint = $Endpoint.Trim('/')
        return "$([OpenAiWebSession]::BaseUri)/$cleanEndpoint"
    }

    hidden [string] SerializeBody([object]$Body) {
        if ($null -eq $Body) {
            return ""
        }

        if ($Body -is [string]) {
            return $Body
        }

        if ($Body.PSObject.Methods.Match("ToJson").Count -gt 0) {
            return $Body.ToJson()
        }

        return ($Body | ConvertTo-Json -Depth 100)
    }

    [object] Post([object]$Body, [string]$Endpoint) {
        $uri = $this.BuildUri($Endpoint)
        $payload = $this.SerializeBody($Body)

        try {
            return Invoke-RestMethod -Method POST -Uri $uri -Body $payload -WebSession $this -ErrorAction Stop
        }
        catch {
            throw "OpenAI POST failed at '$Endpoint': $($_.Exception.Message)"
        }
    }

    [object] Post([string]$Endpoint) {
        $uri = $this.BuildUri($Endpoint)

        try {
            return Invoke-RestMethod -Method POST -Uri $uri -WebSession $this -ErrorAction Stop
        }
        catch {
            throw "OpenAI POST failed at '$Endpoint': $($_.Exception.Message)"
        }
    }

    [object] Get([string]$Endpoint) {
        $uri = $this.BuildUri($Endpoint)

        try {
            return Invoke-RestMethod -Method GET -Uri $uri -WebSession $this -ErrorAction Stop
        }
        catch {
            throw "OpenAI GET failed at '$Endpoint': $($_.Exception.Message)"
        }
    }

    hidden [object] ParseSseEvent([string]$EventName, [System.Collections.Generic.List[string]]$DataLines) {
        if ($null -eq $DataLines -or $DataLines.Count -eq 0) {
            return $null
        }

        $rawData = ($DataLines -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($rawData)) {
            return $null
        }

        if ($rawData -eq "[DONE]") {
            return [pscustomobject]@{
                type = "stream.done"
            }
        }

        $eventObject = $null
        try {
            $eventObject = $rawData | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        }
        catch {
            $eventObject = [pscustomobject]@{
                type = if ([string]::IsNullOrWhiteSpace($EventName)) { "stream.raw" } else { $EventName }
                data = $rawData
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($EventName)) {
            $hasType = $false
            if ($eventObject -is [System.Collections.IDictionary]) {
                $hasType = $eventObject.Contains("type")
                if (-not $hasType) {
                    $eventObject["type"] = $EventName
                }
            }
            else {
                $hasType = $null -ne $eventObject.PSObject.Properties["type"]
                if (-not $hasType) {
                    $eventObject | Add-Member -NotePropertyName "type" -NotePropertyValue $EventName -Force
                }
            }
        }

        return $eventObject
    }

    [object] PostStream([object]$Body, [string]$Endpoint, [scriptblock]$OnEvent) {
        $uri = $this.BuildUri($Endpoint)
        $payload = $this.SerializeBody($Body)

        $httpClient = [System.Net.Http.HttpClient]::new()
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $uri)
        $request.Content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, "application/json")
        $request.Headers.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("text/event-stream"))

        $authHeader = $this.Headers["Authorization"]
        if (-not [string]::IsNullOrWhiteSpace($authHeader)) {
            $request.Headers.TryAddWithoutValidation("Authorization", $authHeader) | Out-Null
        }

        $httpResponse = $null
        $responseStream = $null
        $streamReader = $null

        $result = [ordered]@{
            Response = $null
            TerminalEventType = $null
            ErrorEvent = $null
        }

        try {
            $httpResponse = $httpClient.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            if (-not $httpResponse.IsSuccessStatusCode) {
                $errorBody = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                throw "OpenAI streaming POST failed at '$Endpoint' with status code $([int]$httpResponse.StatusCode): $errorBody"
            }

            $responseStream = $httpResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $streamReader = [System.IO.StreamReader]::new($responseStream)

            $currentEventName = ""
            $currentDataLines = [System.Collections.Generic.List[string]]::new()

            while (-not $streamReader.EndOfStream) {
                $line = $streamReader.ReadLine()
                if ($null -eq $line) {
                    continue
                }

                if ($line.Length -eq 0) {
                    $eventObject = $this.ParseSseEvent($currentEventName, $currentDataLines)
                    $currentEventName = ""
                    $currentDataLines = [System.Collections.Generic.List[string]]::new()

                    if ($null -eq $eventObject) {
                        continue
                    }

                    if ($OnEvent) {
                        & $OnEvent $eventObject
                    }

                    $eventType = ""
                    if ($eventObject -is [System.Collections.IDictionary]) {
                        if ($eventObject.Contains("type")) {
                            $eventType = [string]$eventObject.type
                        }
                    }
                    elseif ($eventObject.PSObject.Properties["type"]) {
                        $eventType = [string]$eventObject.type
                    }

                    switch ($eventType) {
                        "response.completed" {
                            $result.TerminalEventType = $eventType
                            if ($eventObject.response) {
                                $result.Response = $eventObject.response
                            }
                            break
                        }
                        "response.failed" {
                            $result.TerminalEventType = $eventType
                            if ($eventObject.response) {
                                $result.Response = $eventObject.response
                            }
                            break
                        }
                        "response.incomplete" {
                            $result.TerminalEventType = $eventType
                            if ($eventObject.response) {
                                $result.Response = $eventObject.response
                            }
                            break
                        }
                        "error" {
                            $result.TerminalEventType = $eventType
                            $result.ErrorEvent = $eventObject
                            break
                        }
                        "stream.done" {
                            if (-not $result.TerminalEventType) {
                                $result.TerminalEventType = $eventType
                            }
                            break
                        }
                    }

                    if ($result.TerminalEventType -in @("response.completed", "response.failed", "response.incomplete", "error", "stream.done")) {
                        break
                    }

                    continue
                }

                if ($line.StartsWith(":")) {
                    continue
                }

                if ($line.StartsWith("event:")) {
                    $currentEventName = $line.Substring(6).Trim()
                    continue
                }

                if ($line.StartsWith("data:")) {
                    $currentDataLines.Add($line.Substring(5).TrimStart())
                }
            }

            if (-not $result.TerminalEventType -and $currentDataLines.Count -gt 0) {
                $eventObject = $this.ParseSseEvent($currentEventName, $currentDataLines)
                if ($eventObject -and $OnEvent) {
                    & $OnEvent $eventObject
                }
            }
        }
        catch {
            throw "OpenAI streaming POST failed at '$Endpoint': $($_.Exception.Message)"
        }
        finally {
            if ($streamReader) {
                $streamReader.Dispose()
            }
            if ($responseStream) {
                $responseStream.Dispose()
            }
            if ($httpResponse) {
                $httpResponse.Dispose()
            }
            if ($request) {
                $request.Dispose()
            }
            if ($httpClient) {
                $httpClient.Dispose()
            }
        }

        return [pscustomobject]$result
    }
}

class OpenAiRequestBody {
    [string]$previous_response_id
    [string]$model
    [System.Collections.Generic.List[object]]$input = [System.Collections.Generic.List[object]]::new()
    [System.Collections.Generic.List[object]]$tools = [System.Collections.Generic.List[object]]::new()
    [bool]$store = $true
    [hashtable]$reasoning
    [string]$instructions

    OpenAiRequestBody() {
        $this.SetModel("gpt-5.2")
    }

    OpenAiRequestBody([string]$Model) {
        $this.SetModel($Model)
    }

    hidden [hashtable] GetDefaultReasoningForModel([string]$Model) {
        if ($Model -match '^gpt-5') {
            return @{ effort = 'none' }
        }

        return $null
    }

    [void] SetModel([string]$Model) {
        if ([string]::IsNullOrWhiteSpace($Model)) {
            throw "Model is required."
        }

        $this.model = $Model
        $this.reasoning = $this.GetDefaultReasoningForModel($Model)
    }

    [void] SetReasoningEffort([string]$Effort) {
        if ([string]::IsNullOrWhiteSpace($Effort)) {
            throw "Effort is required."
        }

        $normalizedEffort = $Effort.ToLowerInvariant()
        if ($normalizedEffort -notin @('none', 'low', 'medium', 'high')) {
            throw "Reasoning effort '$Effort' is invalid. Valid values are: none, low, medium, high."
        }

        $this.reasoning = @{ effort = $normalizedEffort }
    }

    [void] ResetReasoningEffort() {
        $this.reasoning = $this.GetDefaultReasoningForModel($this.model)
    }

    [void] ClearInput() {
        $this.input.Clear()
    }

    [hashtable] ToPayload() {
        $payload = [ordered]@{
            model = $this.model
            input = @($this.input)
            tools = @($this.tools)
            store = $this.store
        }

        if (-not [string]::IsNullOrWhiteSpace($this.previous_response_id)) {
            $payload.previous_response_id = $this.previous_response_id
        }

        if ($this.reasoning) {
            $payload.reasoning = $this.reasoning
        }

        if (-not [string]::IsNullOrWhiteSpace($this.instructions)) {
            $payload.instructions = $this.instructions
        }

        return $payload
    }

    [string] ToJson() {
        return ($this.ToPayload() | ConvertTo-Json -Depth 100)
    }
}

class OpenAiInput {
    [string]$role
    [System.Collections.Generic.List[object]]$content = [System.Collections.Generic.List[object]]::new()

    OpenAiInput([string]$Role, [string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Role)) {
            throw "Role is required."
        }

        $this.role = $Role
        $null = $this.content.Add(
            [ordered]@{
                type = "input_text"
                text = $Text
            }
        )
    }
}

class OpenAiTool {
    [string]$type
    [string]$name
    [string]$description
    [object]$parameters

    OpenAiTool() {
    }

    OpenAiTool([string]$Type, [string]$Name, [string]$Description, [object]$Parameters) {
        $this.type = $Type
        $this.name = $Name
        $this.description = $Description
        $this.parameters = $Parameters
    }

    static [OpenAiTool] CreateFromJson([string]$Json) {
        $object = $Json | ConvertFrom-Json
        return [OpenAiTool]::CreateFromPSObject($object)
    }

    static [OpenAiTool] CreateFromPSObject([pscustomobject]$PSObject) {
        return [OpenAiTool]::new($PSObject.type, $PSObject.name, $PSObject.description, $PSObject.parameters)
    }

    static [OpenAiTool] CreateFromHashTable([hashtable]$HashTable) {
        return [OpenAiTool]::new($HashTable.type, $HashTable.name, $HashTable.description, $HashTable.parameters)
    }

    [hashtable] ToPayload() {
        return [ordered]@{
            type = $this.type
            name = $this.name
            description = $this.description
            parameters = $this.parameters
        }
    }
}

class OpenAi {
    [OpenAiWebSession]$Session
    [OpenAiRequestBody]$Body
    [System.Collections.Generic.List[object]]$Responses = [System.Collections.Generic.List[object]]::new()
    [hashtable]$ToolHandlers = @{}
    [hashtable]$AddedFunctionTools = @{}
    [bool]$AllowLegacyCommandInvocation = $true

    OpenAi([string]$ApiKey) {
        $this.Session = [OpenAiWebSession]::new($ApiKey)
        $this.Body = [OpenAiRequestBody]::new()
    }

    OpenAi([string]$ApiKey, [string]$Model) {
        $this.Session = [OpenAiWebSession]::new($ApiKey)
        $this.Body = [OpenAiRequestBody]::new($Model)
    }

    [void] SetModel([string]$Model) {
        $this.Body.SetModel($Model)
    }

    [void] SetReasoningEffort([string]$Effort) {
        $this.Body.SetReasoningEffort($Effort)
    }

    [void] ClearReasoningEffort() {
        $this.Body.ResetReasoningEffort()
    }

    [void] SetInstructions([string]$Instructions) {
        $this.Body.instructions = $Instructions
    }

    [void] ClearInstructions() {
        $this.Body.instructions = $null
    }

    [void] SetStoreResponses([bool]$State) {
        $this.Body.store = $State
        $this.Forget()
    }

    [void] Forget() {
        $this.Body.previous_response_id = $null
        $this.Body.ClearInput()
        $this.Responses.Clear()
    }

    [void] AddUserInput([string]$Text) {
        $message = [OpenAiInput]::new("user", $Text)
        $null = $this.Body.input.Add($message)
    }

    [void] AddTool([OpenAiTool]$Tool) {
        if ($null -eq $Tool) {
            throw "Tool is required."
        }

        $this.AddToolPayload($Tool.ToPayload())
    }

    [void] AddTool([System.Collections.IDictionary]$ToolDefinition) {
        $this.AddToolPayload($ToolDefinition)
    }

    [void] AddTool([pscustomobject]$ToolDefinition) {
        $this.AddToolPayload($ToolDefinition)
    }

    hidden [void] AddToolPayload([object]$ToolPayload) {
        if ($null -eq $ToolPayload) {
            throw "Tool definition is required."
        }

        $type = $null
        $name = $null

        if ($ToolPayload -is [System.Collections.IDictionary]) {
            if ($ToolPayload.Contains("type")) {
                $type = [string]$ToolPayload.type
            }
            if ($ToolPayload.Contains("name")) {
                $name = [string]$ToolPayload.name
            }
        }
        else {
            if ($ToolPayload.PSObject.Properties["type"]) {
                $type = [string]$ToolPayload.type
            }
            if ($ToolPayload.PSObject.Properties["name"]) {
                $name = [string]$ToolPayload.name
            }
        }

        if ([string]::IsNullOrWhiteSpace($type)) {
            throw "Tool definition is missing required 'type'. If this came from a manifest-style .psd1 file, move the tool into a standalone .tool/.json/.psd1 definition file."
        }

        $normalizedPayload = $ToolPayload
        if ($ToolPayload -is [System.Collections.IDictionary] -and $ToolPayload -isnot [hashtable]) {
            $normalizedPayload = @{}
            foreach ($key in $ToolPayload.Keys) {
                $normalizedPayload[$key] = $ToolPayload[$key]
            }
        }

        $null = $this.Body.tools.Add($normalizedPayload)

        if ($type -eq "function" -and -not [string]::IsNullOrWhiteSpace($name)) {
            $this.AddedFunctionTools[$name] = $true
        }
    }

    hidden [string] GetToolStringValue([object]$ToolPayload, [string]$PropertyName) {
        if ($null -eq $ToolPayload -or [string]::IsNullOrWhiteSpace($PropertyName)) {
            return ""
        }

        $value = $null
        if ($ToolPayload -is [System.Collections.IDictionary]) {
            if ($ToolPayload.Contains($PropertyName)) {
                $value = $ToolPayload[$PropertyName]
            }
        }
        elseif ($ToolPayload.PSObject.Properties[$PropertyName]) {
            $value = $ToolPayload.$PropertyName
        }

        if ($null -eq $value) {
            return ""
        }

        return [string]$value
    }

    hidden [void] RefreshFunctionToolCache() {
        $this.AddedFunctionTools.Clear()

        foreach ($tool in $this.Body.tools) {
            $toolType = $this.GetToolStringValue($tool, "type")
            $toolName = $this.GetToolStringValue($tool, "name")

            if ($toolType -eq "function" -and -not [string]::IsNullOrWhiteSpace($toolName)) {
                $this.AddedFunctionTools[$toolName] = $true
            }
        }
    }

    [object[]] GetTools() {
        $items = [System.Collections.Generic.List[object]]::new()

        for ($i = 0; $i -lt $this.Body.tools.Count; $i++) {
            $tool = $this.Body.tools[$i]
            $type = $this.GetToolStringValue($tool, "type")
            $name = $this.GetToolStringValue($tool, "name")
            $description = $this.GetToolStringValue($tool, "description")
            $hasHandler = $false
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $hasHandler = $this.ToolHandlers.ContainsKey($name)
            }

            $items.Add([pscustomobject]@{
                    Index = $i
                    Type = $type
                    Name = $name
                    Description = $description
                    HasHandler = $hasHandler
                }) | Out-Null
        }

        return @($items)
    }

    hidden [void] CleanupHandlersAfterRemoval([object[]]$RemovedTools, [bool]$KeepHandler) {
        if ($KeepHandler -or $null -eq $RemovedTools -or $RemovedTools.Count -eq 0) {
            return
        }

        $removedFunctionToolNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($removedTool in $RemovedTools) {
            if ($removedTool.Type -eq "function" -and -not [string]::IsNullOrWhiteSpace($removedTool.Name)) {
                $removedFunctionToolNames.Add($removedTool.Name) | Out-Null
            }
        }

        foreach ($toolName in $removedFunctionToolNames) {
            if (-not $this.AddedFunctionTools.ContainsKey($toolName)) {
                $this.ToolHandlers.Remove($toolName) | Out-Null
            }
        }
    }

    [object[]] RemoveToolsByName([string[]]$Name, [string]$Type, [bool]$KeepHandler) {
        if ($null -eq $Name -or $Name.Count -eq 0) {
            return @()
        }

        $nameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($toolName in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($toolName)) {
                $nameSet.Add($toolName) | Out-Null
            }
        }

        $removed = [System.Collections.Generic.List[object]]::new()
        for ($i = $this.Body.tools.Count - 1; $i -ge 0; $i--) {
            $tool = $this.Body.tools[$i]
            $toolName = $this.GetToolStringValue($tool, "name")
            $toolType = $this.GetToolStringValue($tool, "type")

            if (-not $nameSet.Contains($toolName)) {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($Type) -and $toolType -ne $Type) {
                continue
            }

            $removed.Add([pscustomobject]@{
                    Index = $i
                    Type = $toolType
                    Name = $toolName
                    Description = $this.GetToolStringValue($tool, "description")
                    HasHandler = $this.ToolHandlers.ContainsKey($toolName)
                }) | Out-Null

            $this.Body.tools.RemoveAt($i)
        }

        $this.RefreshFunctionToolCache()
        $this.CleanupHandlersAfterRemoval(@($removed), $KeepHandler)

        return @($removed | Sort-Object -Property Index)
    }

    [object[]] RemoveToolsByIndex([int[]]$Index, [bool]$KeepHandler) {
        if ($null -eq $Index -or $Index.Count -eq 0) {
            return @()
        }

        $uniqueIndices = $Index | Select-Object -Unique
        foreach ($toolIndex in $uniqueIndices) {
            if ($toolIndex -lt 0 -or $toolIndex -ge $this.Body.tools.Count) {
                throw "Tool index '$toolIndex' is out of range."
            }
        }

        $removed = [System.Collections.Generic.List[object]]::new()
        foreach ($toolIndex in ($uniqueIndices | Sort-Object -Descending)) {
            $tool = $this.Body.tools[$toolIndex]
            $toolName = $this.GetToolStringValue($tool, "name")
            $toolType = $this.GetToolStringValue($tool, "type")

            $removed.Add([pscustomobject]@{
                    Index = $toolIndex
                    Type = $toolType
                    Name = $toolName
                    Description = $this.GetToolStringValue($tool, "description")
                    HasHandler = $this.ToolHandlers.ContainsKey($toolName)
                }) | Out-Null

            $this.Body.tools.RemoveAt($toolIndex)
        }

        $this.RefreshFunctionToolCache()
        $this.CleanupHandlersAfterRemoval(@($removed), $KeepHandler)

        return @($removed | Sort-Object -Property Index)
    }

    [void] AddToolFromPath([string]$Path) {
        $item = Get-Item -Path $Path -ErrorAction Stop

        switch ($item.Extension.ToLowerInvariant()) {
            ".psd1" {
                $tool = Import-PowerShellDataFile -Path $item.FullName

                $hasType = $false
                if ($tool -is [hashtable]) {
                    $hasType = $tool.ContainsKey("type")
                }
                elseif ($tool -and $tool.PSObject.Properties["type"]) {
                    $hasType = $true
                }

                if ($hasType) {
                    $this.AddTool($tool)
                    break
                }

                $toolCompanionPath = [System.IO.Path]::ChangeExtension($item.FullName, ".tool")
                if (Test-Path -Path $toolCompanionPath) {
                    $this.AddToolFromPath($toolCompanionPath)
                    break
                }

                throw "No tool definition found in '$($item.FullName)'. If this file is a module manifest, provide a .tool/.json tool file instead."
            }
            ".tool" {
                try {
                    $tool = Import-PowerShellDataFile -Path $item.FullName
                }
                catch {
                    $tool = Get-Content -Path $item.FullName -Raw | ConvertFrom-Json
                }

                if ($tool -is [System.Array]) {
                    foreach ($toolDef in $tool) {
                        $this.AddTool($toolDef)
                    }
                }
                else {
                    $this.AddTool($tool)
                }
            }
            ".json" {
                $tool = Get-Content -Path $item.FullName -Raw | ConvertFrom-Json
                if ($tool -is [System.Array]) {
                    foreach ($toolDef in $tool) {
                        $this.AddTool($toolDef)
                    }
                }
                else {
                    $this.AddTool($tool)
                }
            }
            default {
                throw "Unsupported tool file extension '$($item.Extension)'."
            }
        }
    }

    [void] SetLegacyAutoToolInvocation([bool]$Enabled) {
        $this.AllowLegacyCommandInvocation = $Enabled
    }

    [void] RegisterToolHandler([string]$ToolName, [scriptblock]$Handler) {
        if ([string]::IsNullOrWhiteSpace($ToolName)) {
            throw "ToolName is required."
        }

        if ($null -eq $Handler) {
            throw "Handler is required."
        }

        $this.ToolHandlers[$ToolName] = $Handler
    }

    hidden [void] ApplyConversationState() {
        if (-not $this.Body.store) {
            $this.Body.previous_response_id = $null
            return
        }

        $this.RemoveTrailingUnresolvedResponses()

        if ($this.Responses.Count -gt 0) {
            $this.Body.previous_response_id = $this.Responses[$this.Responses.Count - 1].id
        }
        else {
            $this.Body.previous_response_id = $null
        }
    }

    hidden [bool] IsResponseAwaitingToolOutput([object]$Response) {
        if ($null -eq $Response) {
            return $false
        }

        $functionCalls = @($Response.output) | Where-Object { $_.type -eq "function_call" }
        return ($functionCalls.Count -gt 0)
    }

    hidden [void] RemoveTrailingUnresolvedResponses() {
        while ($this.Responses.Count -gt 0) {
            $lastIndex = $this.Responses.Count - 1
            $lastResponse = $this.Responses[$lastIndex]
            if (-not $this.IsResponseAwaitingToolOutput($lastResponse)) {
                break
            }

            $this.Responses.RemoveAt($lastIndex)
        }
    }

    hidden [object] SendResponse() {
        return $this.Session.Post($this.Body, "responses")
    }

    hidden [void] CommitTurnResponses([System.Collections.Generic.List[object]]$TurnResponses) {
        if ($null -eq $TurnResponses) {
            return
        }

        foreach ($response in $TurnResponses) {
            if ($null -ne $response) {
                $null = $this.Responses.Add($response)
            }
        }
    }

    hidden [void] RollbackTurn([int]$ResponseCountBefore, [string]$PreviousResponseIdBefore) {
        $this.Body.ClearInput()

        while ($this.Responses.Count -gt $ResponseCountBefore) {
            $this.Responses.RemoveAt($this.Responses.Count - 1)
        }

        $this.Body.previous_response_id = $PreviousResponseIdBefore
    }

    hidden [string] GetStreamEventProperty([object]$EventObject, [string]$PropertyName) {
        if ($null -eq $EventObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
            return ""
        }

        if ($EventObject -is [System.Collections.IDictionary]) {
            if ($EventObject.Contains($PropertyName) -and $null -ne $EventObject[$PropertyName]) {
                return [string]$EventObject[$PropertyName]
            }

            return ""
        }

        if ($EventObject.PSObject.Properties[$PropertyName] -and $null -ne $EventObject.$PropertyName) {
            return [string]$EventObject.$PropertyName
        }

        return ""
    }

    hidden [object] SendResponseStream([scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $payload = $this.Body.ToPayload()
        $payload.stream = $true
        $payload.stream_options = @{ include_obfuscation = $IncludeObfuscation }

        $streamOnDelta = $OnDelta
        $streamOnEvent = $OnEvent

        $eventHandler = {
            param($eventObject)

            if ($streamOnEvent) {
                & $streamOnEvent $eventObject
            }

            if ($streamOnDelta) {
                $eventType = ""
                if ($eventObject -is [System.Collections.IDictionary]) {
                    if ($eventObject.Contains("type")) {
                        $eventType = [string]$eventObject["type"]
                    }
                }
                elseif ($eventObject -and $eventObject.PSObject.Properties["type"]) {
                    $eventType = [string]$eventObject.type
                }

                $delta = ""
                switch ($eventType) {
                    "response.output_text.delta" {
                        if ($eventObject -is [System.Collections.IDictionary]) {
                            if ($eventObject.Contains("delta")) {
                                $delta = [string]$eventObject["delta"]
                            }
                        }
                        elseif ($eventObject.PSObject.Properties["delta"]) {
                            $delta = [string]$eventObject.delta
                        }
                    }
                    "response.refusal.delta" {
                        if ($eventObject -is [System.Collections.IDictionary]) {
                            if ($eventObject.Contains("delta")) {
                                $delta = [string]$eventObject["delta"]
                            }
                        }
                        elseif ($eventObject.PSObject.Properties["delta"]) {
                            $delta = [string]$eventObject.delta
                        }
                    }
                }

                if (-not [string]::IsNullOrEmpty($delta)) {
                    & $streamOnDelta $delta $eventObject
                }
            }
        }.GetNewClosure()

        $streamResult = $this.Session.PostStream($payload, "responses", $eventHandler)
        $response = $streamResult.Response

        $terminalType = [string]$streamResult.TerminalEventType
        switch ($terminalType) {
            "response.completed" {
                if ($response) {
                    return $response
                }

                throw "OpenAI streaming response completed without a response payload."
            }
            "response.incomplete" {
                if ($response) {
                    Write-Warning "OpenAI streaming response ended as incomplete."
                    return $response
                }

                throw "OpenAI streaming response ended as incomplete without a response payload."
            }
            "response.failed" {
                $message = "OpenAI streaming response failed."
                if ($response -and $response.error -and $response.error.message) {
                    $message = "OpenAI streaming response failed: $($response.error.message)"
                }

                throw $message
            }
            "error" {
                $message = "OpenAI streaming error event received."
                if ($streamResult.ErrorEvent -and $streamResult.ErrorEvent.message) {
                    $message = "OpenAI streaming error: $($streamResult.ErrorEvent.message)"
                }

                throw $message
            }
            default {
                if ($response) {
                    return $response
                }

                throw "OpenAI streaming ended unexpectedly without a terminal response event."
            }
        }

        return $response
    }

    hidden [void] FinalizeConversationState([object]$Response) {
        $this.Body.ClearInput()
        if ($this.Body.store -and $Response -and $Response.id) {
            $this.Body.previous_response_id = $Response.id
        }
        else {
            $this.Body.previous_response_id = $null
        }
    }

    hidden [hashtable] ConvertArgumentsToHashtable([object]$Arguments) {
        if ($null -eq $Arguments) {
            return @{}
        }

        if ($Arguments -is [hashtable]) {
            return $Arguments
        }

        if ($Arguments -is [string]) {
            if ([string]::IsNullOrWhiteSpace($Arguments)) {
                return @{}
            }

            $parsed = $Arguments | ConvertFrom-Json -AsHashtable
            return $parsed
        }

        $result = @{}
        foreach ($property in $Arguments.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }

        return $result
    }

    hidden [string] FormatToolOutput([object]$Output) {
        if ($null -eq $Output) {
            return ""
        }

        if ($Output -is [string]) {
            return $Output
        }

        $canSerializeToJson = $false
        if ($Output -is [hashtable] -or $Output -is [pscustomobject]) {
            $canSerializeToJson = $true
        }
        elseif ($Output -is [System.Array]) {
            if ($Output.Count -eq 0) {
                $canSerializeToJson = $true
            }
            else {
                $firstItem = $Output[0]
                if ($firstItem -is [hashtable] -or $firstItem -is [pscustomobject] -or $firstItem -is [string]) {
                    $canSerializeToJson = $true
                }
            }
        }

        if ($canSerializeToJson) {
            try {
                return ($Output | ConvertTo-Json -Depth 12 -Compress -ErrorAction Stop -WarningAction SilentlyContinue)
            }
            catch {
            }
        }

        return (($Output | Out-String).Trim())
    }

    hidden [string] InvokeRegisteredTool([object]$ToolCall) {
        $toolName = [string]$ToolCall.name

        if ([string]::IsNullOrWhiteSpace($toolName)) {
            return "Tool call is missing a tool name."
        }

        if (-not $this.AddedFunctionTools.ContainsKey($toolName)) {
            return "Tool '$toolName' was not added to this session."
        }

        if ($this.ToolHandlers.ContainsKey($toolName)) {
            try {
                $arguments = $this.ConvertArgumentsToHashtable($ToolCall.arguments)
                $output = & $this.ToolHandlers[$toolName] @arguments
                return $this.FormatToolOutput($output)
            }
            catch {
                return "Tool '$toolName' failed: $($_.Exception.Message)"
            }
        }

        if (-not $this.AllowLegacyCommandInvocation) {
            return "Tool '$toolName' is not registered."
        }

        $command = Get-Command -Name $toolName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) {
            return "Tool '$toolName' is not available in the current session."
        }

        if ($command.CommandType -notin @("Function", "Cmdlet", "Alias")) {
            return "Tool '$toolName' resolves to unsupported command type '$($command.CommandType)'."
        }

        try {
            $arguments = $this.ConvertArgumentsToHashtable($ToolCall.arguments)
            $output = & $command @arguments
            return $this.FormatToolOutput($output)
        }
        catch {
            return "Tool '$toolName' failed via legacy command invocation: $($_.Exception.Message)"
        }
    }

    hidden [object] ResolveToolCalls([object]$Response, [System.Collections.Generic.List[object]]$TurnResponses) {
        $currentResponse = $Response

        while ($true) {
            $toolCalls = @($currentResponse.output) | Where-Object { $_.type -eq "function_call" }
            if ($toolCalls.Count -eq 0) {
                return $currentResponse
            }

            $this.Body.ClearInput()

            foreach ($toolCall in $toolCalls) {
                $toolOutput = $this.InvokeRegisteredTool($toolCall)
                $null = $this.Body.input.Add(
                    [ordered]@{
                        type = "function_call_output"
                        call_id = $toolCall.call_id
                        output = $toolOutput
                    }
                )
            }

            $this.Body.previous_response_id = $currentResponse.id
            $currentResponse = $this.SendResponse()
            if ($null -ne $TurnResponses) {
                $TurnResponses.Add($currentResponse) | Out-Null
            }
        }

        return $currentResponse
    }

    hidden [object] ResolveToolCallsStream([object]$Response, [System.Collections.Generic.List[object]]$TurnResponses, [scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $currentResponse = $Response

        while ($true) {
            $toolCalls = @($currentResponse.output) | Where-Object { $_.type -eq "function_call" }
            if ($toolCalls.Count -eq 0) {
                return $currentResponse
            }

            $this.Body.ClearInput()

            foreach ($toolCall in $toolCalls) {
                $toolOutput = $this.InvokeRegisteredTool($toolCall)
                $null = $this.Body.input.Add(
                    [ordered]@{
                        type = "function_call_output"
                        call_id = $toolCall.call_id
                        output = $toolOutput
                    }
                )
            }

            $this.Body.previous_response_id = $currentResponse.id
            $currentResponse = $this.SendResponseStream($OnDelta, $OnEvent, $IncludeObfuscation)
            if ($null -ne $TurnResponses) {
                $TurnResponses.Add($currentResponse) | Out-Null
            }
        }

        return $currentResponse
    }

    hidden [string] GetOutputText([object]$Response) {
        $message = @($Response.output) | Where-Object { $_.type -eq "message" } | Select-Object -Last 1
        if (-not $message) {
            return ""
        }

        $textParts = @($message.content) | ForEach-Object {
            if ($_.type -in @("output_text", "text")) {
                if ($_.text -is [string]) {
                    $_.text
                }
                elseif ($_.text -and $_.text.value) {
                    $_.text.value
                }
            }
        }

        return ($textParts -join "")
    }

    [object] GetRawResponse() {
        $this.ApplyConversationState()

        $responseCountBefore = $this.Responses.Count
        $previousResponseIdBefore = $this.Body.previous_response_id
        $turnResponses = [System.Collections.Generic.List[object]]::new()

        try {
            $response = $this.SendResponse()
            $turnResponses.Add($response) | Out-Null

            $response = $this.ResolveToolCalls($response, $turnResponses)
            $this.CommitTurnResponses($turnResponses)
            $this.FinalizeConversationState($response)

            return $response
        }
        catch {
            $this.RollbackTurn($responseCountBefore, $previousResponseIdBefore)
            throw
        }
    }

    [object] GetRawResponse([string]$Text) {
        $this.AddUserInput($Text)
        return $this.GetRawResponse()
    }

    [string] GetResponse() {
        $response = $this.GetRawResponse()
        return $this.GetOutputText($response)
    }

    [string] GetTextResponse([string]$Text) {
        $response = $this.GetRawResponse($Text)
        return $this.GetOutputText($response)
    }

    [object] GetRawResponseStream([scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $this.ApplyConversationState()

        $responseCountBefore = $this.Responses.Count
        $previousResponseIdBefore = $this.Body.previous_response_id
        $turnResponses = [System.Collections.Generic.List[object]]::new()

        try {
            $response = $this.SendResponseStream($OnDelta, $OnEvent, $IncludeObfuscation)
            $turnResponses.Add($response) | Out-Null

            $response = $this.ResolveToolCallsStream($response, $turnResponses, $OnDelta, $OnEvent, $IncludeObfuscation)
            $this.CommitTurnResponses($turnResponses)
            $this.FinalizeConversationState($response)

            return $response
        }
        catch {
            $this.RollbackTurn($responseCountBefore, $previousResponseIdBefore)
            throw
        }
    }

    [object] GetRawResponseStream([string]$Text, [scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $this.AddUserInput($Text)
        return $this.GetRawResponseStream($OnDelta, $OnEvent, $IncludeObfuscation)
    }

    [string] GetResponseStream([scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $response = $this.GetRawResponseStream($OnDelta, $OnEvent, $IncludeObfuscation)
        return $this.GetOutputText($response)
    }

    [string] GetTextResponseStream([string]$Text, [scriptblock]$OnDelta, [scriptblock]$OnEvent, [bool]$IncludeObfuscation) {
        $textBuilder = [System.Text.StringBuilder]::new()
        $userOnDelta = $OnDelta

        $captureDelta = {
            param($delta, $eventObject)

            if (-not [string]::IsNullOrEmpty($delta)) {
                $null = $textBuilder.Append($delta)
            }

            if ($userOnDelta) {
                & $userOnDelta $delta $eventObject
            }
        }.GetNewClosure()

        $response = $this.GetRawResponseStream($Text, $captureDelta, $OnEvent, $IncludeObfuscation)
        $streamedText = $textBuilder.ToString()
        if (-not [string]::IsNullOrEmpty($streamedText)) {
            return $streamedText
        }

        return $this.GetOutputText($response)
    }
}

