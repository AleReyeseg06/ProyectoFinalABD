/* =====================================================================
   Ejecutar DESPUÉS de GymBD.sql y ANTES de Datos.sql
   Requiere: sesión con rol sysadmin.
   Antes de ejecutar: crear la carpeta C:\SQLAudit\ y cambia la ruta en
   el script
   En caso de ejecutar en docker dejar en /var/opt/mssql/data/ en 7.2
   ===================================================================== */
 
/* ---------------------------------------------------------------------
   1. LOGINS
   --------------------------------------------------------------------- */
USE master;
GO
 
IF SUSER_ID(N'lg_gym_admin') IS NULL
    CREATE LOGIN lg_gym_admin     WITH PASSWORD = N'Gym#Admin2026!',  DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
IF SUSER_ID(N'lg_gym_recepcion') IS NULL
    CREATE LOGIN lg_gym_recepcion WITH PASSWORD = N'Gym#Recep2026!',  DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
IF SUSER_ID(N'lg_gym_entrenador') IS NULL
    CREATE LOGIN lg_gym_entrenador WITH PASSWORD = N'Gym#Entre2026!', DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
IF SUSER_ID(N'lg_gym_finanzas') IS NULL
    CREATE LOGIN lg_gym_finanzas  WITH PASSWORD = N'Gym#Finan2026!',  DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
IF SUSER_ID(N'lg_gym_powerbi') IS NULL
    CREATE LOGIN lg_gym_powerbi   WITH PASSWORD = N'Gym#PowerBI2026!', DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
IF SUSER_ID(N'lg_gym_respaldos') IS NULL
    CREATE LOGIN lg_gym_respaldos WITH PASSWORD = N'Gym#Backup2026!', DEFAULT_DATABASE = GymDB, CHECK_EXPIRATION = OFF, CHECK_POLICY = ON;
GO
 
/* ---------------------------------------------------------------------
   2. ESQUEMAS
   gym       -> datos operativos (socios, entrenadores, clases, horarios, reservas)
   finanzas  -> información económica (pagos). Permite aislar permisos del personal
                que no debe ver dinero (entrenadores) con un solo DENY.
   auditoria -> bitácoras. Solo lectura para el administrador.
   dbo       -> queda reservado para objetos del sistema.
   NOTA: los scripts de los demás integrantes deben usar gym.Socios, finanzas.Pagos, etc.
   --------------------------------------------------------------------- */
USE GymDB;
GO
 
IF SCHEMA_ID(N'gym')       IS NULL EXEC(N'CREATE SCHEMA gym AUTHORIZATION dbo');
IF SCHEMA_ID(N'finanzas')  IS NULL EXEC(N'CREATE SCHEMA finanzas AUTHORIZATION dbo');
IF SCHEMA_ID(N'auditoria') IS NULL EXEC(N'CREATE SCHEMA auditoria AUTHORIZATION dbo');
GO
 
-- Mover las tablas creadas en dbo (las FK, PK y constraints se conservan)
IF OBJECT_ID(N'dbo.Socios')       IS NOT NULL ALTER SCHEMA gym      TRANSFER dbo.Socios;
IF OBJECT_ID(N'dbo.Entrenadores') IS NOT NULL ALTER SCHEMA gym      TRANSFER dbo.Entrenadores;
IF OBJECT_ID(N'dbo.Clases')       IS NOT NULL ALTER SCHEMA gym      TRANSFER dbo.Clases;
IF OBJECT_ID(N'dbo.Horarios')     IS NOT NULL ALTER SCHEMA gym      TRANSFER dbo.Horarios;
IF OBJECT_ID(N'dbo.Reservas')     IS NOT NULL ALTER SCHEMA gym      TRANSFER dbo.Reservas;
IF OBJECT_ID(N'dbo.Pagos')        IS NOT NULL ALTER SCHEMA finanzas TRANSFER dbo.Pagos;
GO
 
-- Comprobación de esquemas
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name IN (N'gym', N'finanzas', N'auditoria', N'dbo')
ORDER BY s.name, t.name;
GO
 
/* ---------------------------------------------------------------------
   3. USUARIOS DE BASE DE DATOS
   --------------------------------------------------------------------- */
