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
- Ver dispositivos conectados a la red local (PCs, impresoras, routers, etc.)
- Arreglo rápido de red (renovar IP y limpiar DNS)
- Calidad de la conexión WiFi (intensidad, canal)
- Historial de desconexiones de WiFi
- Chequear IP duplicada en la red
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
4. Los resultados se pueden guardar en un archivo de texto desde el menú principal, en la carpeta `Testeos`.

Para personalizar el nombre que aparece en los menús, editar el archivo `config.json`:

```json
{
    "Sede": "Mi Empresa"
}
```

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
