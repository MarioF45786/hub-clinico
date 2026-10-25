-- ============================================================
-- 08_programacion_hub.sql
-- Procedimientos y vistas para las pantallas propias del hub:
-- captura clínica de la consulta, conflictos, consentimientos,
-- errores de integración, instituciones y usuarios.
-- Ejecutar DESPUÉS de 05_programacion.sql. Es re-ejecutable.
--
-- Clasificación:
--   FUNCIONES de apoyo (SELECT; no cuentan como procedimientos):
--     fn_encuentro_editable, fn_crear_procedencia
--   PROCEDIMIENTOS (CALL): SP-13 a SP-21
--     sp_registrar_diagnostico, sp_registrar_signo_vital, sp_indicar_medicamento,
--     sp_resolver_conflicto, sp_registrar_consentimiento, sp_gestionar_error,
--     sp_registrar_organizacion, sp_cambiar_estado_organizacion, sp_cambiar_estado_usuario
--   VISTAS: v_procedencia_origen, v_duplicado_resumen, v_conflicto_resumen,
--     v_consentimiento_resumen, v_paquete_resumen, v_error_detalle,
--     v_organizacion_resumen, v_usuario_resumen, v_auditoria_detalle
-- ============================================================


-- ============================================================
-- FUNCIONES DE APOYO
-- ============================================================

