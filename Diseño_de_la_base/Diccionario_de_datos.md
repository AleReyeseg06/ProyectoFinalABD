# Diccionario de datos · GymDB

**Fuente:** `Diseño_de_la_base/GymDB.sql` del repositorio compartido, revisado el 14 de noviembre de 2026.

**Alcance:** seis tablas principales, 31 columnas y cinco claves foráneas. El script de creación coloca las tablas en `dbo`; posteriormente, `Seguridad-datos/Seguridad.sql` las transfiere a `gym` (cinco tablas) y `finanzas` (Pagos).

**Convenciones:** PK = clave primaria; FK = clave foránea; UQ = restricción de unicidad; *obligatorio* = `NOT NULL`; *opcional* = `NULL`.

## gym.Socios

**Objetivo:** identificar a las personas inscritas en el gimnasio.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_socio` | `INT IDENTITY(1,1)` | PK; obligatorio; número consecutivo |
| `nombre` | `VARCHAR(100)` | Obligatorio; nombre del socio |
| `apellido` | `VARCHAR(100)` | Obligatorio; apellido del socio |
| `correo` | `VARCHAR(150)` | Obligatorio; UQ_Socios_Correo |
| `telefono` | `VARCHAR(20)` | Opcional |
| `fecha_registro` | `DATE` | Obligatorio; default fecha actual |

## gym.Entrenadores

**Objetivo:** registrar a los instructores y sus especialidades.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_entrenador` | `INT IDENTITY(1,1)` | PK; obligatorio |
| `nombre` | `VARCHAR(100)` | Obligatorio |
| `apellido` | `VARCHAR(100)` | Obligatorio |
| `especialidad` | `VARCHAR(100)` | Obligatorio |
| `telefono` | `VARCHAR(20)` | Opcional |

## gym.Clases

**Objetivo:** describir las actividades disponibles y su duración.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_clase` | `INT IDENTITY(1,1)` | PK; obligatorio |
| `nombre` | `VARCHAR(100)` | Obligatorio |
| `descripcion` | `VARCHAR(255)` | Opcional |
| `duracion_minutos` | `INT` | Obligatorio; CHECK > 0 |

## gym.Horarios

**Objetivo:** programar cada sesión con fecha, hora, entrenador y cupo.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_horario` | `INT IDENTITY(1,1)` | PK; obligatorio |
| `id_clase` | `INT` | FK → Clases.id_clase; obligatorio |
| `id_entrenador` | `INT` | FK → Entrenadores.id_entrenador; obligatorio |
| `fecha` | `DATE` | Obligatorio |
| `hora_inicio` | `TIME(0)` | Obligatorio |
| `cupo_maximo` | `INT` | Obligatorio; CHECK > 0 |

## gym.Reservas

**Objetivo:** registrar las inscripciones de socios a horarios.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_reserva` | `INT IDENTITY(1,1)` | PK; obligatorio |
| `id_socio` | `INT` | FK → Socios.id_socio; obligatorio |
| `id_horario` | `INT` | FK → Horarios.id_horario; obligatorio |
| `fecha_reserva` | `DATETIME2(0)` | Obligatorio; default SYSDATETIME() |
| `estado` | `VARCHAR(20)` | Obligatorio; default Confirmada; CHECK en 3 estados |

## finanzas.Pagos

**Objetivo:** registrar ingresos asociados a socios.

| Columna | Tipo de dato | Nulabilidad y reglas |
|---|---|---|
| `id_pago` | `INT IDENTITY(1,1)` | PK; obligatorio |
| `id_socio` | `INT` | FK → Socios.id_socio; obligatorio |
| `monto` | `DECIMAL(10,2)` | Obligatorio; CHECK > 0 |
| `fecha_pago` | `DATE` | Obligatorio; default fecha actual |
| `metodo_pago` | `VARCHAR(30)` | Obligatorio |

## Relaciones (todas 1:N)

| Tabla padre | Tabla hija | Clave foránea | Campo de unión |
|---|---|---|---|
| `Clases` | `Horarios` | `FK_Horarios_Clases` | `id_clase` |
| `Entrenadores` | `Horarios` | `FK_Horarios_Entrenadores` | `id_entrenador` |
| `Socios` | `Reservas` | `FK_Reservas_Socios` | `id_socio` |
| `Horarios` | `Reservas` | `FK_Reservas_Horarios` | `id_horario` |
| `Socios` | `Pagos` | `FK_Pagos_Socios` | `id_socio` |

La relación conceptual N:M entre socios y horarios se implementa mediante `Reservas`, que tiene dos FK y una restricción única compuesta sobre `(id_socio, id_horario)`.

## Restricciones nombradas en el script

- **PK (6):** `PK_Socios`, `PK_Entrenadores`, `PK_Clases`, `PK_Horarios`, `PK_Reservas`, `PK_Pagos`.
- **FK (5):** `FK_Horarios_Clases`, `FK_Horarios_Entrenadores`, `FK_Reservas_Socios`, `FK_Reservas_Horarios`, `FK_Pagos_Socios`.
- **UQ (2):** `UQ_Socios_Correo`, `UQ_Reservas_Socio_Horario`.
- **CHECK (4):** `CK_Clases_Duracion`, `CK_Horarios_Cupo`, `CK_Reservas_Estado`, `CK_Pagos_Monto`.
- **DEFAULT (4):** `DF_Socios_FechaRegistro`, `DF_Reservas_FechaReserva`, `DF_Reservas_Estado`, `DF_Pagos_FechaPago`.

## Modelo extendido (fuera de las seis tablas principales)

`Seguridad-datos/Seguridad.sql` crea `auditoria.BitacoraPagos` (`id_bitacora`, `id_pago`, `accion`, `usuario`, `fecha_evento`, `monto_anterior`, `monto_nuevo`) y un trigger sobre `finanzas.Pagos`. En el script no existe una FK entre bitácora y pagos; se registra el identificador del pago como referencia histórica.

## Reglas que el modelo NO garantiza por sí solo

- `cupo_maximo > 0` está validado, pero no hay un trigger o procedimiento en `GymDB.sql` que impida insertar más reservas confirmadas que el cupo.
- No existe una tabla de membresías o vigencia de suscripción.
- El estado de la reserva está restringido a `Confirmada`, `Cancelada` y `Completada`; no se valida automáticamente la fecha de una reserva respecto del horario.
- Los índices de rendimiento y los permisos pertenecen a otros integrantes, no al script DDL original.

## Nota de integridad

Las filas preparadas en los CSV son 500 Socios, 10 Entrenadores, 12 Clases, 300 Horarios, 3,771 Reservas y 5,280 Pagos. Son archivos de origen, no evidencia de importación efectiva a SQL Server.

