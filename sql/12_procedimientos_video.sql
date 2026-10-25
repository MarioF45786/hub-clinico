CREATE PROCEDURE sp_iniciar_sesion(
  IN p_correo VARCHAR(150),
  IN p_contrasena TEXT,
  OUT p_usuario REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_usuario BIGINT;
  v_rol VARCHAR(25);
BEGIN
  SELECT id_usuario, rol INTO v_id_usuario, v_rol
    FROM usuario
    WHERE LOWER(correo) = LOWER(TRIM(p_correo))
      AND activo = TRUE
      AND hash_contrasena = crypt(p_contrasena, hash_contrasena);

  IF v_id_usuario IS NOT NULL THEN
    INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, resultado, detalle)
    VALUES (v_id_usuario, v_rol, 'consultar', 'usuario', v_id_usuario, 'exito', 'Inicio de sesión.');
    RAISE NOTICE 'Usuario % entró con rol %', v_id_usuario, v_rol;
  ELSE
    RAISE NOTICE 'Correo o contraseña incorrectos';
  END IF;

  p_usuario := 'cursor_usuario';
  OPEN p_usuario FOR
    SELECT u.id_usuario, u.rol,
           COALESCE(u.nombre || ' ' || u.apellido_paterno,
                    'Dr(a). ' || ps.nombre || ' ' || ps.apellido_paterno),
           u.id_profesional
    FROM usuario u
    LEFT JOIN profesional_salud ps ON ps.id_profesional = u.id_profesional
    WHERE u.id_usuario = v_id_usuario;
END;
$$;


