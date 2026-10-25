-- ============================================================
-- 05_programacion.sql
-- Programación avanzada en PostgreSQL: funciones de apoyo,
-- procedimientos almacenados y vistas.
-- Ejecutar DESPUÉS de 04_datos_prueba.sql. Es re-ejecutable.
--
-- Clasificación (requisito del segundo avance):
--   FUNCIONES (se invocan con SELECT; NO cuentan como procedimientos)
--     fn_verificar_rol, fn_registrar_auditoria, fn_autenticar_usuario
--   PROCEDIMIENTOS (CREATE PROCEDURE, se invocan con CALL): 12
--     Pacientes:     sp_registrar_paciente, sp_actualizar_paciente, sp_baja_paciente
--     Médicos:       sp_registrar_profesional, sp_actualizar_profesional, sp_baja_profesional
--     Consultas:     sp_registrar_encuentro, sp_actualizar_encuentro, sp_cancelar_encuentro
--     Identidad:     sp_resolver_duplicado
--     Consentimiento:sp_revocar_consentimiento
--     Seguridad:     sp_registrar_usuario
--   VISTAS: 6
--     v_paciente_resumen, v_historial_consultas, v_consultas_por_especialidad,
--     v_indicadores_atencion, v_consultas_pendientes, v_profesional_resumen
--
-- Permisos por rol que validan los procedimientos (en el servidor):
--   administrador -> médicos y usuarios
--   coordinador   -> pacientes, duplicados, consentimientos y consultas
--   medico        -> consultas propias (solo como profesional que atiende)
--   analista_integracion -> solo lectura en esta fase
--
-- Convención de errores: RAISE EXCEPTION con mensaje legible para mostrar
-- tal cual en Flask (e.diag.message_primary). Cualquier error deshace la
-- transacción completa del procedimiento.
-- ============================================================


-- ============================================================
-- FUNCIONES DE APOYO
-- ============================================================

-- fn_verificar_rol: valida que el usuario exista, esté activo y tenga uno
-- de los roles permitidos. Devuelve el rol. Lanza excepción si no.
CREATE OR REPLACE FUNCTION fn_verificar_rol(p_id_usuario BIGINT, VARIADIC p_roles TEXT[])
RETURNS VARCHAR
LANGUAGE plpgsql AS $$
DECLARE
  v_rol VARCHAR;
  v_activo BOOLEAN;
BEGIN
  SELECT rol, activo INTO v_rol, v_activo FROM usuario WHERE id_usuario = p_id_usuario;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El usuario % no existe.', p_id_usuario;
  END IF;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'El usuario está inactivo.';
  END IF;
  IF NOT (v_rol = ANY (p_roles)) THEN
    RAISE EXCEPTION 'Operación no autorizada para el rol %.', v_rol;
  END IF;
  RETURN v_rol;
END $$;

-- fn_registrar_auditoria: inserta un evento en la bitácora con el rol que
-- tenía el usuario en ese momento.
CREATE OR REPLACE FUNCTION fn_registrar_auditoria(
  p_id_usuario BIGINT, p_accion VARCHAR, p_tabla VARCHAR, p_id_registro BIGINT,
  p_id_paciente BIGINT, p_resultado VARCHAR, p_detalle TEXT)
RETURNS VOID
LANGUAGE sql AS $$
  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  SELECT p_id_usuario, u.rol, p_accion, p_tabla, p_id_registro, p_id_paciente, p_resultado, p_detalle
  FROM usuario u WHERE u.id_usuario = p_id_usuario;
$$;

-- fn_autenticar_usuario: valida correo y contraseña contra el hash bcrypt.
-- Devuelve una fila si las credenciales son correctas y el usuario está
-- activo; ninguna fila en cualquier otro caso. La usa el login de Flask.
CREATE OR REPLACE FUNCTION fn_autenticar_usuario(p_correo VARCHAR, p_contrasena TEXT)
RETURNS TABLE (id_usuario BIGINT, rol VARCHAR, nombre_mostrar TEXT, id_profesional BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT u.id_usuario, u.rol,
         COALESCE(u.nombre || ' ' || u.apellido_paterno,
                  'Dr(a). ' || ps.nombre || ' ' || ps.apellido_paterno),
         u.id_profesional
  FROM usuario u
  LEFT JOIN profesional_salud ps ON ps.id_profesional = u.id_profesional
  WHERE lower(u.correo) = lower(trim(p_correo))
    AND u.activo
    AND u.hash_contrasena = crypt(p_contrasena, u.hash_contrasena);
$$;


-- ============================================================
-- PROCEDIMIENTOS: PACIENTES
-- ============================================================

-- ------------------------------------------------------------
-- SP-01 sp_registrar_paciente
-- Propósito: dar de alta un paciente maestro desde el portal.
-- Entrada:   p_id_usuario, p_nombre, p_apellido_paterno, p_apellido_materno,
--            p_fecha_nacimiento, p_sexo, p_curp (opcional)
-- Salida:    p_id_paciente (INOUT) = id generado
-- Tablas:    paciente_maestro, usuario, auditoria
-- Reglas:    solo coordinador; nombre y apellido obligatorios; fecha de
--            nacimiento no futura y no mayor a 120 años; CURP con formato
--            oficial y única; si ya existe un paciente activo con el mismo
--            nombre, apellido y fecha de nacimiento se rechaza (posible duplicado).
-- Excepciones: rol no autorizado, datos inválidos, CURP repetida, duplicado.
-- Ejemplo:   CALL sp_registrar_paciente(3,'Laura','Pérez','Soto','1990-05-01','femenino',NULL,NULL);
-- Resultado: devuelve el nuevo id_paciente y registra 'crear' en auditoría.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_paciente(
  p_id_usuario BIGINT, p_nombre VARCHAR, p_apellido_paterno VARCHAR, p_apellido_materno VARCHAR,
  p_fecha_nacimiento DATE, p_sexo VARCHAR, p_curp VARCHAR, INOUT p_id_paciente BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_curp VARCHAR := NULLIF(upper(trim(p_curp)), '');
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_apellido_paterno), '') IS NULL THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;
  IF p_fecha_nacimiento IS NULL OR p_fecha_nacimiento > CURRENT_DATE
     OR p_fecha_nacimiento < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'La fecha de nacimiento no es válida.';
  END IF;
  IF v_curp IS NOT NULL AND v_curp !~ '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9][0-9]$' THEN
    RAISE EXCEPTION 'La CURP % no tiene un formato válido.', v_curp;
  END IF;
  IF v_curp IS NOT NULL AND EXISTS (SELECT 1 FROM paciente_maestro WHERE curp = v_curp) THEN
    RAISE EXCEPTION 'Ya existe un paciente con la CURP %.', v_curp;
  END IF;
  IF EXISTS (SELECT 1 FROM paciente_maestro
             WHERE lower(nombre) = lower(trim(p_nombre))
               AND lower(apellido_paterno) = lower(trim(p_apellido_paterno))
               AND fecha_nacimiento = p_fecha_nacimiento
               AND estado = 'activo') THEN
    RAISE EXCEPTION 'Ya existe un paciente activo con el mismo nombre, apellido y fecha de nacimiento.';
  END IF;

  INSERT INTO paciente_maestro (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo)
  VALUES (v_curp, trim(p_nombre), trim(p_apellido_paterno), NULLIF(trim(p_apellido_materno), ''),
          p_fecha_nacimiento, p_sexo)
  RETURNING id_paciente_maestro INTO p_id_paciente;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito', 'Alta de paciente.');
