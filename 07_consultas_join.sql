-- ============================================================
-- 07_consultas_join.sql
-- Consultas con todos los tipos de JOIN y consultas complementarias.
-- Cada una responde a una pregunta real del proceso. Solo lectura.
-- ============================================================


-- ------------------------------------------------------------
-- J-1 INNER JOIN
-- Pregunta: ¿qué diagnóstico principal tuvo cada consulta finalizada?
-- Explicación: solo aparecen consultas que SÍ tienen diagnóstico principal;
-- las tomas de muestra, la cancelada y las planeadas quedan fuera.
-- Aplicación: detalle de consulta y reportes de morbilidad.
-- ------------------------------------------------------------
SELECT e.id_encuentro, e.fecha_inicio::date AS fecha, cc.codigo, cc.descripcion AS diagnostico
FROM encuentro_clinico e
INNER JOIN diagnostico d      ON d.id_encuentro = e.id_encuentro AND d.tipo = 'principal'
INNER JOIN catalogo_codigo cc ON cc.id_codigo = d.id_codigo
WHERE e.estado = 'finalizado'
ORDER BY e.fecha_inicio;


-- ------------------------------------------------------------
-- J-2 LEFT JOIN
-- Pregunta: ¿cuántas consultas tiene cada paciente, incluidos los que no tienen ninguna?
-- Explicación: conserva todos los pacientes; los que no tienen consultas
-- (28-32) salen con 0. Con INNER JOIN esos pacientes desaparecerían.
-- Aplicación: listado de pacientes (columna "consultas").
-- ------------------------------------------------------------
SELECT p.id_paciente_maestro, p.nombre || ' ' || p.apellido_paterno AS paciente, p.estado,
       COUNT(e.id_encuentro) AS consultas
FROM paciente_maestro p
LEFT JOIN encuentro_clinico e ON e.id_paciente_maestro = p.id_paciente_maestro
GROUP BY p.id_paciente_maestro
ORDER BY consultas, p.id_paciente_maestro;


-- ------------------------------------------------------------
-- J-3 RIGHT JOIN
-- Pregunta: ¿qué profesionales no han atendido ninguna consulta?
-- Explicación: la tabla de la derecha (profesional_salud) se conserva
-- completa; los profesionales sin consultas (11 y 12) tienen encuentro nulo.
-- Aplicación: depuración del padrón de médicos antes de dar bajas.
-- ------------------------------------------------------------
SELECT ps.id_profesional, ps.nombre || ' ' || ps.apellido_paterno AS profesional, ps.activo
FROM encuentro_clinico e
RIGHT JOIN profesional_salud ps ON ps.id_profesional = e.id_profesional
WHERE e.id_encuentro IS NULL;


-- ------------------------------------------------------------
-- J-4 FULL OUTER JOIN
-- Pregunta: ¿qué cuentas de acceso no son de médicos y qué médicos no tienen cuenta?
-- Explicación: conserva filas sin pareja de ambos lados: usuarios
-- administrativos (sin profesional) y profesionales sin usuario.
-- Aplicación: módulo de usuarios, para saber a qué médicos falta darles acceso.
-- ------------------------------------------------------------
SELECT u.id_usuario, u.correo, u.rol,
       ps.id_profesional, ps.nombre || ' ' || ps.apellido_paterno AS profesional,
       CASE WHEN u.id_usuario IS NULL THEN 'Médico sin cuenta'
            WHEN ps.id_profesional IS NULL THEN 'Usuario no médico'
            ELSE 'Médico con cuenta' END AS situacion
FROM usuario u
FULL OUTER JOIN profesional_salud ps ON ps.id_profesional = u.id_profesional
ORDER BY situacion, u.id_usuario, ps.id_profesional;


-- ------------------------------------------------------------
-- J-5 CROSS JOIN
-- Pregunta: ¿cuántos consentimientos autorizan a cada institución activa en
-- cada categoría de información, incluidas las combinaciones sin ninguno?
-- Explicación: el CROSS JOIN genera todas las combinaciones institución ×
-- categoría (matriz completa) y luego se cuentan las autorizaciones; las
-- combinaciones vacías aparecen con 0, lo que no lograría un JOIN normal.
-- Aplicación: matriz de cobertura de consentimientos para el coordinador.
-- ------------------------------------------------------------
SELECT o.nombre AS institucion, ci.nombre AS categoria,
       COUNT(c.id_consentimiento) AS autorizaciones_vigentes
