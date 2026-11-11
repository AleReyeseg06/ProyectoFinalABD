
/* =====================================================================
   Ejecutar DESPUÉS de Seguridad.sql
 
   Antes de ejecutar:
   1) Copiar la carpeta datos\ (6 CSV) a una ruta que el SERVICIO de SQL Server pueda leer,
      p. ej. C:\GymDB\datos\ . Si SQL Server corre en otra máquina/contenedor, la ruta es
      la de ESA máquina.
   2) Ajustar @ruta (con "\" final) en la sección 1.
   3) Ejecutar con un login sysadmin (BULK INSERT requiere ADMINISTER BULK OPERATIONS).
   ===================================================================== */
USE GymDB;
go
 
SET NOCOUNT ON;
SET XACT_ABORT ON;
go

DECLARE @ruta NVARCHAR(260) = N'/var/opt/mssql/datos/';   -- << AJUSTAR
 
/* ---------------------------------------------------------------------
   1. CARGA (en una sola transacción: o entra todo o no entra nada)
   Orden: primero tablas padre, luego tablas con claves foráneas.
   CHECK_CONSTRAINTS hace que BULK INSERT valide FK y CHECK durante la carga.
   Los triggers se desactivan para no llenar la bitácora con la carga masiva.
   --------------------------------------------------------------------- */
