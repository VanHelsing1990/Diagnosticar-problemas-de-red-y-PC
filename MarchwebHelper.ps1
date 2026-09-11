# MarchwebHelper.ps1
# Herramienta de soporte tecnico - Menu principal con areas separadas:
#   1. Testeo de Red (Internet, velocidad, RDP, WiFi)
#   2. Mantenimiento de PC (disco, sistema, limpieza)
#
# Version publica / gratuita de marchweb.com.ar

param([switch]$Mantenimiento)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Ajusta la codificacion de la consola a la misma que usan los programas de consola
# clasicos (chkdsk, sfc, dism, ipconfig), para que no se vean caracteres raros.
try {
    $codigoPagina = [int]((cmd /c chcp) -replace '.*?(\d+)\D*$', '$1')
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding($codigoPagina)
} catch {}

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$CarpetaTesteos = Join-Path $ScriptDir "Testeos"
if (-not (Test-Path $CarpetaTesteos)) { New-Item -ItemType Directory -Path $CarpetaTesteos | Out-Null }

$ConfigFile = Join-Path $ScriptDir "config.json"
$Sede = "Mi Empresa"
if (Test-Path $ConfigFile) {
    try {
        $loaded = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($loaded.Sede) { $Sede = $loaded.Sede }
    } catch {}
}

$SedeArchivo = ($Sede -replace '[^a-zA-Z0-9]', '')

function Reset-Buffer {
    $script:BufferActual = @()
}

function Log {
    param([string]$Texto, [string]$Color = "White")
    Write-Host $Texto -ForegroundColor $Color
    $script:BufferActual += $Texto
}

function Titulo {
    param([string]$Texto, [string]$Explicacion = "")
    Log ""
    Log ("=" * 60) "Cyan"
    Log $Texto "Cyan"
    if ($Explicacion) { Log $Explicacion "DarkGray" }
    Log ("=" * 60) "Cyan"
}

function Reset-Resultados {
    $script:Resultados = @()
}

function Agregar-Resultado {
    param([string]$Prueba, [string]$Destino, [string]$Estado)
    $script:Resultados += [pscustomobject]@{ Prueba = $Prueba; Destino = $Destino; Estado = $Estado }
}

function Mostrar-Resumen {
    if (-not $script:Resultados -or $script:Resultados.Count -eq 0) { return }
    Titulo "RESUMEN"
    foreach ($r in $script:Resultados) {
        $color = if ($r.Estado -match "^(OK|EXCELENTE|BUENA|ACTIVO)") { "Green" } elseif ($r.Estado -match "^(ALERTA|REGULAR|INESTABLE|OMITIDO)") { "Yellow" } else { "Red" }
        Log ("{0,-28} {1,-22} {2}" -f $r.Prueba, $r.Destino, $r.Estado) $color
    }
}

# ============================================================
# AREA 1: TESTEO DE RED
# ============================================================

function Get-Adaptadores {
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
}

function Get-InfoIP {
    param($Adaptador)
    Get-NetIPConfiguration -InterfaceIndex $Adaptador.ifIndex -ErrorAction SilentlyContinue
}

function Mostrar-IpConfigAll {
    Titulo "IPCONFIG /ALL - Configuracion completa de red" "Muestra el detalle tecnico completo: IP, mascara, gateway y DNS de todos los adaptadores."
    Log "Cuando usar esto: cuando necesitas el detalle tecnico completo, por ejemplo para pasarselo a un proveedor o dejar anotada la configuracion exacta de una PC." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }
    Log ""
    $salida = ipconfig /all
    $salida | ForEach-Object { Log $_ }
}

function Mostrar-Adaptadores {
    Titulo "Adaptadores de red activos"
    $adaptadores = Get-Adaptadores
    if (-not $adaptadores) { Log "No hay adaptadores activos." "Red"; return }
    foreach ($a in $adaptadores) {
        $tipo = "Desconocido"
        if ($a.PhysicalMediaType -match "802.11") { $tipo = "WIFI" }
        elseif ($a.PhysicalMediaType -match "802.3") { $tipo = "CABLE (Ethernet)" }
        $info = Get-InfoIP $a
        Log ""
        Log ("Nombre     : {0}" -f $a.Name)
        Log ("Tipo       : {0}" -f $tipo)
        Log ("Descripcion: {0}" -f $a.InterfaceDescription)
        Log ("Estado     : {0}" -f $a.Status)
        if ($info) {
            Log ("IP Local   : {0}" -f ($info.IPv4Address.IPAddress -join ", "))
            Log ("Gateway    : {0}" -f ($info.IPv4DefaultGateway.NextHop -join ", "))
            Log ("DNS        : {0}" -f ($info.DNSServer.ServerAddresses -join ", "))
        }
    }
}

function Menu-VerAdaptadores {
    Log ""
    Log "Muestra, sin tanto detalle como ipconfig /all, que adaptador esta activo (wifi o cable), su IP local, gateway y DNS." "DarkGray"
    Log "Cuando usar esto: para ver rapido con que conexion esta trabajando la PC y sus datos basicos, sin todo el volumen de ipconfig /all." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }
    Mostrar-Adaptadores
}

function Test-PingHost {
    param([string]$Destino, [string]$Etiqueta, [string]$IpOrigen = $null)
    if ([string]::IsNullOrWhiteSpace($Destino)) {
        Log ("(Sin destino para {0}, se omite)" -f $Etiqueta) "DarkYellow"
        Agregar-Resultado -Prueba $Etiqueta -Destino "(sin datos)" -Estado "OMITIDO"
        return
    }
    Log ""
    Log ("--- Ping a {0} ({1}) ---" -f $Etiqueta, $Destino) "Yellow"
    if ($IpOrigen) {
        $resultado = ping $Destino -S $IpOrigen -n 4
    } else {
        $resultado = ping $Destino -n 4
    }
    $resultado | ForEach-Object { Log $_ }

    $texto = $resultado -join "`n"
    $match = [regex]::Match($texto, "(\d+)%\s*(perdidos|loss)")
    if ($match.Success) {
        $perdida = [int]$match.Groups[1].Value
        if ($perdida -eq 0) { $estado = "OK (0% perdidos)" }
        elseif ($perdida -eq 100) { $estado = "FALLA (sin respuesta)" }
        else { $estado = "ALERTA ($perdida% perdidos)" }
    } else {
        $estado = "FALLA (host no encontrado)"
    }
    Agregar-Resultado -Prueba $Etiqueta -Destino $Destino -Estado $estado
}

function Test-Puerto {
    param([string]$Destino, [int]$Puerto, [string]$Etiqueta)
    Log ""
    Log ("--- Test de puerto {0} en {1} ({2}) ---" -f $Puerto, $Destino, $Etiqueta) "Yellow"
    $r = Test-NetConnection -ComputerName $Destino -Port $Puerto -WarningAction SilentlyContinue
    if ($r) {
        Log ("Destino: {0}  Puerto: {1}  Conectado: {2}" -f $r.ComputerName, $Puerto, $r.TcpTestSucceeded)
        $estado = if ($r.TcpTestSucceeded) { "OK" } else { "FALLA" }
    } else {
        Log "No se pudo resolver/contactar el destino." "Red"
        $estado = "FALLA (sin resolver)"
    }
    Agregar-Resultado -Prueba ("Puerto {0} - {1}" -f $Puerto, $Etiqueta) -Destino $Destino -Estado $estado
}

function Get-IPPublica {
    try {
        return (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)
    } catch {
        return $null
    }
}

function Menu-ChequeoInternet {
    Titulo "CHEQUEO RAPIDO - ESTA CAIDO INTERNET?" "Prueba varios sitios conocidos (Google, Cloudflare, Microsoft), DNS e IP publica de una sola vez para dar un veredicto general."
    Log "Cuando usar esto: como primer chequeo cuando alguien dice 'no anda internet', antes de entrar en detalle con otras opciones." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Mostrar-Adaptadores

    $destinos = @(
        @{ Host = "8.8.8.8";           Nombre = "Google DNS" }
        @{ Host = "1.1.1.1";           Nombre = "Cloudflare DNS" }
        @{ Host = "www.google.com";    Nombre = "Google (web)" }
        @{ Host = "www.microsoft.com"; Nombre = "Microsoft (web)" }
    )
    $exitos = 0
    foreach ($d in $destinos) {
        Test-Puerto -Destino $d.Host -Puerto 443 -Etiqueta $d.Nombre
        if ($script:Resultados[-1].Estado -eq "OK") { $exitos++ }
    }

    Log ""
    Log "--- Resolucion de nombres (DNS) ---" "Yellow"
    $dns = Resolve-DnsName -Name "google.com" -ErrorAction SilentlyContinue
    if ($dns) {
        $ips = ($dns | Where-Object {$_.Type -eq 'A'}).IPAddress -join ", "
        Log ("google.com resuelve a: {0}" -f $ips)
        Agregar-Resultado -Prueba "DNS" -Destino "google.com" -Estado "OK"
    } else {
        Log "No se pudo resolver google.com (posible falla de DNS)" "Red"
        Agregar-Resultado -Prueba "DNS" -Destino "google.com" -Estado "FALLA"
    }

    Log ""
    Log "--- IP Publica ---" "Yellow"
    $ipPublica = Get-IPPublica
    if ($ipPublica) {
        Log ("IP Publica actual: {0}" -f $ipPublica)
        Agregar-Resultado -Prueba "IP Publica" -Destino "api.ipify.org" -Estado "OK"
    } else {
        Log "No se pudo obtener la IP publica (posible corte de internet)" "Red"
        Agregar-Resultado -Prueba "IP Publica" -Destino "api.ipify.org" -Estado "FALLA"
    }

    Log ""
    if ($exitos -eq $destinos.Count -and $dns -and $ipPublica) {
        Log "VEREDICTO: INTERNET FUNCIONANDO CORRECTAMENTE" "Green"
    } elseif ($exitos -eq 0 -and -not $dns -and -not $ipPublica) {
        Log "VEREDICTO: INTERNET CAIDO (no hay salida a internet)" "Red"
    } else {
        Log "VEREDICTO: INTERNET INESTABLE / CON PROBLEMAS PARCIALES" "Yellow"
    }
}

