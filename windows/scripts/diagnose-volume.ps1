param(
    [string]$AppPath,
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) ("SideB-volume-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'))
)

# Run on the affected Windows PC. Observe the existing app; do not change audio,
# account settings, registry, installation or files inside the app profile.
$ErrorActionPreference = 'Stop'
$running = @(Get-Process -Name 'sideb-windows' -ErrorAction SilentlyContinue)
if (-not $AppPath) {
    $paths = @($running | ForEach-Object { $_.Path } | Select-Object -Unique)
    if ($paths.Count -ne 1) { throw 'Abri Side B primero, o indica -AppPath con la ruta de sideb-windows.exe.' }
    $AppPath = $paths[0]
}
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
if ([IO.Path]::GetFileName($AppPath) -ne 'sideb-windows.exe') { throw 'Selecciona sideb-windows.exe.' }
if ($running.Count) {
    Write-Host 'Cerra Side B normalmente. Despues presiona Enter aqui para empezar la captura.'
    $null = Read-Host
    if (Get-Process -Name 'sideb-windows' -ErrorAction SilentlyContinue) { throw 'Side B sigue abierto. Cerralo y ejecuta este archivo otra vez.' }
}

# Microsoft documents this per-process WebView2 debugging argument. Allocate a
# loopback-only port; no persistent environment/registry changes or open origins.
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $AppPath
$start.WorkingDirectory = [IO.Path]::GetDirectoryName($AppPath)
$start.UseShellExecute = $false
$start.EnvironmentVariables['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'] = "--remote-debugging-port=$port --remote-debugging-address=127.0.0.1"
$app = [Diagnostics.Process]::Start($start)
$socket = $null
$breakpoints = @()
$script:cdpId = 0
function Invoke-Cdp([string]$Method, [hashtable]$Parameters) {
    $script:cdpId++
    $id = $script:cdpId
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 20 -Compress))
    $timeout = [Threading.CancellationTokenSource]::new(10000)
    try {
        $socket.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $timeout.Token).GetAwaiter().GetResult()
        do {
            $message = [IO.MemoryStream]::new()
            try {
                do {
                    $buffer = [byte[]]::new(16384)
                    $received = $socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $timeout.Token).GetAwaiter().GetResult()
                    if ($received.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'La conexion con Side B se cerro.' }
                    $message.Write($buffer, 0, $received.Count)
                    if ($message.Length -gt 1048576) { throw 'Respuesta de diagnostico demasiado grande.' }
                } while (-not $received.EndOfMessage)
                $reply = [Text.Encoding]::UTF8.GetString($message.ToArray()) | ConvertFrom-Json
            } finally { $message.Dispose() }
        } while ($reply.id -ne $id)
        if ($reply.error) { throw ('CDP: ' + $reply.error.message) }
        if ($reply.result.exceptionDetails) { throw 'No se pudo ejecutar la captura en Side B.' }
        return $reply.result
    } finally { $timeout.Dispose() }
}

$probe = @'
(() => {
  const key = '__sidebVolumeProbe';
  if (window[key]) throw new Error('Capture already active');
  const ipc = window.__TAURI_INTERNALS__;
  if (typeof ipc?.invoke !== 'function') throw new Error('Side B IPC unavailable');
  const started = performance.now(), entries = [], removers = [], pending = new Map(), afterEvents = new Set();
  let stopped = false, lastSurface = null, calls = 0, wheels = 0, limit = false;
  const log = (kind, fields = {}) => {
    if (stopped) return;
    if (entries.length === 400) { limit = true; return; }
    entries.push({ms: Math.round(performance.now() - started), kind, ...fields});
  };
  const surface = target => {
    if (!(target instanceof Element)) return null;
    if (target.closest('[data-volume-excluded],[data-volume-dragging],[inert],[role="dialog"],[role="menu"]')) return null;
    const kind = target.closest('[data-volume-scroll]')?.getAttribute('data-volume-scroll');
    if (kind !== 'bar' && kind !== 'fullscreen') return null;
    if (kind === 'fullscreen' && target.closest('input,textarea,select,a,[contenteditable="true"],[role="slider"],button:not([data-volume-scroll-control])')) return null;
    return kind;
  };
  const number = value => typeof value === 'number' && Number.isFinite(value) ? value : null;
  const displayed = () => {
    const text = document.querySelector('.artwork-percentage')?.textContent ?? '';
    const match = text.match(/^\s*(\d{1,3})\s*%\s*$/);
    return match ? Number(match[1]) : null;
  };
  function request(message) {
    if (stopped || !message) return;
    const command = message.cmd, args = message.payload;
    const observed = ['set_playback_volume','set_playback_muted','set_exponential_volume'].includes(command);
    if (!observed) return;
    const id = ++calls;
    log('audio-request', {id, command, volume:number(args?.volume), muted:typeof args?.muted === 'boolean' ? args.muted : null});
    if (pending.size >= 200) { limit = true; return; }
    const entry = {id, callback:message.callback, error:message.error};
    pending.set(message.callback, {...entry, success:true});
    pending.set(message.error, {...entry, success:false});
  }
  function confirmed(callback, dto) {
    const entry = pending.get(callback);
    if (!entry || stopped) return;
    pending.delete(entry.callback);pending.delete(entry.error);
    if (entry.success) log('audio-confirmed', {id:entry.id, volume:number(dto?.volume)});
    else log('audio-rejected', {id:entry.id});
  }
  const on = (target, name, handler, options) => {
    target.addEventListener(name, handler, options);
    removers.push(() => target.removeEventListener(name, handler, options));
  };
  on(window, 'wheel', event => {
    const hit = surface(document.elementFromPoint(event.clientX,event.clientY));
    if (!hit && !lastSurface) return;
    const id = ++wheels;
    const mode = event.deltaMode;
    log('wheel', {id, x:number(event.deltaX), y:number(event.deltaY), mode, surface:hit,
      cancelable:event.cancelable, preventedBefore:event.defaultPrevented, trusted:event.isTrusted,
      modified:event.altKey||event.ctrlKey||event.metaKey||event.shiftKey,
      momentum:typeof event.momentum === 'boolean' ? event.momentum : null,
      focused:document.hasFocus(), hidden:document.hidden,
      overlay:!!document.querySelector('[role="dialog"],[role="menu"]'),
      dragging:!!document.querySelector('[data-volume-dragging]'), displayed:displayed()});
    lastSurface = hit;
    // A microtask from a capture listener can run before the app's bubble
    // listener. Read cancellation in the following task, after dispatch ends.
    if (entries.length < 400) {
      const timer = setTimeout(() => {afterEvents.delete(timer);log('wheel-after', {id, prevented:event.defaultPrevented});}, 0);
      afterEvents.add(timer);
    }
  }, {capture:true,passive:true});
  on(window, 'pointermove', event => {
    const hit = surface(document.elementFromPoint(event.clientX,event.clientY));
    if (hit !== lastSurface && (hit || lastSurface)) log('pointer-surface', {surface:hit});
    lastSurface = hit;
  }, {capture:true,passive:true});
  on(window, 'pointerdown', () => log('pointerdown'), {capture:true,passive:true});
  for (const name of ['blur','focus','resize']) on(window, name, () => log(name), {passive:true});
  on(document, 'visibilitychange', () => log('visibility', {hidden:document.hidden}), {passive:true});
  const stop = () => {
    const report = {schema:2, runtime:navigator.userAgent, ipcObservation:'cdp-function-calls', elapsedMs:Math.round(performance.now()-started), wheels, audioRequests:calls, truncated:limit, entries};
    stopped = true; clearTimeout(expiry);
    for (const timer of afterEvents) clearTimeout(timer);
    afterEvents.clear();
    for (const remove of removers) remove();
    pending.clear();
    delete window[key];
    return report;
  };
  // Bounded even if the terminal disconnects before collecting the report.
  const expiry = setTimeout(() => { const report = stop(); window[key] = {stop:() => {delete window[key];return report;}}; }, 120000);
  window[key] = {stop, request, confirmed};
  return 'ready';
})()
'@

