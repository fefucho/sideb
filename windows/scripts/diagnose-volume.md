# Capturar el fallo de rueda en Windows

Esta captura observa la app ya instalada. No instala otra version ni envia datos a un servidor. Guarda deltas/unidades de rueda, cancelacion, zona bajo el cursor, foco y peticiones/confirmaciones numericas de volumen. No copia cuenta, canciones, cookies, URLs ni mensajes completos de errores.

1. Copia los tres archivos `diagnose-volume.cmd`, `diagnose-volume.ps1` y este documento al mismo directorio en la PC Windows. Abri Side B como siempre.
2. Ejecuta `diagnose-volume.cmd` con doble clic. Cuando lo indique, cerra Side B normalmente y presiona Enter en la consola. El script vuelve a abrir el mismo ejecutable.
3. Espera el mensaje **Captura lista**. Pone volumen 50 con la barra, deja el cursor sobre la portada grande y gira unas diez muescas hacia abajo. Proba tambien sobre la barra de volumen abierta.
4. Volve a la consola y presiona Enter antes de dos minutos. El archivo `SideB-volume-FECHA-HORA.json` aparece en el Escritorio. Ese archivo es el que hace falta compartir para investigar el fallo.
5. Cerra Side B normalmente y volve a abrirlo. Asi termina la sesion de diagnostico del runtime.

Si la consola informa un error, conserva ese texto: no indica que el bug de volumen haya sido identificado. Para un portable sin abrir se puede ejecutar `diagnose-volume.ps1 -AppPath 'C:\ruta\sideb-windows.exe'` desde PowerShell, con la ruta real del EXE.

El launcher usa una politica de ejecucion limitada a su proceso PowerShell; no cambia la configuracion del sistema. El argumento de depuracion de WebView2 se aplica solo al proceso de Side B iniciado por el script, en un puerto local temporal; no modifica registro ni preferencias de cuenta. El observador se retira al recoger la captura o al cumplir dos minutos, y no altera los argumentos, resultados o promesas de los comandos originales. La salida se limita a 400 registros. Cerrando la app se retira tambien el puerto de diagnostico.

Referencia: [Microsoft: depurar WebView2 mediante argumentos del proceso](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/debug-visual-studio-code). No se usa un puente de eventos nativos nuevo ni se cambia la politica de volumen para intentar adivinar los deltas del dispositivo.

El launcher ya produjo una captura real en Windows/WebView2 155 con la app1.2.2, recibida el2026-10-18. La salida schema1 leyo `wheel-after` desde una microtarea del listener de captura: esos valores pueden ser anteriores al handler de la app y no sirven para afirmar si se cancelo el evento. Schema2 realiza esa lectura en la tarea siguiente; pruebas Node del observador y de la politica/frontend aprobadas, nueva lectura tardia pendiente de repeticion en WebView2. La captura original si aporta deltas reales y ordenes/confirmaciones numericas IPC utiles para FIX-211. No hace falta repetirla para reproducir la cancelacion por eje lateral encontrada.