function Test-Latencia {
    param([string]$Destino = "8.8.8.8")
    Log ""
    Log ("--- Latencia hacia {0} ---" -f $Destino) "Yellow"
    $resultado = ping $Destino -n 8
    $resultado | ForEach-Object { Log $_ }
    $texto = $resultado -join "`n"
    $match = [regex]::Match($texto, "(\d+)ms,[^\d]+(\d+)ms,[^\d]+(\d+)ms")
    if ($match.Success) {
        $min = $match.Groups[1].Value
        $max = $match.Groups[2].Value
        $prom = [int]$match.Groups[3].Value
        Log ("Latencia -> Minima: {0}ms  Maxima: {1}ms  Promedio: {2}ms" -f $min, $max, $prom) "Cyan"
        if ($prom -lt 30) { $calif = "EXCELENTE"; $colorCalif = "Green" }
        elseif ($prom -lt 80) { $calif = "BUENA"; $colorCalif = "Green" }
        elseif ($prom -lt 150) { $calif = "REGULAR"; $colorCalif = "Yellow" }
        else { $calif = "MALA"; $colorCalif = "Red" }
        Log ("Calificacion: {0}  (menos de 30ms=Excelente, 30-80ms=Buena, 80-150ms=Regular, mas de 150ms=Mala)" -f $calif) $colorCalif
        Agregar-Resultado -Prueba "Latencia" -Destino $Destino -Estado ("{0} ({1} ms prom)" -f $calif, $prom)
    } else {
        Log "No se pudo medir la latencia (sin respuesta)." "Red"
        Agregar-Resultado -Prueba "Latencia" -Destino $Destino -Estado "FALLA (sin respuesta)"
    }
}

function Test-VelocidadDescarga {
    Log ""
    Log "--- Velocidad de descarga ---" "Yellow"
    Log "Descargando archivo de prueba (~20 MB), puede tardar unos segundos..." "DarkGray"
    $url = "https://speed.cloudflare.com/__down?bytes=20000000"
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        $sw.Stop()
        $bytes = $resp.RawContentLength
        if (-not $bytes) { $bytes = $resp.Content.Length }
        $segundos = $sw.Elapsed.TotalSeconds
        $mb = [math]::Round($bytes / 1MB, 1)
        $mbps = [math]::Round((($bytes * 8) / $segundos) / 1MB, 2)
        Log ("Descargados {0} MB en {1} segundos" -f $mb, [math]::Round($segundos, 2))
        Log ("Velocidad de descarga: {0} Mbps" -f $mbps) "Cyan"
        if ($mbps -ge 50) { $calif = "EXCELENTE"; $colorCalif = "Green" }
        elseif ($mbps -ge 20) { $calif = "BUENA"; $colorCalif = "Green" }
        elseif ($mbps -ge 5) { $calif = "REGULAR"; $colorCalif = "Yellow" }
        else { $calif = "MALA"; $colorCalif = "Red" }
        Log ("Calificacion: {0}  (mas de 50 Mbps=Excelente, 20-50=Buena, 5-20=Regular, menos de 5=Mala)" -f $calif) $colorCalif
        Agregar-Resultado -Prueba "Velocidad descarga" -Destino "speed.cloudflare.com" -Estado ("{0} ({1} Mbps)" -f $calif, $mbps)
    } catch {
        Log "No se pudo completar el test de velocidad." "Red"
        Agregar-Resultado -Prueba "Velocidad descarga" -Destino "speed.cloudflare.com" -Estado "FALLA"
    }
}

function Menu-TestVelocidad {
    Titulo "TEST DE VELOCIDAD - INTERNET LENTO?" "Mide la latencia (ping) y la velocidad de descarga bajando un archivo de prueba de 20 MB."
    Log "Cuando usar esto: cuando dicen que 'internet anda lento' y queres un numero concreto (Mbps) para confirmar o descartar el problema." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Test-Latencia -Destino "8.8.8.8"
    Test-VelocidadDescarga
}

function Menu-TestAccesoRemoto {
    Titulo "TEST DE ACCESO REMOTO (RDP)" "Prueba si se puede llegar a un equipo remoto por red y si tiene abierto el puerto de Escritorio Remoto (3389)."
    Log "Cuando usar esto: cuando no se puede conectar por Escritorio Remoto a otra PC y necesitas saber si el problema es de red o del servicio RDP." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $ip = Read-Host "Ingresa la IP o nombre del equipo remoto (ej: 195.0.0.22)"
    if ([string]::IsNullOrWhiteSpace($ip)) { Log "No se ingreso ninguna IP." "Red"; return }
    Test-PingHost -Destino $ip -Etiqueta "Acceso Remoto"
    Test-Puerto -Destino $ip -Puerto 3389 -Etiqueta "RDP"
}

function Test-PingContinuo {
    param([string]$Destino)
    Log ""
    Log ("--- Ping continuo a {0} (estilo ping -t) ---" -f $Destino) "Yellow"
    Log "Se va a quedar pingueando hasta que lo frenes. Presiona la tecla Q (o Ctrl+C) para detenerlo y ver el resumen con los cortes detectados." "DarkGray"
    $enviados = 0
    $recibidos = 0
    $inicio = Get-Date
    $estadoAnterior = $null
    $inicioCorteActual = $null
    $cortes = @()

    $ctrlCOriginal = $false
    try {
        $ctrlCOriginal = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
    } catch {}
    try {
        while ($true) {
            if ([Console]::KeyAvailable) {
                $tecla = [Console]::ReadKey($true)
                $esCtrlC = ($tecla.Key -eq 'C' -and ($tecla.Modifiers -band [ConsoleModifiers]::Control))
                if ($tecla.Key -eq 'Q' -or $esCtrlC) { break }
            }
            $ahora = Get-Date
            $r = ping $Destino -n 1
            $enviados++
            $ok = [bool](($r -join "`n") -match "Respuesta desde|Reply from")
            if ($ok) { $recibidos++ }
            $marca = if ($ok) { "OK" } else { "PERDIDO" }
            $color = if ($ok) { "Green" } else { "Red" }
            Write-Host ("[{0}] Intento {1}: {2}" -f $ahora.ToString("HH:mm:ss"), $enviados, $marca) -ForegroundColor $color

            if ($null -eq $estadoAnterior) {
                if (-not $ok) { $inicioCorteActual = $ahora }
            } elseif ($ok -and -not $estadoAnterior) {
                $duracion = [math]::Round(($ahora - $inicioCorteActual).TotalSeconds, 1)
                $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $ahora; DuracionSeg = $duracion }
            } elseif (-not $ok -and $estadoAnterior) {
                $inicioCorteActual = $ahora
            }
            $estadoAnterior = $ok
        }
    } finally {
        try { [Console]::TreatControlCAsInput = $ctrlCOriginal } catch {}
    }

    $fin = Get-Date
    if ($estadoAnterior -eq $false -and $inicioCorteActual) {
        $duracion = [math]::Round(($fin - $inicioCorteActual).TotalSeconds, 1)
        $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $fin; DuracionSeg = $duracion }
    }

    $perdidos = $enviados - $recibidos
    $porcentaje = if ($enviados -gt 0) { [math]::Round(($perdidos / $enviados) * 100, 1) } else { 0 }

    Log ""
    Log "--- Resumen del ping continuo ---" "Yellow"
    Log ("Destino: {0}" -f $Destino)
    Log ("Enviados: {0}  Recibidos: {1}  Perdidos: {2} ({3}%)" -f $enviados, $recibidos, $perdidos, $porcentaje)

    Mostrar-CronologiaCortes -Cortes $cortes -Inicio $inicio -Fin $fin

    $estado = if ($porcentaje -eq 0) { "OK (0% perdidos)" } elseif ($porcentaje -eq 100) { "FALLA (sin respuesta)" } else { "ALERTA ($porcentaje% perdidos)" }
    Agregar-Resultado -Prueba "Ping continuo" -Destino $Destino -Estado $estado
}

function Formatear-Duracion {
    param([double]$Segundos)
    if ($Segundos -lt 60) { return ("{0} seg" -f [math]::Round($Segundos, 1)) }
    $ts = [TimeSpan]::FromSeconds($Segundos)
    if ($ts.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)
    }
    return ("{0}m {1}s" -f [int]$ts.TotalMinutes, $ts.Seconds)
}

function Mostrar-CronologiaCortes {
    param($Cortes, [datetime]$Inicio, [datetime]$Fin)

    Log ""
    Log "--- Cronologia ---" "Cyan"
    Log ("Monitoreo iniciado   : {0}" -f $Inicio.ToString("dd/MM/yyyy HH:mm:ss"))
    Log ("Monitoreo finalizado : {0}" -f $Fin.ToString("dd/MM/yyyy HH:mm:ss"))
    Log ("Duracion total       : {0}" -f (Formatear-Duracion ($Fin - $Inicio).TotalSeconds))

    if (-not $Cortes -or $Cortes.Count -eq 0) {
        Log ""
        Log "No se detecto ningun corte durante todo el monitoreo." "Green"
        return
    }

    $anterior = $Inicio
    for ($i = 0; $i -lt $Cortes.Count; $i++) {
        $c = $Cortes[$i]
        $tiempoArribaAntes = ($c.Inicio - $anterior).TotalSeconds
        $tipoTxt = if ($c.PSObject.Properties.Name -contains "Tipo") { " - {0}" -f $c.Tipo } else { "" }
        Log ""
        Log ("Corte #{0}{1}" -f ($i + 1), $tipoTxt) "Red"
        Log ("  Antes de este corte funciono bien durante : {0}" -f (Formatear-Duracion $tiempoArribaAntes))
        Log ("  Se corto  : {0}" -f $c.Inicio.ToString("HH:mm:ss"))
        Log ("  Volvio    : {0}" -f $c.Fin.ToString("HH:mm:ss"))
        Log ("  Duro      : {0}" -f (Formatear-Duracion $c.DuracionSeg))
        $anterior = $c.Fin
    }

    $tiempoArribaFinal = ($Fin - $anterior).TotalSeconds
    Log ""
    Log ("Desde el ultimo corte hasta que se detuvo el monitoreo funciono bien: {0}" -f (Formatear-Duracion $tiempoArribaFinal))

    $duraciones = $Cortes | ForEach-Object { $_.DuracionSeg }
    $masLargo = $Cortes | Sort-Object DuracionSeg -Descending | Select-Object -First 1
    $masCorto = $Cortes | Sort-Object DuracionSeg | Select-Object -First 1
    $promedioDuracion = ($duraciones | Measure-Object -Average).Average
    $tiempoTotalCaido = ($duraciones | Measure-Object -Sum).Sum
    $duracionTotalSeg = ($Fin - $Inicio).TotalSeconds
    $porcentajeArriba = if ($duracionTotalSeg -gt 0) { [math]::Round((($duracionTotalSeg - $tiempoTotalCaido) / $duracionTotalSeg) * 100, 2) } else { 100 }

    $gaps = @()
    for ($i = 0; $i -lt $Cortes.Count - 1; $i++) {
        $gaps += ($Cortes[$i + 1].Inicio - $Cortes[$i].Fin).TotalSeconds
    }
    $promedioEntreCortes = if ($gaps.Count -gt 0) { ($gaps | Measure-Object -Average).Average } else { $null }

    Log ""
    Log "--- Estadisticas ---" "Cyan"
    Log ("Cantidad de cortes             : {0}" -f $Cortes.Count)
    Log ("Tiempo total caido             : {0}" -f (Formatear-Duracion $tiempoTotalCaido))
    Log ("Tiempo total funcionando bien  : {0}  ({1}% del total)" -f (Formatear-Duracion ($duracionTotalSeg - $tiempoTotalCaido)), $porcentajeArriba)
    Log ("Corte mas largo                : {0}  (a las {1})" -f (Formatear-Duracion $masLargo.DuracionSeg), $masLargo.Inicio.ToString("HH:mm:ss")) "Red"
    Log ("Corte mas corto                : {0}  (a las {1})" -f (Formatear-Duracion $masCorto.DuracionSeg), $masCorto.Inicio.ToString("HH:mm:ss"))
    Log ("Duracion promedio de un corte  : {0}" -f (Formatear-Duracion $promedioDuracion))
    if ($null -ne $promedioEntreCortes) {
        Log ("Tiempo promedio ENTRE cortes   : {0}  (funcionando bien entre un corte y el siguiente)" -f (Formatear-Duracion $promedioEntreCortes))
    }
}

