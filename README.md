# GymDB | Sistema de reservas de gimnasio

Proyecto de cátedra de Administración de Bases de Datos. Implementación de una base de datos relacional para gestionar socios, entrenadores, clases, horarios, reservas y pagos, con seguridad, auditoría, optimización, respaldo y análisis en Power BI.

## Requisitos

- SQL Server Developer 2022 o 2025 (la rúbrica solicita 2025; las pruebas locales se realizaron en 2022).
- Docker Desktop si se utiliza el entorno Linux descrito aquí.
- SQL Server Management Studio (SSMS).
- Power BI Desktop compatible con el archivo PBIX.
- Acceso administrativo local para instalar la base y configurar el servidor.

## Estructura del repositorio

```text
ProyectoFinalABD/
├── Diseño_de_la_base/
│   ├── GymDB.sql
│   ├── Verificaciones.sql
│   ├── Diagrama_ER_GymDB.png
│   └── Diccionario_de_datos.pdf
├── Seguridad-datos/
│   ├── Seguridad.sql
│   ├── Datos.sql
│   └── datos/                 # seis CSV de prueba
├── Consultas-optimizacion/
│   └── Consultas.sql
├── Respaldos/
│   ├── Respaldos.sql
│   └── GymDB_Final.bak
├── PowerBI/
│   └── GymAnalytics.pbix
└── README.md
```

## Instalación rápida para la presentación (recomendada)

Esta opción conserva las tablas, datos, relaciones, restricciones, índices, usuarios, roles y trigger de la base. Los logins, auditorías de servidor y jobs se configuran aparte. No ejecutar los scripts de creación o carga completa sobre la base restaurada.

### 1. Preparar el servidor

En PowerShell, comprobar que Docker está iniciado:

```powershell
docker ps
```

Los ejemplos suponen un contenedor existente llamado `sqlserver`, con puerto 1433 publicado y una instancia accesible desde SSMS como `localhost,1433`. Si no existe una instancia, instalar SQL Server Developer antes de continuar. Si el nombre del contenedor o puerto es distinto, ajustar los comandos. No eliminar un contenedor existente.

### 2. Copiar el respaldo

Desde la raíz del repositorio en PowerShell (o ajustar la ruta al archivo recibido por privado):

```powershell
docker cp "./Respaldos/GymDB_Final.bak" sqlserver:/var/opt/mssql/data/GymDB_Final.bak
```

### 3. Restaurar GymDB

Conectarse a SSMS como administrador. Verificar que no exista otra base llamada GymDB y revisar los nombres lógicos:

```sql
USE master;
GO
SELECT DB_ID(N'GymDB') AS base_existente;
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak' WITH CHECKSUM;
RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak';
```

Solo si `base_existente` es NULL y los nombres lógicos coinciden, ejecutar:

```sql
RESTORE DATABASE GymDB
FROM DISK = '/var/opt/mssql/data/GymDB_Final.bak'
WITH MOVE 'GymDB' TO '/var/opt/mssql/data/GymDB.mdf',
     MOVE 'GymDB_log' TO '/var/opt/mssql/data/GymDB_log.ldf',
     RECOVERY, CHECKSUM, STATS = 10;
GO
```

Si ya existe GymDB, detenerse y acordar con el equipo cómo conservarla; no usar REPLACE indiscriminadamente. En una instalación nativa de Windows, usar rutas accesibles al servicio de SQL Server en lugar de las rutas Linux.