END $$;

-- ------------------------------------------------------------
-- SP-02 sp_actualizar_paciente
-- Propósito: modificar los datos consolidados de un paciente.
-- Entrada:   p_id_usuario, p_id_paciente, nombre, apellidos, fecha de nacimiento, sexo, CURP
-- Salida:    ninguna
-- Tablas:    paciente_maestro, auditoria
-- Reglas:    solo coordinador; solo pacientes activos (un fusionado o
--            inactivo no se edita); mismas validaciones que el alta; la CURP
--            no puede pertenecer a otro paciente; actualiza fecha_actualizacion.
-- Excepciones: paciente inexistente o no activo, datos inválidos, CURP repetida.
-- Ejemplo:   CALL sp_actualizar_paciente(3, 1,'José Luis','García','Treviño','1985-03-12','masculino','GATJ850312HNLRRS01');
-- Resultado: fila actualizada y evento 'actualizar' en auditoría.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_actualizar_paciente(
  p_id_usuario BIGINT, p_id_paciente BIGINT, p_nombre VARCHAR, p_apellido_paterno VARCHAR,
  p_apellido_materno VARCHAR, p_fecha_nacimiento DATE, p_sexo VARCHAR, p_curp VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  v_estado VARCHAR;
  v_curp VARCHAR := NULLIF(upper(trim(p_curp)), '');
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  SELECT estado INTO v_estado FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El paciente % no existe.', p_id_paciente;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se pueden modificar pacientes activos (estado actual: %).', v_estado;
  END IF;
  IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_apellido_paterno), '') IS NULL THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;
  IF p_fecha_nacimiento IS NULL OR p_fecha_nacimiento > CURRENT_DATE
     OR p_fecha_nacimiento < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'La fecha de nacimiento no es válida.';
  END IF;
  IF v_curp IS NOT NULL AND v_curp !~ '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9][0-9]$' THEN
    RAISE EXCEPTION 'La CURP % no tiene un formato válido.', v_curp;
  END IF;
  IF v_curp IS NOT NULL AND EXISTS (SELECT 1 FROM paciente_maestro
                                    WHERE curp = v_curp AND id_paciente_maestro <> p_id_paciente) THEN
    RAISE EXCEPTION 'La CURP % ya pertenece a otro paciente.', v_curp;
  END IF;

  UPDATE paciente_maestro
     SET nombre = trim(p_nombre), apellido_paterno = trim(p_apellido_paterno),
         apellido_materno = NULLIF(trim(p_apellido_materno), ''),
         fecha_nacimiento = p_fecha_nacimiento, sexo = p_sexo, curp = v_curp,
         fecha_actualizacion = CURRENT_TIMESTAMP
   WHERE id_paciente_maestro = p_id_paciente;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito', 'Actualización de datos del paciente.');
END $$;

-- ------------------------------------------------------------
-- SP-03 sp_baja_paciente
-- Propósito: baja lógica de un paciente (no se borra: conserva su historial).
-- Entrada:   p_id_usuario, p_id_paciente, p_motivo
-- Salida:    p_consultas_canceladas (INOUT) = consultas planeadas que se cancelaron
-- Tablas:    paciente_maestro, encuentro_clinico, auditoria
-- Reglas:    solo coordinador; el paciente debe estar activo; motivo obligatorio;
--            las consultas planeadas a futuro se cancelan; las consultas
--            finalizadas, diagnósticos y resultados se conservan intactos.
-- Excepciones: paciente inexistente, ya inactivo o fusionado, sin motivo.
-- Ejemplo:   CALL sp_baja_paciente(3, 28, 'Cambio de residencia', NULL);
-- Resultado: estado = 'inactivo'; devuelve cuántas consultas se cancelaron.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_baja_paciente(
  p_id_usuario BIGINT, p_id_paciente BIGINT, p_motivo VARCHAR, INOUT p_consultas_canceladas INT)
LANGUAGE plpgsql AS $$
DECLARE
  v_estado VARCHAR;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF NULLIF(trim(p_motivo), '') IS NULL THEN
    RAISE EXCEPTION 'El motivo de la baja es obligatorio.';
  END IF;
  SELECT estado INTO v_estado FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El paciente % no existe.', p_id_paciente;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'El paciente no está activo (estado actual: %).', v_estado;
  END IF;

  UPDATE paciente_maestro
     SET estado = 'inactivo', fecha_actualizacion = CURRENT_TIMESTAMP
   WHERE id_paciente_maestro = p_id_paciente;

  UPDATE encuentro_clinico
     SET estado = 'cancelado'
   WHERE id_paciente_maestro = p_id_paciente AND estado = 'planeado';
  GET DIAGNOSTICS p_consultas_canceladas = ROW_COUNT;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'eliminar', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito',
          format('Baja lógica. Motivo: %s. Consultas planeadas canceladas: %s.', p_motivo, p_consultas_canceladas));
END $$;


-- ============================================================
-- PROCEDIMIENTOS: MÉDICOS (PROFESIONALES DE SALUD)
-- ============================================================