function Test-MonitoreoIntermitencias {
    param([string]$Destino)
    Log ""
    Log ("--- Monitoreo continuo a {0} (estilo ping -t) ---" -f $Destino) "Yellow"
    Log "Pinguea 1 vez por segundo sin parar. Muestra un aviso cada 10 segundos para confirmar que sigue activo, y avisa apenas se corta o vuelve, con la hora y cuanto duro el corte." "DarkGray"
    Log "Dejalo corriendo el tiempo que haga falta (minutos u horas) y presiona Q (o Ctrl+C) para detenerlo y ver el resumen." "DarkGray"
    Log ""

    $enviados = 0
    $recibidos = 0
    $inicio = Get-Date
    $estadoAnterior = $null
    $inicioCorteActual = $null
    $cortes = @()
    $ultimoAviso = Get-Date

    $ctrlCOriginal = $false
    try {
        $ctrlCOriginal = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
    } catch {}
    try {
        while ($true) {
            if ([Console]::KeyAvailable) {
                $tecla = [Console]::ReadKey($true)
                $esCtrlC = ($tecla.Key -eq 'C' -and ($tecla.Modifiers -band [ConsoleModifiers]::Control))
                if ($tecla.Key -eq 'Q' -or $esCtrlC) { break }
            }
            $ahora = Get-Date
            $r = ping $Destino -n 1 -w 1000
            $enviados++
            $ok = [bool](($r -join "`n") -match "Respuesta desde|Reply from")
            if ($ok) { $recibidos++ }

            if ($null -eq $estadoAnterior) {
                if ($ok) {
                    Write-Host ("[{0}] Arranca ACTIVO - con conexion" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor Green
                } else {
                    Write-Host ("[{0}] Arranca CAIDO - sin conexion" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor Red
                    $inicioCorteActual = $ahora
                }
                $ultimoAviso = $ahora
            } elseif ($ok -and -not $estadoAnterior) {
                $duracion = [math]::Round(($ahora - $inicioCorteActual).TotalSeconds, 1)
                $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $ahora; DuracionSeg = $duracion }
                Write-Host ("[{0}] VOLVIO LA CONEXION -> estuvo caido {1} segundos (desde las {2})" -f $ahora.ToString("HH:mm:ss"), $duracion, $inicioCorteActual.ToString("HH:mm:ss")) -ForegroundColor Green
                $ultimoAviso = $ahora
            } elseif (-not $ok -and $estadoAnterior) {
                $inicioCorteActual = $ahora
                Write-Host ("[{0}] SE CORTO - sin conexion" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor Red
                $ultimoAviso = $ahora
            } elseif (($ahora - $ultimoAviso).TotalSeconds -ge 10) {
                if ($ok) {
                    Write-Host ("[{0}] Sigue activo, con conexion (sin cortes por ahora)" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor DarkGray
                } else {
                    Write-Host ("[{0}] Sigue caido, sin conexion" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor DarkGray
                }
                $ultimoAviso = $ahora
            }

            $estadoAnterior = $ok
            Start-Sleep -Milliseconds 1000
        }
    } finally {
        try { [Console]::TreatControlCAsInput = $ctrlCOriginal } catch {}
    }

    $fin = Get-Date
    if ($estadoAnterior -eq $false -and $inicioCorteActual) {
        $duracion = [math]::Round(($fin - $inicioCorteActual).TotalSeconds, 1)
        $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $fin; DuracionSeg = $duracion }
        Write-Host ("[{0}] Se detuvo el monitoreo mientras seguia caido." -f $fin.ToString("HH:mm:ss")) -ForegroundColor Red
    }

    $perdidos = $enviados - $recibidos
    $porcentaje = if ($enviados -gt 0) { [math]::Round(($perdidos / $enviados) * 100, 1) } else { 0 }

    Log ""
    Log "--- Resumen del monitoreo ---" "Yellow"
    Log ("Destino: {0}" -f $Destino)
    Log ("Pings enviados: {0}   Perdidos: {1} ({2}%)" -f $enviados, $perdidos, $porcentaje)

    Mostrar-CronologiaCortes -Cortes $cortes -Inicio $inicio -Fin $fin

    $estado = if ($cortes.Count -eq 0) { "OK (sin cortes)" } else { "ALERTA (INTERMITENTE, {0} cortes)" -f $cortes.Count }
    Agregar-Resultado -Prueba "Monitoreo intermitencias" -Destino $Destino -Estado $estado
}

function Detectar-Gateway {
    $adaptadores = Get-Adaptadores
    if (-not $adaptadores) { return $null }

    $candidatos = @()
    foreach ($a in $adaptadores) {
        $info = Get-InfoIP $a
        $gw = if ($info) { ($info.IPv4DefaultGateway.NextHop | Select-Object -First 1) } else { $null }
        if ([string]::IsNullOrWhiteSpace($gw)) { continue }
        $tipo = "Desconocido"
        if ($a.PhysicalMediaType -match "802.11") { $tipo = "WIFI" }
        elseif ($a.PhysicalMediaType -match "802.3") { $tipo = "CABLE" }
        $candidatos += [pscustomobject]@{ Nombre = $a.Name; Tipo = $tipo; Gateway = $gw }
    }

    if ($candidatos.Count -eq 0) { return $null }
    if ($candidatos.Count -eq 1) { return $candidatos[0] }

    Write-Host ""
    Write-Host "Hay mas de una conexion activa. Cual queres monitorear?"
    for ($i = 0; $i -lt $candidatos.Count; $i++) {
        Write-Host ("  {0}. {1} ({2}) - Gateway: {3}" -f ($i + 1), $candidatos[$i].Nombre, $candidatos[$i].Tipo, $candidatos[$i].Gateway)
    }
    $sel = Read-Host "Opcion"
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $candidatos.Count) {
        return $candidatos[$idx - 1]
    }
    return $candidatos[0]
}

function Test-MonitoreoDual {
    param([string]$Gateway, [string]$Internet)
    Log ""
    Log ("--- Monitoreo continuo: Router ({0}) e Internet ({1}) ---" -f $Gateway, $Internet) "Yellow"
    Log "Pinguea a los dos al mismo tiempo, 1 vez por segundo. Si se corta el router, el problema es la red local (wifi o cable). Si el router responde pero Internet no, el problema es del proveedor." "DarkGray"
    Log "Muestra un aviso cada 10 segundos para confirmar que sigue activo. Dejalo corriendo el tiempo que haga falta y presiona Q (o Ctrl+C) para detenerlo y ver el resumen." "DarkGray"
    Log ""

    $enviados = 0
    $inicio = Get-Date
    $tipoAnterior = $null
    $huboMedicion = $false
    $inicioCorteActual = $null
    $tipoCorteActual = $null
    $cortes = @()
    $ultimoAviso = Get-Date

    $ctrlCOriginal = $false
    try {
        $ctrlCOriginal = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
    } catch {}
    try {
        while ($true) {
            if ([Console]::KeyAvailable) {
                $tecla = [Console]::ReadKey($true)
                $esCtrlC = ($tecla.Key -eq 'C' -and ($tecla.Modifiers -band [ConsoleModifiers]::Control))
                if ($tecla.Key -eq 'Q' -or $esCtrlC) { break }
            }
            $ahora = Get-Date
            $rGw = ping $Gateway -n 1 -w 1000
            $okGw = [bool](($rGw -join "`n") -match "Respuesta desde|Reply from")
            $rNet = ping $Internet -n 1 -w 1000
            $okNet = [bool](($rNet -join "`n") -match "Respuesta desde|Reply from")
            $enviados++

            $tipoActual = if (-not $okGw) { "LOCAL (Wifi/Cable/Router)" } elseif (-not $okNet) { "INTERNET (Proveedor)" } else { $null }

            if (-not $huboMedicion) {
                if ($tipoActual) {
                    Write-Host ("[{0}] Arranca CAIDO - {1}" -f $ahora.ToString("HH:mm:ss"), $tipoActual) -ForegroundColor Red
                    $inicioCorteActual = $ahora
                    $tipoCorteActual = $tipoActual
                } else {
                    Write-Host ("[{0}] Arranca ARRIBA (router e internet OK)" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor Green
                }
                $huboMedicion = $true
                $ultimoAviso = $ahora
            }
            elseif ($tipoActual -and -not $tipoAnterior) {
                $inicioCorteActual = $ahora
                $tipoCorteActual = $tipoActual
                Write-Host ("[{0}] SE CORTO - {1}" -f $ahora.ToString("HH:mm:ss"), $tipoActual) -ForegroundColor Red
                $ultimoAviso = $ahora
            }
            elseif (-not $tipoActual -and $tipoAnterior) {
                $duracion = [math]::Round(($ahora - $inicioCorteActual).TotalSeconds, 1)
                $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $ahora; DuracionSeg = $duracion; Tipo = $tipoCorteActual }
                Write-Host ("[{0}] SE RECUPERO -> estuvo caido {1} segundos ({2}, desde las {3})" -f $ahora.ToString("HH:mm:ss"), $duracion, $tipoCorteActual, $inicioCorteActual.ToString("HH:mm:ss")) -ForegroundColor Green
                $ultimoAviso = $ahora
            }
            elseif ($tipoActual -and $tipoAnterior -and $tipoActual -ne $tipoAnterior) {
                $duracion = [math]::Round(($ahora - $inicioCorteActual).TotalSeconds, 1)
                $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $ahora; DuracionSeg = $duracion; Tipo = $tipoCorteActual }
                Write-Host ("[{0}] Cambia el tipo de corte: ahora es {1}" -f $ahora.ToString("HH:mm:ss"), $tipoActual) -ForegroundColor Red
                $inicioCorteActual = $ahora
                $tipoCorteActual = $tipoActual
                $ultimoAviso = $ahora
            }
            elseif (($ahora - $ultimoAviso).TotalSeconds -ge 10) {
                if ($tipoActual) {
                    Write-Host ("[{0}] Sigue caido - {1}" -f $ahora.ToString("HH:mm:ss"), $tipoActual) -ForegroundColor DarkGray
                } else {
                    Write-Host ("[{0}] Sigue activo, router e internet OK" -f $ahora.ToString("HH:mm:ss")) -ForegroundColor DarkGray
                }
                $ultimoAviso = $ahora
            }

            $tipoAnterior = $tipoActual
            Start-Sleep -Milliseconds 1000
        }
    } finally {
        try { [Console]::TreatControlCAsInput = $ctrlCOriginal } catch {}
    }

    $fin = Get-Date
    if ($tipoAnterior -and $inicioCorteActual) {
        $duracion = [math]::Round(($fin - $inicioCorteActual).TotalSeconds, 1)
        $cortes += [pscustomobject]@{ Inicio = $inicioCorteActual; Fin = $fin; DuracionSeg = $duracion; Tipo = $tipoCorteActual }
        Write-Host ("[{0}] Se detuvo el monitoreo mientras seguia caido ({1})." -f $fin.ToString("HH:mm:ss"), $tipoCorteActual) -ForegroundColor Red
    }

    $cortesLocal = $cortes | Where-Object { $_.Tipo -like "LOCAL*" }
    $cortesInternet = $cortes | Where-Object { $_.Tipo -like "INTERNET*" }

    Log ""
    Log "--- Resumen del monitoreo ---" "Yellow"
    Log ("Router/Gateway: {0}   Internet: {1}" -f $Gateway, $Internet)
    Log ("Mediciones realizadas: {0}" -f $enviados)
    Log ("Cortes de la red local (Wifi/Cable/Router): {0}" -f $cortesLocal.Count)
    Log ("Cortes de Internet (con el router funcionando): {0}" -f $cortesInternet.Count)

    Mostrar-CronologiaCortes -Cortes $cortes -Inicio $inicio -Fin $fin

    Log ""
    if ($cortesLocal.Count -eq 0 -and $cortesInternet.Count -eq 0) {
        Log "VEREDICTO: No hubo cortes. Router e Internet funcionaron bien todo el tiempo." "Green"
    } elseif ($cortesLocal.Count -gt 0 -and $cortesInternet.Count -eq 0) {
        Log "VEREDICTO: Los cortes son de la red local (wifi o cable). Revisar el router, el cable o el wifi, no es el proveedor." "Yellow"
    } elseif ($cortesLocal.Count -eq 0 -and $cortesInternet.Count -gt 0) {
        Log "VEREDICTO: La red local (wifi/cable) funciono bien, pero se corta la salida a Internet. Es el PROVEEDOR." "Red"
    } else {
        Log "VEREDICTO: Hubo cortes de los dos tipos, revisar el detalle arriba." "Yellow"
    }

    $estadoTexto = if ($cortes.Count -eq 0) { "OK (sin cortes)" } else { "ALERTA (INTERMITENTE: {0} local, {1} internet)" -f $cortesLocal.Count, $cortesInternet.Count }
    Agregar-Resultado -Prueba "Monitoreo dual (router+internet)" -Destino ("{0} / {1}" -f $Gateway, $Internet) -Estado $estadoTexto
}

function Menu-MonitoreoIntermitencias {
    Titulo "MONITOREO CONTINUO - DETECTAR CORTES INTERMITENTES" "Sirve para cuando dicen que la red (wifi o cable) o Internet 'va y viene': lo dejas corriendo y anota cada corte con hora y duracion."
    Log "Cuando usar esto: cuando dicen 'la red (wifi o cable) o internet va y viene' pero ahora mismo anda bien, y necesitas dejarlo corriendo un rato para agarrar el momento exacto del corte." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Write-Host "A que queres monitorear?"
    Write-Host "  1. Router + Internet al mismo tiempo (RECOMENDADO: dice si es la red local -wifi o cable- o el proveedor)"
    Write-Host "  2. Solo Internet (8.8.8.8)"
    Write-Host "  3. Solo Router / Gateway"
    Write-Host "  4. IP o host personalizado"
    $op = Read-Host "Opcion"
    switch ($op) {
        "1" {
            $gw = Detectar-Gateway
            if (-not $gw -or [string]::IsNullOrWhiteSpace($gw.Gateway)) {
                Log "No se pudo detectar el gateway automaticamente." "Red"
                return
            }
            Log ("Gateway detectado: {0} ({1}, {2})" -f $gw.Gateway, $gw.Nombre, $gw.Tipo) "Cyan"
            Test-MonitoreoDual -Gateway $gw.Gateway -Internet "8.8.8.8"
        }
        "2" { Test-MonitoreoIntermitencias -Destino "8.8.8.8" }
        "3" {
            $gw = Detectar-Gateway
            if (-not $gw -or [string]::IsNullOrWhiteSpace($gw.Gateway)) {
                Log "No se pudo detectar el gateway automaticamente." "Red"
                return
            }
            Log ("Gateway detectado: {0} ({1}, {2})" -f $gw.Gateway, $gw.Nombre, $gw.Tipo) "Cyan"
            Test-MonitoreoIntermitencias -Destino $gw.Gateway
        }
        "4" {
            $destino = Read-Host "IP o host a monitorear"
            if ([string]::IsNullOrWhiteSpace($destino)) { return }
            Test-MonitoreoIntermitencias -Destino $destino
        }
        default { Log "Opcion invalida" "Red" }
    }
}

function Menu-TestPersonalizado {
    Titulo "TEST PERSONALIZADO" "Permite pinguear, hacer ping continuo, tracert o probar un puerto especifico contra cualquier IP u host que necesites."
    Log "Cuando usar esto: cuando ninguna de las otras opciones cubre justo lo que necesitas probar (una IP puntual, un puerto especifico, etc)." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $destino = Read-Host "Ingresa la IP o el nombre de host a testear"
    if ([string]::IsNullOrWhiteSpace($destino)) { return }
    Write-Host "Que queres hacer?"
    Write-Host "  1. Ping"
    Write-Host "  2. Ping continuo (dejalo corriendo y lo frenas cuando quieras)"
    Write-Host "  3. Tracert (ruta)"
    Write-Host "  4. Test de puerto especifico"
    $op = Read-Host "Opcion"
    switch ($op) {
        "1" { Test-PingHost -Destino $destino -Etiqueta "Personalizado" }
        "2" { Test-PingContinuo -Destino $destino }
        "3" {
            Log ""
            Log ("--- Tracert a {0} ---" -f $destino) "Yellow"
            tracert $destino | ForEach-Object { Log $_ }
        }
        "4" {
            $puerto = Read-Host "Numero de puerto"
            Test-Puerto -Destino $destino -Puerto ([int]$puerto) -Etiqueta "Personalizado"
        }
        default { Log "Opcion invalida" "Red" }
    }
}

function Menu-InfoProveedor {
    Titulo "PROVEEDOR DE INTERNET (ISP)" "Averigua que empresa esta dando el servicio de internet mirando la IP publica, igual que se ve en Speedtest."
    Log "Cuando usar esto: para saber que empresa esta dando el servicio de internet en este momento, por ejemplo si no estas seguro o para confirmar despues de un cambio de proveedor." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $info = $null
    try {
        $info = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=status,message,query,isp,org,as,city,regionName,country" -TimeoutSec 8
    } catch {}

    if (-not $info -or $info.status -ne "success") {
        Log "No se pudo consultar el proveedor (revisa la conexion a internet)." "Red"
        Agregar-Resultado -Prueba "Proveedor de Internet" -Destino "ip-api.com" -Estado "FALLA"
        return
    }

    Log ("IP Publica      : {0}" -f $info.query)
    Log ("Proveedor (ISP) : {0}" -f $info.isp) "Cyan"
    if ($info.org -and $info.org -ne $info.isp) { Log ("Organizacion    : {0}" -f $info.org) }
    if ($info.as) { Log ("AS (red)        : {0}" -f $info.as) }
    Log ("Ubicacion       : {0}, {1}, {2}" -f $info.city, $info.regionName, $info.country)
    Agregar-Resultado -Prueba "Proveedor de Internet" -Destino $info.query -Estado ("OK ({0})" -f $info.isp)
}

function Obtener-RutaFabricantesMac {
    Join-Path $ScriptDir "FabricantesMac.csv"
}

function Cargar-FabricantesMac {
    $ruta = Obtener-RutaFabricantesMac
    if (-not (Test-Path $ruta)) { return $null }
    $tabla = @{}
    Get-Content $ruta -ErrorAction SilentlyContinue | ForEach-Object {
        $partes = $_ -split ',', 2
        if ($partes.Count -eq 2 -and $partes[0].Length -eq 6) { $tabla[$partes[0]] = $partes[1] }
    }
    if ($tabla.Count -eq 0) { return $null }
    return $tabla
}

function Buscar-Fabricante {
    param($Tabla, [string]$Mac)
    if (-not $Tabla -or [string]::IsNullOrWhiteSpace($Mac)) { return $null }
    $prefijo = ($Mac -replace '[:\-]', '').ToUpper()
    if ($prefijo.Length -lt 6) { return $null }
    return $Tabla[$prefijo.Substring(0, 6)]
}

function Actualizar-BaseFabricantesMac {
    Titulo "ACTUALIZAR BASE DE FABRICANTES (MAC)" "Descarga la lista oficial de fabricantes de tarjetas de red (IEEE) para poder identificar la marca de cada equipo (HP, Epson, Zebra, Cisco, TP-Link, etc) a partir de su MAC."
    Log "Cuando usar esto: la primera vez que quieras ver la marca de cada dispositivo en 'Ver dispositivos conectados a la red', o cada tanto para actualizarla. Necesita internet solo esta vez: despues queda guardada y funciona sin conexion." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Log ""
    Log "Descargando la lista de fabricantes (IEEE), puede tardar unos segundos..." "Yellow"
    try {
        $resp = Invoke-WebRequest -Uri "https://standards-oui.ieee.org/oui/oui.txt" -UseBasicParsing -TimeoutSec 30
        $lineas = $resp.Content -split "`n"
        $filas = @()
        foreach ($linea in $lineas) {
            $m = [regex]::Match($linea, '^\s*([0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2})\s+\(hex\)\s+(.+?)\s*$')
            if ($m.Success) {
                $prefijo = ($m.Groups[1].Value -replace '-', '').ToUpper()
                $fabricante = ($m.Groups[2].Value -replace ',', ' ').Trim()
                $filas += "$prefijo,$fabricante"
            }
        }
        if ($filas.Count -eq 0) {
            Log "Se descargo el archivo pero no se pudo interpretar el formato." "Red"
            Agregar-Resultado -Prueba "Base de fabricantes MAC" -Destino "IEEE" -Estado "FALLA (formato)"
            return
        }
        $filas | Set-Content -Path (Obtener-RutaFabricantesMac) -Encoding UTF8
        Log ("Listo: se guardaron {0} fabricantes. Ya se puede usar sin internet." -f $filas.Count) "Green"
        Agregar-Resultado -Prueba "Base de fabricantes MAC" -Destino "IEEE" -Estado ("OK ({0} entradas)" -f $filas.Count)
    } catch {
        Log "No se pudo descargar la lista. Puede ser un problema de internet o que la pagina este bloqueada por un firewall/proxy corporativo." "Red"
        Agregar-Resultado -Prueba "Base de fabricantes MAC" -Destino "IEEE" -Estado "FALLA"
    }
}

function Escanear-Red {
    Titulo "DISPOSITIVOS EN LA RED" "Pinguea toda la red local y arma la lista de equipos conectados (PCs, impresoras, routers, etc) usando la tabla ARP. Tarda entre 20 y 40 segundos."
    Log "Cuando usar esto: para saber cuantos y cuales equipos estan conectados a la red local, ver si hay algo desconocido, o encontrar la IP de una impresora." "DarkGray"
    Log "Tip: ademas de IP, MAC y nombre, esta opcion muestra el fabricante de cada equipo (HP, Epson, Zebra, Cisco, etc). Si es la primera vez que la usas, corre antes la opcion 'Actualizar base de fabricantes (MAC)' para que se pueda mostrar (una sola vez, necesita internet)." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $adaptador = Get-Adaptadores | Select-Object -First 1
    if (-not $adaptador) { Log "No hay adaptadores de red activos." "Red"; return }
    $infoIp = Get-InfoIP $adaptador
    $ipLocal = if ($infoIp) { ($infoIp.IPv4Address.IPAddress | Select-Object -First 1) } else { $null }
    if ([string]::IsNullOrWhiteSpace($ipLocal)) { Log "No se pudo obtener la IP local." "Red"; return }

    $partes = $ipLocal.Split('.')
    $base = "{0}.{1}.{2}." -f $partes[0], $partes[1], $partes[2]

    Log ("Red local: {0}0/24   (tu IP: {1})" -f $base, $ipLocal)
    Log "Escaneando 254 direcciones, esperando respuestas..." "Yellow"
    Log ""

    $tareas = @()
    for ($i = 1; $i -le 254; $i++) {
        $pingObj = New-Object System.Net.NetworkInformation.Ping
        $tareas += $pingObj.SendPingAsync("$base$i", 800)
    }
    try { [System.Threading.Tasks.Task]::WaitAll($tareas, 25000) | Out-Null } catch {}
    Start-Sleep -Milliseconds 500

    $vecinos = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress.StartsWith($base) -and $_.LinkLayerAddress -and $_.LinkLayerAddress -ne "00-00-00-00-00-00" -and $_.State -ne "Unreachable"
    }

    if (-not $vecinos) {
        Log "No se detecto ningun dispositivo. Revisa que estes conectado a la red." "Red"
        Agregar-Resultado -Prueba "Escaneo de red" -Destino ($base + "0/24") -Estado "FALLA (sin resultados)"
        return
    }

    $tablaFabricantes = Cargar-FabricantesMac

    $dispositivos = @()
    foreach ($v in $vecinos) {
        $nombre = "-"
        try {
            $dns = Resolve-DnsName -Name $v.IPAddress -ErrorAction SilentlyContinue
            if ($dns) { $nombre = ($dns | Select-Object -First 1).NameHost }
        } catch {}
        if ($v.IPAddress -eq $ipLocal) { $nombre = "$nombre (ESTA PC)" }
        $fabricante = Buscar-Fabricante -Tabla $tablaFabricantes -Mac $v.LinkLayerAddress
        if ([string]::IsNullOrWhiteSpace($fabricante)) { $fabricante = "-" }
        $dispositivos += [pscustomobject]@{ IP = $v.IPAddress; MAC = $v.LinkLayerAddress; Fabricante = $fabricante; Nombre = $nombre }
    }
    $dispositivos = $dispositivos | Sort-Object { [int]($_.IP.Split('.')[3]) }

    Log ("Se encontraron {0} dispositivos conectados:" -f $dispositivos.Count) "Cyan"
    Log ""
    Log ("  {0,-15}  {1,-17}  {2,-28}  {3}" -f "IP", "MAC", "Fabricante", "Nombre")
    Log ("  " + ("-" * 85))
    foreach ($d in $dispositivos) {
        Log ("  {0,-15}  {1,-17}  {2,-28}  {3}" -f $d.IP, $d.MAC, $d.Fabricante, $d.Nombre)
    }

    Log ""
    Log "Nota: el nombre no siempre se puede resolver (depende del dispositivo). Impresoras y equipos de red suelen aparecer solo con IP y MAC." "DarkGray"
    if (-not $tablaFabricantes) {
        Log "No se pudo mostrar el fabricante porque todavia no se descargo esa base de datos. Usa la opcion 'Actualizar base de fabricantes (MAC)' del menu para poder verlo (una sola vez, necesita internet)." "DarkYellow"
    }
    Agregar-Resultado -Prueba "Escaneo de red" -Destino ($base + "0/24") -Estado ("OK ({0} dispositivos)" -f $dispositivos.Count)
}

