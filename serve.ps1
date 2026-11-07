param([int]$Port = 8123)

# مجلد المشروع = مجلد هذا الملف
$rootFull = [System.IO.Path]::GetFullPath($PSScriptRoot)

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.webp' = 'image/webp'
  '.ico'  = 'image/x-icon'
  '.woff2'= 'font/woff2'
  '.txt'  = 'text/plain; charset=utf-8'
}

function Send-Bytes($stream, [byte[]]$bytes) {
  $stream.Write($bytes, 0, $bytes.Length)
  $stream.Flush()
}

function Send-Response($stream, [int]$code, [string]$reason, [string]$contentType, [byte[]]$body, [string]$method) {
  $head = "HTTP/1.1 $code $reason`r`n" +
          "Content-Type: $contentType`r`n" +
          "Content-Length: $($body.Length)`r`n" +
          "Cache-Control: no-store`r`n" +
          "Connection: close`r`n`r`n"
  Send-Bytes $stream ([System.Text.Encoding]::ASCII.GetBytes($head))
  if ($method -ne 'HEAD' -and $body.Length -gt 0) { Send-Bytes $stream $body }
}

function Handle-Client($client) {
  try {
    $client.ReceiveTimeout = 10000
    $client.SendTimeout = 10000
    $stream = $client.GetStream()

    $buffer = New-Object byte[] 8192
    $sb = New-Object System.Text.StringBuilder
    while ($sb.Length -lt 16384) {
      $read = $stream.Read($buffer, 0, $buffer.Length)
      if ($read -le 0) { break }
      [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read))
      if ($sb.ToString().Contains("`r`n`r`n")) { break }
    }

    $request = $sb.ToString()
    if (-not $request) { return }
    $parts = (($request -split "`r`n")[0]) -split ' '
    if ($parts.Length -lt 2) { return }
    $method = $parts[0].ToUpperInvariant()
    $target = $parts[1]

    if ($method -ne 'GET' -and $method -ne 'HEAD') {
      Send-Response $stream 405 'Method Not Allowed' 'text/plain; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('Method not allowed')) $method
      return
    }

    $path = $target
    $q = $path.IndexOf('?')
    if ($q -ge 0) { $path = $path.Substring(0, $q) }
    $path = [System.Uri]::UnescapeDataString($path)
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }

    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $path.TrimStart('/')))
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      Send-Response $stream 404 'Not Found' 'text/plain; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes('Not found')) $method
      return
    }

    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $contentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
    Send-Response $stream 200 'OK' $contentType ([System.IO.File]::ReadAllBytes($full)) $method
  } catch {
    # ignore individual connection errors
  } finally {
    try { $client.Close() } catch {}
  }
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
try { $listener.Start() } catch { Write-Output $_.Exception.Message; exit 1 }

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object -ExpandProperty IPAddress

Write-Output "Serving $rootFull"
Write-Output "Local:  http://localhost:$Port/index.html"
foreach ($ip in $ips) { Write-Output "Phone:  http://${ip}:$Port/index.html  (same Wi-Fi)" }

while ($true) {
  try {
    $client = $listener.AcceptTcpClient()
    Handle-Client $client
  } catch {
    Start-Sleep -Milliseconds 50
  }
}