CREATE PROCEDURE sp_obtener_pacientes(
  IN p_buscar VARCHAR(100),
  IN p_estado VARCHAR(10),
  OUT p_pacientes REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_pacientes := 'cursor_pacientes';

  OPEN p_pacientes FOR
    SELECT id_paciente_maestro, nombre_completo,
           curp, fecha_nacimiento,
           edad, sexo, total_consultas,
           ultima_consulta, estado
    FROM v_paciente_resumen
    WHERE (p_estado IS NULL OR estado = p_estado)
      AND (p_buscar IS NULL OR p_buscar = ''
           OR nombre_completo ILIKE '%' || p_buscar || '%'
           OR curp ILIKE '%' || p_buscar || '%'
           OR id_paciente_maestro::TEXT = p_buscar)
    ORDER BY apellido_paterno, nombre;
END;
$$;


CREATE PROCEDURE sp_inserta_paciente(
  IN p_id_usuario BIGINT,
  IN p_nombre VARCHAR(100),
  IN p_apellido_paterno VARCHAR(100),
  IN p_apellido_materno VARCHAR(100),
  IN p_fecha_nacimiento DATE,
  IN p_sexo VARCHAR(12),
  IN p_curp VARCHAR(18),
  OUT p_id_paciente BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_curp VARCHAR(18);
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'coordinador' THEN
    RAISE EXCEPTION 'Solo el coordinador puede registrar pacientes.';
  END IF;

  IF COALESCE(TRIM(p_nombre), '') = '' OR COALESCE(TRIM(p_apellido_paterno), '') = '' THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;
  IF p_fecha_nacimiento IS NULL OR p_fecha_nacimiento > CURRENT_DATE OR p_fecha_nacimiento < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'La fecha de nacimiento no es válida.';
  END IF;

  v_curp := NULLIF(UPPER(TRIM(p_curp)), '');
  IF v_curp IS NOT NULL AND v_curp !~ '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9][0-9]$' THEN
    RAISE EXCEPTION 'La CURP % no tiene un formato válido.', v_curp;
  END IF;
  IF EXISTS (SELECT 1 FROM paciente_maestro WHERE curp = v_curp) THEN
    RAISE EXCEPTION 'Ya existe un paciente con la CURP %.', v_curp;
  END IF;
  IF EXISTS (SELECT 1 FROM paciente_maestro
              WHERE LOWER(nombre) = LOWER(TRIM(p_nombre))
                AND LOWER(apellido_paterno) = LOWER(TRIM(p_apellido_paterno))
                AND fecha_nacimiento = p_fecha_nacimiento
                AND estado = 'activo') THEN
    RAISE EXCEPTION 'Ya existe un paciente activo con el mismo nombre, apellido y fecha de nacimiento.';
  END IF;

  INSERT INTO paciente_maestro (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo)
  VALUES (v_curp, TRIM(p_nombre), TRIM(p_apellido_paterno), NULLIF(TRIM(p_apellido_materno), ''), p_fecha_nacimiento, p_sexo)
  RETURNING id_paciente_maestro INTO p_id_paciente;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'crear', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito', 'Alta de paciente.');

  RAISE NOTICE 'Paciente % registrado', p_id_paciente;
END;
$$;


CREATE PROCEDURE sp_actualiza_paciente(
  IN p_id_usuario BIGINT,
  IN p_id_paciente BIGINT,
  IN p_nombre VARCHAR(100),
  IN p_apellido_paterno VARCHAR(100),
  IN p_apellido_materno VARCHAR(100),
  IN p_fecha_nacimiento DATE,
  IN p_sexo VARCHAR(12),
  IN p_curp VARCHAR(18)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_estado VARCHAR(10);
  v_curp VARCHAR(18);
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'coordinador' THEN
    RAISE EXCEPTION 'Solo el coordinador puede modificar pacientes.';
  END IF;

  SELECT estado INTO v_estado FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'El paciente % no existe.', p_id_paciente;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'Solo se pueden modificar pacientes activos (estado actual: %).', v_estado;
  END IF;

  IF COALESCE(TRIM(p_nombre), '') = '' OR COALESCE(TRIM(p_apellido_paterno), '') = '' THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;
  IF p_fecha_nacimiento IS NULL OR p_fecha_nacimiento > CURRENT_DATE OR p_fecha_nacimiento < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'La fecha de nacimiento no es válida.';
  END IF;

  v_curp := NULLIF(UPPER(TRIM(p_curp)), '');
  IF v_curp IS NOT NULL AND v_curp !~ '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9][0-9]$' THEN
    RAISE EXCEPTION 'La CURP % no tiene un formato válido.', v_curp;
  END IF;
  IF EXISTS (SELECT 1 FROM paciente_maestro WHERE curp = v_curp AND id_paciente_maestro <> p_id_paciente) THEN
    RAISE EXCEPTION 'La CURP % ya pertenece a otro paciente.', v_curp;
  END IF;

  UPDATE paciente_maestro SET
    nombre = TRIM(p_nombre),
    apellido_paterno = TRIM(p_apellido_paterno),
    apellido_materno = NULLIF(TRIM(p_apellido_materno), ''),
    fecha_nacimiento = p_fecha_nacimiento,
    sexo = p_sexo,
    curp = v_curp,
    fecha_actualizacion = CURRENT_TIMESTAMP
  WHERE id_paciente_maestro = p_id_paciente;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'actualizar', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito', 'Actualización de datos del paciente.');

  RAISE NOTICE 'Paciente % actualizado', p_id_paciente;
END;
$$;


CREATE PROCEDURE sp_borrar_paciente(
  IN p_id_usuario BIGINT,
  IN p_id_paciente BIGINT,
  IN p_motivo VARCHAR(200),
  OUT p_consultas_canceladas INT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_estado VARCHAR(10);
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'coordinador' THEN
    RAISE EXCEPTION 'Solo el coordinador puede dar de baja pacientes.';
  END IF;
  IF COALESCE(TRIM(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'El motivo de la baja es obligatorio.';
  END IF;

  SELECT estado INTO v_estado FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'El paciente % no existe.', p_id_paciente;
  END IF;
  IF v_estado <> 'activo' THEN
    RAISE EXCEPTION 'El paciente no está activo (estado actual: %).', v_estado;
  END IF;

  UPDATE paciente_maestro SET
    estado = 'inactivo',
    fecha_actualizacion = CURRENT_TIMESTAMP
  WHERE id_paciente_maestro = p_id_paciente;

  UPDATE encuentro_clinico SET estado = 'cancelado'
  WHERE id_paciente_maestro = p_id_paciente AND estado = 'planeado';
  GET DIAGNOSTICS p_consultas_canceladas = ROW_COUNT;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'eliminar', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito',
          'Baja lógica. Motivo: ' || p_motivo);

  RAISE NOTICE 'Paciente % dado de baja, % consultas canceladas', p_id_paciente, p_consultas_canceladas;
END;
$$;


CREATE PROCEDURE sp_inserta_medico(
  IN p_id_usuario BIGINT,
  IN p_cedula VARCHAR(20),
  IN p_nombre VARCHAR(100),
  IN p_apellido_paterno VARCHAR(100),
  IN p_apellido_materno VARCHAR(100),
  IN p_especialidad VARCHAR(100),
  IN p_cedula_especialidad VARCHAR(20),
  IN p_id_institucion BIGINT,
  IN p_rol_institucion VARCHAR(30),
  OUT p_id_medico BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_estado_institucion VARCHAR(15);
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'administrador' THEN
    RAISE EXCEPTION 'Solo el administrador puede registrar médicos.';
  END IF;

  IF COALESCE(TRIM(p_cedula), '') !~ '^[0-9]{7,8}$' THEN
    RAISE EXCEPTION 'La cédula profesional debe tener 7 u 8 dígitos.';
  END IF;
  IF EXISTS (SELECT 1 FROM profesional_salud WHERE cedula_profesional = TRIM(p_cedula)) THEN
    RAISE EXCEPTION 'Ya existe un profesional con la cédula %.', TRIM(p_cedula);
  END IF;
  IF COALESCE(TRIM(p_nombre), '') = '' OR COALESCE(TRIM(p_apellido_paterno), '') = '' THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;

  SELECT estado INTO v_estado_institucion FROM organizacion WHERE id_organizacion = p_id_institucion;
  IF v_estado_institucion IS NULL THEN
    RAISE EXCEPTION 'La institución % no existe.', p_id_institucion;
  END IF;
  IF v_estado_institucion <> 'activa' THEN
    RAISE EXCEPTION 'La institución no está activa (estado: %).', v_estado_institucion;
  END IF;

  INSERT INTO profesional_salud (cedula_profesional, nombre, apellido_paterno, apellido_materno)
  VALUES (TRIM(p_cedula), TRIM(p_nombre), TRIM(p_apellido_paterno), NULLIF(TRIM(p_apellido_materno), ''))
  RETURNING id_profesional INTO p_id_medico;

  IF NULLIF(TRIM(p_especialidad), '') IS NOT NULL THEN
    INSERT INTO profesional_especialidad (id_profesional, especialidad, cedula_especialidad)
    VALUES (p_id_medico, TRIM(p_especialidad), NULLIF(TRIM(p_cedula_especialidad), ''));
  END IF;

  INSERT INTO profesional_organizacion (id_profesional, id_organizacion, rol, fecha_inicio)
  VALUES (p_id_medico, p_id_institucion, p_rol_institucion, CURRENT_DATE);

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'crear', 'profesional_salud', p_id_medico, 'exito', 'Alta de médico.');

  RAISE NOTICE 'Médico % registrado', p_id_medico;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'La cédula de especialidad ya está registrada para otro médico.';
END;
$$;


CREATE PROCEDURE sp_borrar_medico(
  IN p_id_usuario BIGINT,
  IN p_id_medico BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_activo BOOLEAN;
  v_pendientes BIGINT;
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'administrador' THEN
    RAISE EXCEPTION 'Solo el administrador puede dar de baja médicos.';
  END IF;

  SELECT activo INTO v_activo FROM profesional_salud WHERE id_profesional = p_id_medico;
  IF v_activo IS NULL THEN
    RAISE EXCEPTION 'El médico % no existe.', p_id_medico;
  END IF;
  IF v_activo = FALSE THEN
    RAISE EXCEPTION 'El médico ya está dado de baja.';
  END IF;

  SELECT COUNT(*) INTO v_pendientes FROM encuentro_clinico
    WHERE id_profesional = p_id_medico AND estado IN ('planeado', 'en_curso');
  IF v_pendientes > 0 THEN
    RAISE EXCEPTION 'El médico tiene % consulta(s) planeada(s) o en curso; cancélelas antes de la baja.', v_pendientes;
  END IF;

  UPDATE profesional_salud SET activo = FALSE WHERE id_profesional = p_id_medico;

  UPDATE profesional_organizacion SET fecha_fin = GREATEST(CURRENT_DATE, fecha_inicio + 1)
  WHERE id_profesional = p_id_medico AND fecha_fin IS NULL;

  UPDATE usuario SET activo = FALSE WHERE id_profesional = p_id_medico;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'eliminar', 'profesional_salud', p_id_medico, 'exito', 'Baja lógica de médico.');

  RAISE NOTICE 'Médico % dado de baja', p_id_medico;
END;
$$;


CREATE PROCEDURE sp_inserta_consulta(
  IN p_id_usuario BIGINT,
  IN p_id_paciente BIGINT,
  IN p_id_institucion BIGINT,
  IN p_id_medico BIGINT,
  IN p_tipo VARCHAR(20),
  IN p_motivo VARCHAR(250),
  IN p_fecha TIMESTAMPTZ,
  OUT p_id_consulta BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_id_profesional_usuario BIGINT;
  v_sistema BIGINT;
  v_paquete BIGINT;
  v_detalle BIGINT;
  v_procedencia BIGINT;
  v_estado VARCHAR(12);
BEGIN
  SELECT rol, id_profesional INTO v_rol, v_id_profesional_usuario
    FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS NULL OR v_rol NOT IN ('coordinador', 'medico') THEN
    RAISE EXCEPTION 'Solo el coordinador o un médico pueden agendar consultas.';
  END IF;
  IF v_rol = 'medico' AND p_id_medico <> v_id_profesional_usuario THEN
    RAISE EXCEPTION 'Un médico solo puede registrar consultas a su nombre.';
  END IF;

  IF p_fecha IS NULL THEN
    RAISE EXCEPTION 'La fecha y hora de la consulta son obligatorias.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM paciente_maestro WHERE id_paciente_maestro = p_id_paciente AND estado = 'activo') THEN
    RAISE EXCEPTION 'El paciente no existe o no está activo.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM organizacion WHERE id_organizacion = p_id_institucion AND estado = 'activa') THEN
    RAISE EXCEPTION 'La institución no existe o no está activa.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profesional_salud WHERE id_profesional = p_id_medico AND activo = TRUE) THEN
    RAISE EXCEPTION 'El médico no existe o está dado de baja.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profesional_organizacion
                  WHERE id_profesional = p_id_medico AND id_organizacion = p_id_institucion
                    AND fecha_inicio <= p_fecha::DATE
                    AND (fecha_fin IS NULL OR fecha_fin >= p_fecha::DATE)) THEN
    RAISE EXCEPTION 'El médico no trabaja en esa institución en esa fecha.';
  END IF;
  IF EXISTS (SELECT 1 FROM encuentro_clinico
              WHERE id_profesional = p_id_medico AND estado <> 'cancelado'
                AND fecha_inicio BETWEEN p_fecha - INTERVAL '29 minutes' AND p_fecha + INTERVAL '29 minutes') THEN
    RAISE EXCEPTION 'El profesional ya tiene una consulta en ese horario.';
  END IF;

  IF p_fecha > CURRENT_TIMESTAMP THEN
    v_estado := 'planeado';
  ELSE
    v_estado := 'en_curso';
  END IF;

  SELECT id_sistema_origen INTO v_sistema FROM sistema_origen
    WHERE tipo_sistema = 'portal_hub' AND estado = 'activo'
    ORDER BY id_sistema_origen LIMIT 1;
  IF v_sistema IS NULL THEN
    RAISE EXCEPTION 'No hay un sistema de portal activo configurado.';
  END IF;

  INSERT INTO paquete_transaccion (id_sistema_origen, id_usuario_captura, direccion, tipo_paquete, estado, hash_paquete)
  VALUES (v_sistema, p_id_usuario, 'entrante', 'captura_portal', 'procesado',
          encode(sha256(convert_to('captura|' || p_id_paciente || '|' || clock_timestamp() || '|' || gen_random_uuid(), 'UTF8')), 'hex'))
  RETURNING id_paquete INTO v_paquete;

  INSERT INTO detalle_transaccion (id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso,
                                   fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
  VALUES (v_paquete, p_id_paciente, 'Encounter', 'Encounter-portal-' || v_paquete, '1',
          CURRENT_TIMESTAMP, 'integrado',
          encode(sha256(convert_to('encuentro|' || v_paquete || '|' || clock_timestamp(), 'UTF8')), 'hex'),
          CURRENT_TIMESTAMP)
  RETURNING id_detalle INTO v_detalle;

  INSERT INTO procedencia_dato (id_detalle, ruta_elemento, valor_original, fecha_origen)
  VALUES (v_detalle, 'Encounter', p_tipo || ' - ' || COALESCE(p_motivo, ''), CURRENT_TIMESTAMP)
  RETURNING id_procedencia INTO v_procedencia;

  INSERT INTO encuentro_clinico (id_paciente_maestro, id_organizacion, id_profesional, id_procedencia,
                                 tipo_encuentro, motivo, fecha_inicio, estado)
  VALUES (p_id_paciente, p_id_institucion, p_id_medico, v_procedencia,
          p_tipo, NULLIF(TRIM(p_motivo), ''), p_fecha, v_estado)
  RETURNING id_encuentro INTO p_id_consulta;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'crear', 'encuentro_clinico', p_id_consulta, p_id_paciente, 'exito',
          'Consulta registrada en el portal (' || v_estado || ').');

  RAISE NOTICE 'Consulta % registrada como %', p_id_consulta, v_estado;
END;
$$;


CREATE PROCEDURE sp_actualiza_consulta(
  IN p_id_usuario BIGINT,
  IN p_id_consulta BIGINT,
  IN p_motivo VARCHAR(250),
  IN p_fecha TIMESTAMPTZ,
  IN p_estado VARCHAR(12)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_id_profesional_usuario BIGINT;
  v_id_profesional BIGINT;
  v_id_paciente BIGINT;
  v_id_procedencia BIGINT;
  v_estado VARCHAR(12);
  v_motivo VARCHAR(250);
  v_fecha TIMESTAMPTZ;
BEGIN
  SELECT rol, id_profesional INTO v_rol, v_id_profesional_usuario
    FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS NULL OR v_rol NOT IN ('coordinador', 'medico') THEN
    RAISE EXCEPTION 'Solo el coordinador o un médico pueden modificar consultas.';
  END IF;

  SELECT id_profesional, id_paciente_maestro, id_procedencia, estado, motivo, fecha_inicio
    INTO v_id_profesional, v_id_paciente, v_id_procedencia, v_estado, v_motivo, v_fecha
    FROM encuentro_clinico WHERE id_encuentro = p_id_consulta;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'La consulta % no existe.', p_id_consulta;
  END IF;
  IF v_rol = 'medico' AND v_id_profesional IS DISTINCT FROM v_id_profesional_usuario THEN
    RAISE EXCEPTION 'Un médico solo puede modificar sus propias consultas.';
  END IF;
  IF v_estado IN ('finalizado', 'cancelado') THEN
    RAISE EXCEPTION 'La consulta ya está en estado % y no se puede modificar.', v_estado;
  END IF;
  IF NOT ((v_estado = 'planeado' AND p_estado IN ('planeado', 'en_curso'))
       OR (v_estado = 'en_curso' AND p_estado IN ('en_curso', 'finalizado'))) THEN
    RAISE EXCEPTION 'Cambio de estado no permitido: % -> %.', v_estado, p_estado;
  END IF;
  IF p_fecha <> v_fecha AND v_estado <> 'planeado' THEN
    RAISE EXCEPTION 'La fecha solo se puede cambiar mientras la consulta está planeada.';
  END IF;

  IF NULLIF(TRIM(p_motivo), '') IS DISTINCT FROM v_motivo THEN
    INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
    VALUES (v_id_procedencia, 'motivo',
            (SELECT COALESCE(MAX(numero_version), 0) + 1 FROM version_dato WHERE id_procedencia = v_id_procedencia AND campo = 'motivo'),
            v_motivo, NULLIF(TRIM(p_motivo), ''), p_id_usuario, 'Edición desde el portal.');
  END IF;
  IF p_fecha <> v_fecha THEN
    INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
    VALUES (v_id_procedencia, 'fecha_inicio',
            (SELECT COALESCE(MAX(numero_version), 0) + 1 FROM version_dato WHERE id_procedencia = v_id_procedencia AND campo = 'fecha_inicio'),
            v_fecha::TEXT, p_fecha::TEXT, p_id_usuario, 'Edición desde el portal.');
  END IF;
  IF p_estado <> v_estado THEN
    INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
    VALUES (v_id_procedencia, 'estado',
            (SELECT COALESCE(MAX(numero_version), 0) + 1 FROM version_dato WHERE id_procedencia = v_id_procedencia AND campo = 'estado'),
            v_estado, p_estado, p_id_usuario, 'Edición desde el portal.');
  END IF;

  UPDATE encuentro_clinico SET
    motivo = NULLIF(TRIM(p_motivo), ''),
    fecha_inicio = p_fecha,
    estado = p_estado,
    fecha_fin = CASE WHEN p_estado = 'finalizado' THEN GREATEST(CURRENT_TIMESTAMP, p_fecha) ELSE NULL END
  WHERE id_encuentro = p_id_consulta;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'actualizar', 'encuentro_clinico', p_id_consulta, v_id_paciente, 'exito',
          'Consulta actualizada (' || v_estado || ' -> ' || p_estado || ').');

  RAISE NOTICE 'Consulta %: % -> %', p_id_consulta, v_estado, p_estado;
END;
$$;


CREATE PROCEDURE sp_cancelar_consulta(
  IN p_id_usuario BIGINT,
  IN p_id_consulta BIGINT,
  IN p_motivo VARCHAR(200)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_id_profesional_usuario BIGINT;
  v_id_profesional BIGINT;
  v_id_paciente BIGINT;
  v_id_procedencia BIGINT;
  v_estado VARCHAR(12);
BEGIN
  SELECT rol, id_profesional INTO v_rol, v_id_profesional_usuario
    FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS NULL OR v_rol NOT IN ('coordinador', 'medico') THEN
    RAISE EXCEPTION 'Solo el coordinador o un médico pueden cancelar consultas.';
  END IF;
  IF COALESCE(TRIM(p_motivo), '') = '' THEN
    RAISE EXCEPTION 'El motivo de la cancelación es obligatorio.';
  END IF;

  SELECT id_profesional, id_paciente_maestro, id_procedencia, estado
    INTO v_id_profesional, v_id_paciente, v_id_procedencia, v_estado
    FROM encuentro_clinico WHERE id_encuentro = p_id_consulta;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'La consulta % no existe.', p_id_consulta;
  END IF;
  IF v_rol = 'medico' AND v_id_profesional IS DISTINCT FROM v_id_profesional_usuario THEN
    RAISE EXCEPTION 'Un médico solo puede cancelar sus propias consultas.';
  END IF;
  IF v_estado NOT IN ('planeado', 'en_curso') THEN
    RAISE EXCEPTION 'Solo se cancelan consultas planeadas o en curso (estado actual: %).', v_estado;
  END IF;
  IF EXISTS (SELECT 1 FROM diagnostico WHERE id_encuentro = p_id_consulta)
     OR EXISTS (SELECT 1 FROM observacion WHERE id_encuentro = p_id_consulta)
     OR EXISTS (SELECT 1 FROM solicitud_medicamento WHERE id_encuentro = p_id_consulta) THEN
    RAISE EXCEPTION 'La consulta ya tiene información clínica registrada y no puede cancelarse.';
  END IF;

  INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, motivo)
  VALUES (v_id_procedencia, 'estado',
          (SELECT COALESCE(MAX(numero_version), 0) + 1 FROM version_dato WHERE id_procedencia = v_id_procedencia AND campo = 'estado'),
          v_estado, 'cancelado', p_id_usuario, p_motivo);

  UPDATE encuentro_clinico SET estado = 'cancelado', fecha_fin = NULL
  WHERE id_encuentro = p_id_consulta;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'eliminar', 'encuentro_clinico', p_id_consulta, v_id_paciente, 'exito',
          'Cancelación: ' || p_motivo);

  RAISE NOTICE 'Consulta % cancelada', p_id_consulta;
END;
$$;


CREATE PROCEDURE sp_consultas_de_medico(
  IN p_id_medico BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_nombre VARCHAR(200);
  v_consultas BIGINT;
BEGIN
  SELECT nombre || ' ' || apellido_paterno INTO v_nombre
    FROM profesional_salud WHERE id_profesional = p_id_medico;
  IF v_nombre IS NULL THEN
    RAISE EXCEPTION 'El médico % no existe.', p_id_medico;
  END IF;

  SELECT COUNT(*) INTO v_consultas FROM encuentro_clinico
    WHERE id_profesional = p_id_medico AND estado <> 'cancelado';

  RAISE NOTICE '% tuvo % consultas', v_nombre, v_consultas;
END;
$$;


CREATE PROCEDURE sp_promedio_edad_pacientes()
LANGUAGE plpgsql
AS $$
DECLARE
  v_promedio NUMERIC(12,2);
  v_total BIGINT;
BEGIN
  SELECT AVG(DATE_PART('year', AGE(fecha_nacimiento))), COUNT(*)
    INTO v_promedio, v_total
    FROM paciente_maestro WHERE estado = 'activo';

  RAISE NOTICE 'La edad promedio de los % pacientes activos es % años', v_total, v_promedio;
END;
$$;


CREATE PROCEDURE sp_resolver_duplicado(
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