function Reparar-RedRapido {
    Titulo "ARREGLO RAPIDO DE RED" "Libera y renueva la IP (DHCP) y limpia la cache de DNS. Es el clasico primer intento antes de escalar cualquier problema de red."
    Log "Cuando usar esto: como primer intento rapido cuando hay problemas de red raros (no carga nada, IP rara, DNS que no resuelve), antes de reiniciar la PC entera." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Log ""
    Log "--- Liberando la IP actual (ipconfig /release) ---" "Yellow"
    ipconfig /release | ForEach-Object { Log $_ }

    Log ""
    Log "--- Pidiendo una IP nueva (ipconfig /renew) ---" "Yellow"
    ipconfig /renew | ForEach-Object { Log $_ }

    Log ""
    Log "--- Limpiando la cache de DNS (ipconfig /flushdns) ---" "Yellow"
    ipconfig /flushdns | ForEach-Object { Log $_ }

    Log ""
    Log "Listo. Si el problema persiste, puede hacer falta reiniciar la PC o el router." "Cyan"
    Agregar-Resultado -Prueba "Arreglo rapido de red" -Destino $env:COMPUTERNAME -Estado "OK"
}

function Ver-CalidadWifi {
    Titulo "CALIDAD DE LA CONEXION WIFI" "Muestra la intensidad de la conexion, el canal y el nombre de la red WiFi actual."
    Log "Cuando usar esto: para diagnosticar wifi debil en algun sector del lugar, o confirmar si un problema es de wifi flojo y no de internet." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $salida = netsh wlan show interfaces
    $texto = ($salida -join "`n")
    if (-not $salida -or $texto -match "no esta ejecutandose|not running|no hay ninguna interfaz|no wireless interface") {
        Log "No se detecto un adaptador WiFi activo (puede que esta PC este conectada por cable)." "Red"
        Agregar-Resultado -Prueba "Calidad WiFi" -Destino $env:COMPUTERNAME -Estado "FALLA (sin wifi)"
        return
    }

    $ssidMatch = [regex]::Match($texto, "(?m)^\s*SSID\s*:\s*(.+)$")
    $intensidadMatch = [regex]::Match($texto, "(?:Signal|Se.al)\s*:\s*(\d+)%")
    $canalMatch = [regex]::Match($texto, "(?:Channel|Canal)\s*:\s*(\d+)")

    if ($ssidMatch.Success) { Log ("Red (SSID) : {0}" -f $ssidMatch.Groups[1].Value.Trim()) }
    $porcIntensidad = $null
    if ($intensidadMatch.Success) {
        $porcIntensidad = [int]$intensidadMatch.Groups[1].Value
        $color = if ($porcIntensidad -ge 70) { "Green" } elseif ($porcIntensidad -ge 40) { "Yellow" } else { "Red" }
        Log ("Intensidad : {0}%" -f $porcIntensidad) $color
    }
    if ($canalMatch.Success) { Log ("Canal      : {0}" -f $canalMatch.Groups[1].Value) }

    Log ""
    Log "--- Detalle completo (netsh wlan show interfaces) ---" "DarkGray"
    $salida | ForEach-Object { Log $_ "DarkGray" }

    $estadoTexto = if ($null -eq $porcIntensidad) { "OK (sin dato de intensidad)" } elseif ($porcIntensidad -lt 40) { "ALERTA (intensidad baja)" } else { "OK" }
    Agregar-Resultado -Prueba "Calidad WiFi" -Destino $env:COMPUTERNAME -Estado $estadoTexto
}

