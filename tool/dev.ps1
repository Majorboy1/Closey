<#
.SYNOPSIS
    Start (or stop) the whole Closey local demo in one command.

.DESCRIPTION
    Brings up the emulator suite, creates the demo account, seeds the demo data
    and serves the web build — the four things that otherwise have to be done by
    hand, in order, every time the emulator restarts.

    Every step here exists because of something that bit us:

      * `.firebaserc` defaults to the real `closey-ai-coach` project, so the
        demo project has to be named explicitly.
      * The `--only` list is quoted. In PowerShell a bare `--only a,b` is parsed
        as an array, reaches the CLI mangled, and fails with the misleading
        "No emulators to start".
      * firebase-tools is pinned to 13.x because the Firestore emulator bundled
        with 14+ requires JDK 21 and this machine has 17.
      * The emulator keeps its data in memory, so the account and the seed are
        gone after every restart and must be recreated.
      * The seed takes an explicit `--uid`. This Auth emulator answers 405 to
        `accounts:batchGet`, so it cannot discover the signed-in user itself.

.PARAMETER Stop
    Stop the emulators and the web server instead of starting them.

.PARAMETER Build
    Run `flutter build web` first. Slow (about a minute), but it is the only way
    to pick up code changes in the served build.

.PARAMETER WebPort
    Port for the static web server. Default 8092.

.PARAMETER SkipSeed
    Start everything but leave the database empty.

.EXAMPLE
    .\tool\dev.ps1
    Start emulators, seed, and serve at http://localhost:8092

.EXAMPLE
    .\tool\dev.ps1 -Build
    Rebuild the web bundle first, then start everything.

.EXAMPLE
    .\tool\dev.ps1 -Stop
    Shut everything down.
#>
[CmdletBinding()]
param(
    [switch] $Stop,
    [switch] $Build,
    [switch] $SkipSeed,
    [int] $WebPort = 8092
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$firebase = Join-Path (Split-Path -Parent $repo) '.devtools\node_modules\.bin\firebase.cmd'

$emulatorPorts = 9099, 8080, 9199, 5001, 4400, 4000

function Stop-Listener {
    param([int[]] $Ports)
    foreach ($port in $Ports) {
        Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique |
            ForEach-Object {
                try { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } catch { }
            }
    }
}

if ($Stop) {
    Write-Host 'Stopping emulators and web server...' -ForegroundColor Cyan
    Stop-Listener -Ports ($emulatorPorts + $WebPort)
    Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host 'Stopped.' -ForegroundColor Green
    return
}

if (-not (Test-Path $firebase)) {
    throw "Pinned firebase-tools not found at $firebase.`n" +
          "Install it with: npm install --prefix `"$(Split-Path -Parent $repo)\.devtools`" firebase-tools@13"
}

# Start clean. Without this a half-dead emulator from a previous run leaves
# ports taken and `emulators:start` exits with "Could not start Firestore
# Emulator, port taken", which reads like a config problem but is not.
Stop-Listener -Ports $emulatorPorts

if ($Build) {
    Write-Host 'Building web bundle (about a minute)...' -ForegroundColor Cyan
    Push-Location $repo
    try {
        & flutter build web --release --dart-define=CLOSEY_EMULATOR=true
        if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed.' }
    } finally {
        Pop-Location
    }
}

Write-Host 'Starting emulators (auth, firestore, storage, functions)...' -ForegroundColor Cyan
# Each element here is already a discrete argument, so the comma in the --only
# value is not re-parsed as PowerShell array syntax the way it is on a command
# line.
Start-Process -FilePath $firebase `
    -ArgumentList 'emulators:start', '--project', 'demo-closey', '--only', 'auth,firestore,storage,functions' `
    -WorkingDirectory $repo `
    -WindowStyle Minimized

# Wait for the Auth emulator rather than sleeping a fixed amount: the first run
# downloads the Storage rules jar and the Emulator UI, which takes a while.
Write-Host -NoNewline 'Waiting for the Auth emulator'
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    try {
        Invoke-WebRequest "http://127.0.0.1:9099/" -TimeoutSec 2 -UseBasicParsing | Out-Null
        $ready = $true
        break
    } catch {
        # A 404 from the emulator still proves it is listening; only connection
        # failures mean "not yet".
        if ($_.Exception.Response) { $ready = $true; break }
        Write-Host -NoNewline '.'
        Start-Sleep -Milliseconds 1000
    }
}
Write-Host ''

if (-not $ready) { throw 'The Auth emulator did not come up within 120s.' }
Write-Host 'Emulators ready.' -ForegroundColor Green

if (-not $SkipSeed) {
    Write-Host 'Creating the demo account...' -ForegroundColor Cyan
    $identity = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1'
    $credentials = '{"email":"demo@closey.app","password":"closeydemo","displayName":"You","returnSecureToken":true}'

    $uid = $null
    try {
        $uid = (Invoke-RestMethod "$identity/accounts:signUp?key=demo-api-key" `
                -Method Post -ContentType 'application/json' -Body $credentials -TimeoutSec 20).localId
    } catch {
        # The emulator is in-memory, but a fast re-run can still find the account
        # present. Signing in is the correct fallback, not a hard failure.
        $uid = (Invoke-RestMethod "$identity/accounts:signInWithPassword?key=demo-api-key" `
                -Method Post -ContentType 'application/json' -Body $credentials -TimeoutSec 20).localId
    }
    Write-Host "  demo@closey.app / closeydemo   (uid $uid)"

    Write-Host 'Seeding demo data...' -ForegroundColor Cyan
    Push-Location $repo
    try {
        & node tool\seed_emulator.js --fresh --uid=$uid
        if ($LASTEXITCODE -ne 0) { throw 'Seeding failed.' }
    } finally {
        Pop-Location
    }
}

$index = Join-Path $repo 'build\web\index.html'
if (-not (Test-Path $index)) {
    Write-Host 'No web build found — run again with -Build.' -ForegroundColor Yellow
} else {
    Write-Host "Serving the web build on $WebPort..." -ForegroundColor Cyan
    Start-Process -FilePath 'node' `
        -ArgumentList (Join-Path $repo 'tool\serve_web.js'), $WebPort `
        -WorkingDirectory $repo `
        -WindowStyle Minimized

    Write-Host ''
    Write-Host "  App     http://localhost:$WebPort" -ForegroundColor Green
    Write-Host '  UI      http://127.0.0.1:4000' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Sign in with Continue with email -> Sign in, using demo@closey.app / closeydemo.'
    Write-Host 'Google sign-in cannot work here: there is no OAuth server behind the emulator.'
}