-- fn_encuentro_editable: valida que el usuario pueda agregar información
-- clínica a la consulta (coordinador o el médico que atiende) y que la
-- consulta esté en curso. Devuelve el paciente de la consulta.
CREATE OR REPLACE FUNCTION fn_encuentro_editable(p_id_usuario BIGINT, p_id_encuentro BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  v_rol VARCHAR;
  e RECORD;
BEGIN
  v_rol := fn_verificar_rol(p_id_usuario, 'coordinador', 'medico');
  SELECT * INTO e FROM encuentro_clinico WHERE id_encuentro = p_id_encuentro;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La consulta % no existe.', p_id_encuentro;
  END IF;
  IF v_rol = 'medico' AND e.id_profesional IS DISTINCT FROM (SELECT id_profesional FROM usuario WHERE id_usuario = p_id_usuario) THEN
    RAISE EXCEPTION 'Un médico solo puede registrar información en sus propias consultas.';
  END IF;
  IF e.estado <> 'en_curso' THEN
    RAISE EXCEPTION 'Solo se registran diagnósticos, signos y medicamentos en consultas en curso (estado actual: %).', e.estado;
  END IF;
  RETURN e.id_paciente_maestro;
END $$;

-- fn_crear_procedencia: crea el detalle y la procedencia de un dato clínico
-- dentro del mismo paquete de captura de su consulta. Devuelve id_procedencia.
CREATE OR REPLACE FUNCTION fn_crear_procedencia(
  p_id_encuentro BIGINT, p_tipo_recurso VARCHAR, p_ruta VARCHAR, p_valor TEXT, p_codigo VARCHAR)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  v_paquete BIGINT;
  v_paciente BIGINT;
  v_detalle BIGINT;
  v_procedencia BIGINT;
BEGIN
  SELECT dt.id_paquete, e.id_paciente_maestro INTO v_paquete, v_paciente
  FROM encuentro_clinico e
  JOIN procedencia_dato pd ON pd.id_procedencia = e.id_procedencia
  JOIN detalle_transaccion dt ON dt.id_detalle = pd.id_detalle
  WHERE e.id_encuentro = p_id_encuentro;

  INSERT INTO detalle_transaccion (id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso,
                                   fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
  VALUES (v_paquete, v_paciente, p_tipo_recurso, p_tipo_recurso || '-portal-' || v_paquete || '-' || floor(random() * 1e9)::bigint,
          '1', CURRENT_TIMESTAMP, 'integrado',
          encode(sha256(convert_to(format('%s|%s|%s|%s', p_tipo_recurso, v_paquete, clock_timestamp(), random()), 'UTF8')), 'hex'),
          CURRENT_TIMESTAMP)
  RETURNING id_detalle INTO v_detalle;

  INSERT INTO procedencia_dato (id_detalle, ruta_elemento, valor_original, codigo_original, fecha_origen)
  VALUES (v_detalle, p_ruta, p_valor, p_codigo, CURRENT_TIMESTAMP)
  RETURNING id_procedencia INTO v_procedencia;

  RETURN v_procedencia;
END $$;


-- ============================================================
-- PROCEDIMIENTOS: CAPTURA CLÍNICA DE LA CONSULTA
-- ============================================================

-- ------------------------------------------------------------
-- SP-13 sp_registrar_diagnostico
-- Propósito: registrar un diagnóstico CIE-10 en una consulta en curso.
-- Entrada:   p_id_usuario, p_id_encuentro, p_id_codigo, p_tipo ('principal'|'secundario')
-- Salida:    p_id_diagnostico (INOUT)
-- Tablas:    diagnostico, catalogo_codigo, encuentro_clinico, detalle_transaccion,
--            procedencia_dato, auditoria
-- Reglas:    coordinador o el médico que atiende; consulta en curso; código
--            CIE-10 vigente; una sola vez el mismo diagnóstico por consulta;
--            un solo diagnóstico principal por consulta; crea su procedencia.
-- Excepciones: código inválido, repetido, segundo principal, consulta cerrada.
-- Ejemplo:   CALL sp_registrar_diagnostico(5, 46, 2, 'secundario', NULL);
-- Resultado: id del diagnóstico.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_diagnostico(
  p_id_usuario BIGINT, p_id_encuentro BIGINT, p_id_codigo BIGINT, p_tipo VARCHAR, INOUT p_id_diagnostico BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_paciente BIGINT;
  c RECORD;
  v_proc BIGINT;
BEGIN
  v_paciente := fn_encuentro_editable(p_id_usuario, p_id_encuentro);

  SELECT * INTO c FROM catalogo_codigo WHERE id_codigo = p_id_codigo AND sistema_codificacion = 'CIE-10' AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El diagnóstico debe ser un código CIE-10 vigente.';
  END IF;
  IF p_tipo NOT IN ('principal','secundario') THEN
    RAISE EXCEPTION 'El tipo de diagnóstico debe ser principal o secundario.';
  END IF;
  IF EXISTS (SELECT 1 FROM diagnostico WHERE id_encuentro = p_id_encuentro AND id_codigo = p_id_codigo) THEN
    RAISE EXCEPTION 'El diagnóstico % ya está registrado en esta consulta.', c.codigo;
  END IF;
  IF p_tipo = 'principal' AND EXISTS (SELECT 1 FROM diagnostico WHERE id_encuentro = p_id_encuentro AND tipo = 'principal') THEN
    RAISE EXCEPTION 'La consulta ya tiene un diagnóstico principal.';
  END IF;

  v_proc := fn_crear_procedencia(p_id_encuentro, 'Condition', 'Condition.code', c.descripcion, c.codigo);

  INSERT INTO diagnostico (id_encuentro, id_codigo, id_procedencia, tipo, estado_clinico, fecha_diagnostico)
  VALUES (p_id_encuentro, p_id_codigo, v_proc, p_tipo, 'activo', CURRENT_DATE)
  RETURNING id_diagnostico INTO p_id_diagnostico;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'diagnostico', p_id_diagnostico, v_paciente, 'exito',
          format('Diagnóstico %s %s en la consulta %s.', p_tipo, c.codigo, p_id_encuentro));
END $$;

-- ------------------------------------------------------------
-- SP-14 sp_registrar_signo_vital
-- Propósito: registrar un signo vital (LOINC) en una consulta en curso.
-- Entrada:   p_id_usuario, p_id_encuentro, p_id_codigo, p_valor (texto: '120/80' o número)
-- Salida:    p_id_observacion (INOUT)
-- Tablas:    observacion, catalogo_codigo, encuentro_clinico, procedencia_dato, auditoria
-- Reglas:    código LOINC de categoría signo_vital; la presión se captura como
--            sistólica/diastólica; rangos fisiológicos: FC 30-220 lpm,
--            temperatura 30-45 °C, peso 1-400 kg, talla 30-250 cm;
--            la interpretación (normal/alto/bajo) la calcula el procedimiento.
-- Excepciones: valor fuera de rango o con formato inválido, código no válido.
-- Ejemplo:   CALL sp_registrar_signo_vital(5, 46, 13, '88', NULL);
-- Resultado: id de la observación con su interpretación.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_signo_vital(
  p_id_usuario BIGINT, p_id_encuentro BIGINT, p_id_codigo BIGINT, p_valor VARCHAR, INOUT p_id_observacion BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_paciente BIGINT;
  c RECORD;
  v_num NUMERIC;
  v_txt VARCHAR;
  v_min NUMERIC;
  v_max NUMERIC;
  v_interp VARCHAR := 'normal';
  v_sis INT;
  v_dia INT;
  v_proc BIGINT;
BEGIN
  v_paciente := fn_encuentro_editable(p_id_usuario, p_id_encuentro);

  SELECT * INTO c FROM catalogo_codigo WHERE id_codigo = p_id_codigo AND categoria = 'signo_vital' AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El código no corresponde a un signo vital vigente.';
  END IF;
  IF NULLIF(trim(p_valor), '') IS NULL THEN
    RAISE EXCEPTION 'Escribe el valor de %.', lower(c.descripcion);
  END IF;

  IF c.codigo = '85354-9' THEN
    IF trim(p_valor) !~ '^[0-9]{2,3}/[0-9]{2,3}$' THEN
      RAISE EXCEPTION 'La presión se escribe como sistólica/diastólica, por ejemplo 120/80.';
    END IF;
    v_sis := split_part(trim(p_valor), '/', 1)::int;
    v_dia := split_part(trim(p_valor), '/', 2)::int;
    IF v_sis NOT BETWEEN 60 AND 260 OR v_dia NOT BETWEEN 30 AND 160 OR v_dia >= v_sis THEN
      RAISE EXCEPTION 'La presión % no es fisiológicamente posible.', p_valor;
    END IF;
    v_txt := trim(p_valor);
    v_interp := CASE WHEN v_sis >= 140 OR v_dia >= 90 THEN 'alto' WHEN v_sis < 90 OR v_dia < 60 THEN 'bajo' ELSE 'normal' END;
  ELSE
    BEGIN
      v_num := replace(trim(p_valor), ',', '.')::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'El valor de % debe ser numérico.', lower(c.descripcion);
    END;
    CASE c.codigo
      WHEN '8867-4'  THEN v_min := 30;  v_max := 220;
      WHEN '8310-5'  THEN v_min := 30;  v_max := 45;
      WHEN '29463-7' THEN v_min := 1;   v_max := 400;
      WHEN '8302-2'  THEN v_min := 30;  v_max := 250;
      ELSE v_min := 0; v_max := 100000;
    END CASE;
    IF v_num < v_min OR v_num > v_max THEN
      RAISE EXCEPTION '% debe estar entre % y % %.', c.descripcion, v_min, v_max, c.unidad_sugerida;
    END IF;
    v_interp := CASE c.codigo
                  WHEN '8867-4' THEN CASE WHEN v_num > 100 THEN 'alto' WHEN v_num < 60 THEN 'bajo' ELSE 'normal' END
                  WHEN '8310-5' THEN CASE WHEN v_num >= 38 THEN 'alto' WHEN v_num < 35 THEN 'bajo' ELSE 'normal' END
                  ELSE 'normal' END;
  END IF;

  v_proc := fn_crear_procedencia(p_id_encuentro, 'Observation',
              CASE WHEN v_txt IS NULL THEN 'Observation.valueQuantity' ELSE 'Observation.valueString' END,
              c.descripcion || ' ' || trim(p_valor), c.codigo);

  INSERT INTO observacion (id_encuentro, id_codigo, id_procedencia, valor_numerico, valor_texto, unidad,
                           rango_ref_min, rango_ref_max, interpretacion, fecha_observacion)
  VALUES (p_id_encuentro, p_id_codigo, v_proc, v_num, v_txt, c.unidad_sugerida,
          CASE c.codigo WHEN '8867-4' THEN 60 WHEN '8310-5' THEN 36 END,
          CASE c.codigo WHEN '8867-4' THEN 100 WHEN '8310-5' THEN 37.5 END,
          v_interp, CURRENT_TIMESTAMP)
  RETURNING id_observacion INTO p_id_observacion;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'observacion', p_id_observacion, v_paciente, 'exito',
          format('%s %s (%s) en la consulta %s.', c.descripcion, trim(p_valor), v_interp, p_id_encuentro));
END $$;

-- ------------------------------------------------------------
-- SP-15 sp_indicar_medicamento
-- Propósito: indicar un medicamento del cuadro básico en una consulta en curso.
-- Entrada:   p_id_usuario, p_id_encuentro, p_id_codigo, p_dosis, p_via, p_frecuencia, p_duracion_dias
-- Salida:    p_id_solicitud (INOUT)
-- Tablas:    solicitud_medicamento, catalogo_codigo, encuentro_clinico, procedencia_dato, auditoria
-- Reglas:    medicamento del cuadro básico vigente; dosis y frecuencia
--            obligatorias; duración entre 1 y 365 días o nula (uso crónico);
--            el mismo medicamento no se indica dos veces en la consulta.
-- Excepciones: medicamento no válido, repetido, duración fuera de rango.
-- Ejemplo:   CALL sp_indicar_medicamento(5, 46, 27, '1 tableta', 'oral', 'cada 8 horas', 5, NULL);
-- Resultado: id de la indicación.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_indicar_medicamento(
  p_id_usuario BIGINT, p_id_encuentro BIGINT, p_id_codigo BIGINT, p_dosis VARCHAR, p_via VARCHAR,
  p_frecuencia VARCHAR, p_duracion_dias INT, INOUT p_id_solicitud BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_paciente BIGINT;
  c RECORD;
  v_proc BIGINT;
BEGIN
  v_paciente := fn_encuentro_editable(p_id_usuario, p_id_encuentro);

  SELECT * INTO c FROM catalogo_codigo WHERE id_codigo = p_id_codigo AND sistema_codificacion = 'CUADRO_BASICO' AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El medicamento debe pertenecer al cuadro básico vigente.';
  END IF;
  IF NULLIF(trim(p_dosis), '') IS NULL OR NULLIF(trim(p_frecuencia), '') IS NULL THEN
    RAISE EXCEPTION 'La dosis y la frecuencia son obligatorias.';
  END IF;
  IF p_duracion_dias IS NOT NULL AND p_duracion_dias NOT BETWEEN 1 AND 365 THEN
    RAISE EXCEPTION 'La duración debe estar entre 1 y 365 días (déjela vacía para uso crónico).';
  END IF;
  IF EXISTS (SELECT 1 FROM solicitud_medicamento WHERE id_encuentro = p_id_encuentro AND id_codigo = p_id_codigo) THEN
    RAISE EXCEPTION '% ya está indicado en esta consulta.', c.descripcion;
  END IF;

  v_proc := fn_crear_procedencia(p_id_encuentro, 'MedicationRequest', 'MedicationRequest.medicationCodeableConcept',
                                 c.descripcion, c.codigo);

  INSERT INTO solicitud_medicamento (id_encuentro, id_codigo, id_procedencia, dosis, via, frecuencia,
                                     duracion_dias, fecha_solicitud, estado)
  VALUES (p_id_encuentro, p_id_codigo, v_proc, trim(p_dosis), p_via, trim(p_frecuencia),
          p_duracion_dias, CURRENT_TIMESTAMP, 'activa')
  RETURNING id_solicitud INTO p_id_solicitud;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'solicitud_medicamento', p_id_solicitud, v_paciente, 'exito',
          format('Indicó %s en la consulta %s.', c.descripcion, p_id_encuentro));
END $$;


-- ============================================================
-- PROCEDIMIENTOS: CALIDAD DE DATOS Y CONSENTIMIENTO
-- ============================================================

-- ------------------------------------------------------------
-- SP-16 sp_resolver_conflicto
-- Propósito: decidir qué valor queda vigente cuando dos instituciones
--            reportan valores distintos del mismo dato.
-- Entrada:   p_id_usuario, p_id_conflicto, p_resolucion ('vigente_a'|'vigente_b'|'ambos_vigentes'),
--            p_justificacion
-- Salida:    ninguna
-- Tablas:    conflicto_dato, v_procedencia_paciente, nombre_paciente,
--            contacto_paciente, direccion_paciente, alergia, version_dato, auditoria
-- Reglas:    solo coordinador (RN-06); solo conflictos pendientes; el valor
--            que pierde queda como histórico (vigente = false), no se borra;
--            si se deja sin vigencia una alergia confirmada la justificación
--            es obligatoria (mínimo 20 caracteres); cada cambio de vigencia
--            queda en version_dato.
-- Excepciones: conflicto inexistente o resuelto, resolución inválida, falta justificación.
-- Ejemplo:   CALL sp_resolver_conflicto(3, 1, 'ambos_vigentes', 'Se conservan ambos hasta confirmar con el paciente.');
-- Resultado: conflicto 'resuelto' y vigencias actualizadas.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_resolver_conflicto(
  p_id_usuario BIGINT, p_id_conflicto BIGINT, p_resolucion VARCHAR, p_justificacion TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  c RECORD;
  v_tipo VARCHAR;
  v_paciente BIGINT;
  v_tabla VARCHAR;
  v_pierde BIGINT;
  v_es_alergia_real BOOLEAN := FALSE;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF p_resolucion NOT IN ('vigente_a','vigente_b','ambos_vigentes') THEN
    RAISE EXCEPTION 'Resolución inválida: elija vigente A, vigente B o ambos vigentes.';
  END IF;
  SELECT * INTO c FROM conflicto_dato WHERE id_conflicto = p_id_conflicto FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El conflicto % no existe.', p_id_conflicto;
  END IF;
  IF c.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'El conflicto ya fue %.', c.estado;
  END IF;

  SELECT tipo_dato, id_paciente_maestro INTO v_tipo, v_paciente
  FROM v_procedencia_paciente WHERE id_procedencia = c.id_procedencia_a;

  v_pierde := CASE p_resolucion WHEN 'vigente_a' THEN c.id_procedencia_b
                                WHEN 'vigente_b' THEN c.id_procedencia_a END;

  IF v_tipo = 'alergia' AND v_pierde IS NOT NULL THEN
    SELECT NOT sin_alergias_conocidas INTO v_es_alergia_real FROM alergia WHERE id_procedencia = v_pierde;
    IF v_es_alergia_real AND length(coalesce(trim(p_justificacion), '')) < 20 THEN
      RAISE EXCEPTION 'Para dejar sin vigencia una alergia escriba una justificación de al menos 20 caracteres.';
    END IF;
  END IF;

  v_tabla := CASE v_tipo WHEN 'nombre' THEN 'nombre_paciente' WHEN 'contacto' THEN 'contacto_paciente'
                         WHEN 'direccion' THEN 'direccion_paciente' WHEN 'alergia' THEN 'alergia' END;

  -- El valor ganador queda vigente; el perdedor pasa a histórico
  IF v_tabla IS NOT NULL THEN
    EXECUTE format('UPDATE %I SET vigente = TRUE WHERE id_procedencia IN ($1, $2) AND id_procedencia IS DISTINCT FROM $3', v_tabla)
      USING c.id_procedencia_a, c.id_procedencia_b, v_pierde;
    IF v_pierde IS NOT NULL THEN
      EXECUTE format('UPDATE %I SET vigente = FALSE WHERE id_procedencia = $1', v_tabla) USING v_pierde;
      INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
      VALUES (v_pierde, 'vigente',
              COALESCE((SELECT MAX(numero_version) FROM version_dato WHERE id_procedencia = v_pierde AND campo = 'vigente'), 0) + 1,
              'true', 'false', p_id_usuario, left('Conflicto ' || p_id_conflicto || ': ' || coalesce(p_justificacion, ''), 200));
    END IF;
  END IF;

  UPDATE conflicto_dato
     SET estado = 'resuelto', resolucion = p_resolucion, justificacion = NULLIF(trim(p_justificacion), ''),
         id_usuario_resolucion = p_id_usuario, fecha_resolucion = CURRENT_TIMESTAMP
   WHERE id_conflicto = p_id_conflicto;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'resolver', 'conflicto_dato', p_id_conflicto, v_paciente, 'exito',
          format('Conflicto de %s resuelto: %s.', v_tipo, replace(p_resolucion, '_', ' ')));
END $$;

-- ------------------------------------------------------------
-- SP-17 sp_registrar_consentimiento
-- Propósito: registrar el consentimiento firmado por un paciente con sus
--            alcances (qué categorías puede enviar o consultar una institución).
-- Entrada:   p_id_usuario, p_id_paciente, p_fecha_otorgamiento, p_fecha_inicio,
--            p_fecha_fin, p_id_organizacion, p_enviar (ids de categoría),
--            p_consultar (ids de categoría)
-- Salida:    p_id_consentimiento (INOUT)
-- Tablas:    consentimiento, consentimiento_alcance, paciente_maestro,
--            organizacion, categoria_informacion, auditoria
-- Reglas:    solo coordinador (RN-08); paciente activo; institución activa;
--            la firma no es posterior al inicio y el fin es posterior al
--            inicio; al menos una categoría marcada; no se traslapa con otro
--            consentimiento activo que ya autorice la misma categoría,
--            institución y permiso en esas fechas (RN-09).
-- Excepciones: cualquiera de las reglas anteriores.
-- Ejemplo:   CALL sp_registrar_consentimiento(3, 25, '2026-10-17', '2026-10-17', '2027-10-17', 1, ARRAY[1,2], ARRAY[1], NULL);
-- Resultado: consentimiento activo con sus alcances.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_consentimiento(
  p_id_usuario BIGINT, p_id_paciente BIGINT, p_fecha_otorgamiento DATE, p_fecha_inicio DATE, p_fecha_fin DATE,
  p_id_organizacion BIGINT, p_enviar BIGINT[], p_consultar BIGINT[], INOUT p_id_consentimiento BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_choque BIGINT;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF NOT EXISTS (SELECT 1 FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente AND estado = 'activo') THEN
    RAISE EXCEPTION 'El paciente no existe o no está activo.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM organizacion WHERE id_organizacion = p_id_organizacion AND estado = 'activa') THEN
    RAISE EXCEPTION 'La institución no existe o no está activa.';
  END IF;
  IF p_fecha_otorgamiento IS NULL OR p_fecha_inicio IS NULL OR p_fecha_fin IS NULL THEN
    RAISE EXCEPTION 'Las fechas de firma, inicio y fin son obligatorias.';
  END IF;
  IF p_fecha_otorgamiento > p_fecha_inicio THEN
    RAISE EXCEPTION 'La vigencia no puede iniciar antes de la fecha de firma.';
  END IF;
  IF p_fecha_fin <= p_fecha_inicio THEN
    RAISE EXCEPTION 'El fin de la vigencia debe ser posterior al inicio.';
  END IF;
  IF coalesce(cardinality(p_enviar), 0) + coalesce(cardinality(p_consultar), 0) = 0 THEN
    RAISE EXCEPTION 'Marque al menos una categoría para enviar o consultar.';
  END IF;

  SELECT c.id_consentimiento INTO v_choque
  FROM consentimiento c
  JOIN consentimiento_alcance a ON a.id_consentimiento = c.id_consentimiento
  WHERE c.id_paciente_maestro = p_id_paciente AND c.estado = 'activo'
    AND c.fecha_inicio <= p_fecha_fin AND p_fecha_inicio <= c.fecha_fin
    AND a.id_organizacion = p_id_organizacion
    AND ((a.permiso = 'enviar' AND a.id_categoria = ANY (coalesce(p_enviar, '{}')))
      OR (a.permiso = 'consultar' AND a.id_categoria = ANY (coalesce(p_consultar, '{}'))))
  LIMIT 1;
  IF v_choque IS NOT NULL THEN
    RAISE EXCEPTION 'Se traslapa con el consentimiento CONS-%, que ya autoriza algunas de estas categorías con esa institución en esas fechas.', lpad(v_choque::text, 5, '0');
  END IF;

  INSERT INTO consentimiento (id_paciente_maestro, id_usuario_registro, fecha_otorgamiento, fecha_inicio, fecha_fin, estado)
  VALUES (p_id_paciente, p_id_usuario, p_fecha_otorgamiento, p_fecha_inicio, p_fecha_fin, 'activo')
  RETURNING id_consentimiento INTO p_id_consentimiento;

  UPDATE consentimiento SET ref_documento = 'consentimientos/CONS-' || lpad(p_id_consentimiento::text, 5, '0') || '.pdf'
   WHERE id_consentimiento = p_id_consentimiento;

  INSERT INTO consentimiento_alcance (id_consentimiento, id_categoria, id_organizacion, permiso)
  SELECT p_id_consentimiento, cat, p_id_organizacion, 'enviar' FROM unnest(coalesce(p_enviar, '{}')) AS cat
  UNION
  SELECT p_id_consentimiento, cat, p_id_organizacion, 'consultar' FROM unnest(coalesce(p_consultar, '{}')) AS cat;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'consentimiento', p_id_consentimiento, p_id_paciente, 'exito',
          format('Consentimiento con la institución %s: %s para enviar, %s para consultar.',
                 p_id_organizacion, coalesce(cardinality(p_enviar), 0), coalesce(cardinality(p_consultar), 0)));
EXCEPTION
  WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'Alguna de las categorías marcadas no existe.';
END $$;


-- ============================================================
-- PROCEDIMIENTOS: INTEGRACIÓN, RED Y USUARIOS
-- ============================================================

-- ------------------------------------------------------------
-- SP-18 sp_gestionar_error
-- Propósito: decidir qué pasa con un recurso que no pasó la validación:
--            reprocesarlo (cuando la institución ya lo corrigió) o rechazarlo.
-- Entrada:   p_id_usuario, p_id_detalle, p_accion ('reprocesar'|'rechazar'), p_motivo
-- Salida:    ninguna
-- Tablas:    detalle_transaccion, error_validacion, auditoria
-- Reglas:    solo analista de integración; el recurso debe estar pendiente
--            (estado 'recibido') y tener errores registrados; rechazar exige
--            motivo; reprocesar lo deja 'validado' para su integración.
-- Excepciones: recurso inexistente, ya gestionado, sin errores, sin motivo.
-- Ejemplo:   CALL sp_gestionar_error(2, 903, 'reprocesar', 'El laboratorio corrigió el código.');
-- Resultado: nuevo estado del recurso y evento en auditoría.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_gestionar_error(p_id_usuario BIGINT, p_id_detalle BIGINT, p_accion VARCHAR, p_motivo TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  d RECORD;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'analista_integracion');

  IF p_accion NOT IN ('reprocesar','rechazar') THEN
    RAISE EXCEPTION 'Acción inválida: use reprocesar o rechazar.';
  END IF;
  SELECT * INTO d FROM detalle_transaccion WHERE id_detalle = p_id_detalle FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El recurso % no existe.', p_id_detalle;
  END IF;
  IF d.estado <> 'recibido' THEN
    RAISE EXCEPTION 'El recurso ya fue gestionado (estado actual: %).', d.estado;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM error_validacion WHERE id_detalle = p_id_detalle) THEN
    RAISE EXCEPTION 'El recurso no tiene errores de validación.';
  END IF;
  IF p_accion = 'rechazar' AND length(coalesce(trim(p_motivo), '')) < 5 THEN
    RAISE EXCEPTION 'Escriba el motivo del rechazo.';
  END IF;

  UPDATE detalle_transaccion
     SET estado = CASE p_accion WHEN 'reprocesar' THEN 'validado' ELSE 'rechazado' END,
         fecha_procesamiento = CURRENT_TIMESTAMP
   WHERE id_detalle = p_id_detalle;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'detalle_transaccion', p_id_detalle, d.id_paciente_maestro, 'exito',
          CASE p_accion WHEN 'reprocesar' THEN 'Solicitó reproceso' ELSE 'Rechazó el recurso' END
          || coalesce(': ' || NULLIF(trim(p_motivo), ''), '.'));