function Ver-HistorialDesconexionesWifi {
    Titulo "HISTORIAL DE DESCONEXIONES DE WIFI" "Busca en el registro de eventos de Windows las desconexiones de WiFi de las ultimas 48 horas, sin tener que dejar nada corriendo en vivo."
    Log "Cuando usar esto: cuando dicen 'esto viene pasando hace dias' y necesitas ver si hay un patron, sin tener que dejar el Monitoreo continuo corriendo tanto tiempo." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $logInfo = Get-WinEvent -ListLog 'Microsoft-Windows-WLAN-AutoConfig/Operational' -ErrorAction SilentlyContinue
    if (-not $logInfo -or -not $logInfo.IsEnabled) {
        Log "Este registro de Windows esta desactivado por defecto en esta PC, asi que todavia no hay historial guardado." "DarkYellow"
        Log "Se puede activar corriendo una sola vez, como administrador:" "DarkGray"
        Log "  wevtutil sl Microsoft-Windows-WLAN-AutoConfig/Operational /e:true" "DarkGray"
        Log "Despues de activarlo, Windows va a ir guardando el historial para la proxima vez." "DarkGray"
        Agregar-Resultado -Prueba "Historial WiFi" -Destino $env:COMPUTERNAME -Estado "OMITIDO (log desactivado)"
        return
    }

    $desde = (Get-Date).AddHours(-48)
    $eventos = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; StartTime = $desde } -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Log "No se encontraron eventos de WiFi en las ultimas 48 horas." "Green"
        Agregar-Resultado -Prueba "Historial WiFi" -Destino $env:COMPUTERNAME -Estado "OK (sin eventos)"
        return
    }

    Log ("Se encontraron {0} eventos de WiFi en las ultimas 48 horas:" -f $eventos.Count) "Cyan"
    Log ""
    foreach ($e in ($eventos | Select-Object -First 30)) {
        Log ("[{0}] ID {1}: {2}" -f $e.TimeCreated.ToString("dd/MM HH:mm:ss"), $e.Id, (($e.Message -split "`n")[0]))
    }
    Agregar-Resultado -Prueba "Historial WiFi" -Destino $env:COMPUTERNAME -Estado ("OK ({0} eventos)" -f $eventos.Count)
}