-- ------------------------------------------------------------
-- SP-04 sp_registrar_profesional
-- Propósito: alta de un profesional con su especialidad y su vínculo con una
--            institución, en una sola transacción.
-- Entrada:   p_id_usuario, p_cedula, p_nombre, p_apellido_paterno, p_apellido_materno,
--            p_especialidad, p_cedula_especialidad, p_id_organizacion, p_rol_organizacion
-- Salida:    p_id_profesional (INOUT)
-- Tablas:    profesional_salud, profesional_especialidad, profesional_organizacion,
--            organizacion, auditoria
-- Reglas:    solo administrador; cédula de 7 u 8 dígitos y única; la
--            institución debe estar activa; el vínculo inicia hoy.
-- Excepciones: rol no autorizado, cédula inválida o repetida, institución no activa.
-- Ejemplo:   CALL sp_registrar_profesional(1,'9100150','Sofía','Garza','Lee','Pediatría','E9205001',1,'medico_tratante',NULL);
-- Resultado: tres inserciones relacionadas y el id del profesional.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_profesional(
  p_id_usuario BIGINT, p_cedula VARCHAR, p_nombre VARCHAR, p_apellido_paterno VARCHAR,
  p_apellido_materno VARCHAR, p_especialidad VARCHAR, p_cedula_especialidad VARCHAR,
  p_id_organizacion BIGINT, p_rol_organizacion VARCHAR, INOUT p_id_profesional BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_estado_org VARCHAR;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  IF trim(p_cedula) !~ '^[0-9]{7,8}$' THEN
    RAISE EXCEPTION 'La cédula profesional debe tener 7 u 8 dígitos.';
  END IF;
  IF EXISTS (SELECT 1 FROM profesional_salud WHERE cedula_profesional = trim(p_cedula)) THEN
    RAISE EXCEPTION 'Ya existe un profesional con la cédula %.', trim(p_cedula);
  END IF;
  IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_apellido_paterno), '') IS NULL THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;
  SELECT estado INTO v_estado_org FROM organizacion WHERE id_organizacion = p_id_organizacion;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La institución % no existe.', p_id_organizacion;
  END IF;
  IF v_estado_org <> 'activa' THEN
    RAISE EXCEPTION 'La institución no está activa (estado: %).', v_estado_org;
  END IF;

  INSERT INTO profesional_salud (cedula_profesional, nombre, apellido_paterno, apellido_materno)
  VALUES (trim(p_cedula), trim(p_nombre), trim(p_apellido_paterno), NULLIF(trim(p_apellido_materno), ''))
  RETURNING id_profesional INTO p_id_profesional;

  IF NULLIF(trim(p_especialidad), '') IS NOT NULL THEN
    INSERT INTO profesional_especialidad (id_profesional, especialidad, cedula_especialidad)
    VALUES (p_id_profesional, trim(p_especialidad), NULLIF(trim(p_cedula_especialidad), ''));
  END IF;

  INSERT INTO profesional_organizacion (id_profesional, id_organizacion, rol, fecha_inicio)
  VALUES (p_id_profesional, p_id_organizacion, p_rol_organizacion, CURRENT_DATE);

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'profesional_salud', p_id_profesional, NULL, 'exito', 'Alta de profesional.');
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'La cédula de especialidad ya está registrada para otro profesional.';
END $$;

-- ------------------------------------------------------------
-- SP-05 sp_actualizar_profesional
-- Propósito: modificar nombre, apellidos y cédula de un profesional activo.
-- Entrada:   p_id_usuario, p_id_profesional, p_cedula, p_nombre, p_apellido_paterno, p_apellido_materno
-- Salida:    ninguna
-- Tablas:    profesional_salud, auditoria
-- Reglas:    solo administrador; el profesional debe estar activo; la
--            cédula conserva formato y unicidad.
-- Excepciones: profesional inexistente o inactivo, cédula inválida o repetida.
-- Ejemplo:   CALL sp_actualizar_profesional(1, 2,'9100102','Laura','Salinas','Cantú');
-- Resultado: fila actualizada y evento en auditoría.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_actualizar_profesional(
  p_id_usuario BIGINT, p_id_profesional BIGINT, p_cedula VARCHAR, p_nombre VARCHAR,
  p_apellido_paterno VARCHAR, p_apellido_materno VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  v_activo BOOLEAN;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  SELECT activo INTO v_activo FROM profesional_salud WHERE id_profesional = p_id_profesional FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El profesional % no existe.', p_id_profesional;
  END IF;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'No se puede modificar un profesional dado de baja.';
  END IF;
  IF trim(p_cedula) !~ '^[0-9]{7,8}$' THEN
    RAISE EXCEPTION 'La cédula profesional debe tener 7 u 8 dígitos.';
  END IF;
  IF EXISTS (SELECT 1 FROM profesional_salud
             WHERE cedula_profesional = trim(p_cedula) AND id_profesional <> p_id_profesional) THEN
    RAISE EXCEPTION 'La cédula % ya pertenece a otro profesional.', trim(p_cedula);
  END IF;
  IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_apellido_paterno), '') IS NULL THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;

  UPDATE profesional_salud
     SET cedula_profesional = trim(p_cedula), nombre = trim(p_nombre),
         apellido_paterno = trim(p_apellido_paterno), apellido_materno = NULLIF(trim(p_apellido_materno), '')
   WHERE id_profesional = p_id_profesional;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'profesional_salud', p_id_profesional, NULL, 'exito', 'Actualización de profesional.');
END $$;

-- ------------------------------------------------------------
-- SP-06 sp_baja_profesional
-- Propósito: baja lógica de un profesional.
-- Entrada:   p_id_usuario, p_id_profesional
-- Salida:    ninguna
-- Tablas:    profesional_salud, profesional_organizacion, encuentro_clinico, usuario, auditoria
-- Reglas:    solo administrador; no procede si el profesional tiene consultas
--            planeadas o en curso (deben reasignarse o cancelarse antes);
--            cierra sus vínculos vigentes con fecha de hoy y desactiva su
--            cuenta de usuario; sus consultas históricas se conservan.
-- Excepciones: profesional inexistente o ya inactivo, consultas pendientes.
-- Ejemplo:   CALL sp_baja_profesional(1, 12);
-- Resultado: activo = false, vínculos cerrados, usuario desactivado.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_baja_profesional(p_id_usuario BIGINT, p_id_profesional BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_activo BOOLEAN;
  v_pendientes INT;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  SELECT activo INTO v_activo FROM profesional_salud WHERE id_profesional = p_id_profesional FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El profesional % no existe.', p_id_profesional;
  END IF;
  IF NOT v_activo THEN
    RAISE EXCEPTION 'El profesional ya está dado de baja.';
  END IF;

  SELECT COUNT(*) INTO v_pendientes FROM encuentro_clinico
   WHERE id_profesional = p_id_profesional AND estado IN ('planeado','en_curso');
  IF v_pendientes > 0 THEN
    RAISE EXCEPTION 'El profesional tiene % consulta(s) planeada(s) o en curso; cancélelas antes de la baja.', v_pendientes;
  END IF;

  UPDATE profesional_salud SET activo = FALSE WHERE id_profesional = p_id_profesional;

  UPDATE profesional_organizacion
     SET fecha_fin = GREATEST(CURRENT_DATE, fecha_inicio + 1)
   WHERE id_profesional = p_id_profesional AND fecha_fin IS NULL;

  UPDATE usuario SET activo = FALSE WHERE id_profesional = p_id_profesional;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'eliminar', 'profesional_salud', p_id_profesional, NULL, 'exito', 'Baja lógica de profesional.');