END $$;

-- ------------------------------------------------------------
-- SP-19 sp_registrar_organizacion
-- Propósito: dar de alta una institución con su contacto principal y,
--            opcionalmente, su primer sistema de origen.
-- Entrada:   p_id_usuario, p_clave (CLUES), p_nombre, p_tipo, p_telefono, p_calle,
--            p_numero_exterior, p_colonia, p_codigo_postal, p_contacto_nombre,
--            p_contacto_correo, p_nombre_sistema, p_tipo_sistema
-- Salida:    p_id_organizacion (INOUT)
-- Tablas:    organizacion, codigo_postal, contacto_organizacion, sistema_origen, auditoria
-- Reglas:    solo administrador; CLUES con 5 letras y 6 dígitos, única;
--            el código postal debe existir en el catálogo; contacto obligatorio.
-- Excepciones: clave inválida o repetida, código postal fuera del catálogo.
-- Ejemplo:   CALL sp_registrar_organizacion(1,'NLSSA900011','Clínica Linda Vista','clinica','8183011000',
--              'Av. Linda Vista','500','Linda Vista','67100','Dra. Ana Ruiz','aruiz@clv.example.mx','CLV Expediente','expediente_clinico',NULL);
-- Resultado: institución activa con contacto principal y sistema de origen.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_organizacion(
  p_id_usuario BIGINT, p_clave VARCHAR, p_nombre VARCHAR, p_tipo VARCHAR, p_telefono VARCHAR,
  p_calle VARCHAR, p_numero_exterior VARCHAR, p_colonia VARCHAR, p_codigo_postal VARCHAR,
  p_contacto_nombre VARCHAR, p_contacto_correo VARCHAR, p_nombre_sistema VARCHAR, p_tipo_sistema VARCHAR,
  INOUT p_id_organizacion BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_clave VARCHAR := upper(trim(p_clave));
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  IF v_clave !~ '^[A-Z]{5}[0-9]{6}$' THEN
    RAISE EXCEPTION 'La clave CLUES tiene 5 letras y 6 dígitos, por ejemplo NLSSA000123.';
  END IF;
  IF EXISTS (SELECT 1 FROM organizacion WHERE clave_organizacion = v_clave) THEN
    RAISE EXCEPTION 'Ya existe una institución con la clave %.', v_clave;
  END IF;
  IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_calle), '') IS NULL OR NULLIF(trim(p_numero_exterior), '') IS NULL THEN
    RAISE EXCEPTION 'El nombre, la calle y el número exterior son obligatorios.';
  END IF;
  IF p_tipo NOT IN ('hospital','clinica','laboratorio') THEN
    RAISE EXCEPTION 'Tipo de institución inválido.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM codigo_postal WHERE codigo_postal = trim(p_codigo_postal)) THEN
    RAISE EXCEPTION 'El código postal % no está en el catálogo.', p_codigo_postal;
  END IF;
  IF NULLIF(trim(p_contacto_nombre), '') IS NULL THEN
    RAISE EXCEPTION 'Escriba quién es el contacto de la institución.';
  END IF;

  INSERT INTO organizacion (clave_organizacion, nombre, tipo_organizacion, telefono, calle, numero_exterior, colonia, codigo_postal)
  VALUES (v_clave, trim(p_nombre), p_tipo, NULLIF(trim(p_telefono), ''), trim(p_calle), trim(p_numero_exterior),
          NULLIF(trim(p_colonia), ''), trim(p_codigo_postal))
  RETURNING id_organizacion INTO p_id_organizacion;

  INSERT INTO contacto_organizacion (id_organizacion, nombre, correo, es_principal)
  VALUES (p_id_organizacion, trim(p_contacto_nombre), NULLIF(lower(trim(p_contacto_correo)), ''), TRUE);

  IF NULLIF(trim(p_nombre_sistema), '') IS NOT NULL THEN
    INSERT INTO sistema_origen (id_organizacion, nombre_sistema, tipo_sistema, version_sistema, uri_identificador)
    VALUES (p_id_organizacion, trim(p_nombre_sistema), coalesce(p_tipo_sistema, 'expediente_clinico'), '1.0',
            'urn:' || lower(v_clave) || ':' || replace(coalesce(p_tipo_sistema, 'expediente_clinico'), '_', '-'));
  END IF;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'organizacion', p_id_organizacion, NULL, 'exito',
          'Alta de ' || trim(p_nombre) || '.');
