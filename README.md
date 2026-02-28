# PSOpenAiToolKit

PSOpenAiToolKit is a first-class PowerShell integration and workflow framework for the OpenAI Responses API.
It helps you build AI-driven automation with native PowerShell tools, streaming responses, tool calling, reasoning controls, and flexible endpoint access.

I designed this to follow a more SDK style approach, with specialized classes for the instance and subsequent endpoints.
It is a continued work in progress, and I have merged a lot of code from a previous project. This is mostly a refactor but has quickly become a much larger project.

## Requirements

- PowerShell 7.2 or newer
- OpenAI API key

## Import

```powershell
Import-Module .\PSOpenAiToolKit.psd1 -Force
```

## Core Commands

- Session: `New-Ai`, `Get-Ai`, `Clear-AiConversation`
- Responses: `Get-AiResponse`, `Get-AiResponseStream`
- Tools: `Add-AiTool`, `Get-AiTools`, `Remove-AiTool`, `Register-AiToolHandler`
- Controls: `Set-AiInstructions`, `Set-AiReasoningEffort`, `Set-AiStoreResponses`, `Set-AiLegacyToolAutoInvoke`
- Raw API: `Invoke-OpenAiMethod`

## Quick Start

```powershell
New-Ai -ApiKey $env:OPENAI_API_KEY -Model "gpt-5.2"
Get-AiResponse -Message "Hello from PowerShell"
```

## Streaming

```powershell
# Live stream to host
Get-AiResponseStream -Message "Give me three bullet points about PowerShell 7"

# Return final full text without live token output
$text = Get-AiResponseStream -Message "Summarize this" -NoLiveText

# Live stream and return final text
$text = Get-AiResponseStream -Message "Summarize this" -PassThru
```

## Reasoning Effort

```powershell
# Set at creation time
New-Ai -ApiKey $env:OPENAI_API_KEY -Model "gpt-5.2" -ReasoningEffort low

# Change effort later
Set-AiReasoningEffort -Effort high

# Restore model default reasoning effort
Set-AiReasoningEffort -Clear
```

## Tooling Workflows

```powershell
# Add from command in memory
Add-AiTool -Command Get-PSDrive

# Add from file definition
Add-AiTool -Tool ".\Tools\WebSearch.psd1"

# Inspect loaded tools
Get-AiTools

# Remove a tool by name
Remove-AiTool -Name Get-PSDrive
```

Tip: when adding command tools, prefer `-IncludeParameters` or `-ExcludeParameters` to keep tool schemas focused.

## Optional Handler Override

```powershell
# Optional advanced path if you want a custom implementation for a tool name
Register-AiToolHandler -ToolName "get_weather" -Handler {
    param([string]$city)
    "Sunny in $city"
}
```

By default, function tools can still auto invoke matching PowerShell commands.
Use `Set-AiLegacyToolAutoInvoke -State $false` to require explicit handlers only.

## Raw Endpoint Calls

```powershell
# Reuse current New-Ai session
Invoke-OpenAiMethod -Method GET -Endpoint "models"

# One-off call with explicit key
Invoke-OpenAiMethod -Method GET -Endpoint "models" -ApiKey $env:OPENAI_API_KEY

# Example POST body
Invoke-OpenAiMethod -Method POST -Endpoint "responses" -Body @{
    model = "gpt-5.2"
    input = @(@{
        role = "user"
        content = @(@{ type = "input_text"; text = "hello" })
    })
}
```

Note: `Invoke-OpenAiMethod` accepts either `-Body` or `-BodyJson`, not both.