IF USER_ID(N'usr_admin')     IS NULL CREATE USER usr_admin     FOR LOGIN lg_gym_admin     WITH DEFAULT_SCHEMA = gym;
IF USER_ID(N'usr_recepcion') IS NULL CREATE USER usr_recepcion FOR LOGIN lg_gym_recepcion WITH DEFAULT_SCHEMA = gym;
IF USER_ID(N'usr_entrenador') IS NULL CREATE USER usr_entrenador FOR LOGIN lg_gym_entrenador WITH DEFAULT_SCHEMA = gym;
IF USER_ID(N'usr_finanzas')  IS NULL CREATE USER usr_finanzas  FOR LOGIN lg_gym_finanzas  WITH DEFAULT_SCHEMA = finanzas;
IF USER_ID(N'usr_powerbi')   IS NULL CREATE USER usr_powerbi   FOR LOGIN lg_gym_powerbi   WITH DEFAULT_SCHEMA = gym;
IF USER_ID(N'usr_respaldos') IS NULL CREATE USER usr_respaldos FOR LOGIN lg_gym_respaldos WITH DEFAULT_SCHEMA = gym;
GO
 
/* ---------------------------------------------------------------------
   4. ROLES POR FUNCIÓN (principio de mínimo privilegio)
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'rol_gym_admin')  IS NULL CREATE ROLE rol_gym_admin;
IF DATABASE_PRINCIPAL_ID(N'rol_recepcion')  IS NULL CREATE ROLE rol_recepcion;
IF DATABASE_PRINCIPAL_ID(N'rol_entrenador') IS NULL CREATE ROLE rol_entrenador;
IF DATABASE_PRINCIPAL_ID(N'rol_finanzas')   IS NULL CREATE ROLE rol_finanzas;
IF DATABASE_PRINCIPAL_ID(N'rol_analista_bi') IS NULL CREATE ROLE rol_analista_bi;
GO
 
/* ---------------------------------------------------------------------
   5. PERMISOS
   --------------------------------------------------------------------- */
 
-- 5.1 Administrador del gimnasio: control total de sus esquemas
--     y lectura de la bitácora de auditoría.
GRANT CONTROL ON SCHEMA::gym      TO rol_gym_admin;
GRANT CONTROL ON SCHEMA::finanzas TO rol_gym_admin;
GRANT SELECT  ON SCHEMA::auditoria TO rol_gym_admin;
 
-- 5.2 Recepción: registra socios, gestiona reservas y cobra membresías. No borra nada.
GRANT SELECT, INSERT, UPDATE ON gym.Socios   TO rol_recepcion;
GRANT SELECT, INSERT, UPDATE ON gym.Reservas TO rol_recepcion;
GRANT SELECT ON gym.Clases       TO rol_recepcion;
GRANT SELECT ON gym.Horarios     TO rol_recepcion;
GRANT SELECT ON gym.Entrenadores TO rol_recepcion;
GRANT SELECT, INSERT ON finanzas.Pagos TO rol_recepcion;      -- registra pagos pero no los modifica
DENY  DELETE ON SCHEMA::gym      TO rol_recepcion;
DENY  DELETE ON SCHEMA::finanzas TO rol_recepcion;
 
-- 5.3 Entrenador: consulta horarios y asistentes; solo marca el estado de la reserva.
--     Del socio solo ve nombre y apellido (sin correo ni teléfono). Sin acceso a finanzas.
GRANT SELECT ON gym.Clases       TO rol_entrenador;
GRANT SELECT ON gym.Horarios     TO rol_entrenador;
GRANT SELECT ON gym.Entrenadores (id_entrenador, nombre, apellido, especialidad) TO rol_entrenador;
GRANT SELECT ON gym.Reservas     TO rol_entrenador;
GRANT UPDATE ON gym.Reservas (estado) TO rol_entrenador;
GRANT SELECT ON gym.Socios (id_socio, nombre, apellido) TO rol_entrenador;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::finanzas TO rol_entrenador;
 
-- 5.4 Finanzas: gestiona pagos; del socio solo necesita identificarlo.
GRANT SELECT, INSERT, UPDATE ON finanzas.Pagos TO rol_finanzas;
GRANT SELECT ON gym.Socios (id_socio, nombre, apellido, correo) TO rol_finanzas;
DENY  DELETE ON SCHEMA::finanzas TO rol_finanzas;
 
-- 5.5 Analista BI (Power BI): solo lectura, sin datos de contacto del socio.
--     En Power BI se deben seleccionar columnas explícitas de gym.Socios (no SELECT *).
GRANT SELECT ON SCHEMA::gym      TO rol_analista_bi;
GRANT SELECT ON SCHEMA::finanzas TO rol_analista_bi;
DENY  SELECT ON gym.Socios (correo, telefono) TO rol_analista_bi;
DENY  SELECT ON SCHEMA::auditoria TO rol_analista_bi;
 
-- 5.6 Respaldos: rol fijo de BD que solo permite BACKUP (sin leer datos).
-- (se asigna abajo con ALTER ROLE db_backupoperator)
 