END $$;

-- ------------------------------------------------------------
-- SP-20 sp_cambiar_estado_organizacion
-- Propósito: suspender, reactivar o dar de baja una institución.
-- Entrada:   p_id_usuario, p_id_organizacion, p_estado ('activa'|'suspendida'|'inactiva'), p_motivo
-- Salida:    ninguna
-- Tablas:    organizacion, credencial_sistema, sistema_origen, encuentro_clinico, auditoria
-- Reglas:    solo administrador (RN-11); transiciones válidas:
--            activa -> suspendida | inactiva, suspendida -> activa | inactiva;
--            una institución inactiva ya no cambia; motivo obligatorio al
--            suspender o inactivar; al suspender o inactivar se revocan sus
--            credenciales activas; al inactivar sus sistemas quedan inactivos;
--            no se inactiva si tiene consultas planeadas.
-- Excepciones: transición inválida, sin motivo, consultas planeadas.
-- Ejemplo:   CALL sp_cambiar_estado_organizacion(1, 6, 'suspendida', 'Credencial comprometida');
-- Resultado: nuevo estado y credenciales revocadas.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_organizacion(
  p_id_usuario BIGINT, p_id_organizacion BIGINT, p_estado VARCHAR, p_motivo TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  v_actual VARCHAR;
  v_revocadas INT := 0;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  SELECT estado INTO v_actual FROM organizacion WHERE id_organizacion = p_id_organizacion FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La institución % no existe.', p_id_organizacion;
  END IF;
  IF NOT ((v_actual = 'activa' AND p_estado IN ('suspendida','inactiva'))
       OR (v_actual = 'suspendida' AND p_estado IN ('activa','inactiva'))) THEN
    RAISE EXCEPTION 'Cambio no permitido: % -> %.', v_actual, p_estado;
  END IF;
  IF p_estado <> 'activa' AND length(coalesce(trim(p_motivo), '')) < 5 THEN
    RAISE EXCEPTION 'Escriba el motivo del cambio.';
  END IF;
  IF p_estado = 'inactiva' AND EXISTS (SELECT 1 FROM encuentro_clinico
                                       WHERE id_organizacion = p_id_organizacion AND estado = 'planeado') THEN
    RAISE EXCEPTION 'La institución tiene consultas planeadas; cancélelas antes de darla de baja.';
  END IF;

  UPDATE organizacion SET estado = p_estado WHERE id_organizacion = p_id_organizacion;

  IF p_estado IN ('suspendida','inactiva') THEN
    UPDATE credencial_sistema cs SET estado = 'revocada'
      FROM sistema_origen so
     WHERE so.id_sistema_origen = cs.id_sistema_origen AND so.id_organizacion = p_id_organizacion AND cs.estado = 'activa';
    GET DIAGNOSTICS v_revocadas = ROW_COUNT;
  END IF;
  IF p_estado = 'inactiva' THEN
    UPDATE sistema_origen SET estado = 'inactivo' WHERE id_organizacion = p_id_organizacion;
  END IF;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'organizacion', p_id_organizacion, NULL, 'exito',
          format('Estado %s -> %s. Credenciales revocadas: %s.%s', v_actual, p_estado, v_revocadas,
                 coalesce(' Motivo: ' || NULLIF(trim(p_motivo), ''), '')));
