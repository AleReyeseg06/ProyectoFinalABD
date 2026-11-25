use master;
GO

create database GymDB;

use GymDB;
GO

CREATE TABLE dbo.Socios (id_socio INT IDENTITY(1,1) NOT NULL,
nombre VARCHAR(100) NOT NULL, apellido VARCHAR(100) NOT NULL, correo VARCHAR(150) NOT NULL,
telefono VARCHAR(20) NULL, fecha_registro DATE NOT NULL CONSTRAINT DF_Socios_FechaRegistro DEFAULT (CONVERT(DATE, GETDATE())),
CONSTRAINT PK_Socios PRIMARY KEY (id_socio), CONSTRAINT UQ_Socios_Correo UNIQUE (correo)
);

CREATE TABLE dbo.Entrenadores (id_entrenador INT IDENTITY(1,1) NOT NULL,
nombre VARCHAR(100) NOT NULL, apellido VARCHAR(100) NOT NULL, especialidad VARCHAR(100) NOT NULL,
telefono VARCHAR(20) NULL, CONSTRAINT PK_Entrenadores PRIMARY KEY (id_entrenador)
);

CREATE TABLE dbo.Clases (id_clase INT IDENTITY(1,1) NOT NULL, nombre VARCHAR(100) NOT NULL, 
descripcion VARCHAR(255) NULL, duracion_minutos INT NOT NULL,
CONSTRAINT PK_Clases PRIMARY KEY (id_clase),CONSTRAINT CK_Clases_Duracion CHECK (duracion_minutos > 0)
);

CREATE TABLE dbo.Horarios (id_horario INT IDENTITY(1,1) NOT NULL,
id_clase INT NOT NULL, id_entrenador INT NOT NULL, fecha DATE NOT NULL,
hora_inicio TIME(0) NOT NULL, cupo_maximo INT NOT NULL,
CONSTRAINT PK_Horarios PRIMARY KEY (id_horario),
CONSTRAINT FK_Horarios_Clases FOREIGN KEY (id_clase) REFERENCES dbo.Clases(id_clase),
CONSTRAINT FK_Horarios_Entrenadores FOREIGN KEY (id_entrenador) REFERENCES dbo.Entrenadores(id_entrenador),
CONSTRAINT CK_Horarios_Cupo CHECK (cupo_maximo > 0)
);

CREATE TABLE dbo.Reservas (id_reserva INT IDENTITY(1,1) NOT NULL, id_socio INT NOT NULL,
id_horario INT NOT NULL, fecha_reserva DATETIME2(0) NOT NULL CONSTRAINT DF_Reservas_FechaReserva DEFAULT (SYSDATETIME()),
estado VARCHAR(20) NOT NULL CONSTRAINT DF_Reservas_Estado DEFAULT ('Confirmada'),
CONSTRAINT PK_Reservas PRIMARY KEY (id_reserva),
CONSTRAINT FK_Reservas_Socios FOREIGN KEY (id_socio) REFERENCES dbo.Socios(id_socio),
CONSTRAINT FK_Reservas_Horarios FOREIGN KEY (id_horario) REFERENCES dbo.Horarios(id_horario),
CONSTRAINT UQ_Reservas_Socio_Horario UNIQUE (id_socio, id_horario),
CONSTRAINT CK_Reservas_Estado CHECK (estado IN ('Confirmada', 'Cancelada', 'Completada'))
);

CREATE TABLE dbo.Pagos (id_pago INT IDENTITY(1,1) NOT NULL, id_socio INT NOT NULL,
monto DECIMAL(10,2) NOT NULL, fecha_pago DATE NOT NULL CONSTRAINT DF_Pagos_FechaPago DEFAULT (CONVERT(DATE, GETDATE())),
metodo_pago VARCHAR(30) NOT NULL,
CONSTRAINT PK_Pagos PRIMARY KEY (id_pago),
CONSTRAINT FK_Pagos_Socios FOREIGN KEY (id_socio) REFERENCES dbo.Socios(id_socio),
CONSTRAINT CK_Pagos_Monto CHECK (monto > 0)
);

--Comprobacion de tablas
SELECT t.name AS tabla
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID(N'dbo') AND t.name IN (N'Socios', N'Entrenadores', N'Clases', N'Horarios', N'Reservas', N'Pagos')
ORDER BY t.name;
GO

SELECT fk.name AS clave_foranea,
OBJECT_NAME(fk.parent_object_id) AS tabla_origen,
OBJECT_NAME(fk.referenced_object_id) AS tabla_referenciada
FROM sys.foreign_keys AS fk
WHERE fk.parent_object_id IN (
    OBJECT_ID(N'dbo.Horarios'),
    OBJECT_ID(N'dbo.Reservas'),
    OBJECT_ID(N'dbo.Pagos')
)
ORDER BY tabla_origen, clave_foranea;