END $$;


-- ============================================================
-- PROCEDIMIENTOS: CONSULTAS (ENCUENTROS CLÍNICOS)
-- ============================================================

-- ------------------------------------------------------------
-- SP-07 sp_registrar_encuentro
-- Propósito: registrar una consulta capturada en el portal. Además del
--            encuentro crea su rastro de procedencia (paquete captura_portal,
--            detalle y procedencia), como exige el modelo.
-- Entrada:   p_id_usuario, p_id_paciente, p_id_organizacion, p_id_profesional,
--            p_tipo_encuentro, p_motivo, p_fecha_inicio
-- Salida:    p_id_encuentro (INOUT)
-- Tablas:    encuentro_clinico, paquete_transaccion, detalle_transaccion,
--            procedencia_dato, sistema_origen, paciente_maestro,
--            profesional_salud, profesional_organizacion, organizacion, auditoria
-- Reglas:    coordinador o médico; un médico solo registra consultas propias;
--            paciente activo; institución activa; profesional activo y con
--            vínculo vigente en esa institución; el profesional no puede tener
--            otra consulta no cancelada en el mismo horario (±30 min);
--            fecha futura -> 'planeado', fecha pasada o actual -> 'en_curso'.
-- Excepciones: cualquier regla anterior incumplida.
-- Ejemplo:   CALL sp_registrar_encuentro(5, 1, 1, 1,'consulta_externa','Control','2026-11-03 10:00-06',NULL);
-- Resultado: id del nuevo encuentro y 4 inserciones relacionadas.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_encuentro(
  p_id_usuario BIGINT, p_id_paciente BIGINT, p_id_organizacion BIGINT, p_id_profesional BIGINT,
  p_tipo_encuentro VARCHAR, p_motivo VARCHAR, p_fecha_inicio TIMESTAMPTZ, INOUT p_id_encuentro BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_rol VARCHAR;
  v_prof_usuario BIGINT;
  v_sistema BIGINT;
  v_paquete BIGINT;
  v_detalle BIGINT;
  v_procedencia BIGINT;
  v_estado VARCHAR;
BEGIN
  v_rol := fn_verificar_rol(p_id_usuario, 'coordinador', 'medico');

  IF v_rol = 'medico' THEN
    SELECT id_profesional INTO v_prof_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    IF p_id_profesional IS DISTINCT FROM v_prof_usuario THEN
      RAISE EXCEPTION 'Un médico solo puede registrar consultas a su nombre.';
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente AND estado = 'activo') THEN
    RAISE EXCEPTION 'El paciente no existe o no está activo.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM organizacion WHERE id_organizacion = p_id_organizacion AND estado = 'activa') THEN
    RAISE EXCEPTION 'La institución no existe o no está activa.';
  END IF;
  IF p_fecha_inicio IS NULL THEN
    RAISE EXCEPTION 'La fecha y hora de la consulta son obligatorias.';
  END IF;

  IF p_id_profesional IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM profesional_salud WHERE id_profesional = p_id_profesional AND activo) THEN
      RAISE EXCEPTION 'El profesional no existe o está dado de baja.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profesional_organizacion
                   WHERE id_profesional = p_id_profesional AND id_organizacion = p_id_organizacion
                     AND fecha_inicio <= p_fecha_inicio::date
                     AND (fecha_fin IS NULL OR fecha_fin >= p_fecha_inicio::date)) THEN
      RAISE EXCEPTION 'El profesional no tiene un vínculo vigente con esa institución.';
    END IF;
    IF EXISTS (SELECT 1 FROM encuentro_clinico
               WHERE id_profesional = p_id_profesional AND estado <> 'cancelado'
                 AND fecha_inicio BETWEEN p_fecha_inicio - INTERVAL '29 minutes'
                                      AND p_fecha_inicio + INTERVAL '29 minutes') THEN
      RAISE EXCEPTION 'El profesional ya tiene una consulta en ese horario.';
    END IF;
  END IF;

  SELECT id_sistema_origen INTO v_sistema FROM sistema_origen
   WHERE tipo_sistema = 'portal_hub' AND estado = 'activo' ORDER BY id_sistema_origen LIMIT 1;
  IF v_sistema IS NULL THEN
    RAISE EXCEPTION 'No hay un sistema de portal activo configurado.';
  END IF;

  v_estado := CASE WHEN p_fecha_inicio > CURRENT_TIMESTAMP THEN 'planeado' ELSE 'en_curso' END;

  INSERT INTO paquete_transaccion (id_sistema_origen, id_usuario_captura, direccion, tipo_paquete, estado, hash_paquete)
  VALUES (v_sistema, p_id_usuario, 'entrante', 'captura_portal', 'procesado',
          encode(sha256(convert_to(format('captura|%s|%s|%s', p_id_paciente, clock_timestamp(), gen_random_uuid()), 'UTF8')), 'hex'))
  RETURNING id_paquete INTO v_paquete;

  INSERT INTO detalle_transaccion (id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso,
                                   fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
  VALUES (v_paquete, p_id_paciente, 'Encounter', 'Encounter-portal-' || v_paquete, '1',
          CURRENT_TIMESTAMP, 'integrado',
          encode(sha256(convert_to(format('encuentro|%s|%s', v_paquete, clock_timestamp()), 'UTF8')), 'hex'),
          CURRENT_TIMESTAMP)
  RETURNING id_detalle INTO v_detalle;

  INSERT INTO procedencia_dato (id_detalle, ruta_elemento, valor_original, fecha_origen)
  VALUES (v_detalle, 'Encounter', p_tipo_encuentro || ' - ' || coalesce(p_motivo, ''), CURRENT_TIMESTAMP)
  RETURNING id_procedencia INTO v_procedencia;

  INSERT INTO encuentro_clinico (id_paciente_maestro, id_organizacion, id_profesional, id_procedencia,
                                 tipo_encuentro, motivo, fecha_inicio, estado)
  VALUES (p_id_paciente, p_id_organizacion, p_id_profesional, v_procedencia,
          p_tipo_encuentro, NULLIF(trim(p_motivo), ''), p_fecha_inicio, v_estado)
  RETURNING id_encuentro INTO p_id_encuentro;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'encuentro_clinico', p_id_encuentro, p_id_paciente, 'exito',
          format('Consulta registrada en el portal (estado %s).', v_estado));
END $$;