END $$;

-- ------------------------------------------------------------
-- SP-21 sp_cambiar_estado_usuario
-- Propósito: activar o desactivar una cuenta de acceso.
-- Entrada:   p_id_usuario (administrador), p_id_objetivo, p_activo
-- Salida:    ninguna
-- Tablas:    usuario, profesional_salud, auditoria
-- Reglas:    solo administrador; un administrador no se desactiva a sí mismo;
--            una cuenta de médico solo se reactiva si su profesional está activo.
-- Excepciones: usuario inexistente, autodesactivación, profesional dado de baja.
-- Ejemplo:   CALL sp_cambiar_estado_usuario(1, 4, TRUE);
-- Resultado: cuenta activada o desactivada.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_usuario(p_id_usuario BIGINT, p_id_objetivo BIGINT, p_activo BOOLEAN)
LANGUAGE plpgsql AS $$
DECLARE
  u RECORD;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  SELECT * INTO u FROM usuario WHERE id_usuario = p_id_objetivo FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario % no existe.', p_id_objetivo;
  END IF;
  IF p_id_objetivo = p_id_usuario AND NOT p_activo THEN
    RAISE EXCEPTION 'No puede desactivar su propia cuenta.';
  END IF;
  IF p_activo AND u.id_profesional IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM profesional_salud WHERE id_profesional = u.id_profesional AND activo) THEN
    RAISE EXCEPTION 'El profesional de esta cuenta está dado de baja; no se puede reactivar.';
  END IF;

  UPDATE usuario SET activo = p_activo WHERE id_usuario = p_id_objetivo;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'usuario', p_id_objetivo, NULL, 'exito',
          CASE WHEN p_activo THEN 'Cuenta activada: ' ELSE 'Cuenta desactivada: ' END || u.correo);