function Chequear-IpDuplicada {
    Titulo "CHEQUEAR IP DUPLICADA" "Busca si otro equipo de la red esta usando la misma IP que esta PC, algo que causa cortes intermitentes dificiles de explicar."
    Log "Cuando usar esto: cuando hay cortes raros que no coinciden con el router ni con el proveedor (ver Monitoreo continuo), y sospechas de un conflicto de direcciones IP." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $adaptador = Get-Adaptadores | Select-Object -First 1
    if (-not $adaptador) { Log "No hay adaptadores de red activos." "Red"; return }
    $infoIp = Get-InfoIP $adaptador
    $ipLocal = if ($infoIp) { ($infoIp.IPv4Address.IPAddress | Select-Object -First 1) } else { $null }
    if ([string]::IsNullOrWhiteSpace($ipLocal)) { Log "No se pudo obtener la IP local." "Red"; return }

    Log ("Chequeando si la IP {0} esta duplicada en la red..." -f $ipLocal) "Yellow"

    $eventos = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip'; Id = 4198, 4199 } -MaxEvents 10 -ErrorAction SilentlyContinue
    if ($eventos) {
        Log ""
        Log "Windows tiene registrados conflictos de IP anteriores:" "Red"
        foreach ($e in $eventos) {
            Log ("  [{0}] {1}" -f $e.TimeCreated.ToString("dd/MM/yyyy HH:mm"), (($e.Message -split "`n")[0])) "Red"
        }
    } else {
        Log "Windows no tiene registrado ningun conflicto de IP en el historial." "Green"
    }

    Log ""
    Log "Haciendo un chequeo activo (tabla ARP)..." "Yellow"
    arp -d $ipLocal 2>$null | Out-Null
    Start-Sleep -Milliseconds 300
    ping $ipLocal -n 2 -w 500 | Out-Null
    $arpInfo = Get-NetNeighbor -IPAddress $ipLocal -ErrorAction SilentlyContinue
    $miMac = (Get-NetAdapter | Where-Object { $_.ifIndex -eq $adaptador.ifIndex } | Select-Object -First 1).MacAddress

    if ($arpInfo -and $arpInfo.LinkLayerAddress -and $miMac -and ($arpInfo.LinkLayerAddress.Replace('-', ':').ToUpper() -ne $miMac.Replace('-', ':').ToUpper())) {
        Log ("ALERTA: otro equipo de la red responde por la IP {0} con una MAC distinta a la de esta PC." -f $ipLocal) "Red"
        Agregar-Resultado -Prueba "IP duplicada" -Destino $ipLocal -Estado "ALERTA (posible duplicado)"
        return
    }

    Log "No se detecto que otro equipo este usando la misma IP ahora mismo." "Green"
    Agregar-Resultado -Prueba "IP duplicada" -Destino $ipLocal -Estado "OK"
}

function Mostrar-MenuRed {
    Clear-Host
    Mostrar-Banner
    Write-Host "============================================================"
    Write-Host ("   TESTEO DE RED - {0}" -f $Sede.ToUpper())
    Write-Host "============================================================"
    Write-Host " 1. Ver configuracion completa de red (ipconfig /all)"
    Write-Host " 2. Ver adaptadores de red activos (Wifi/Cable)"
    Write-Host " 3. CHEQUEO RAPIDO: esta caido Internet?"
    Write-Host " 4. Test de Velocidad: esta lento Internet?"
    Write-Host " 5. Test de Acceso Remoto (RDP)"
    Write-Host " 6. Monitoreo continuo (Wifi/Cable/Internet que va y viene, estilo ping -t)"
    Write-Host " 7. Averiguar el proveedor de Internet (ISP) actual"
    Write-Host " 8. Ver dispositivos conectados a la red (PCs, impresoras, etc)"
    Write-Host " 9. Test personalizado (ping/puerto)"
    Write-Host " 10. Arreglo rapido de red (renovar IP y limpiar DNS)"
    Write-Host " 11. Calidad de la conexion WiFi (intensidad, canal)"
    Write-Host " 12. Historial de desconexiones de WiFi (Visor de Eventos)"
    Write-Host " 13. Chequear IP duplicada en la red"
    Write-Host " 14. Actualizar base de fabricantes (MAC) - HP, Epson, Zebra, Cisco, etc"
    Write-Host " 0. Volver al menu principal"
    Write-Host "============================================================"
    Write-Host ""
}

function Start-MenuRed {
    do {
        Mostrar-MenuRed
        $opcionRed = Read-Host "Elegi una opcion"
        Reset-Resultados
        switch ($opcionRed) {
            "1" { Mostrar-IpConfigAll }
            "2" { Menu-VerAdaptadores }
            "3" { Menu-ChequeoInternet }
            "4" { Menu-TestVelocidad }
            "5" { Menu-TestAccesoRemoto }
            "6" { Menu-MonitoreoIntermitencias }
            "7" { Menu-InfoProveedor }
            "8" { Escanear-Red }
            "9" { Menu-TestPersonalizado }
            "10" { Reparar-RedRapido }
            "11" { Ver-CalidadWifi }
            "12" { Ver-HistorialDesconexionesWifi }
            "13" { Chequear-IpDuplicada }
            "14" { Actualizar-BaseFabricantesMac }
            "0" { }
            default { Write-Host "Opcion invalida" -ForegroundColor Red }
        }
        Mostrar-Resumen
        if ($opcionRed -ne "0") {
            Write-Host ""
            Read-Host "Presiona ENTER para volver"
        }
    } while ($opcionRed -ne "0")
}

# ============================================================
# AREA 2: MANTENIMIENTO DE PC (disco, sistema, limpieza)
# ============================================================

function Asegurar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($esAdmin) { return $true }
    Write-Host ""
    Write-Host "Esta seccion necesita permisos de Administrador. Pidiendo permisos..." -ForegroundColor Yellow
    try {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Mantenimiento" -ErrorAction Stop
        Write-Host "Se abrio una ventana nueva como Administrador. Esta ventana se va a cerrar." -ForegroundColor Cyan
        exit
    } catch {
        Write-Host "No se otorgaron los permisos de Administrador. Sin ellos no se puede usar Mantenimiento de PC." -ForegroundColor Red
        return $false
    }
}

function Ver-EspacioDisco {
    Titulo "ESPACIO EN DISCO" "Muestra cuanto espacio usado/libre tiene cada unidad."
    Log "Cuando usar esto: para chequear rapido si el disco se esta quedando sin espacio (Windows anda lento cuando el disco esta muy lleno) o antes de instalar una actualizacion grande." "DarkGray"
    Log ""
    $discos = Get-Volume | Where-Object { $_.DriveLetter }
    foreach ($d in $discos) {
        $totalGB = [math]::Round($d.Size / 1GB, 1)
        $libreGB = [math]::Round($d.SizeRemaining / 1GB, 1)
        $usadoGB = [math]::Round($totalGB - $libreGB, 1)
        $porcLibre = if ($totalGB -gt 0) { [math]::Round(($libreGB / $totalGB) * 100, 0) } else { 0 }
        $color = if ($porcLibre -lt 10) { "Red" } elseif ($porcLibre -lt 20) { "Yellow" } else { "Green" }
        Log ("Unidad {0}:  Total: {1} GB   Usado: {2} GB   Libre: {3} GB ({4}%)" -f $d.DriveLetter, $totalGB, $usadoGB, $libreGB, $porcLibre) $color
    }
}

function Ver-SaludDisco {
    Titulo "SALUD DEL DISCO (S.M.A.R.T)" "Indica si el disco fisico esta sano, alertado o fallando."
    Log "Cuando usar esto: chequeo preventivo cada tanto, o cuando la PC anda muy lenta / se cuelga / hace ruidos raros y sospechas del disco fisico (no de Windows)." "DarkGray"
    Log ""
    $discos = Get-PhysicalDisk
    if (-not $discos) { Log "No se pudo obtener informacion de los discos fisicos." "Red"; return }
    foreach ($d in $discos) {
        $color = switch ($d.HealthStatus) {
            "Healthy" { "Green" }
            "Warning" { "Yellow" }
            default   { "Red" }
        }
        Log ("Disco: {0}  |  Tipo: {1}  |  Estado: {2}" -f $d.FriendlyName, $d.MediaType, $d.HealthStatus) $color
    }
    Log ""
    Log "Si algun disco figura 'Warning' o 'Unhealthy', hacer backup y planificar el cambio del disco." "DarkGray"
}

