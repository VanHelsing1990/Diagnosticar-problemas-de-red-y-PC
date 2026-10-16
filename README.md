# Marchweb Helper

Herramienta gratuita para Windows que centraliza los diagnósticos de red y PC más usados en soporte técnico, en un solo menú interactivo por consola. Pensada para que la pueda usar cualquiera: cada opción explica qué hace y cuándo conviene usarla, antes de pedir confirmación para ejecutarla.

Donada por [marchweb.com.ar](https://marchweb.com.ar) para uso libre de la comunidad.

## ¿Qué incluye?

### 🌐 Testeo de Red
- Ver configuración completa de red (`ipconfig /all`) y adaptadores activos
- Chequeo rápido: ¿está caído Internet?
- Test de velocidad (latencia y descarga)
- Test de acceso remoto (RDP)
- Monitoreo continuo para detectar cortes intermitentes (wifi o internet que "va y viene"), con cronología detallada de cada corte
- Averiguar el proveedor de Internet (ISP) actual
- Ver dispositivos conectados a la red local (PCs, impresoras, routers, etc.), identificando la marca de cada uno por su MAC (HP, Epson, Zebra, Cisco, etc.)
- Arreglo rápido de red (renovar IP y limpiar DNS)
- Calidad de la conexión WiFi (intensidad, canal)
- Historial de desconexiones de WiFi
- Chequear IP duplicada en la red
- Omitir verificación de identidad remota (RDP), para no ver el cartel de advertencia al conectarte por IP a equipos de tu propia red
- Actualizar horario de la PC contra un servidor de hora público
- Reparar IP (DHCP): para cuando la PC viene de otra red con IP fija y se queda sin internet (IP 169.254.x.x). Vuelve a pedir IP automática y hace un diagnóstico de dónde falla (red local, internet o DNS)
- Test personalizado: ping, ping continuo, tracert, puertos

### 💻 Mantenimiento de PC
- Ver espacio en disco y salud del disco (S.M.A.R.T)
- CHKDSK /F /R, SFC /scannow y DISM /RestoreHealth
- Liberar espacio (temporales y papelera)
- Optimizar / desfragmentar disco
- Información general del equipo (CPU, RAM, tiempo de actividad)
- Procesos que más consumen CPU/memoria
- Reiniciar spooler de impresión
- Estado del antivirus (Windows Defender)
- Programas que arrancan con Windows
- Errores recientes (Visor de Eventos)

## Requisitos

- Windows 10 u 11
- PowerShell (viene incluido en Windows)
- Permisos de Administrador solo para usar la sección de Mantenimiento de PC (el programa los pide automáticamente cuando hacen falta)

## Cómo usarlo

1. Descargar la carpeta completa.
2. Ejecutar `MarchwebHelper.bat` (doble clic).
3. Elegir un área del menú principal (Testeo de Red o Mantenimiento de PC) y después la opción que se necesite.
4. Cada prueba que corras se guarda **sola y automáticamente** como un archivo de texto en la carpeta `Testeos` (con fecha, usuario, equipo y el resultado completo), apenas termina — no hace falta guardar nada a mano, y si cerrás la ventana de golpe no se pierde lo que ya se alcanzó a mostrar.

Para personalizar el nombre que aparece en los menús, editar el archivo `config.json`:

```json
{
    "Sede": "Mi Empresa"
}
```

### Panel web opcional (ver los testeos en vivo desde el navegador)

Cualquier opción de **Testeo de Red** (las de Mantenimiento de PC quedan afuera a propósito) puede quedar publicada en un panel web propio: el programa pregunta un nombre para identificar el testeo, lo manda a un hosting propio, y desde cualquier navegador se puede ver la lista de testeos — el que está corriendo en ese momento aparece marcado como **EN VIVO**, y haciendo clic se ve el detalle actualizándose solo. Pensado para que un compañero de sistemas pueda ver cómo viene un testeo sin estar sentado frente a esa PC. Es opcional y viene desactivado por defecto.

Para activarlo hace falta un hosting propio con PHP y MySQL (no incluido en este repositorio por simplicidad — son unos 10 archivos PHP chicos), y agregar estas dos claves al `config.json`, apuntando a la carpeta donde subas esos archivos:

```json
{
    "Sede": "Mi Empresa",
    "WebMonitorUrl": "https://tu-dominio.com/ruta",
    "WebMonitorKey": "una-clave-secreta-que-vos-elijas"
}
```

Si estos campos no están configurados, el programa funciona exactamente igual, solo que no manda nada a ningún lado ni pregunta ningún nombre.

## Licencia y condiciones de uso

Este programa se **dona para uso libre y gratuito**, personal o profesional (por ejemplo, técnicos de soporte que quieran usarlo con sus clientes).

**No está permitido**:
- Venderlo, revenderlo, ni cobrar por su uso, instalación o distribución.
- Ofrecerlo como parte de un producto o servicio pago sin autorización expresa del autor.
- Eliminar la atribución a marchweb.com.ar como autor original.

**Sí está permitido**:
- Usarlo libremente, modificarlo y adaptarlo a necesidades propias.
- Distribuirlo de forma gratuita, manteniendo esta licencia y la atribución al autor original.

En términos de licencias reconocidas, esto equivale a [Creative Commons Atribución-NoComercial 4.0 (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/deed.es).

## Autor

Desarrollado por [marchweb.com.ar](https://marchweb.com.ar).

Sugerencias, bugs o ideas para sumar: son bienvenidos a través de GitHub o el sitio web.