END $$;


-- ============================================================
-- VISTAS PARA LAS PANTALLAS DEL HUB
-- ============================================================

-- De qué institución y sistema llegó cada dato (procedencia -> detalle -> paquete -> sistema -> institución).
CREATE OR REPLACE VIEW v_procedencia_origen AS
SELECT pd.id_procedencia, pd.valor_original, pd.codigo_original, pd.fecha_origen, pd.fecha_recepcion,
       dt.id_detalle, dt.tipo_recurso, pq.id_paquete, pq.tipo_paquete,
       so.id_sistema_origen, so.nombre_sistema, o.id_organizacion, o.nombre AS institucion
FROM procedencia_dato pd
JOIN detalle_transaccion dt ON dt.id_detalle = pd.id_detalle
JOIN paquete_transaccion pq ON pq.id_paquete = dt.id_paquete
JOIN sistema_origen so      ON so.id_sistema_origen = pq.id_sistema_origen
JOIN organizacion o         ON o.id_organizacion = so.id_organizacion;

-- Candidatos a duplicado con nombres de ambos pacientes y quién resolvió.
CREATE OR REPLACE VIEW v_duplicado_resumen AS
SELECT v.*,
       concat_ws(' ', a.nombre, a.apellido_paterno, a.apellido_materno) AS nombre_a,
       concat_ws(' ', b.nombre, b.apellido_paterno, b.apellido_materno) AS nombre_b,
       COALESCE(u.nombre || ' ' || u.apellido_paterno, u.correo) AS resolvio