BEGIN TRY
    BEGIN TRAN;
 
    -- 1.1 Limpieza (permite re-ejecutar el script): hijas primero
    ALTER TABLE finanzas.Pagos DISABLE TRIGGER ALL;
    DELETE FROM finanzas.Pagos;
    DELETE FROM gym.Reservas;
    DELETE FROM gym.Horarios;
    DELETE FROM gym.Clases;
    DELETE FROM gym.Entrenadores;
    DELETE FROM gym.Socios;
    DBCC CHECKIDENT (N'finanzas.Pagos',    RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT (N'gym.Reservas',      RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT (N'gym.Horarios',      RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT (N'gym.Clases',        RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT (N'gym.Entrenadores',  RESEED, 0) WITH NO_INFOMSGS;
    DBCC CHECKIDENT (N'gym.Socios',        RESEED, 0) WITH NO_INFOMSGS;
 
    -- 1.2 Carga: tabla destino y archivo en el mismo orden de dependencias
    DECLARE @cargas TABLE (orden INT, tabla NVARCHAR(128), archivo NVARCHAR(60));
    INSERT INTO @cargas VALUES
        (1, N'gym.Socios',       N'socios.csv'),
        (2, N'gym.Entrenadores', N'entrenadores.csv'),
        (3, N'gym.Clases',       N'clases.csv'),
        (4, N'gym.Horarios',     N'horarios.csv'),
        (5, N'gym.Reservas',     N'reservas.csv'),
        (6, N'finanzas.Pagos',   N'pagos.csv');
 
    DECLARE @sql NVARCHAR(MAX), @tabla NVARCHAR(128), @archivo NVARCHAR(60);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tabla, archivo FROM @cargas ORDER BY orden;
    OPEN c; FETCH NEXT FROM c INTO @tabla, @archivo;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'BULK INSERT ' + @tabla + N' FROM ''' + @ruta + @archivo + N''' WITH (
                        FORMAT = ''CSV'', FIRSTROW = 2,FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0d0a'',
                        KEEPIDENTITY, KEEPNULLS, CHECK_CONSTRAINTS, TABLOCK);';
        EXEC sys.sp_executesql @sql;
        PRINT N'Cargado: ' + @tabla + N' <- ' + @archivo;
        FETCH NEXT FROM c INTO @tabla, @archivo;
    END
    CLOSE c; DEALLOCATE c;
 
    ALTER TABLE finanzas.Pagos ENABLE TRIGGER ALL;
    COMMIT TRAN;
    PRINT N'*** Carga completada correctamente ***';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT N'*** ERROR en la carga, se revirtió todo: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO
 
/* ---------------------------------------------------------------------
   2. VALIDACIÓN DE LA CARGA (capturar pantalla como evidencia)
   --------------------------------------------------------------------- */
-- 2.1 Conteo de filas vs. lo esperado en los CSV
SELECT x.tabla, x.filas_cargadas, x.filas_esperadas,
       CASE WHEN x.filas_cargadas = x.filas_esperadas THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM (
    SELECT N'gym.Socios' AS tabla,       (SELECT COUNT(*) FROM gym.Socios)       AS filas_cargadas, 500  AS filas_esperadas UNION ALL
    SELECT N'gym.Entrenadores',          (SELECT COUNT(*) FROM gym.Entrenadores), 10   UNION ALL
    SELECT N'gym.Clases',                (SELECT COUNT(*) FROM gym.Clases),       12   UNION ALL
    SELECT N'gym.Horarios',              (SELECT COUNT(*) FROM gym.Horarios),     300  UNION ALL
    SELECT N'gym.Reservas',              (SELECT COUNT(*) FROM gym.Reservas),     3771 UNION ALL
    SELECT N'finanzas.Pagos',            (SELECT COUNT(*) FROM finanzas.Pagos),   5280
) AS x;
 
-- 2.2 Integridad referencial: todas deben devolver 0
SELECT 'Horarios sin clase'        AS control, COUNT(*) AS huerfanos FROM gym.Horarios h  LEFT JOIN gym.Clases c       ON c.id_clase = h.id_clase           WHERE c.id_clase IS NULL
UNION ALL SELECT 'Horarios sin entrenador',   COUNT(*) FROM gym.Horarios h  LEFT JOIN gym.Entrenadores e ON e.id_entrenador = h.id_entrenador WHERE e.id_entrenador IS NULL
UNION ALL SELECT 'Reservas sin socio',        COUNT(*) FROM gym.Reservas r  LEFT JOIN gym.Socios s        ON s.id_socio = r.id_socio           WHERE s.id_socio IS NULL
UNION ALL SELECT 'Reservas sin horario',      COUNT(*) FROM gym.Reservas r  LEFT JOIN gym.Horarios h      ON h.id_horario = r.id_horario       WHERE h.id_horario IS NULL
UNION ALL SELECT 'Pagos sin socio',           COUNT(*) FROM finanzas.Pagos p LEFT JOIN gym.Socios s       ON s.id_socio = p.id_socio           WHERE s.id_socio IS NULL;
 
-- 2.3 Regla de negocio: reservas activas por horario no deben superar el cupo (debe devolver 0 filas)
SELECT h.id_horario, h.cupo_maximo, COUNT(*) AS reservas_activas
FROM gym.Horarios h
JOIN gym.Reservas r ON r.id_horario = h.id_horario AND r.estado <> 'Cancelada'
GROUP BY h.id_horario, h.cupo_maximo
HAVING COUNT(*) > h.cupo_maximo;
 
-- 2.4 Restricciones confiables (is_not_trusted debe ser 0)
SELECT OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) AS tabla,
       name AS restriccion, is_not_trusted
FROM sys.foreign_keys
UNION ALL
SELECT OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id), name, is_not_trusted
FROM sys.check_constraints
ORDER BY 1, 2;
 
-- 2.5 Muestras y distribución de los datos
SELECT estado, COUNT(*) AS reservas FROM gym.Reservas GROUP BY estado ORDER BY reservas DESC;
SELECT metodo_pago, COUNT(*) AS pagos, SUM(monto) AS total FROM finanzas.Pagos GROUP BY metodo_pago ORDER BY total DESC;
SELECT YEAR(fecha_pago) AS anio, MONTH(fecha_pago) AS mes, SUM(monto) AS ingresos
FROM finanzas.Pagos GROUP BY YEAR(fecha_pago), MONTH(fecha_pago) ORDER BY anio, mes;
GO