### 4. Verificar los datos

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
```

| Tabla | Filas esperadas |
|---|---:|
| Socios | 500 |
| Entrenadores | 10 |
| Clases | 12 |
| Horarios | 300 |
| Reservas | 3771 |
| Pagos | 5280 |
| **Total operativo** | **9873** |

Ingresos esperados: $181,800.00. La bitácora de auditoría contiene registros adicionales.

### 5. Restablecer seguridad

Ejecutar únicamente la sección 1 de `Seguridad-datos/Seguridad.sql` para crear los logins que falten, sustituyendo los valores `CAMBIAR_LOCAL_*` de las variables `@pw_*` por contraseñas locales seguras en una copia que no se subirá a Git. No publicar credenciales activas. Después vincular los usuarios restaurados:

```sql
USE GymDB;
GO
ALTER USER usr_admin WITH LOGIN = lg_gym_admin;
ALTER USER usr_recepcion WITH LOGIN = lg_gym_recepcion;
ALTER USER usr_entrenador WITH LOGIN = lg_gym_entrenador;
ALTER USER usr_finanzas WITH LOGIN = lg_gym_finanzas;
ALTER USER usr_powerbi WITH LOGIN = lg_gym_powerbi;
ALTER USER usr_respaldos WITH LOGIN = lg_gym_respaldos;
GO
```

En una instancia dedicada al proyecto, ejecutar la sección 7 de `Seguridad.sql` para recrear `Audit_GymDB`, `SrvAuditSpec_GymDB` y `DbAuditSpec_GymDB`. Verificar el contexto `master` al iniciar la sección y utilizar `/var/opt/mssql/data/` en Docker. No recrear auditorías compartidas sin autorización. Las pruebas 8.1–8.3 comprueban permisos; la 8.4 modifica pagos de prueba, por lo que no se recomienda sobre los datos finales sin controlar sus efectos.

```sql
USE master;
SELECT name, status_desc, audit_file_path FROM sys.dm_server_audit_status;
USE GymDB;
SELECT name, is_state_enabled FROM sys.database_audit_specifications;
SELECT TOP 10 * FROM auditoria.BitacoraPagos;
```

### 6. Abrir Power BI

Abrir `PowerBI/GymAnalytics.pbix` (la versión guardada después de corregir las medidas DAX). El modo Importar permite mostrar los datos y filtros sin conexión. Para actualizar desde SQL Server: File > Options and settings > Data source settings; ajustar el origen si cambia, editar credenciales de base de datos con `lg_gym_powerbi` y su contraseña local, y pulsar Refresh. No usar `sa` para el dashboard.

Comprobar sin filtros: ingresos $181,800; 500 socios; 3771 reservas; cancelación 8.14%. Al filtrar Efectivo: $68,360. Al filtrar Yoga: 391 reservas. Los filtros de clases no modifican ingresos porque el modelo no vincula pagos directamente con clases.

### 7. Habilitar SQL Server Agent y jobs

En PowerShell, sobre el contenedor dedicado al proyecto:

```powershell
docker exec -u root sqlserver /opt/mssql/bin/mssql-conf set sqlagent.enabled true
docker restart sqlserver
```

Reconectar SSMS y comprobar:

```sql
SELECT servicename, status_desc FROM sys.dm_server_services;
```

Antes de programar los jobs, crear un respaldo completo normal en el nuevo servidor para establecer la base de los diferenciales y respaldos de log. Usar un nombre de archivo nuevo:

```sql
BACKUP DATABASE GymDB TO DISK = '/var/opt/mssql/data/GymDB_Instalacion_Full.bak'
WITH COMPRESSION, CHECKSUM, STATS = 10;
```

Crear la tabla temporal en SSMS:

```sql
USE master;
GO
IF OBJECT_ID('tempdb..#cfg') IS NOT NULL DROP TABLE #cfg;
CREATE TABLE #cfg (ruta NVARCHAR(260) NOT NULL);
INSERT INTO #cfg VALUES (N'/var/opt/mssql/data/');
GO
```

En la misma ventana y sesión, pegar y ejecutar únicamente la sección 6 de `Respaldos/Respaldos.sql`. Esta sección crea o reemplaza los tres jobs del proyecto. Los horarios corresponden al reloj del servidor.

| Job | Frecuencia |
|---|---|
| GymDB - Respaldo FULL semanal | Domingo 02:00 |
| GymDB - Respaldo DIFERENCIAL diario | Lunes a sábado 02:00 |
| GymDB - Respaldo LOG cada 30 min | Cada 30 minutos |

Probar individualmente con `sp_start_job` y esperar el éxito de cada uno antes del siguiente (FULL, DIFERENCIAL, LOG):

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo FULL semanal';
-- Ejecutar las siguientes líneas por separado tras comprobar el éxito anterior.
-- EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo DIFERENCIAL diario';
-- EXEC msdb.dbo.sp_start_job @job_name = N'GymDB - Respaldo LOG cada 30 min';
```

```sql
SELECT j.name, h.run_date, h.run_time, h.run_status, h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name LIKE N'GymDB%' AND h.step_id = 0
ORDER BY h.instance_id DESC;
```

`run_status = 1` significa ejecución exitosa. Los jobs guardan archivos con fecha y hora; planificar retención y copias fuera del contenedor para evitar agotar el disco.

## Instalación desde cero (alternativa)

Solo si no se dispone del respaldo y no existe una GymDB que deba conservarse:

