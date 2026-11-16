/* =====================================================================
   VERIFICACION DE ESTRUCTURA - GymDB (SOLO LECTURA)
   Compatible con la etapa dbo (inicial) y gym/finanzas (integrada).
   No borra, inserta ni modifica registros.
   Ejecutar en SQL Server Management Studio después de crear la BD.
   ===================================================================== */
USE GymDB;
GO
SET NOCOUNT ON;

PRINT '1) Ubicacion de las seis tablas esperadas';
WITH esperadas AS (
 SELECT v.tabla, v.esquema_final
 FROM (VALUES
  ('Socios','gym'), ('Entrenadores','gym'), ('Clases','gym'),
  ('Horarios',N'gym'), ('Reservas','gym'), ('Pagos','finanzas')
 ) v(tabla,esquema_final)
)
SELECT e.tabla, COALESCE(s.name, 'NO ENCONTRADA') AS esquema_actual,
       e.esquema_final,
       CASE WHEN s.name='dbo' THEN 'ETAPA INICIAL'
            WHEN s.name=e.esquema_final THEN 'ETAPA INTEGRADA'
            ELSE 'REVISAR' END AS estado
FROM esperadas e
OUTER APPLY (
    SELECT TOP (1) x.name FROM sys.tables t
    JOIN sys.schemas x ON x.schema_id=t.schema_id
    WHERE t.name=e.tabla AND x.name IN ('dbo','gym','finanzas')
    ORDER BY CASE WHEN x.name=e.esquema_final THEN 0 ELSE 1 END
) s
ORDER BY e.tabla;

PRINT '2) Conteos: se esperan seis PK, cinco FK y 31 columnas';
;WITH principales AS (
 SELECT t.object_id FROM sys.tables t
 JOIN sys.schemas s ON s.schema_id=t.schema_id
 WHERE t.name IN ('Socios','Entrenadores','Clases','Horarios','Reservas','Pagos')
   AND s.name IN ('dbo','gym','finanzas')
)
SELECT (SELECT COUNT(*) FROM principales) AS tablas,
       (SELECT COUNT(*) FROM sys.columns c JOIN principales p ON c.object_id=p.object_id) AS columnas,
       (SELECT COUNT(*) FROM sys.key_constraints k JOIN principales p ON k.parent_object_id=p.object_id WHERE k.type='PK') AS claves_primarias,
       (SELECT COUNT(*) FROM sys.foreign_keys f JOIN principales p ON f.parent_object_id=p.object_id) AS claves_foraneas,
       (SELECT COUNT(*) FROM sys.check_constraints c JOIN principales p ON c.parent_object_id=p.object_id) AS restricciones_check,
       (SELECT COUNT(*) FROM sys.key_constraints k JOIN principales p ON k.parent_object_id=p.object_id WHERE k.type='UQ') AS restricciones_unique,
       (SELECT COUNT(*) FROM sys.default_constraints d JOIN principales p ON d.parent_object_id=p.object_id) AS restricciones_default;

PRINT '3) Claves foraneas (se esperan cinco filas)';
SELECT fk.name AS fk,
       OBJECT_SCHEMA_NAME(fk.parent_object_id)+'.'+OBJECT_NAME(fk.parent_object_id) AS tabla_hija,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id)+'.'+OBJECT_NAME(fk.referenced_object_id) AS tabla_padre,
       fk.is_disabled, fk.is_not_trusted
FROM sys.foreign_keys fk
WHERE OBJECT_NAME(fk.parent_object_id) IN ('Horarios','Reservas','Pagos')
ORDER BY tabla_hija,fk;

PRINT '4) Restricciones de negocio (cuatro CHECK y dos UNIQUE)';
SELECT OBJECT_SCHEMA_NAME(c.parent_object_id)+'.'+OBJECT_NAME(c.parent_object_id) AS tabla,
       c.name, c.definition, c.is_disabled, c.is_not_trusted
FROM sys.check_constraints c
WHERE OBJECT_NAME(c.parent_object_id) IN ('Clases','Horarios','Reservas','Pagos')
ORDER BY tabla,c.name;
SELECT OBJECT_SCHEMA_NAME(k.parent_object_id)+'.'+OBJECT_NAME(k.parent_object_id) AS tabla,
       k.name, k.type_desc
FROM sys.key_constraints k
WHERE k.type='UQ' AND OBJECT_NAME(k.parent_object_id) IN ('Socios','Reservas');

PRINT '5) Esquemas: gym, finanzas, auditoria si Seguridad.sql ya se ejecuto';
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.name IN ('Socios','Entrenadores','Clases','Horarios','Reservas','Pagos','BitacoraPagos')
ORDER BY s.name,t.name;

-- Para validar conteos importados y huérfanos, ejecutar la sección 2
-- de Seguridad-datos/Datos.sql DESPUÉS de la carga de los CSV.