FROM v_candidato_duplicado v
JOIN paciente_maestro a ON a.id_paciente_maestro = v.id_paciente_a
JOIN paciente_maestro b ON b.id_paciente_maestro = v.id_paciente_b
LEFT JOIN usuario u     ON u.id_usuario = v.id_usuario_resolucion;

-- Conflictos con paciente, tipo de dato, ambos valores con su origen y la regla sugerida.
CREATE OR REPLACE VIEW v_conflicto_resumen AS
SELECT c.id_conflicto, c.campo, c.estado, c.resolucion, c.justificacion, c.fecha_deteccion, c.fecha_resolucion,
       c.id_procedencia_a, c.id_procedencia_b,
       p.id_paciente_maestro,
       concat_ws(' ', pm.nombre, pm.apellido_paterno, pm.apellido_materno) AS paciente,
       p.tipo_dato,
       oa.valor_original AS valor_a, oa.codigo_original AS original_a, oa.fecha_origen AS fecha_a,
       oa.id_organizacion AS id_org_a, oa.institucion AS institucion_a, oa.nombre_sistema AS sistema_a,
       ob.valor_original AS valor_b, ob.codigo_original AS original_b, ob.fecha_origen AS fecha_b,
       ob.id_organizacion AS id_org_b, ob.institucion AS institucion_b, ob.nombre_sistema AS sistema_b,
       r.criterio AS regla_criterio, r.descripcion AS regla_descripcion,
       COALESCE(u.nombre || ' ' || u.apellido_paterno, u.correo) AS resolvio
FROM conflicto_dato c
JOIN v_procedencia_paciente p ON p.id_procedencia = c.id_procedencia_a
JOIN paciente_maestro pm      ON pm.id_paciente_maestro = p.id_paciente_maestro
JOIN v_procedencia_origen oa  ON oa.id_procedencia = c.id_procedencia_a
JOIN v_procedencia_origen ob  ON ob.id_procedencia = c.id_procedencia_b
LEFT JOIN regla_autoridad r   ON r.id_regla = c.id_regla_sugerida
LEFT JOIN usuario u           ON u.id_usuario = c.id_usuario_resolucion;

-- Consentimientos con paciente, quién registró, cuántas autorizaciones y si están por vencer.
CREATE OR REPLACE VIEW v_consentimiento_resumen AS
SELECT c.*,
       'CONS-' || lpad(c.id_consentimiento::text, 5, '0') AS folio,
       concat_ws(' ', p.nombre, p.apellido_paterno, p.apellido_materno) AS paciente,
       COALESCE(u.nombre || ' ' || u.apellido_paterno, u.correo) AS registro,
       (SELECT COUNT(*) FROM consentimiento_alcance a WHERE a.id_consentimiento = c.id_consentimiento AND a.permiso = 'enviar') AS n_enviar,
       (SELECT COUNT(*) FROM consentimiento_alcance a WHERE a.id_consentimiento = c.id_consentimiento AND a.permiso = 'consultar') AS n_consultar,
       (c.estado = 'activo' AND c.fecha_fin <= CURRENT_DATE + 30) AS por_vencer
FROM consentimiento c
JOIN paciente_maestro p ON p.id_paciente_maestro = c.id_paciente_maestro
JOIN usuario u          ON u.id_usuario = c.id_usuario_registro;

-- Paquetes con su origen, número de recursos, errores y tiempo de procesamiento (calculados, no guardados).
CREATE OR REPLACE VIEW v_paquete_resumen AS
SELECT pq.id_paquete, 'PKG-' || lpad(pq.id_paquete::text, 5, '0') AS codigo,
       pq.direccion, pq.tipo_paquete, pq.fecha_recepcion, pq.estado,
       so.id_sistema_origen, so.nombre_sistema, o.id_organizacion, o.nombre AS institucion,
       ps.nombre || ' ' || ps.apellido_paterno AS capturo,
       (SELECT COUNT(*) FROM detalle_transaccion d WHERE d.id_paquete = pq.id_paquete) AS recursos,
       (SELECT COUNT(*) FROM error_validacion ev JOIN detalle_transaccion d ON d.id_detalle = ev.id_detalle
         WHERE d.id_paquete = pq.id_paquete) AS errores,
       (SELECT EXTRACT(EPOCH FROM MAX(d.fecha_procesamiento) - pq.fecha_recepcion)
          FROM detalle_transaccion d WHERE d.id_paquete = pq.id_paquete) AS segundos
