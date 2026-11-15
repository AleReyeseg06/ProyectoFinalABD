/* ---------------------------------------------------------------------
   1. CONFIGURACIÓN
   --------------------------------------------------------------------- */
USE master;
GO

IF DB_ID(N'GymDB') IS NULL
    THROW 50001, N'No existe GymDB. Ejecutar antes GymDB.sql, Seguridad.sql y Datos.sql.', 1;
GO

-- 1.1 Ruta de respaldos (una sola vez para todo el script)
IF OBJECT_ID(N'tempdb..#cfg') IS NOT NULL DROP TABLE #cfg;
CREATE TABLE #cfg (ruta NVARCHAR(260) NOT NULL);
INSERT INTO #cfg (ruta)
VALUES (CASE WHEN @@VERSION LIKE N'%Linux%' THEN N'/var/opt/mssql/backup/'   -- << AJUSTAR si se desea otra ruta
             ELSE N'C:\Backups\GymDB\' END);
SELECT ruta AS ruta_de_respaldos FROM #cfg;
GO

-- 1.2 Crear la carpeta (el servicio de SQL Server debe tener permiso de escritura)
DECLARE @ruta NVARCHAR(260) = (SELECT ruta FROM #cfg);
BEGIN TRY
    EXEC master.dbo.xp_create_subdir @ruta;
    PRINT N'Carpeta lista: ' + @ruta;
END TRY
BEGIN CATCH
    PRINT N'No se pudo crear la carpeta (puede que ya exista): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 1.3 Modelo de recuperación FULL: necesario para respaldos de log y recuperación a un punto en el tiempo
ALTER DATABASE GymDB SET RECOVERY FULL;
ALTER DATABASE GymDB SET PAGE_VERIFY CHECKSUM;
GO

-- 1.4 Tamaño de archivos según el dimensionamiento (sección 2): 64 MB de datos y 64 MB de log,
--     crecimiento fijo de 64 MB (no en porcentaje). Los nombres lógicos se leen de la propia base.
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'ALTER DATABASE GymDB MODIFY FILE (NAME = N''' + name + N''', FILEGROWTH = 64MB);'
             + CASE WHEN size * 8 / 1024 < 64
                    THEN N'ALTER DATABASE GymDB MODIFY FILE (NAME = N''' + name + N''', SIZE = 64MB);' ELSE N'' END
FROM GymDB.sys.database_files
WHERE type IN (0, 1);
EXEC (@sql);
GO

-- Evidencia: modelo de recuperación y archivos
SELECT name, recovery_model_desc, state_desc, page_verify_option_desc
FROM sys.databases WHERE name = N'GymDB';

SELECT name AS archivo_logico, type_desc, physical_name,
       size * 8 / 1024 AS tamano_mb, growth * 8 / 1024 AS crecimiento_mb
FROM GymDB.sys.database_files;
GO

/* ---------------------------------------------------------------------
   2. DIMENSIONAMIENTO
   --------------------------------------------------------------------- */
USE GymDB;
GO

-- 2.1 Espacio real total (evidencia)
EXEC sp_spaceused;
GO

-- 2.2 Espacio real por tabla: filas, datos e índices (evidencia)
SELECT s.name + N'.' + t.name AS tabla,
       SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.row_count ELSE 0 END) AS filas,
       CAST(SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.used_page_count ELSE 0 END) * 8 / 1024.0 AS DECIMAL(10,3)) AS datos_mb,
       CAST(SUM(CASE WHEN ps.index_id > 1       THEN ps.used_page_count ELSE 0 END) * 8 / 1024.0 AS DECIMAL(10,3)) AS indices_mb,
       CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(10,3)) AS total_mb
FROM sys.dm_db_partition_stats AS ps
JOIN sys.tables  AS t ON t.object_id = ps.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
GROUP BY s.name, t.name
ORDER BY total_mb DESC;
GO

-- 2.3 Proyección del crecimiento a 0, 1, 3 y 5 años
--   Supuestos (tomados de los CSV de Datos.sql, ver Documentacion.md):
--     socios +275/año | horarios +1,040/año | reservas +17,900/año
--     pagos = 9 por socio por año (se acumulan; crecen con los socios) | bitácora = 1 fila por pago nuevo
--   bytes_fila = tamaño promedio de la fila + sus índices (incluye los de Consultas.sql) con páginas al 90 %.
--   Se parte de las filas reales actuales.
IF OBJECT_ID(N'tempdb..#proy') IS NOT NULL DROP TABLE #proy;

;WITH base AS (
    SELECT N'gym.Socios'               AS tabla, COUNT_BIG(*) AS filas, 120 AS bytes_fila FROM gym.Socios
    UNION ALL SELECT N'gym.Entrenadores',          COUNT_BIG(*),  71 FROM gym.Entrenadores
    UNION ALL SELECT N'gym.Clases',                COUNT_BIG(*),  73 FROM gym.Clases
    UNION ALL SELECT N'gym.Horarios',              COUNT_BIG(*),  99 FROM gym.Horarios
    UNION ALL SELECT N'gym.Reservas',              COUNT_BIG(*), 118 FROM gym.Reservas
    UNION ALL SELECT N'finanzas.Pagos',            COUNT_BIG(*), 102 FROM finanzas.Pagos
    UNION ALL SELECT N'auditoria.BitacoraPagos',   COUNT_BIG(*),  90 FROM auditoria.BitacoraPagos
), anios AS (
    SELECT y FROM (VALUES (0), (1), (3), (5)) AS a(y)
)
SELECT a.y AS anio, b.tabla, b.bytes_fila,
       b.filas + CAST(CASE b.tabla
                        WHEN N'gym.Socios'             THEN 275.0   * a.y
                        WHEN N'gym.Horarios'           THEN 1040.0  * a.y
                        WHEN N'gym.Reservas'           THEN 17900.0 * a.y
                        WHEN N'finanzas.Pagos'         THEN 4500.0  * a.y + 1237.5 * a.y * a.y
                        WHEN N'auditoria.BitacoraPagos' THEN 4500.0 * a.y + 1237.5 * a.y * a.y
                        ELSE 0 END AS BIGINT) AS filas_proyectadas
INTO #proy
FROM base AS b CROSS JOIN anios AS a;

-- Total por año (el archivo de datos sugerido incluye 50 % de holgura)
SELECT anio,
       CAST(SUM(filas_proyectadas * bytes_fila) / 1048576.0 AS DECIMAL(10,2))        AS datos_mas_indices_mb,
       CAST(SUM(filas_proyectadas * bytes_fila) * 1.5 / 1048576.0 AS DECIMAL(10,2))  AS con_holgura_mb
FROM #proy GROUP BY anio ORDER BY anio;

-- Detalle por tabla en el año 5
SELECT tabla, filas_proyectadas AS filas_anio_5,
       CAST(filas_proyectadas * bytes_fila / 1048576.0 AS DECIMAL(10,2)) AS mb_anio_5
FROM #proy WHERE anio = 5 ORDER BY mb_anio_5 DESC;
GO

/* ---------------------------------------------------------------------
   3. RESPALDOS (BACKUP DATABASE / BACKUP LOG)
   Secuencia: FULL -> cambio -> DIFERENCIAL -> cambio -> LOG
   Los "cambios" se hacen en dbo.PruebaRespaldo (tabla propia de la prueba),
   sin tocar los datos oficiales del gimnasio.
   Nota: COMPRESSION no está disponible en la edición Express; quitarla si falla.
   --------------------------------------------------------------------- */
USE GymDB;
GO

IF OBJECT_ID(N'dbo.PruebaRespaldo') IS NOT NULL DROP TABLE dbo.PruebaRespaldo;
CREATE TABLE dbo.PruebaRespaldo (
    id    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    etapa VARCHAR(40)  NOT NULL,
    fecha DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
INSERT INTO dbo.PruebaRespaldo (etapa) VALUES ('1 - antes del FULL');
GO

-- 3.1 RESPALDO COMPLETO
DECLARE @f NVARCHAR(300) = (SELECT ruta FROM #cfg) + N'GymDB_FULL.bak';
BACKUP DATABASE GymDB TO DISK = @f
WITH INIT, FORMAT, COMPRESSION, CHECKSUM, STATS = 10,
     NAME = N'GymDB - Respaldo completo';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;
GO

INSERT INTO dbo.PruebaRespaldo (etapa) VALUES ('2 - despues del FULL (entra en el DIFERENCIAL)');
GO

-- 3.2 RESPALDO DIFERENCIAL
DECLARE @f NVARCHAR(300) = (SELECT ruta FROM #cfg) + N'GymDB_DIFF.bak';
BACKUP DATABASE GymDB TO DISK = @f
WITH DIFFERENTIAL, INIT, FORMAT, COMPRESSION, CHECKSUM, STATS = 10,
     NAME = N'GymDB - Respaldo diferencial';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;
GO

INSERT INTO dbo.PruebaRespaldo (etapa) VALUES ('3 - despues del DIFERENCIAL (entra en el LOG)');
GO

-- 3.3 RESPALDO DEL LOG DE TRANSACCIONES
DECLARE @f NVARCHAR(300) = (SELECT ruta FROM #cfg) + N'GymDB_LOG.trn';
BACKUP LOG GymDB TO DISK = @f
WITH INIT, FORMAT, COMPRESSION, CHECKSUM, STATS = 10,
     NAME = N'GymDB - Respaldo de log';
RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;
GO

-- 3.4 Respaldo ejecutado con el login de respaldos (rol db_backupoperator, creado en Seguridad.sql)
--     COPY_ONLY: no altera la cadena de respaldos anterior.
--     Demuestra que puede respaldar pero NO leer datos.
IF SUSER_ID(N'lg_gym_respaldos') IS NULL
    PRINT N'lg_gym_respaldos no existe (falta ejecutar Seguridad.sql): se omite 3.4.';
ELSE
BEGIN
    DECLARE @f NVARCHAR(300) = (SELECT ruta FROM #cfg) + N'GymDB_FULL_copia_respaldos.bak';

    BEGIN TRY
        EXECUTE AS LOGIN = N'lg_gym_respaldos';
        BACKUP DATABASE GymDB TO DISK = @f
        WITH COPY_ONLY, INIT, FORMAT, COMPRESSION, CHECKSUM, NAME = N'GymDB - copia hecha por lg_gym_respaldos';
        REVERT;
        PRINT N'OK: lg_gym_respaldos pudo ejecutar BACKUP DATABASE.';
    END TRY
    BEGIN CATCH
        REVERT;
        PRINT N'ERROR en el respaldo con lg_gym_respaldos: ' + ERROR_MESSAGE();
    END CATCH;

    BEGIN TRY
        EXECUTE AS LOGIN = N'lg_gym_respaldos';
        SELECT TOP (1) correo FROM gym.Socios;
        REVERT;
        PRINT N'ATENCIÓN: lg_gym_respaldos pudo leer datos (revisar permisos).';
    END TRY
    BEGIN CATCH
        REVERT;
        PRINT N'OK: lg_gym_respaldos NO puede leer datos -> ' + ERROR_MESSAGE();
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------
   4. HISTORIAL DE RESPALDOS (capturar pantalla como evidencia)
   --------------------------------------------------------------------- */
USE master;
GO
SELECT TOP (10)
       bs.database_name,
       CASE bs.type WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFERENCIAL' WHEN 'L' THEN 'LOG' END AS tipo,
       bs.is_copy_only,
       bs.backup_start_date, bs.backup_finish_date,
       CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,2))            AS tamano_mb,
       CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS comprimido_mb,
       bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'GymDB'
ORDER BY bs.backup_start_date DESC;
GO

/* ---------------------------------------------------------------------
   5. RESTAURACIÓN DE PRUEBA (RESTORE DATABASE)
   Se restaura en una base NUEVA (GymDB_Test): GymDB no se toca.
   Cadena: FULL (NORECOVERY) -> DIFERENCIAL (NORECOVERY) -> LOG (RECOVERY)
   --------------------------------------------------------------------- */
USE master;
GO

-- 5.1 Contenido del respaldo (evidencia)
DECLARE @f NVARCHAR(300) = (SELECT ruta FROM #cfg) + N'GymDB_FULL.bak';
RESTORE FILELISTONLY FROM DISK = @f;
GO

-- 5.2 Limpieza por si se repite la prueba
IF DB_ID(N'GymDB_Test') IS NOT NULL
BEGIN
    ALTER DATABASE GymDB_Test SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GymDB_Test;
END
GO

-- 5.3 Restaurar la cadena completa. Los archivos van a la misma carpeta de respaldos
--     con otro nombre (MOVE), los nombres lógicos se leen de GymDB.
DECLARE @r    NVARCHAR(260) = (SELECT ruta FROM #cfg),
        @move NVARCHAR(MAX) = N'',
        @sql  NVARCHAR(MAX),
        @f    NVARCHAR(300);

SELECT @move += N'MOVE N''' + name + N''' TO N''' + @r + N'GymDB_Test'
              + CASE type WHEN 1 THEN N'_log.ldf' ELSE N'.mdf' END + N''', '
FROM sys.master_files
WHERE database_id = DB_ID(N'GymDB') AND type IN (0, 1);

-- FULL
SET @sql = N'RESTORE DATABASE GymDB_Test FROM DISK = N''' + @r + N'GymDB_FULL.bak'' WITH '
         + @move + N'NORECOVERY, STATS = 10;';
EXEC (@sql);

-- DIFERENCIAL
SET @f = @r + N'GymDB_DIFF.bak';
RESTORE DATABASE GymDB_Test FROM DISK = @f WITH NORECOVERY, STATS = 10;

-- LOG (deja la base en línea)
SET @f = @r + N'GymDB_LOG.trn';
RESTORE LOG GymDB_Test FROM DISK = @f WITH RECOVERY, STATS = 10;
GO

-- 5.4 Validación (capturar pantalla como evidencia)
SELECT name, state_desc, recovery_model_desc FROM sys.databases WHERE name IN (N'GymDB', N'GymDB_Test');
GO

DBCC CHECKDB (N'GymDB_Test') WITH NO_INFOMSGS;   -- sin filas de salida = sin errores
GO

-- Comparación original vs restaurada: filas y suma de verificación de cada tabla
IF OBJECT_ID(N'tempdb..#cmp') IS NOT NULL DROP TABLE #cmp;
CREATE TABLE #cmp (tabla NVARCHAR(128), bd SYSNAME, filas BIGINT, chk INT);

DECLARE @tablas TABLE (t NVARCHAR(128));
INSERT INTO @tablas VALUES (N'gym.Socios'), (N'gym.Entrenadores'), (N'gym.Clases'), (N'gym.Horarios'),
                           (N'gym.Reservas'), (N'finanzas.Pagos'), (N'auditoria.BitacoraPagos'), (N'dbo.PruebaRespaldo');
DECLARE @s NVARCHAR(MAX) = N'';
SELECT @s += N'INSERT #cmp SELECT N''' + t + N''', N''GymDB'', COUNT_BIG(*), CHECKSUM_AGG(CHECKSUM(*)) FROM GymDB.' + t + N';'
           + N'INSERT #cmp SELECT N''' + t + N''', N''GymDB_Test'', COUNT_BIG(*), CHECKSUM_AGG(CHECKSUM(*)) FROM GymDB_Test.' + t + N';'
FROM @tablas;
EXEC (@s);

SELECT o.tabla, o.filas AS filas_original, r.filas AS filas_restaurada,
       CASE WHEN o.filas = r.filas AND ISNULL(o.chk, 0) = ISNULL(r.chk, 0) THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM #cmp AS o
JOIN #cmp AS r ON r.tabla = o.tabla AND r.bd = N'GymDB_Test'
WHERE o.bd = N'GymDB'
ORDER BY o.tabla;
GO

-- Las 3 marcas (antes del FULL, entre FULL y DIFERENCIAL, entre DIFERENCIAL y LOG) deben estar en la copia restaurada
SELECT id, etapa, fecha FROM GymDB_Test.dbo.PruebaRespaldo ORDER BY id;
GO

/* ---------------------------------------------------------------------
   5.5 ESCENARIO DE DESASTRE (OPCIONAL, SOLO SI EL EQUIPO LO AUTORIZA)
   Restaurar SOBRE la base original GymDB. Descomentar con cuidado:

   DECLARE @r NVARCHAR(260) = (SELECT ruta FROM #cfg), @f NVARCHAR(300);
   SET @f = @r + N'GymDB_TAIL.trn';
   BACKUP LOG GymDB TO DISK = @f WITH NO_TRUNCATE, INIT;          -- cola del log: no perder transacciones
   ALTER DATABASE GymDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
   SET @f = @r + N'GymDB_FULL.bak'; RESTORE DATABASE GymDB FROM DISK = @f WITH REPLACE, NORECOVERY;
   SET @f = @r + N'GymDB_DIFF.bak'; RESTORE DATABASE GymDB FROM DISK = @f WITH NORECOVERY;
   SET @f = @r + N'GymDB_LOG.trn';  RESTORE LOG GymDB FROM DISK = @f WITH NORECOVERY;
   SET @f = @r + N'GymDB_TAIL.trn'; RESTORE LOG GymDB FROM DISK = @f WITH RECOVERY;
   ALTER DATABASE GymDB SET MULTI_USER;
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   5.6 LIMPIEZA (ejecutar DESPUÉS de capturar las pantallas)

   DROP DATABASE GymDB_Test;
   DROP TABLE GymDB.dbo.PruebaRespaldo;
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   6. AUTOMATIZACIÓN CON SQL SERVER AGENT (OPCIONAL)
      FULL: domingos 02:00 | DIFERENCIAL: lunes a sábado 02:00 | LOG: cada 30 minutos
   Se omite si SQL Server Agent no está en ejecución (en Docker se activa con
   MSSQL_AGENT_ENABLED=true; la edición Express no lo incluye).
   Cada respaldo automático lleva fecha y hora en el nombre para conservar historial.
   --------------------------------------------------------------------- */
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%' AND status_desc = N'Running')
    PRINT N'SQL Server Agent no está en ejecución: se omite la sección 6.';
ELSE
BEGIN
    DECLARE @r NVARCHAR(260) = (SELECT ruta FROM #cfg);
    DECLARE @jobs TABLE (nombre SYSNAME, nombre_corto NVARCHAR(10), extension NVARCHAR(5),
                         opciones NVARCHAR(100), sentencia NVARCHAR(60),
                         freq_type INT, freq_interval INT, subday_type INT, subday_interval INT, hora INT, programa SYSNAME);
    INSERT INTO @jobs VALUES
      (N'GymDB - Respaldo FULL semanal',       N'FULL', N'.bak', N'INIT, COMPRESSION, CHECKSUM',               N'BACKUP DATABASE GymDB', 8,   1, 0,  0, 020000, N'GymDB - Domingo 02:00'),
      (N'GymDB - Respaldo DIFERENCIAL diario', N'DIFF', N'.bak', N'DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM', N'BACKUP DATABASE GymDB', 8, 126, 0,  0, 020000, N'GymDB - Lunes a sabado 02:00'),
      (N'GymDB - Respaldo LOG cada 30 min',    N'LOG',  N'.trn', N'INIT, COMPRESSION, CHECKSUM',               N'BACKUP LOG GymDB',      4,   1, 4, 30, 000000, N'GymDB - Cada 30 minutos');

    DECLARE @nombre SYSNAME, @corto NVARCHAR(10), @ext NVARCHAR(5), @op NVARCHAR(100), @sent NVARCHAR(60),
            @ft INT, @fi INT, @st INT, @si INT, @hora INT, @prog SYSNAME, @cmd NVARCHAR(MAX);

    DECLARE cj CURSOR LOCAL FAST_FORWARD FOR
        SELECT nombre, nombre_corto, extension, opciones, sentencia, freq_type, freq_interval, subday_type, subday_interval, hora, programa FROM @jobs;
    OPEN cj;
    FETCH NEXT FROM cj INTO @nombre, @corto, @ext, @op, @sent, @ft, @fi, @st, @si, @hora, @prog;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @nombre)
            EXEC dbo.sp_delete_job @job_name = @nombre, @delete_unused_schedule = 1;

        SET @cmd = N'DECLARE @f NVARCHAR(300) = N''' + @r + N'GymDB_' + @corto + N'_'' + FORMAT(SYSDATETIME(), ''yyyyMMdd_HHmm'') + N''' + @ext + N''';'
                 + N' ' + @sent + N' TO DISK = @f WITH ' + @op + N';'
                 + CASE WHEN @corto <> N'LOG' THEN N' RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM;' ELSE N'' END;

        EXEC dbo.sp_add_job @job_name = @nombre;
        EXEC dbo.sp_add_jobstep @job_name = @nombre, @step_name = N'Respaldo', @subsystem = N'TSQL',
             @database_name = N'master', @command = @cmd;
        EXEC dbo.sp_add_schedule @schedule_name = @prog, @freq_type = @ft, @freq_interval = @fi,
             @freq_subday_type = @st, @freq_subday_interval = @si, @freq_recurrence_factor = 1, @active_start_time = @hora;
        EXEC dbo.sp_attach_schedule @job_name = @nombre, @schedule_name = @prog;
        EXEC dbo.sp_add_jobserver @job_name = @nombre;

        FETCH NEXT FROM cj INTO @nombre, @corto, @ext, @op, @sent, @ft, @fi, @st, @si, @hora, @prog;
    END
    CLOSE cj; DEALLOCATE cj;
END;
GO

-- Evidencia: jobs creados
SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'GymDB%';
GO