FROM organizacion o
CROSS JOIN categoria_informacion ci
LEFT JOIN consentimiento_alcance ca
       ON ca.id_organizacion = o.id_organizacion AND ca.id_categoria = ci.id_categoria
LEFT JOIN consentimiento c
       ON c.id_consentimiento = ca.id_consentimiento AND c.estado = 'activo'
WHERE o.estado = 'activa'
GROUP BY o.nombre, ci.id_categoria, ci.nombre
ORDER BY o.nombre, ci.id_categoria;


-- ------------------------------------------------------------
-- J-6 SELF JOIN
-- Pregunta: ¿qué pacientes fueron fusionados y en qué registro quedaron?
-- Explicación: paciente_maestro se une consigo misma por la autorrelación
-- id_paciente_fusionado_en (registro absorbido -> registro sobreviviente).
-- Aplicación: historial del módulo de duplicados.
-- ------------------------------------------------------------
SELECT f.id_paciente_maestro AS id_absorbido,
       f.nombre || ' ' || f.apellido_paterno AS registro_absorbido,
       s.id_paciente_maestro AS id_sobreviviente,
       s.nombre || ' ' || s.apellido_paterno AS registro_sobreviviente
FROM paciente_maestro f
JOIN paciente_maestro s ON s.id_paciente_maestro = f.id_paciente_fusionado_en;


-- ------------------------------------------------------------
-- J-7 JOIN de 3 o más tablas
-- Pregunta: ¿cuál es el historial clínico del paciente 1 (consultas, médico,
-- institución, diagnósticos y medicamentos)?
-- Explicación: une 7 tablas; diagnóstico y medicamento con LEFT JOIN porque
-- no todas las consultas los tienen.
-- Aplicación: pantalla de detalle del paciente.
-- ------------------------------------------------------------
SELECT e.fecha_inicio::date AS fecha, e.tipo_encuentro, o.nombre AS institucion,
       ps.nombre || ' ' || ps.apellido_paterno AS medico,
       dx.descripcion AS diagnostico, d.tipo AS tipo_dx,
       med.descripcion AS medicamento, sm.dosis, sm.frecuencia
FROM encuentro_clinico e
JOIN organizacion o              ON o.id_organizacion = e.id_organizacion
LEFT JOIN profesional_salud ps   ON ps.id_profesional = e.id_profesional
LEFT JOIN diagnostico d          ON d.id_encuentro = e.id_encuentro
LEFT JOIN catalogo_codigo dx     ON dx.id_codigo = d.id_codigo
LEFT JOIN solicitud_medicamento sm ON sm.id_encuentro = e.id_encuentro
LEFT JOIN catalogo_codigo med    ON med.id_codigo = sm.id_codigo
WHERE e.id_paciente_maestro = 1
ORDER BY e.fecha_inicio, d.tipo;


-- ============================================================
-- CONSULTAS COMPLEMENTARIAS
-- ============================================================

-- ------------------------------------------------------------
-- C-1 Agregación (COUNT, AVG, MIN, MAX)
-- Pregunta: por institución, ¿cuántas consultas finalizadas hubo, cuánto
-- duraron en promedio y entre qué fechas?
-- Aplicación: indicadores por institución.
-- ------------------------------------------------------------
SELECT o.nombre AS institucion,
       COUNT(*) AS consultas,
       ROUND(AVG(EXTRACT(EPOCH FROM (e.fecha_fin - e.fecha_inicio)) / 60)) AS duracion_promedio_min,
       MIN(e.fecha_inicio)::date AS primera,
       MAX(e.fecha_inicio)::date AS ultima
FROM encuentro_clinico e
JOIN organizacion o ON o.id_organizacion = e.id_organizacion
WHERE e.estado = 'finalizado'
GROUP BY o.nombre
ORDER BY consultas DESC;