try {
    $target = $null
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        try {
            $targets = @(Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/list" -TimeoutSec 1)
            $matches = @($targets | Where-Object { $_.type -eq 'page' -and ($_.url -match '^https?://tauri\.localhost(?:/|$)' -or $_.url -match '^tauri://localhost(?:/|$)') })
            if ($matches.Count -eq 1) { $target = $matches[0]; break }
            if ($matches.Count -gt 1) { throw 'Hay mas de una ventana principal; deja una sola.' }
        } catch { if ($attempt -eq 79) { throw } }
        Start-Sleep -Milliseconds 250
    }
    if (-not $target) { throw 'No aparecio la ventana principal de Side B.' }
    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $connectTimeout = [Threading.CancellationTokenSource]::new(10000)
    try { $socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $connectTimeout.Token).GetAwaiter().GetResult() }
    finally { $connectTimeout.Dispose() }
    $null = Invoke-Cdp 'Runtime.evaluate' @{expression=$probe; returnByValue=$true}
    # Tauri defines its IPC functions as non-writable/non-configurable. Observe
    # function calls through CDP conditions that always return false; never
    # replace invoke, callbacks or promises, and never pause playback.
    $null = Invoke-Cdp 'Debugger.enable' @{}
    foreach ($hook in @(
        @{function='postMessage'; condition='try { window.__sidebVolumeProbe?.request?.(arguments[0]); } catch (_) {} false'},
        @{function='runCallback'; condition='try { window.__sidebVolumeProbe?.confirmed?.(arguments[0], arguments[1]); } catch (_) {} false'}
    )) {
        $function = Invoke-Cdp 'Runtime.evaluate' @{expression=('window.__TAURI_INTERNALS__.' + $hook.function)}
        if (-not $function.result.objectId) { throw 'No se pudo observar la comunicacion de audio.' }
        $breakpoint = Invoke-Cdp 'Debugger.setBreakpointOnFunctionCall' @{objectId=$function.result.objectId; condition=$hook.condition}
        $breakpoints += $breakpoint.breakpointId
    }
    Write-Host 'Captura lista. Pone volumen 50 con la barra; despues gira 10 muescas abajo sobre la portada grande.'
    Write-Host 'Proba tambien la rueda sobre la barra abierta. Volve aqui y presiona Enter en menos de dos minutos.'
    $null = Read-Host
    $result = Invoke-Cdp 'Runtime.evaluate' @{expression='window.__sidebVolumeProbe.stop()'; returnByValue=$true}
    $report = $result.result.value
    $report | Add-Member -NotePropertyName executableSHA256 -NotePropertyValue ((Get-FileHash -LiteralPath $AppPath -Algorithm SHA256).Hash.ToLowerInvariant())
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Captura guardada: $OutputPath"
    Write-Host 'Cerra Side B normalmente y volve a abrirlo para terminar esta sesion de diagnostico.'
} finally {
    if ($socket -and $socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
        foreach ($breakpoint in $breakpoints) { try { $null = Invoke-Cdp 'Debugger.removeBreakpoint' @{breakpointId=$breakpoint} } catch { } }
        try { $null = Invoke-Cdp 'Debugger.disable' @{} } catch { }
        try { $null = Invoke-Cdp 'Runtime.evaluate' @{expression='window.__sidebVolumeProbe?.stop()'; returnByValue=$true} } catch { }
    }
    if ($socket) { $socket.Dispose() }
    $app.Dispose()
}