-- ------------------------------------------------------------
-- SP-08 sp_actualizar_encuentro
-- Propósito: modificar motivo y fecha de una consulta, o avanzar su estado
--            (planeado -> en_curso -> finalizado). Cada cambio queda en version_dato.
-- Entrada:   p_id_usuario, p_id_encuentro, p_motivo, p_fecha_inicio, p_estado
-- Salida:    ninguna
-- Tablas:    encuentro_clinico, version_dato, usuario, auditoria
-- Reglas:    coordinador o el médico que atiende; una consulta finalizada o
--            cancelada ya no se modifica; transiciones válidas:
--            planeado->planeado|en_curso, en_curso->en_curso|finalizado
--            (para cancelar se usa sp_cancelar_encuentro); al finalizar se
--            registra fecha_fin; la fecha solo cambia mientras está planeada.
-- Excepciones: consulta inexistente, cerrada, transición inválida, sin permiso.
-- Ejemplo:   CALL sp_actualizar_encuentro(5, 48,'Control de glucosa','2026-10-21 09:00-06','en_curso');
-- Resultado: encuentro actualizado; una fila en version_dato por campo cambiado.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_actualizar_encuentro(
  p_id_usuario BIGINT, p_id_encuentro BIGINT, p_motivo VARCHAR, p_fecha_inicio TIMESTAMPTZ, p_estado VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  v_rol VARCHAR;
  e RECORD;
  v_motivo VARCHAR := NULLIF(trim(p_motivo), '');
BEGIN
  v_rol := fn_verificar_rol(p_id_usuario, 'coordinador', 'medico');

  SELECT * INTO e FROM encuentro_clinico WHERE id_encuentro = p_id_encuentro FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La consulta % no existe.', p_id_encuentro;
  END IF;
  IF v_rol = 'medico' AND e.id_profesional IS DISTINCT FROM (SELECT id_profesional FROM usuario WHERE id_usuario = p_id_usuario) THEN
    RAISE EXCEPTION 'Un médico solo puede modificar sus propias consultas.';
  END IF;
  IF e.estado IN ('finalizado','cancelado') THEN
    RAISE EXCEPTION 'La consulta ya está en estado % y no se puede modificar.', e.estado;
  END IF;
  IF NOT ((e.estado = 'planeado' AND p_estado IN ('planeado','en_curso'))
       OR (e.estado = 'en_curso' AND p_estado IN ('en_curso','finalizado'))) THEN
    RAISE EXCEPTION 'Cambio de estado no permitido: % -> %.', e.estado, p_estado;
  END IF;
  IF p_fecha_inicio IS DISTINCT FROM e.fecha_inicio AND e.estado <> 'planeado' THEN
    RAISE EXCEPTION 'La fecha solo se puede cambiar mientras la consulta está planeada.';
  END IF;

  -- Historial de cambios (un registro por campo modificado)
  INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
  SELECT e.id_procedencia, c.campo,
         COALESCE((SELECT MAX(numero_version) FROM version_dato v
                   WHERE v.id_procedencia = e.id_procedencia AND v.campo = c.campo), 0) + 1,
         c.anterior, c.nuevo, p_id_usuario, 'Edición desde el portal.'
  FROM (VALUES ('motivo', e.motivo::text, v_motivo::text),
               ('fecha_inicio', e.fecha_inicio::text, p_fecha_inicio::text),
               ('estado', e.estado::text, p_estado::text)) AS c(campo, anterior, nuevo)
  WHERE c.anterior IS DISTINCT FROM c.nuevo;

  UPDATE encuentro_clinico
     SET motivo = v_motivo,
         fecha_inicio = p_fecha_inicio,
         estado = p_estado,
         fecha_fin = CASE WHEN p_estado = 'finalizado' THEN GREATEST(CURRENT_TIMESTAMP, p_fecha_inicio) ELSE NULL END
   WHERE id_encuentro = p_id_encuentro;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'encuentro_clinico', p_id_encuentro, e.id_paciente_maestro, 'exito',
          format('Consulta actualizada (%s -> %s).', e.estado, p_estado));
END $$;

-- ------------------------------------------------------------
-- SP-09 sp_cancelar_encuentro
-- Propósito: baja lógica de una consulta (se cancela, no se borra).
-- Entrada:   p_id_usuario, p_id_encuentro, p_motivo
-- Salida:    ninguna
-- Tablas:    encuentro_clinico, diagnostico, observacion, solicitud_medicamento,
--            version_dato, auditoria
-- Reglas:    coordinador o el médico que atiende; solo consultas planeadas o
--            en curso; no se cancela una consulta que ya tiene diagnósticos,
--            observaciones o medicamentos registrados; motivo obligatorio.
-- Excepciones: consulta inexistente o cerrada, con información clínica, sin motivo.
-- Ejemplo:   CALL sp_cancelar_encuentro(3, 49,'El paciente no podrá asistir');
-- Resultado: estado = 'cancelado' y registro en version_dato.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_encuentro(p_id_usuario BIGINT, p_id_encuentro BIGINT, p_motivo VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  v_rol VARCHAR;
  e RECORD;
BEGIN
  v_rol := fn_verificar_rol(p_id_usuario, 'coordinador', 'medico');

  IF NULLIF(trim(p_motivo), '') IS NULL THEN
    RAISE EXCEPTION 'El motivo de la cancelación es obligatorio.';
  END IF;
  SELECT * INTO e FROM encuentro_clinico WHERE id_encuentro = p_id_encuentro FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La consulta % no existe.', p_id_encuentro;
  END IF;
  IF v_rol = 'medico' AND e.id_profesional IS DISTINCT FROM (SELECT id_profesional FROM usuario WHERE id_usuario = p_id_usuario) THEN
    RAISE EXCEPTION 'Un médico solo puede cancelar sus propias consultas.';
  END IF;
  IF e.estado NOT IN ('planeado','en_curso') THEN
    RAISE EXCEPTION 'Solo se cancelan consultas planeadas o en curso (estado actual: %).', e.estado;
  END IF;
  IF EXISTS (SELECT 1 FROM diagnostico WHERE id_encuentro = p_id_encuentro)
     OR EXISTS (SELECT 1 FROM observacion WHERE id_encuentro = p_id_encuentro)
     OR EXISTS (SELECT 1 FROM solicitud_medicamento WHERE id_encuentro = p_id_encuentro) THEN
    RAISE EXCEPTION 'La consulta ya tiene información clínica registrada y no puede cancelarse.';
  END IF;

  INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
  VALUES (e.id_procedencia, 'estado',
          COALESCE((SELECT MAX(numero_version) FROM version_dato
                    WHERE id_procedencia = e.id_procedencia AND campo = 'estado'), 0) + 1,
          e.estado, 'cancelado', p_id_usuario, left(p_motivo, 200));

  UPDATE encuentro_clinico SET estado = 'cancelado', fecha_fin = NULL WHERE id_encuentro = p_id_encuentro;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'eliminar', 'encuentro_clinico', p_id_encuentro, e.id_paciente_maestro, 'exito',
          'Cancelación: ' || p_motivo);