-- ------------------------------------------------------------
-- C-2 Subconsulta 1 (en HAVING)
-- Pregunta: ¿qué médicos atienden más consultas que el promedio de los médicos?
-- Aplicación: distribución de carga de trabajo.
-- ------------------------------------------------------------
SELECT ps.id_profesional, ps.nombre || ' ' || ps.apellido_paterno AS medico, COUNT(*) AS consultas
FROM encuentro_clinico e
JOIN profesional_salud ps ON ps.id_profesional = e.id_profesional
WHERE e.estado <> 'cancelado'
GROUP BY ps.id_profesional
HAVING COUNT(*) > (SELECT AVG(n) FROM (SELECT COUNT(*) AS n FROM encuentro_clinico
                                       WHERE id_profesional IS NOT NULL AND estado <> 'cancelado'
                                       GROUP BY id_profesional) t)
ORDER BY consultas DESC;


-- ------------------------------------------------------------
-- C-3 Subconsulta 2 (IN / NOT EXISTS)
-- Pregunta: ¿qué pacientes activos tienen consultas registradas pero NO
-- tienen un consentimiento vigente? (riesgo de compartir sin autorización)
-- Aplicación: alerta del módulo de consentimientos.
-- ------------------------------------------------------------
SELECT p.id_paciente_maestro, p.nombre || ' ' || p.apellido_paterno AS paciente
FROM paciente_maestro p
WHERE p.estado = 'activo'
  AND p.id_paciente_maestro IN (SELECT id_paciente_maestro FROM encuentro_clinico)
  AND NOT EXISTS (SELECT 1 FROM consentimiento c
                  WHERE c.id_paciente_maestro = p.id_paciente_maestro
                    AND c.estado = 'activo' AND CURRENT_DATE BETWEEN c.fecha_inicio AND c.fecha_fin)
ORDER BY 1;


-- ------------------------------------------------------------
-- C-4 Expresión de tabla común (WITH)
-- Pregunta: ¿cuántas consultas finalizadas hubo cada mes y cuál fue el
-- cambio respecto al mes anterior?
-- Aplicación: gráfica mensual del panel.
-- ------------------------------------------------------------
WITH por_mes AS (
  SELECT date_trunc('month', fecha_inicio)::date AS mes, COUNT(*) AS consultas
  FROM encuentro_clinico
  WHERE estado = 'finalizado'
  GROUP BY 1
)
SELECT mes, consultas,
       consultas - LAG(consultas) OVER (ORDER BY mes) AS cambio_vs_mes_anterior
FROM por_mes
ORDER BY mes;


-- ------------------------------------------------------------
-- C-5 Función de ventana (ROW_NUMBER, RANK, SUM OVER)
-- Pregunta: dentro de cada institución, ¿qué lugar ocupa cada médico por
-- número de consultas y cuál es el acumulado de la institución?
-- Aplicación: ranking de productividad por institución.
-- ------------------------------------------------------------
SELECT institucion, medico, consultas,
       RANK() OVER (PARTITION BY institucion ORDER BY consultas DESC) AS lugar,
       SUM(consultas) OVER (PARTITION BY institucion ORDER BY consultas DESC, medico) AS acumulado
FROM (SELECT o.nombre AS institucion, ps.nombre || ' ' || ps.apellido_paterno AS medico, COUNT(*) AS consultas
      FROM encuentro_clinico e
      JOIN organizacion o ON o.id_organizacion = e.id_organizacion
      JOIN profesional_salud ps ON ps.id_profesional = e.id_profesional
      WHERE e.estado <> 'cancelado'
      GROUP BY o.nombre, ps.id_profesional) t
ORDER BY institucion, lugar;

-- Variante con ROW_NUMBER: última consulta de cada paciente.
SELECT id_paciente_maestro, id_encuentro, fecha_inicio::date AS ultima_consulta
FROM (SELECT e.*, ROW_NUMBER() OVER (PARTITION BY id_paciente_maestro ORDER BY fecha_inicio DESC) AS rn
      FROM encuentro_clinico e WHERE estado IN ('finalizado','en_curso')) t
WHERE rn = 1
ORDER BY id_paciente_maestro;