FROM paquete_transaccion pq
JOIN sistema_origen so ON so.id_sistema_origen = pq.id_sistema_origen
JOIN organizacion o    ON o.id_organizacion = so.id_organizacion
LEFT JOIN usuario u    ON u.id_usuario = pq.id_usuario_captura
LEFT JOIN profesional_salud ps ON ps.id_profesional = u.id_profesional;

-- Errores de validación con su recurso, paquete, institución y estado de gestión.
CREATE OR REPLACE VIEW v_error_detalle AS
SELECT ev.id_error, ev.codigo_error, ev.severidad, ev.ruta_elemento, ev.descripcion,
       d.id_detalle, d.tipo_recurso, d.id_recurso_externo, d.estado AS estado_recurso,
       CASE d.estado WHEN 'recibido' THEN 'pendiente' WHEN 'rechazado' THEN 'rechazado'
                     WHEN 'validado' THEN 'reprocesado' ELSE 'cerrado' END AS estado_gestion,
       pq.id_paquete, 'PKG-' || lpad(pq.id_paquete::text, 5, '0') AS paquete,
       so.nombre_sistema, o.id_organizacion, o.nombre AS institucion
FROM error_validacion ev
JOIN detalle_transaccion d  ON d.id_detalle = ev.id_detalle
JOIN paquete_transaccion pq ON pq.id_paquete = d.id_paquete
JOIN sistema_origen so      ON so.id_sistema_origen = pq.id_sistema_origen
JOIN organizacion o         ON o.id_organizacion = so.id_organizacion;

-- Instituciones con ubicación, contacto principal, sistemas y credenciales.
CREATE OR REPLACE VIEW v_organizacion_resumen AS
SELECT o.*, cp.municipio, cp.entidad_federativa,
       co.nombre AS contacto, co.puesto AS contacto_puesto, co.telefono AS contacto_telefono, co.correo AS contacto_correo,
       (SELECT COUNT(*) FROM sistema_origen s WHERE s.id_organizacion = o.id_organizacion) AS sistemas,
       (SELECT MIN(cs.fecha_expiracion) FROM credencial_sistema cs JOIN sistema_origen s ON s.id_sistema_origen = cs.id_sistema_origen
         WHERE s.id_organizacion = o.id_organizacion AND cs.estado = 'activa') AS proxima_expiracion,
       (SELECT COUNT(*) FROM encuentro_clinico e WHERE e.id_organizacion = o.id_organizacion) AS consultas
FROM organizacion o
JOIN codigo_postal cp ON cp.codigo_postal = o.codigo_postal
LEFT JOIN contacto_organizacion co ON co.id_organizacion = o.id_organizacion AND co.es_principal;

-- Usuarios con el nombre que se muestra (el de un médico sale de profesional_salud).
CREATE OR REPLACE VIEW v_usuario_resumen AS
SELECT u.id_usuario, u.correo, u.rol, u.activo, u.fecha_registro, u.id_profesional,
       CASE WHEN u.id_profesional IS NULL THEN concat_ws(' ', u.nombre, u.apellido_paterno, u.apellido_materno)
            ELSE concat_ws(' ', ps.nombre, ps.apellido_paterno, ps.apellido_materno) END AS nombre_mostrar,
       ps.cedula_profesional
FROM usuario u
LEFT JOIN profesional_salud ps ON ps.id_profesional = u.id_profesional;

-- Bitácora con el nombre de quien actuó (usuario o sistema externo) y del paciente.
CREATE OR REPLACE VIEW v_auditoria_detalle AS
SELECT a.id_auditoria, a.fecha_hora, a.rol_en_evento, a.accion, a.tabla_afectada, a.id_registro_afectado,
       a.id_paciente_maestro, a.resultado, a.detalle,
       COALESCE(vu.nombre_mostrar, so.nombre_sistema || ' (' || o.nombre || ')') AS quien,
       concat_ws(' ', p.nombre, p.apellido_paterno) AS paciente
FROM auditoria a
LEFT JOIN v_usuario_resumen vu ON vu.id_usuario = a.id_usuario
LEFT JOIN sistema_origen so    ON so.id_sistema_origen = a.id_sistema_origen
LEFT JOIN organizacion o       ON o.id_organizacion = so.id_organizacion
LEFT JOIN paciente_maestro p   ON p.id_paciente_maestro = a.id_paciente_maestro;

COMMENT ON VIEW v_procedencia_origen IS 'Institución y sistema de origen de cada dato.';
COMMENT ON VIEW v_duplicado_resumen IS 'Candidatos a duplicado con nombres y puntaje.';
COMMENT ON VIEW v_conflicto_resumen IS 'Conflictos con ambos valores, su origen y la regla sugerida.';
COMMENT ON VIEW v_consentimiento_resumen IS 'Consentimientos con folio, autorizaciones y aviso de vencimiento.';
COMMENT ON VIEW v_paquete_resumen IS 'Paquetes con recursos, errores y tiempo de procesamiento calculados.';
COMMENT ON VIEW v_error_detalle IS 'Errores de validación con su recurso, institución y estado de gestión.';
COMMENT ON VIEW v_organizacion_resumen IS 'Instituciones con ubicación, contacto, sistemas y credenciales.';
COMMENT ON VIEW v_usuario_resumen IS 'Usuarios con su nombre para mostrar.';
COMMENT ON VIEW v_auditoria_detalle IS 'Bitácora con nombres de quien actuó y del paciente.';


-- ============================================================
-- AJUSTE DE ESCENARIOS DE PRUEBA (idempotente)
-- Deja recursos con error pendientes de decisión del analista y una
-- credencial próxima a vencer, para las pantallas de Errores e Inicio.
-- (04_datos_prueba.sql ya incluye estos valores.)
-- ------------------------------------------------------------
UPDATE detalle_transaccion SET estado = 'recibido', fecha_procesamiento = NULL
 WHERE id_detalle IN (903, 904) AND estado = 'rechazado'
   AND NOT EXISTS (SELECT 1 FROM auditoria WHERE tabla_afectada = 'detalle_transaccion' AND id_registro_afectado IN (903, 904));
UPDATE credencial_sistema SET fecha_expiracion = DATE '2026-11-10'
 WHERE id_sistema_origen = 3 AND estado = 'activa' AND fecha_expiracion = DATE '2027-01-01';
