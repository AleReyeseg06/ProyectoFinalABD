# GymDB — instalación para la defensa

## Opción A: restaurar el respaldo (recomendada)

Usar una instancia Docker dedicada al proyecto, SQL Server Developer 2025 (el respaldo se creó en 2022), SSMS y Power BI Desktop. No usar una instancia de producción. Las credenciales fijas de demostración de Seguridad.sql son las originales del equipo; no son seguras para un servidor público. No publicar este ZIP ni el script con credenciales en un repositorio público. Si los logins ya existen, conservan sus contraseñas anteriores.

### 1. PowerShell: preparar el contenedor

Abrir PowerShell desde la raíz del repositorio (la carpeta que contiene Respaldos). Este bloque detecta el contenedor `sqlserver-2025` o `sqlserver`, prefiriendo el primero. No cambia otros contenedores. Si no existe ninguno, primero se debe instalar SQL Server Docker Developer.

```powershell
$contenedor = @('sqlserver-2025','sqlserver') | Where-Object { (docker ps -a --format '{{.Names}}') -contains $_ } | Select-Object -First 1
if (-not $contenedor) { throw 'No existe sqlserver-2025 ni sqlserver' }
if (-not (Test-Path './Respaldos/GymDB_Final.bak')) { throw 'Abre PowerShell en la raiz del repositorio' }
docker start $contenedor
if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar SQL Server' }
docker cp './Respaldos/GymDB_Final.bak' "${contenedor}:/var/opt/mssql/data/GymDB_Final.bak"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar el respaldo' }
docker exec -u root $contenedor /opt/mssql/bin/mssql-conf set sqlagent.enabled true
if ($LASTEXITCODE -ne 0) { throw 'No se pudo habilitar Agent' }
docker restart $contenedor
docker port $contenedor 1433/tcp
```

Conectar SSMS como `sa` con la contraseña de la instancia y el puerto indicado por el último comando: por ejemplo `localhost,1434` para sqlserver-2025 o `localhost,1433` para sqlserver. Activar confiar en el certificado para el entorno local. Si todavía está iniciando, conectar cuando esté disponible.

### 2. SSMS: restaurar

Ejecutar este bloque en una consulta nueva. Si ya existe GymDB, no se sobrescribe; confirmar que es la copia correcta antes de continuar. Los nombres lógicos corresponden al respaldo del proyecto; si FILELISTONLY muestra otros, detenerse.

```sql
USE master;
GO
IF DB_ID(N'GymDB') IS NULL
BEGIN
    RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak' WITH CHECKSUM;
    RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak';
    RESTORE DATABASE GymDB FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak'
    WITH MOVE 'GymDB' TO '/var/opt/mssql/data/GymDB.mdf',
         MOVE 'GymDB_log' TO '/var/opt/mssql/data/GymDB_log.ldf',
         RECOVERY, CHECKSUM, STATS = 10;
END
ELSE PRINT N'GymDB ya existe: no se sobrescribe.';
GO
```

### 3. SSMS: abrir y ejecutar archivos completos (F5)

Ejecutar uno por uno, en este orden, con `sa`. No editar contraseñas, rutas ni seleccionar secciones. Revisar Mensajes antes de pasar al siguiente archivo.

1. `Seguridad-datos/Seguridad.sql`: crea los logins originales si faltan, vincula usuarios restaurados, conserva roles y permisos, recrea auditoría y ejecuta pruebas. Las contraseñas de demostración están en la sección 1. No modifica pagos en las pruebas ordinarias.
2. `Diseño_de_la_base/Verificaciones.sql`: revisa tablas, restricciones y esquemas.
3. `Consultas-optimizacion/Consultas.sql`: seis consultas e índices.
4. `Respaldos/Respaldos.sql`: dimensionamiento, FULL, DIFF, LOG, restauración de prueba y jobs. Ejecutar en una sola ventana SSMS porque utiliza #cfg. Recrea GymDB_Test y dbo.PruebaRespaldo; no ejecutar si necesitan conservar esos objetos. No reemplaza GymDB ni el archivo GymDB_Final.bak. Si Agent está detenido, omite jobs: comprobar estado antes de ejecutar.

**No ejecutar GymDB.sql ni Datos.sql al restaurar:** ya existen las tablas y los datos.

### 4. Verificar resultados

