USE GymDB;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- 1. JOIN + GROUP BY: ocupacion de cada horario (cupo, reservas activas y cupos libres)
SELECT h.id_horario,
       c.nombre                            AS clase,
       CONCAT(e.nombre, ' ', e.apellido)   AS entrenador,
       h.fecha,
       h.hora_inicio,
       h.cupo_maximo,
       COUNT(r.id_reserva)                 AS reservas_activas,
       h.cupo_maximo - COUNT(r.id_reserva) AS cupos_libres
FROM gym.Horarios      AS h
JOIN gym.Clases        AS c ON c.id_clase = h.id_clase
JOIN gym.Entrenadores  AS e ON e.id_entrenador = h.id_entrenador
LEFT JOIN gym.Reservas AS r ON r.id_horario = h.id_horario AND r.estado <> 'Cancelada'
GROUP BY h.id_horario, c.nombre, e.nombre, e.apellido, h.fecha, h.hora_inicio, h.cupo_maximo
ORDER BY h.fecha, h.hora_inicio;
GO


-- 2. Subconsulta: socios cuyo total pagado supera el promedio por socio
SELECT s.id_socio,
       CONCAT(s.nombre, ' ', s.apellido) AS socio,
       t.total_pagado
FROM gym.Socios AS s
JOIN (SELECT id_socio, SUM(monto) AS total_pagado
      FROM finanzas.Pagos
      GROUP BY id_socio) AS t ON t.id_socio = s.id_socio
WHERE t.total_pagado > (SELECT AVG(x.total)
                        FROM (SELECT SUM(monto) AS total
                              FROM finanzas.Pagos
                              GROUP BY id_socio) AS x)
ORDER BY t.total_pagado DESC;
GO

-- 3. ROW_NUMBER: ultimo pago de cada socio
SELECT id_socio, id_pago, fecha_pago, monto, metodo_pago
FROM (SELECT p.id_socio, p.id_pago, p.fecha_pago, p.monto, p.metodo_pago,
             ROW_NUMBER() OVER (PARTITION BY p.id_socio
                                ORDER BY p.fecha_pago DESC, p.id_pago DESC) AS rn
      FROM finanzas.Pagos AS p) AS x
WHERE rn = 1
ORDER BY id_socio;
GO

-- 4. RANK: top 3 clases de cada entrenador segun reservas completadas
SELECT id_entrenador, entrenador, clase, completadas, posicion
FROM (SELECT e.id_entrenador,
             CONCAT(e.nombre, ' ', e.apellido) AS entrenador,
             c.nombre                          AS clase,
             COUNT(*)                          AS completadas,
             RANK() OVER (PARTITION BY e.id_entrenador ORDER BY COUNT(*) DESC) AS posicion
      FROM gym.Reservas     AS r
      JOIN gym.Horarios     AS h ON h.id_horario = r.id_horario
      JOIN gym.Clases       AS c ON c.id_clase = h.id_clase
      JOIN gym.Entrenadores AS e ON e.id_entrenador = h.id_entrenador
      WHERE r.estado = 'Completada'
      GROUP BY e.id_entrenador, e.nombre, e.apellido, c.nombre) AS x
WHERE posicion <= 3
ORDER BY id_entrenador, posicion;
GO

-- 5. SUM() OVER: ingresos por mes, acumulado del anio y porcentaje sobre el total del anio
WITH mensual AS (
    SELECT YEAR(fecha_pago) AS anio, MONTH(fecha_pago) AS mes, SUM(monto) AS ingresos
    FROM finanzas.Pagos
    GROUP BY YEAR(fecha_pago), MONTH(fecha_pago)
)
SELECT anio, mes, ingresos,
       SUM(ingresos) OVER (PARTITION BY anio ORDER BY mes
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS acumulado_anio,
       CAST(100.0 * ingresos / SUM(ingresos) OVER (PARTITION BY anio) AS DECIMAL(5,2)) AS pct_del_anio
FROM mensual
ORDER BY anio, mes;
GO

-- 6. PIVOT: reservas por clase, con cada estado como columna
SELECT clase, [Confirmada], [Cancelada], [Completada],
       [Confirmada] + [Cancelada] + [Completada] AS total
FROM (SELECT c.nombre AS clase, r.estado
      FROM gym.Reservas AS r
      JOIN gym.Horarios AS h ON h.id_horario = r.id_horario
      JOIN gym.Clases   AS c ON c.id_clase = h.id_clase) AS origen
PIVOT (COUNT(estado) FOR estado IN ([Confirmada], [Cancelada], [Completada])) AS p
ORDER BY total DESC;
GO


--Indices

-- Consultas 1, 4 y 6: buscar reservas por horario y por estado
CREATE NONCLUSTERED INDEX IX_Reservas_Horario_Estado
    ON gym.Reservas (id_horario, estado);

CREATE NONCLUSTERED INDEX IX_Reservas_Estado_Horario
    ON gym.Reservas (estado, id_horario);

-- Consultas 1 y 4: joins de Horarios hacia Clases y Entrenadores (claves foraneas)
CREATE NONCLUSTERED INDEX IX_Horarios_Clase
    ON gym.Horarios (id_clase) INCLUDE (id_entrenador, fecha, hora_inicio, cupo_maximo);

CREATE NONCLUSTERED INDEX IX_Horarios_Entrenador
    ON gym.Horarios (id_entrenador) INCLUDE (id_clase, fecha, hora_inicio, cupo_maximo);

-- Consultas 2 y 3: pagos agrupados / ordenados por socio y fecha
CREATE NONCLUSTERED INDEX IX_Pagos_Socio_Fecha
    ON finanzas.Pagos (id_socio, fecha_pago DESC) INCLUDE (monto, metodo_pago);

-- Consulta 5: ingresos agrupados por fecha
CREATE NONCLUSTERED INDEX IX_Pagos_Fecha
    ON finanzas.Pagos (fecha_pago) INCLUDE (monto);
GO

--Borrar indices para repetir las pruebas
DROP INDEX IF EXISTS IX_Reservas_Horario_Estado ON gym.Reservas;
DROP INDEX IF EXISTS IX_Reservas_Estado_Horario ON gym.Reservas;
DROP INDEX IF EXISTS IX_Horarios_Clase          ON gym.Horarios;
DROP INDEX IF EXISTS IX_Horarios_Entrenador     ON gym.Horarios;
DROP INDEX IF EXISTS IX_Pagos_Socio_Fecha       ON finanzas.Pagos;
DROP INDEX IF EXISTS IX_Pagos_Fecha             ON finanzas.Pagos;
GO