function Ejecutar-Chkdsk {
    Titulo "CHKDSK - Revisar y reparar el disco" "Busca y repara errores del sistema de archivos, y opcionalmente localiza sectores con fallas fisicas."
    Log "/F  = repara errores logicos del sistema de archivos. Rapido (minutos)." "DarkGray"
    Log "/R  = ademas localiza sectores con fallas fisicas e intenta recuperar la informacion (implica /F). Mucho mas lento (puede tardar horas en discos grandes)." "DarkGray"
    Log ""
    Log "Cuando usar esto: Windows avisa que hay que reparar el disco, aparecen errores de lectura/escritura, archivos que se corrompen sin razon, arranques con pantallas de chequeo de disco, o fallo una copia/clonado del disco." "DarkGray"
    Log ""
    $unidad = Read-Host "Que unidad queres revisar? (ej: C, D, F) [Enter = C]"
    if ([string]::IsNullOrWhiteSpace($unidad)) { $unidad = "C" }
    $unidad = ($unidad.Trim().TrimEnd(':')) + ":"

    Log ""
    Write-Host "Que tipo de revision queres hacer?"
    Write-Host "  1. Solo /F  - repara errores logicos (rapido, minutos)"
    Write-Host "  2. /F y /R  - ademas busca sectores con fallas fisicas (lento, puede tardar horas)"
    $opcionChk = Read-Host "Opcion [Enter = 1]"
    if ([string]::IsNullOrWhiteSpace($opcionChk)) { $opcionChk = "1" }
    $usarR = ($opcionChk -eq "2")

    Log ""
    Log ("Se va a ejecutar: chkdsk {0} {1}" -f $unidad, $(if ($usarR) { "/f /r" } else { "/f" })) "Yellow"
    Log "Si es la unidad donde esta instalado Windows, no se puede revisar mientras esta en uso: Windows va a ofrecer programarlo para el proximo reinicio." "Yellow"
    $confirmar = Read-Host "Confirmar? (s/n)"
    if ($confirmar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Log ""
    Log "Arrancando... si no ves nada por un rato es normal, no se colgo, sigue trabajando." "DarkGray"
    if ($usarR) {
        "S`nY`n" | chkdsk $unidad /f /r | ForEach-Object { Log $_ }
    } else {
        "S`nY`n" | chkdsk $unidad /f | ForEach-Object { Log $_ }
    }
    Log ""
    Log "Si aparecio el mensaje de programar la revision, hay que REINICIAR la PC para que se ejecute antes de arrancar Windows." "Cyan"
}

function Ejecutar-SFC {
    Titulo "SFC /SCANNOW - Verificar archivos de sistema" "Revisa que los archivos protegidos de Windows no esten corruptos o modificados, y los repara con una copia interna."
    Log "Cuando usar esto: Windows se comporta raro (programas que se cierran solos, funciones que desaparecen), errores mencionando archivos de sistema, o como chequeo despues de sacar un virus." "DarkGray"
    Log ""
    Log "Esto puede tardar entre 10 y 30 minutos. No cerrar la ventana." "Yellow"
    $confirmar = Read-Host "Confirmar? (s/n)"
    if ($confirmar -ne "s") { Log "Cancelado." "DarkYellow"; return }
    Log ""
    Log "Arrancando... si tarda en aparecer el porcentaje es normal, no se colgo, sigue trabajando." "DarkGray"
    sfc /scannow | ForEach-Object { Log $_ }
}

function Ejecutar-DISM {
    Titulo "DISM /RESTOREHEALTH - Reparar la imagen de Windows" "Descarga y reemplaza archivos base de Windows corruptos usando Windows Update. Se usa cuando SFC no puede reparar algo, como paso previo a SFC. Necesita conexion a internet."
    Log "Cuando usar esto: cuando SFC (opcion 4) dijo que encontro archivos con fallas pero no pudo reparar algunos, o cuando Windows Update falla repetidamente con errores. Despues de correr esto, volve a correr SFC." "DarkGray"
    Log ""
    Log "Esto puede tardar 15-30 minutos segun la conexion." "Yellow"
    $confirmar = Read-Host "Confirmar? (s/n)"
    if ($confirmar -ne "s") { Log "Cancelado." "DarkYellow"; return }
    Log ""
    Log "Arrancando... si tarda en aparecer el porcentaje es normal, no se colgo, sigue trabajando." "DarkGray"
    DISM /Online /Cleanup-Image /RestoreHealth | ForEach-Object { Log $_ }
}

function Liberar-Espacio {
    Titulo "LIBERAR ESPACIO EN DISCO" "Borra archivos temporales de Windows y del usuario, cache de actualizaciones antiguas y vacia la papelera de reciclaje."
    Log "Cuando usar esto: cuando en la opcion 1 (Ver espacio en disco) el disco esta al 85-90% lleno o mas, cuando aparece el cartel de 'poco espacio en disco', o como mantenimiento de rutina cada 2-3 meses." "DarkGray"
    Log ""
    $confirmar = Read-Host "Esto borra archivos temporales y vacia la papelera. Confirmar? (s/n)"
    if ($confirmar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $carpetas = @(
        $env:TEMP,
        "$env:WINDIR\Temp",
        "$env:WINDIR\SoftwareDistribution\Download"
    )
    $liberadoTotal = 0
    foreach ($carpeta in $carpetas) {
        if (-not (Test-Path $carpeta)) { continue }
        $archivos = Get-ChildItem -Path $carpeta -Recurse -Force -ErrorAction SilentlyContinue
        $tamanoAntes = ($archivos | Measure-Object -Property Length -Sum).Sum
        $archivos | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $mb = if ($tamanoAntes) { [math]::Round($tamanoAntes / 1MB, 1) } else { 0 }
        $liberadoTotal += $mb
        Log ("Limpiado: {0}  (~{1} MB)" -f $carpeta, $mb)
    }

    Log ""
    Log "Vaciando la papelera de reciclaje..." "Yellow"
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log "Papelera vaciada." "Green"

    Log ""
    Log ("Espacio liberado (archivos temporales): ~{0} MB" -f [math]::Round($liberadoTotal, 1)) "Cyan"
}

function Optimizar-Disco {
    Titulo "OPTIMIZAR / DESFRAGMENTAR DISCO" "En discos rigidos (HDD) reordena los archivos para que Windows los lea mas rapido. En discos solidos (SSD) hace un TRIM, no una desfragmentacion tradicional."
    Log "Cuando usar esto: solo tiene sentido en discos rigidos (HDD) viejos que tardan en abrir archivos. Windows ya lo hace solo una vez por semana, asi que rara vez hace falta correrlo a mano (en SSD no mejora la velocidad)." "DarkGray"
    Log ""
    $unidad = Read-Host "Que unidad queres optimizar? (ej: C) [Enter = C]"
    if ([string]::IsNullOrWhiteSpace($unidad)) { $unidad = "C" }
    $unidad = ($unidad.Trim().TrimEnd(':')) + ":"
    Log ""
    Log "Esto puede tardar bastante tiempo en discos grandes o muy fragmentados." "Yellow"
    $confirmar = Read-Host "Confirmar? (s/n)"
    if ($confirmar -ne "s") { Log "Cancelado." "DarkYellow"; return }
    Log ""
    Log "Arrancando... si no ves nada por un rato es normal, no se colgo, sigue trabajando." "DarkGray"
    defrag $unidad /O /V | ForEach-Object { Log $_ }
}

function Ver-InfoEquipo {
    Titulo "INFORMACION GENERAL DEL EQUIPO" "Resumen rapido: procesador, memoria, modelo, version de Windows y hace cuanto no se reinicia."
    Log "Cuando usar esto: como chequeo rapido general, o para saber si conviene reiniciar la PC (muchos problemas se resuelven con un reinicio)." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $cs -or -not $os) {
        Log "No se pudo obtener la informacion del equipo." "Red"
        return
    }

    $ramTotalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $ramLibreGB = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 1)
    $ramUsadaGB = [math]::Round($ramTotalGB - $ramLibreGB, 1)
    $porcRamLibre = if ($ramTotalGB -gt 0) { [math]::Round(($ramLibreGB / $ramTotalGB) * 100, 0) } else { 0 }
    $uptime = (Get-Date) - $os.LastBootUpTime
    $colorRam = if ($porcRamLibre -lt 15) { "Red" } elseif ($porcRamLibre -lt 30) { "Yellow" } else { "Green" }
    $colorUptime = if ($uptime.TotalDays -gt 14) { "Yellow" } else { "Green" }

    Log ("Equipo          : {0} {1}" -f $cs.Manufacturer, $cs.Model)
    Log ("Procesador      : {0}" -f $cpu.Name)
    Log ("Windows         : {0} ({1})" -f $os.Caption, $os.OSArchitecture)
    Log ("Memoria RAM     : {0} GB total, {1} GB usada, {2} GB libre ({3}%)" -f $ramTotalGB, $ramUsadaGB, $ramLibreGB, $porcRamLibre) $colorRam
    Log ("Ultimo reinicio : {0}" -f $os.LastBootUpTime.ToString("dd/MM/yyyy HH:mm"))
    Log ("Tiempo prendida : {0}" -f (Formatear-Duracion $uptime.TotalSeconds)) $colorUptime

    if ($uptime.TotalDays -gt 14) {
        Log ""
        Log "Sugerencia: hace mas de 2 semanas que no se reinicia. Si hay algun problema raro, probar reiniciar la PC." "Yellow"
    }
    Agregar-Resultado -Prueba "Info del equipo" -Destino $env:COMPUTERNAME -Estado "OK"
}

function Ver-ProcesosTop {
    Titulo "PROCESOS QUE MAS CONSUMEN" "Muestra los procesos que mas memoria y CPU estan usando en este momento."
    Log "Cuando usar esto: cuando alguien dice que la PC esta lenta AHORA MISMO, para ver rapido que la esta frenando." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Log "--- Top 10 por uso de memoria ---" "Yellow"
    $porMemoria = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    foreach ($p in $porMemoria) {
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Log ("  {0,-30} PID {1,-7} {2,8} MB" -f $p.ProcessName, $p.Id, $mb)
    }

    Log ""
    Log "--- Top 10 por tiempo de CPU acumulado (desde que arranco el proceso) ---" "Yellow"
    $porCpu = Get-Process | Where-Object { $_.CPU } | Sort-Object CPU -Descending | Select-Object -First 10
    foreach ($p in $porCpu) {
        Log ("  {0,-30} PID {1,-7} {2,10:N1} seg CPU" -f $p.ProcessName, $p.Id, $p.CPU)
    }

    Agregar-Resultado -Prueba "Procesos top" -Destino $env:COMPUTERNAME -Estado "OK"
}

function Reiniciar-Spooler {
    Titulo "REINICIAR SPOOLER DE IMPRESION" "Para y vuelve a arrancar el servicio de impresion de Windows (Print Spooler), y borra trabajos de impresion trabados."
    Log "Cuando usar esto: cuando una impresora no imprime, quedan trabajos trabados en la cola, o el icono de impresora tarda en responder." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    Log ""
    Log "Deteniendo el servicio Spooler..." "Yellow"
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Log "Borrando trabajos de impresion pendientes en la cola..." "Yellow"
    Remove-Item -Path "$env:WINDIR\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Log "Iniciando el servicio Spooler..." "Yellow"
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $servicio = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($servicio -and $servicio.Status -eq "Running") {
        Log "Spooler reiniciado correctamente." "Green"
        Agregar-Resultado -Prueba "Reinicio de Spooler" -Destino $env:COMPUTERNAME -Estado "OK"
    } else {
        Log "No se pudo confirmar que el Spooler quedo activo." "Red"
        Agregar-Resultado -Prueba "Reinicio de Spooler" -Destino $env:COMPUTERNAME -Estado "FALLA"
    }
}