-- Asignación de usuarios a roles
ALTER ROLE rol_gym_admin     ADD MEMBER usr_admin;
ALTER ROLE rol_recepcion     ADD MEMBER usr_recepcion;
ALTER ROLE rol_entrenador    ADD MEMBER usr_entrenador;
ALTER ROLE rol_finanzas      ADD MEMBER usr_finanzas;
ALTER ROLE rol_analista_bi   ADD MEMBER usr_powerbi;
ALTER ROLE db_backupoperator ADD MEMBER usr_respaldos;
GO
 
/* ---------------------------------------------------------------------
   6. BITÁCORA POR TRIGGER (esquema auditoria) - historial de cambios en pagos
   Los pagos son el dato más sensible; se guarda quién, cuándo y qué cambió.
   El trigger escribe en auditoria por encadenamiento de propiedad (mismo dueño: dbo),
   por lo que los usuarios no necesitan permisos sobre el esquema auditoria.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'auditoria.BitacoraPagos') IS NULL
CREATE TABLE auditoria.BitacoraPagos (
    id_bitacora     INT IDENTITY(1,1) NOT NULL,
    id_pago         INT           NOT NULL,
    accion          VARCHAR(10)   NOT NULL,
    usuario         SYSNAME       NOT NULL CONSTRAINT DF_BitPagos_Usuario DEFAULT (ORIGINAL_LOGIN()),
    fecha_evento    DATETIME2(0)  NOT NULL CONSTRAINT DF_BitPagos_Fecha   DEFAULT (SYSDATETIME()),
    monto_anterior  DECIMAL(10,2) NULL,
    monto_nuevo     DECIMAL(10,2) NULL,
    CONSTRAINT PK_BitacoraPagos PRIMARY KEY (id_bitacora),
    CONSTRAINT CK_BitPagos_Accion CHECK (accion IN ('INSERT','UPDATE','DELETE'))
);
GO
 
CREATE OR ALTER TRIGGER finanzas.trg_Pagos_Auditoria
ON finanzas.Pagos
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO auditoria.BitacoraPagos (id_pago, accion, monto_anterior, monto_nuevo)
    SELECT COALESCE(i.id_pago, d.id_pago),
           CASE WHEN i.id_pago IS NOT NULL AND d.id_pago IS NOT NULL THEN 'UPDATE'
                WHEN i.id_pago IS NOT NULL THEN 'INSERT' ELSE 'DELETE' END,
           d.monto, i.monto
    FROM inserted i FULL OUTER JOIN deleted d ON i.id_pago = d.id_pago;
END;
GO
 
/* ---------------------------------------------------------------------
   7. AUDITORÍA DE SQL SERVER (SQL Server Audit)
   Archivo de auditoría en C:\SQLAudit\ (la carpeta debe existir y el servicio de
   SQL Server debe tener permiso de escritura).
   --------------------------------------------------------------------- */
USE master;
GO
 
-- 7.1 Limpieza para poder re-ejecutar el script
IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'SrvAuditSpec_GymDB')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION SrvAuditSpec_GymDB WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION SrvAuditSpec_GymDB;
END;
GO
USE GymDB;
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'DbAuditSpec_GymDB')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION DbAuditSpec_GymDB WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION DbAuditSpec_GymDB;
END;
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Audit_GymDB')
BEGIN
    ALTER SERVER AUDIT Audit_GymDB WITH (STATE = OFF);
    DROP SERVER AUDIT Audit_GymDB;
END;
GO
 
-- 7.2 Auditoría de servidor (destino: archivo)
CREATE SERVER AUDIT Audit_GymDB
TO FILE (FILEPATH = N'/var/opt/mssql/data/', MAXSIZE = 50 MB, MAX_ROLLOVER_FILES = 10, RESERVE_DISK_SPACE = OFF)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO
ALTER SERVER AUDIT Audit_GymDB WITH (STATE = ON);
GO
 
-- 7.3 Especificación a nivel servidor: accesos fallidos y cambios en logins/roles de servidor
CREATE SERVER AUDIT SPECIFICATION SrvAuditSpec_GymDB
FOR SERVER AUDIT Audit_GymDB
    ADD (FAILED_LOGIN_GROUP),
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
    ADD (LOGIN_CHANGE_PASSWORD_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
GO
 
-- 7.4 Especificación a nivel base de datos
USE GymDB;
GO
CREATE DATABASE AUDIT SPECIFICATION DbAuditSpec_GymDB
FOR SERVER AUDIT Audit_GymDB
    ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::finanzas BY public),   -- toda operación sobre pagos
    ADD (INSERT, UPDATE, DELETE ON OBJECT::gym.Socios BY public),         -- cambios en datos personales
    ADD (DELETE ON OBJECT::gym.Reservas BY public),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),            -- CREATE/ALTER/DROP de objetos
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),     -- cambios de miembros en roles
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),      -- GRANT/DENY/REVOKE
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP)        -- CREATE/ALTER/DROP de usuarios y roles
WITH (STATE = ON);
GO