```sql
USE GymDB;
GO
SELECT 'Socios' AS tabla, COUNT(*) AS filas FROM gym.Socios
UNION ALL SELECT 'Entrenadores', COUNT(*) FROM gym.Entrenadores
UNION ALL SELECT 'Clases', COUNT(*) FROM gym.Clases
UNION ALL SELECT 'Horarios', COUNT(*) FROM gym.Horarios
UNION ALL SELECT 'Reservas', COUNT(*) FROM gym.Reservas
UNION ALL SELECT 'Pagos', COUNT(*) FROM finanzas.Pagos;
SELECT SUM(monto) AS ingresos FROM finanzas.Pagos;
DBCC CHECKDB ('GymDB') WITH NO_INFOMSGS;
SELECT dp.name AS usuario, sp.name AS login_nombre FROM sys.database_principals dp
JOIN sys.server_principals sp ON dp.sid=sp.sid WHERE dp.name LIKE N'usr[_]%';
SELECT name, status_desc FROM sys.dm_server_audit_status;
SELECT name, is_state_enabled FROM sys.database_audit_specifications;
SELECT servicename, status_desc FROM sys.dm_server_services;
```

Esperado: 500 socios, 10 entrenadores, 12 clases, 300 horarios, 3771 reservas, 5280 pagos; 9873 registros operativos, ingresos 181800. Seis usuarios vinculados, auditoría habilitada, Agent en ejecución. La bitácora contiene registros adicionales.

Para probar los jobs, ejecutar los siguientes comandos por separado y comprobar que termine con éxito cada uno antes de iniciar el siguiente. No iniciar simultáneamente.

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo FULL semanal';
```
```sql
EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo DIFERENCIAL diario';
```
```sql
EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo LOG cada 30 min';
```
```sql
SELECT j.name,h.run_status,h.message FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id=h.job_id
WHERE j.name LIKE N'GymDB%' AND h.step_id=0 ORDER BY h.instance_id DESC;
```

run_status=1 significa éxito. RPO objetivo 30 min, RTO objetivo 1 hora (no medido). Horarios según reloj del servidor: FULL domingo 02:00; DIFF lunes a sábado 02:00; LOG cada 30 min.

### 5. Power BI

Abrir PowerBI/GymAnalytics.pbix. En modo Importar los filtros funcionan sin conexión. Para actualizar, en File > Options and settings > Data source settings, cambiar servidor al puerto real, base GymDB, autenticación de base de datos con lg_gym_powerbi y la contraseña original de la sección 1 de Seguridad.sql (si el login ya existía, usar su contraseña actual). Pulsar Refresh. No usar sa para BI. Esperado: $181800, 500 socios, 3771 reservas, 8.14% cancelación; Efectivo $68360; Yoga 391 reservas.

## Opción B: crear desde cero (solo en instancia sin GymDB)

No ejecutar esta opción si ya restauraste el respaldo. En PowerShell, preparar los archivos de carga con este único bloque (no modificar los CSV ni SQL a mano):

```powershell
$contenedor = @('sqlserver-2025','sqlserver') | Where-Object { (docker ps --format '{{.Names}}') -contains $_ } | Select-Object -First 1
if (-not $contenedor) { throw 'Inicia SQL Server Docker' }
$dest = Join-Path $env:TEMP 'GymDB_datos_unicode'
New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem './Seguridad-datos/datos/*.csv' | ForEach-Object {
    $texto = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dest $_.Name), $texto, [System.Text.Encoding]::Unicode)
}
docker exec -u root $contenedor mkdir -p /var/opt/mssql/datos_unicode
docker cp "$dest/." "${contenedor}:/var/opt/mssql/datos_unicode/"
docker exec -u root $contenedor chmod -R a+rX /var/opt/mssql/datos_unicode
```

En SSMS como sa, ejecutar GymDB.sql, Seguridad.sql, Datos.sql, Verificaciones.sql, Consultas.sql y Respaldos.sql, en ese orden. Habilitar Agent previamente (paso 1). Seguridad.sql incluye pruebas de lectura que en esta fase pueden devolver cero filas; repetir después de cargar. Datos.sql elimina registros previos y solo debe usarse para la carga inicial. Validar conteos y caracteres acentuados: la carga Unicode no se ha ejecutado en una instancia real desde que se revisó el script. Para la defensa se recomienda la opción A, que evita la importación.

## Entrega y límites

Conservar informe, presentación, capturas reales y copia privada del respaldo y PBIX. No publicar las credenciales de demostración ni usar las mismas en producción. Cambiar las credenciales expuestas después de la defensa. Esta revisión se hizo estáticamente; debe probarse en SQL Server 2025. Los archivos BAK y PBIX se conservan sin cambios. La ruta rápida se limita a Docker Linux con los nombres de contenedor indicados. No se promete ejecución en cualquier entorno sin instalación previa.