END $$;


-- ============================================================
-- PROCEDIMIENTOS: IDENTIDAD, CONSENTIMIENTO Y SEGURIDAD
-- ============================================================

-- ------------------------------------------------------------
-- SP-10 sp_resolver_duplicado
-- Propósito: decidir un candidato a duplicado: fusionar los dos pacientes
--            en uno o descartar la coincidencia.
-- Entrada:   p_id_usuario, p_id_candidato, p_decision ('fusionar'|'descartar'), p_justificacion
-- Salida:    ninguna
-- Tablas:    candidato_duplicado, paciente_maestro, identificador_paciente,
--            nombre_paciente, contacto_paciente, direccion_paciente, alergia,
--            encuentro_clinico, detalle_transaccion, consentimiento, auditoria
-- Reglas:    solo coordinador (RN-07); el candidato debe estar pendiente;
--            justificación obligatoria; al fusionar, el paciente B se integra
--            en A (id menor): todos sus datos pasan a A, sus identificadores
--            oficiales en sistemas donde A ya tiene uno quedan como 'antiguo',
--            sus nombres quedan como 'alias' y B queda 'fusionado' apuntando a A.
-- Excepciones: candidato inexistente o ya resuelto, decisión inválida,
--            alguno de los pacientes ya no está activo.
-- Ejemplo:   CALL sp_resolver_duplicado(3, 1,'fusionar','Misma persona confirmada con el paciente.');
-- Resultado: datos de B movidos a A; candidato 'fusionado'.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_resolver_duplicado(
  p_id_usuario BIGINT, p_id_candidato BIGINT, p_decision VARCHAR, p_justificacion TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  c RECORD;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF p_decision NOT IN ('fusionar','descartar') THEN
    RAISE EXCEPTION 'Decisión inválida: use fusionar o descartar.';
  END IF;
  IF NULLIF(trim(p_justificacion), '') IS NULL THEN
    RAISE EXCEPTION 'La justificación es obligatoria.';
  END IF;
  SELECT * INTO c FROM candidato_duplicado WHERE id_candidato = p_id_candidato FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El candidato % no existe.', p_id_candidato;
  END IF;
  IF c.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'El candidato ya fue resuelto (%).', c.estado;
  END IF;

  IF p_decision = 'descartar' THEN
    UPDATE candidato_duplicado
       SET estado = 'descartado', id_usuario_resolucion = p_id_usuario,
           fecha_resolucion = CURRENT_TIMESTAMP, justificacion = p_justificacion
     WHERE id_candidato = p_id_candidato;
    PERFORM fn_registrar_auditoria(p_id_usuario, 'resolver', 'candidato_duplicado', p_id_candidato, c.id_paciente_a, 'exito', 'Duplicado descartado.');
    RETURN;
  END IF;

  IF (SELECT COUNT(*) FROM paciente_maestro
      WHERE id_paciente_maestro IN (c.id_paciente_a, c.id_paciente_b) AND estado = 'activo') <> 2 THEN
    RAISE EXCEPTION 'Ambos pacientes deben estar activos para fusionarlos.';
  END IF;

  -- Identificadores: el oficial de B en un sistema donde A ya tiene oficial pasa a 'antiguo'
  UPDATE identificador_paciente ib SET uso = 'antiguo'
   WHERE ib.id_paciente_maestro = c.id_paciente_b AND ib.uso = 'oficial'
     AND EXISTS (SELECT 1 FROM identificador_paciente ia
                 WHERE ia.id_paciente_maestro = c.id_paciente_a
                   AND ia.id_sistema_origen = ib.id_sistema_origen AND ia.uso = 'oficial');
  UPDATE identificador_paciente SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;

  UPDATE nombre_paciente     SET id_paciente_maestro = c.id_paciente_a, uso = 'alias' WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE contacto_paciente   SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE direccion_paciente  SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE alergia             SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE encuentro_clinico   SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE detalle_transaccion SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;
  UPDATE consentimiento      SET id_paciente_maestro = c.id_paciente_a WHERE id_paciente_maestro = c.id_paciente_b;

  UPDATE paciente_maestro
     SET estado = 'fusionado', id_paciente_fusionado_en = c.id_paciente_a, fecha_actualizacion = CURRENT_TIMESTAMP
   WHERE id_paciente_maestro = c.id_paciente_b;

  UPDATE candidato_duplicado
     SET estado = 'fusionado', id_usuario_resolucion = p_id_usuario,
         fecha_resolucion = CURRENT_TIMESTAMP, justificacion = p_justificacion
   WHERE id_candidato = p_id_candidato;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'fusionar', 'paciente_maestro', c.id_paciente_b, c.id_paciente_a, 'exito',
          format('Paciente %s fusionado en %s.', c.id_paciente_b, c.id_paciente_a));
END $$;

-- ------------------------------------------------------------
-- SP-11 sp_revocar_consentimiento
-- Propósito: revocar un consentimiento activo a petición del paciente.
-- Entrada:   p_id_usuario, p_id_consentimiento, p_motivo
-- Salida:    ninguna
-- Tablas:    consentimiento, auditoria
-- Reglas:    solo coordinador (RN-10); solo consentimientos activos;
--            motivo obligatorio; la revocación aplica desde hoy.
-- Excepciones: consentimiento inexistente o no activo, sin motivo.
-- Ejemplo:   CALL sp_revocar_consentimiento(3, 5,'Solicitud del paciente');
-- Resultado: estado = 'revocado' con fecha y motivo.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_revocar_consentimiento(p_id_usuario BIGINT, p_id_consentimiento BIGINT, p_motivo VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  c RECORD;
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'coordinador');

  IF NULLIF(trim(p_motivo), '') IS NULL THEN
    RAISE EXCEPTION 'El motivo de la revocación es obligatorio.';
  END IF;
  SELECT * INTO c FROM consentimiento WHERE id_consentimiento = p_id_consentimiento FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El consentimiento % no existe.', p_id_consentimiento;
  END IF;
  IF c.estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se revocan consentimientos activos (estado actual: %).', c.estado;
  END IF;

  UPDATE consentimiento
     SET estado = 'revocado', fecha_revocacion = CURRENT_DATE, motivo_revocacion = trim(p_motivo)
   WHERE id_consentimiento = p_id_consentimiento;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'actualizar', 'consentimiento', p_id_consentimiento, c.id_paciente_maestro, 'exito',
          'Revocación: ' || p_motivo);