1. Ejecutar `Diseño_de_la_base/GymDB.sql` y sus verificaciones iniciales (esquema dbo).
2. Ejecutar secciones 1–7 de `Seguridad-datos/Seguridad.sql`, ajustando credenciales y rutas.
3. Copiar los CSV al contenedor, por ejemplo desde la raíz del repositorio:
   ```powershell
   $dest = Join-Path $env:TEMP "GymDB_datos_unicode"
   New-Item -ItemType Directory -Force $dest | Out-Null
   Get-ChildItem "./Seguridad-datos/datos/*.csv" | ForEach-Object {
       $texto = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
       [System.IO.File]::WriteAllText((Join-Path $dest $_.Name), $texto, [System.Text.Encoding]::Unicode)
   }
   docker exec sqlserver mkdir -p /var/opt/mssql/datos_unicode
   docker cp "$dest/." sqlserver:/var/opt/mssql/datos_unicode/
   ```
   Comprobar que el servicio pueda leerlos. Ajustar `@ruta` en `Datos.sql`.
4. Ejecutar `Seguridad-datos/Datos.sql`. Advertencia: elimina los datos anteriores antes de cargarlos. El script revisado usa copias UTF-16 LE en Linux para evitar depender de CODEPAGE UTF-8 y los originales UTF-8 en Windows. Comprobar conteos y tildes tras cargar; esta modificación aún requiere una prueba real de importación.
5. Ejecutar consultas de seguridad y las seis consultas de `Consultas-optimizacion/Consultas.sql`. Crear sus seis índices adicionales; el bloque DROP INDEX quedó comentado y las creaciones comprueban si el índice ya existe.
6. Configurar respaldos y dimensionamiento con `Respaldos/Respaldos.sql`, revisando rutas y bloques de restauración antes de ejecutarlos. Crear y probar jobs según el procedimiento anterior.
7. Abrir el PBIX, configurar origen y credenciales y actualizar.

## Demostración recomendada

1. Mostrar el diagrama ER y las seis tablas operativas.
2. Demostrar conteos e integridad referencial.
3. Ejecutar una prueba de permisos y consultar la auditoría.
4. Mostrar consultas avanzadas, índices y planes de ejecución (no afirmar una mejora sin métricas comparables).
5. Mostrar historial de jobs y evidencia de restauración en GymDB_Test.
6. Abrir el dashboard y probar filtros financieros y operativos.

## Entrega y seguridad

Conservar el respaldo verificado, el PBIX corregido, scripts SQL, CSV, informe, diagrama, diccionario y evidencias. Compartir el respaldo y PBIX de forma privada si el repositorio es público; los archivos pueden contener datos y metadatos del entorno. No publicar contraseñas, logs sensibles ni credenciales. Si alguna contraseña activa fue publicada, rotarla. No utilizar el archivo experimental de Power BI anterior a la corrección de medidas.

La instalación rápida está documentada a partir de los scripts originales y las pruebas realizadas en el equipo local; aún debe probarse en la computadora de destino. El respaldo final no incluye los jobs ni los logins de servidor, y no sustituye las evidencias de la restauración de prueba. La diferencia entre SQL Server 2022 utilizado y 2025 solicitado debe comunicarse al docente.

## Objetivos y evidencias pendientes de incorporar al informe

- RPO objetivo: 30 minutos, sujeto a disponibilidad y éxito de backups LOG. RTO objetivo: 1 hora, pendiente de medición.
- Dimensionamiento: sección 2 de `Respaldos.sql` presenta las estimaciones por tabla, índices y margen del 50%; los valores históricos observados localmente fueron 72 MiB de datos y 8 MiB de log, no una garantía para otras instalaciones.
- Auditoría: `auditoria.BitacoraPagos` tiene `id_bitacora` (INT IDENTITY, PK), `id_pago` (INT, sin FK para conservar el historial de eliminaciones), `accion` (VARCHAR(10), CHECK INSERT/UPDATE/DELETE), `usuario` (SYSNAME, DEFAULT ORIGINAL_LOGIN()), `fecha_evento` (DATETIME2(0), DEFAULT SYSDATETIME()), `monto_anterior` y `monto_nuevo` (DECIMAL(10,2), admiten NULL). El trigger usa inserted/deleted. ORIGINAL_LOGIN registra el login original, no el usuario simulado por EXECUTE AS.
- Guardar evidencias reales de auditoría, comparación de IO/tiempo de las tres consultas ventana, historial de jobs, restauración y filtros Power BI. No se incluyen capturas que no estén disponibles.
- Entregar informe Word/PDF de máximo 30 páginas y presentación; no están incluidos en este ZIP. El archivo PBIX y el BAK originales se conservaron sin cambios.
- Los scripts revisados no se han ejecutado en SQL Server; probarlos en una instancia de ensayo antes de utilizar la instalación desde cero. La ruta rápida por respaldo evita volver a cargar datos.
- Si se publicaron contraseñas anteriores, cambiarlas en la instancia; retirar secretos del historial Git requiere coordinación con el equipo.