function Ver-EstadoAntivirus {
    Titulo "ESTADO DEL ANTIVIRUS (WINDOWS DEFENDER)" "Muestra si el antivirus esta activo, actualizado, y cuando fue el ultimo analisis."
    Log "Cuando usar esto: chequeo de seguridad de rutina, o cuando se sospecha que el antivirus esta apagado o desactualizado." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $estado = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if (-not $estado) {
        Log "No se pudo consultar el estado (puede que esta PC use otro antivirus distinto de Windows Defender)." "Red"
        Agregar-Resultado -Prueba "Antivirus" -Destino $env:COMPUTERNAME -Estado "FALLA (sin datos)"
        return
    }

    Log ("Proteccion en tiempo real : {0}" -f $(if ($estado.RealTimeProtectionEnabled) { "ACTIVA" } else { "DESACTIVADA" })) $(if ($estado.RealTimeProtectionEnabled) { "Green" } else { "Red" })
    Log ("Antivirus activo          : {0}" -f $(if ($estado.AntivirusEnabled) { "SI" } else { "NO" })) $(if ($estado.AntivirusEnabled) { "Green" } else { "Red" })
    Log ("Firmas actualizadas       : {0}" -f $estado.AntivirusSignatureLastUpdated)
    Log ("Ultimo analisis rapido    : {0}" -f $estado.QuickScanEndTime)
    Log ("Ultimo analisis completo  : {0}" -f $estado.FullScanEndTime)

    $ok = $estado.RealTimeProtectionEnabled -and $estado.AntivirusEnabled
    $estadoTexto = if ($ok) { "OK (activo)" } else { "ALERTA (desactivado)" }
    Agregar-Resultado -Prueba "Antivirus" -Destino $env:COMPUTERNAME -Estado $estadoTexto
}

function Ver-ProgramasInicio {
    Titulo "PROGRAMAS QUE ARRANCAN CON WINDOWS" "Lista los programas configurados para iniciar automaticamente al prender la PC."
    Log "Cuando usar esto: cuando la PC tarda mucho en arrancar o quedar usable despues de prenderla." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $items = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    if (-not $items) {
        Log "No se encontraron programas de inicio (o no se pudo consultar)." "DarkYellow"
        Agregar-Resultado -Prueba "Programas de inicio" -Destino $env:COMPUTERNAME -Estado "OK (0 items)"
        return
    }
    foreach ($it in $items) {
        Log ("  {0,-30} {1}" -f $it.Name, $it.Location)
    }
    Log ""
    Log ("Total: {0} programas configurados para iniciar con Windows." -f $items.Count) "Cyan"
    Agregar-Resultado -Prueba "Programas de inicio" -Destino $env:COMPUTERNAME -Estado ("OK ({0} items)" -f $items.Count)
}

function Ver-ErroresRecientes {
    Titulo "ERRORES RECIENTES (VISOR DE EVENTOS)" "Busca errores criticos y de error en el Visor de Eventos de las ultimas 48 horas (System y Application)."
    Log "Cuando usar esto: para investigar crashes, pantallas azules, o cuando la PC se reinicio sola y queres saber por que." "DarkGray"
    Log ""
    $continuar = Read-Host "Deseas ejecutar esto? (s/n)"
    if ($continuar -ne "s") { Log "Cancelado." "DarkYellow"; return }

    $desde = (Get-Date).AddHours(-48)
    $eventos = Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $desde } -MaxEvents 30 -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Log "No se encontraron errores criticos en las ultimas 48 horas. Buena noticia." "Green"
        Agregar-Resultado -Prueba "Errores recientes" -Destino $env:COMPUTERNAME -Estado "OK (sin errores)"
        return
    }

    foreach ($e in $eventos) {
        $color = if ($e.Level -eq 1) { "Red" } else { "Yellow" }
        $mensaje = ($e.Message -split "`n")[0]
        if ($mensaje.Length -gt 100) { $mensaje = $mensaje.Substring(0, 100) + "..." }
        Log ("[{0}] {1} - {2}: {3}" -f $e.TimeCreated.ToString("dd/MM HH:mm"), $e.LogName, $e.ProviderName, $mensaje) $color
    }
    Log ""
    Log ("Se encontraron {0} errores/criticos en las ultimas 48 horas." -f $eventos.Count) "Cyan"
    Agregar-Resultado -Prueba "Errores recientes" -Destino $env:COMPUTERNAME -Estado ("ALERTA ({0} errores)" -f $eventos.Count)
}

function Mostrar-MenuMantenimiento {
    Clear-Host
    Mostrar-Banner
    Write-Host "============================================================"
    Write-Host "   MANTENIMIENTO DE PC - Disco y Sistema"
    Write-Host "============================================================"
    Write-Host " 1. Ver espacio en disco"
    Write-Host " 2. Ver salud del disco (S.M.A.R.T)"
    Write-Host " 3. CHKDSK /F /R - Revisar y reparar el disco"
    Write-Host " 4. SFC /scannow - Verificar archivos de sistema"
    Write-Host " 5. DISM /RestoreHealth - Reparar la imagen de Windows"
    Write-Host " 6. Liberar espacio (temporales + papelera)"
    Write-Host " 7. Optimizar / desfragmentar disco"
    Write-Host " 8. Informacion general del equipo (CPU, RAM, uptime)"
    Write-Host " 9. Ver procesos que mas consumen CPU/memoria"
    Write-Host " 10. Reiniciar spooler de impresion (impresora no imprime)"
    Write-Host " 11. Estado del antivirus (Windows Defender)"
    Write-Host " 12. Ver programas que arrancan con Windows"
    Write-Host " 13. Errores recientes (Visor de Eventos)"
    Write-Host " 0. Volver al menu principal"
    Write-Host "============================================================"
    Write-Host ""
}

function Start-MenuMantenimiento {
    if (-not (Asegurar-Admin)) {
        Write-Host ""
        Read-Host "Presiona ENTER para volver al menu principal"
        return
    }
    do {
        Mostrar-MenuMantenimiento
        $opcionMant = Read-Host "Elegi una opcion"
        switch ($opcionMant) {
            "1" { Ver-EspacioDisco }
            "2" { Ver-SaludDisco }
            "3" { Ejecutar-Chkdsk }
            "4" { Ejecutar-SFC }
            "5" { Ejecutar-DISM }
            "6" { Liberar-Espacio }
            "7" { Optimizar-Disco }
            "8" { Ver-InfoEquipo }
            "9" { Ver-ProcesosTop }
            "10" { Reiniciar-Spooler }
            "11" { Ver-EstadoAntivirus }
            "12" { Ver-ProgramasInicio }
            "13" { Ver-ErroresRecientes }
            "0" { }
            default { Write-Host "Opcion invalida" -ForegroundColor Red }
        }
        if ($opcionMant -ne "0") {
            Write-Host ""
            Read-Host "Presiona ENTER para volver"
        }
    } while ($opcionMant -ne "0")
}

# ============================================================
# MENU PRINCIPAL
# ============================================================

function Mostrar-Banner {
    param([switch]$Animado)

    $fuente = @{
        'M' = @("#   #", "## ##", "# # #", "#   #", "#   #")
        'A' = @(" ### ", "#   #", "#####", "#   #", "#   #")
        'R' = @("#### ", "#   #", "#### ", "#  # ", "#   #")
        'C' = @(" ####", "#    ", "#    ", "#    ", " ####")
        'H' = @("#   #", "#   #", "#####", "#   #", "#   #")
        'W' = @("#   #", "#   #", "# # #", "## ##", "#   #")
        'E' = @("#####", "#    ", "#### ", "#    ", "#####")
        'B' = @("#### ", "#   #", "#### ", "#   #", "#### ")
    }
    $palabra = "MARCHWEB"

    $anchoConsola = 80
    try { $anchoConsola = $Host.UI.RawUI.WindowSize.Width } catch {}
    if (-not $anchoConsola -or $anchoConsola -lt 20) { $anchoConsola = 80 }

    $lineas = @()
    for ($fila = 0; $fila -lt 5; $fila++) {
        $linea = ""
        foreach ($letra in $palabra.ToCharArray()) {
            $linea += $fuente[[string]$letra][$fila] + " "
        }
        $lineas += $linea.TrimEnd()
    }
    $anchoBanner = ($lineas | Measure-Object -Property Length -Maximum).Maximum
    $prefijo = " " * [Math]::Max(0, [int](($anchoConsola - $anchoBanner) / 2))

    $subtitulo = "Herramientas de soporte tecnico  -  Desarrollado por marchweb.com.ar"
    $prefijoSub = " " * [Math]::Max(0, [int](($anchoConsola - $subtitulo.Length) / 2))

    Write-Host ""
    foreach ($linea in $lineas) {
        Write-Host ($prefijo + $linea) -ForegroundColor Green
        if ($Animado) { Start-Sleep -Milliseconds 70 }
    }
    Write-Host ""
    Write-Host ($prefijoSub + $subtitulo) -ForegroundColor DarkGreen
    Write-Host ""
    if ($Animado) { Start-Sleep -Milliseconds 900 }
}

function Guardar-Testeo {
    if (-not $script:BufferActual -or $script:BufferActual.Count -eq 0) {
        Write-Host "No hay ningun testeo pendiente para guardar." -ForegroundColor Yellow
        return
    }
    $nombreArchivo = "{0}_Testeos_{1}.txt" -f $SedeArchivo, (Get-Date -Format "yyyyMMdd_HHmmss")
    $ruta = Join-Path $CarpetaTesteos $nombreArchivo
    $script:BufferActual | Set-Content -Path $ruta -Encoding UTF8
    Write-Host ("Guardado: {0}" -f $ruta) -ForegroundColor Green
    Reset-Buffer
}

function Mostrar-MenuPrincipal {
    Clear-Host
    Mostrar-Banner
    Write-Host "============================================================"
    Write-Host ("   HERRAMIENTAS DE SOPORTE - {0}" -f $Sede.ToUpper())
    Write-Host "============================================================"
    Write-Host " 1. Testeo de Red (Internet, proveedores, velocidad, RDP)"
    Write-Host " 2. Mantenimiento de PC (disco, sistema, limpieza)"
    Write-Host " 3. Guardar todo lo testeado"
    Write-Host " 0. Salir"
    Write-Host "============================================================"
    if ($script:BufferActual -and $script:BufferActual.Count -gt 0) {
        Write-Host " Tenes testeos sin guardar. Elegi la opcion 3 para guardarlos." -ForegroundColor Yellow
    }
    Write-Host ""
}

Reset-Buffer
if ($Mantenimiento) {
    Start-MenuMantenimiento
} else {
    Clear-Host
    Mostrar-Banner -Animado
}
do {
    Mostrar-MenuPrincipal
    $opcion = Read-Host "Elegi un area"
    switch ($opcion) {
        "1" { Start-MenuRed }
        "2" { Start-MenuMantenimiento }
        "3" { Guardar-Testeo }
        "0" {
            if ($script:BufferActual -and $script:BufferActual.Count -gt 0) {
                $guardar = Read-Host "Tenes testeos sin guardar. Guardarlos antes de salir? (s/n)"
                if ($guardar -eq "s") { Guardar-Testeo }
            }
            Write-Host "Saliendo..." -ForegroundColor Cyan
        }
        default { Write-Host "Opcion invalida" -ForegroundColor Red }
    }
} while ($opcion -ne "0")