END $$;

-- ------------------------------------------------------------
-- SP-12 sp_registrar_usuario
-- Propósito: crear una cuenta de acceso con contraseña cifrada (bcrypt).
-- Entrada:   p_id_usuario (administrador), p_correo, p_contrasena, p_rol,
--            p_nombre, p_apellido_paterno, p_apellido_materno, p_id_profesional
-- Salida:    p_id_nuevo (INOUT)
-- Tablas:    usuario, profesional_salud, auditoria
-- Reglas:    solo administrador; correo con formato válido y único;
--            contraseña de al menos 8 caracteres; si el rol es médico debe
--            ligarse a un profesional activo sin cuenta (su nombre se toma de
--            profesional_salud); en otro rol se exigen nombre y apellido.
-- Excepciones: correo inválido o repetido, contraseña corta, profesional inválido.
-- Ejemplo:   CALL sp_registrar_usuario(1,'medico3@flojorama.mx','Segura2026!','medico',NULL,NULL,NULL,2,NULL);
-- Resultado: id del nuevo usuario; la contraseña se guarda solo como hash.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_usuario(
  p_id_usuario BIGINT, p_correo VARCHAR, p_contrasena TEXT, p_rol VARCHAR,
  p_nombre VARCHAR, p_apellido_paterno VARCHAR, p_apellido_materno VARCHAR,
  p_id_profesional BIGINT, INOUT p_id_nuevo BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
  v_correo VARCHAR := lower(trim(p_correo));
BEGIN
  PERFORM fn_verificar_rol(p_id_usuario, 'administrador');

  IF v_correo !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' THEN
    RAISE EXCEPTION 'El correo % no es válido.', p_correo;
  END IF;
  IF EXISTS (SELECT 1 FROM usuario WHERE lower(correo) = v_correo) THEN
    RAISE EXCEPTION 'Ya existe un usuario con el correo %.', v_correo;
  END IF;
  IF length(coalesce(p_contrasena, '')) < 8 THEN
    RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres.';
  END IF;
  IF p_rol NOT IN ('administrador','analista_integracion','coordinador','medico') THEN
    RAISE EXCEPTION 'Rol inválido: %.', p_rol;
  END IF;

  IF p_rol = 'medico' THEN
    IF NOT EXISTS (SELECT 1 FROM profesional_salud WHERE id_profesional = p_id_profesional AND activo) THEN
      RAISE EXCEPTION 'Un usuario médico debe ligarse a un profesional activo.';
    END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE id_profesional = p_id_profesional) THEN
      RAISE EXCEPTION 'Ese profesional ya tiene una cuenta de usuario.';
    END IF;
    INSERT INTO usuario (id_profesional, correo, hash_contrasena, rol)
    VALUES (p_id_profesional, v_correo, crypt(p_contrasena, gen_salt('bf', 12)), 'medico')
    RETURNING id_usuario INTO p_id_nuevo;
  ELSE
    IF NULLIF(trim(p_nombre), '') IS NULL OR NULLIF(trim(p_apellido_paterno), '') IS NULL THEN
      RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
    END IF;
    INSERT INTO usuario (nombre, apellido_paterno, apellido_materno, correo, hash_contrasena, rol)
    VALUES (trim(p_nombre), trim(p_apellido_paterno), NULLIF(trim(p_apellido_materno), ''),
            v_correo, crypt(p_contrasena, gen_salt('bf', 12)), p_rol)
    RETURNING id_usuario INTO p_id_nuevo;
  END IF;

  PERFORM fn_registrar_auditoria(p_id_usuario, 'crear', 'usuario', p_id_nuevo, NULL, 'exito', 'Alta de usuario con rol ' || p_rol || '.');
END $$;


-- ============================================================
-- VISTAS
-- ============================================================

-- V-01 v_paciente_resumen: pacientes con su última consulta, número de
-- consultas y si tienen consentimiento vigente. (Listado de Pacientes en Flask)
CREATE OR REPLACE VIEW v_paciente_resumen AS
SELECT p.id_paciente_maestro,
       p.curp,
       p.nombre, p.apellido_paterno, p.apellido_materno,
       concat_ws(' ', p.nombre, p.apellido_paterno, p.apellido_materno) AS nombre_completo,
       p.fecha_nacimiento,
       date_part('year', age(p.fecha_nacimiento))::int AS edad,
       p.sexo,
       p.estado,
       p.id_paciente_fusionado_en,
       COALESCE(c.total_consultas, 0) AS total_consultas,
       c.ultima_consulta,
       EXISTS (SELECT 1 FROM consentimiento k
               WHERE k.id_paciente_maestro = p.id_paciente_maestro AND k.estado = 'activo'
                 AND CURRENT_DATE BETWEEN k.fecha_inicio AND k.fecha_fin) AS consentimiento_vigente
FROM paciente_maestro p
LEFT JOIN (SELECT id_paciente_maestro,
                  COUNT(*) FILTER (WHERE estado <> 'cancelado') AS total_consultas,
                  MAX(fecha_inicio) FILTER (WHERE estado IN ('finalizado','en_curso')) AS ultima_consulta
           FROM encuentro_clinico GROUP BY id_paciente_maestro) c
  ON c.id_paciente_maestro = p.id_paciente_maestro;

-- V-02 v_historial_consultas: cada consulta con paciente, médico,
-- institución y diagnóstico principal. (Listado de Consultas en Flask)
CREATE OR REPLACE VIEW v_historial_consultas AS
SELECT e.id_encuentro,
       e.id_paciente_maestro,
       concat_ws(' ', p.nombre, p.apellido_paterno, p.apellido_materno) AS paciente,
       e.id_profesional,
       CASE WHEN ps.id_profesional IS NULL THEN 'Sin asignar'
            ELSE concat_ws(' ', ps.nombre, ps.apellido_paterno, ps.apellido_materno) END AS medico,
       e.id_organizacion,
       o.nombre AS institucion,
       e.tipo_encuentro,
       e.motivo,
       e.fecha_inicio,
       e.fecha_fin,
       e.estado,
       cc.codigo AS codigo_diagnostico,
       cc.descripcion AS diagnostico_principal,
       (pq.tipo_paquete = 'captura_portal') AS capturada_en_portal
FROM encuentro_clinico e
JOIN paciente_maestro p      ON p.id_paciente_maestro = e.id_paciente_maestro
JOIN organizacion o          ON o.id_organizacion = e.id_organizacion
LEFT JOIN profesional_salud ps ON ps.id_profesional = e.id_profesional
LEFT JOIN diagnostico d      ON d.id_encuentro = e.id_encuentro AND d.tipo = 'principal'
LEFT JOIN catalogo_codigo cc ON cc.id_codigo = d.id_codigo
JOIN procedencia_dato pr     ON pr.id_procedencia = e.id_procedencia
JOIN detalle_transaccion dt  ON dt.id_detalle = pr.id_detalle
JOIN paquete_transaccion pq  ON pq.id_paquete = dt.id_paquete;

-- V-03 v_consultas_por_especialidad: consultas y pacientes atendidos por
-- especialidad. Un médico con dos especialidades cuenta en ambas.
CREATE OR REPLACE VIEW v_consultas_por_especialidad AS
SELECT COALESCE(pe.especialidad, 'Sin especialidad / sin médico') AS especialidad,
       COUNT(DISTINCT e.id_encuentro) AS total_consultas,
       COUNT(DISTINCT e.id_encuentro) FILTER (WHERE e.estado = 'finalizado') AS finalizadas,
       COUNT(DISTINCT e.id_encuentro) FILTER (WHERE e.estado IN ('planeado','en_curso')) AS pendientes,
       COUNT(DISTINCT e.id_paciente_maestro) AS pacientes_distintos
FROM encuentro_clinico e
LEFT JOIN profesional_especialidad pe ON pe.id_profesional = e.id_profesional
WHERE e.estado <> 'cancelado'
GROUP BY COALESCE(pe.especialidad, 'Sin especialidad / sin médico');

-- V-04 v_indicadores_atencion: indicadores generales en una fila.
-- (Panel principal en Flask)
CREATE OR REPLACE VIEW v_indicadores_atencion AS
SELECT
  (SELECT COUNT(*) FROM paciente_maestro WHERE estado = 'activo')                        AS pacientes_activos,
  (SELECT COUNT(*) FROM profesional_salud WHERE activo)                                   AS medicos_activos,
  (SELECT COUNT(*) FROM encuentro_clinico WHERE estado = 'finalizado')                    AS consultas_finalizadas,
  (SELECT COUNT(*) FROM encuentro_clinico WHERE estado IN ('planeado','en_curso'))        AS consultas_pendientes,
  (SELECT COUNT(*) FROM encuentro_clinico WHERE estado = 'cancelado')                     AS consultas_canceladas,
  (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (fecha_fin - fecha_inicio)) / 60))::int
     FROM encuentro_clinico WHERE estado = 'finalizado' AND tipo_encuentro = 'consulta_externa') AS duracion_promedio_min,
  (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE interpretacion IN ('alto','bajo','critico')) / NULLIF(COUNT(*), 0), 1)
     FROM observacion)                                                                    AS pct_resultados_anormales,
  (SELECT COUNT(*) FROM candidato_duplicado WHERE estado = 'pendiente')                   AS duplicados_pendientes,
  (SELECT COUNT(*) FROM conflicto_dato WHERE estado = 'pendiente')                        AS conflictos_pendientes,
  (SELECT COUNT(*) FROM consentimiento WHERE estado = 'activo')                           AS consentimientos_activos;

-- V-05 v_consultas_pendientes: consultas planeadas o en curso con el
-- teléfono vigente del paciente para contactarlo. (Panel en Flask)
CREATE OR REPLACE VIEW v_consultas_pendientes AS
SELECT e.id_encuentro,
       e.fecha_inicio,
       e.estado,
       e.tipo_encuentro,
       e.motivo,
       e.id_paciente_maestro,
       concat_ws(' ', p.nombre, p.apellido_paterno, p.apellido_materno) AS paciente,
       tel.valor AS telefono_paciente,
       e.id_profesional,
       CASE WHEN ps.id_profesional IS NULL THEN 'Sin asignar'
            ELSE concat_ws(' ', ps.nombre, ps.apellido_paterno) END AS medico,
       o.nombre AS institucion
FROM encuentro_clinico e
JOIN paciente_maestro p ON p.id_paciente_maestro = e.id_paciente_maestro
JOIN organizacion o     ON o.id_organizacion = e.id_organizacion
LEFT JOIN profesional_salud ps ON ps.id_profesional = e.id_profesional
LEFT JOIN LATERAL (SELECT cp.valor FROM contacto_paciente cp
                   WHERE cp.id_paciente_maestro = e.id_paciente_maestro
                     AND cp.tipo_contacto = 'telefono' AND cp.vigente
                   ORDER BY cp.id_contacto DESC LIMIT 1) tel ON TRUE
WHERE e.estado IN ('planeado','en_curso');

-- V-06 v_profesional_resumen: profesionales con sus especialidades,
-- instituciones vigentes y número de consultas. (Listado de Médicos en Flask)
CREATE OR REPLACE VIEW v_profesional_resumen AS
SELECT ps.id_profesional,
       ps.cedula_profesional,
       ps.nombre, ps.apellido_paterno, ps.apellido_materno,
       concat_ws(' ', ps.nombre, ps.apellido_paterno, ps.apellido_materno) AS nombre_completo,
       ps.activo,
       (SELECT string_agg(pe.especialidad, ', ' ORDER BY pe.especialidad)
          FROM profesional_especialidad pe WHERE pe.id_profesional = ps.id_profesional) AS especialidades,
       (SELECT string_agg(DISTINCT o.nombre, ', ')
          FROM profesional_organizacion po JOIN organizacion o ON o.id_organizacion = po.id_organizacion
         WHERE po.id_profesional = ps.id_profesional AND po.fecha_fin IS NULL) AS instituciones_vigentes,
       (SELECT COUNT(*) FROM encuentro_clinico e
         WHERE e.id_profesional = ps.id_profesional AND e.estado <> 'cancelado') AS total_consultas,
       (SELECT MAX(e.fecha_inicio) FROM encuentro_clinico e
         WHERE e.id_profesional = ps.id_profesional AND e.estado = 'finalizado') AS ultima_consulta
FROM profesional_salud ps;

COMMENT ON VIEW v_paciente_resumen IS 'Pacientes con su última consulta, número de consultas y consentimiento vigente.';
COMMENT ON VIEW v_historial_consultas IS 'Historial de consultas con paciente, médico, institución y diagnóstico principal.';
COMMENT ON VIEW v_consultas_por_especialidad IS 'Consultas y pacientes atendidos por especialidad médica.';
COMMENT ON VIEW v_indicadores_atencion IS 'Indicadores generales de atención en una sola fila.';
COMMENT ON VIEW v_consultas_pendientes IS 'Consultas planeadas o en curso con el teléfono vigente del paciente.';
COMMENT ON VIEW v_profesional_resumen IS 'Profesionales con especialidades, instituciones vigentes y consultas.';
