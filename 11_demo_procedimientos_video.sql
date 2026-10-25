-- ============================================================
-- 11_demo_procedimientos_video.sql
-- Procedimientos almacenados para el video: primero cómo está
-- construido cada uno (CREATE PROCEDURE) y luego su demostración (CALL).
-- Requiere que ya estén cargados 02 a 08 (sp_resolver_duplicado usa las
-- funciones fn_verificar_rol y fn_registrar_auditoria de 05_programacion.sql).
--
-- Cómo correrlo (desde la carpeta de los scripts):
--   psql -h localhost -U user_proy -d proyecto -f 11_demo_procedimientos_video.sql
-- o dentro de psql:  \i 11_demo_procedimientos_video.sql
--
-- Cada demostración va entre BEGIN y ROLLBACK: se ve el resultado
-- pero al final se deshace, así el script se puede correr las veces
-- que sea sin cambiar los datos de prueba.
-- Si quieres que un cambio SÍ se quede, cambia su ROLLBACK por COMMIT.
--
-- Usuarios que se usan como primer parámetro:
--   1 = administrador   3 = coordinador   5 = médico (Carlos Garza, médico 1)
-- ============================================================

\pset footer off
\pset null '(vacío)'


\echo
\echo '==================== 1. sp_iniciar_sesion ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_iniciar_sesion
-- Propósito: validar correo y contraseña para entrar al sistema.
-- Entrada:   p_correo, p_contrasena
-- Salida:    p_usuario REFCURSOR ('cursor_usuario'): 1 fila si los datos son
--            correctos; 0 filas si no.
--            Columnas: id_usuario, rol, nombre a mostrar, id_profesional
-- Tablas:    usuario, profesional_salud, auditoria
-- Reglas:    la contraseña se guarda como hash bcrypt, nunca legible; crypt()
--            aplica el mismo hash a lo que escribió el usuario y lo compara;
--            un usuario inactivo no entra; cada entrada queda en auditoría.
-- Ejemplo:   BEGIN;
--            CALL sp_iniciar_sesion('coordinador@flojorama.mx', 'Flojorama2026!', NULL);
--            FETCH ALL FROM cursor_usuario;
--            COMMIT;
-- Resultado: 3 | coordinador | Mariana Cantú | (vacío)
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_iniciar_sesion;
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

-- ===== Demostración =====
\echo '--- Correo y contraseña correctos: regresa 1 fila'
BEGIN;
CALL sp_iniciar_sesion('coordinador@flojorama.mx', 'Flojorama2026!', NULL);
FETCH ALL FROM cursor_usuario;
ROLLBACK;

\echo '--- Contraseña incorrecta: regresa 0 filas'
BEGIN;
CALL sp_iniciar_sesion('coordinador@flojorama.mx', 'otra', NULL);
FETCH ALL FROM cursor_usuario;
ROLLBACK;


\echo
\echo '==================== 2. sp_obtener_pacientes ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_obtener_pacientes
-- Propósito: listado de pacientes con búsqueda y filtro por estado.
-- Entrada:   p_buscar (nombre, CURP o número; vacío = todos)
--            p_estado ('activo', 'inactivo', 'fusionado'; NULL = todos)
-- Salida:    p_pacientes REFCURSOR ('cursor_pacientes')
--            Columnas: 0 id, 1 nombre completo, 2 curp, 3 fecha de nacimiento,
--            4 edad, 5 sexo, 6 número de consultas, 7 última consulta, 8 estado
-- Tablas:    vista v_paciente_resumen (paciente_maestro + encuentro_clinico)
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_pacientes('garza', 'activo', NULL);
--            FETCH ALL FROM cursor_pacientes;
--            COMMIT;
-- Resultado: los pacientes activos cuyo nombre contiene "garza".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_obtener_pacientes;
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

-- ===== Demostración =====
\echo '--- Pacientes activos que tienen "garza" en el nombre'
BEGIN;
CALL sp_obtener_pacientes('garza', 'activo', NULL);
FETCH ALL FROM cursor_pacientes;
ROLLBACK;


\echo
\echo '==================== 3. sp_inserta_paciente ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_inserta_paciente
-- Propósito: registrar un paciente nuevo.
-- Entrada:   p_id_usuario (quien registra), p_nombre, p_apellido_paterno,
--            p_apellido_materno, p_fecha_nacimiento, p_sexo, p_curp (opcional)
-- Salida:    p_id_paciente (número que se le asignó)
-- Tablas:    paciente_maestro, usuario, auditoria
-- Reglas:    solo el coordinador registra pacientes; nombre y apellido
--            obligatorios; fecha de nacimiento no futura ni de hace más de 120
--            años; la CURP, si se da, debe tener formato oficial y no repetirse;
--            no se permite otro paciente activo con mismo nombre, apellido y
--            fecha de nacimiento (sería un duplicado).
-- Excepciones: RAISE EXCEPTION con el motivo cuando falla una regla.
-- Ejemplo:   CALL sp_inserta_paciente(3, 'Laura', 'Pérez', 'Soto', '1990-05-01', 'femenino', NULL, NULL);
-- Resultado: p_id_paciente = 33 y aviso "Paciente 33 registrado".
--            Si se repite la misma llamada: ERROR "Ya existe un paciente activo...".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_inserta_paciente;
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
  -- Permiso
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'coordinador' THEN
    RAISE EXCEPTION 'Solo el coordinador puede registrar pacientes.';
  END IF;

  -- Validaciones
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

  -- Inserción
  INSERT INTO paciente_maestro (curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo)
  VALUES (v_curp, TRIM(p_nombre), TRIM(p_apellido_paterno), NULLIF(TRIM(p_apellido_materno), ''), p_fecha_nacimiento, p_sexo)
  RETURNING id_paciente_maestro INTO p_id_paciente;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'crear', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito', 'Alta de paciente.');

  RAISE NOTICE 'Paciente % registrado', p_id_paciente;
END;
$$;

-- ===== Demostración =====
\echo '--- Alta correcta (coordinador) y revisión en la tabla paciente_maestro'
BEGIN;
CALL sp_inserta_paciente(3, 'Laura', 'Pérez', 'Soto', '1990-05-01', 'femenino', NULL, NULL);
SELECT id_paciente_maestro, nombre, apellido_paterno, fecha_nacimiento, estado
  FROM paciente_maestro ORDER BY id_paciente_maestro DESC LIMIT 1;
ROLLBACK;

\echo '--- Error: paciente repetido (mismo nombre, apellido y fecha)'
BEGIN;
CALL sp_inserta_paciente(3, 'José Luis', 'García', NULL, '1985-03-12', 'masculino', NULL, NULL);
ROLLBACK;

\echo '--- Error: un médico (usuario 5) no puede registrar pacientes'
BEGIN;
CALL sp_inserta_paciente(5, 'Ana', 'Ruiz', NULL, '1990-01-01', 'femenino', NULL, NULL);
ROLLBACK;


\echo
\echo '==================== 4. sp_actualiza_paciente ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_actualiza_paciente
-- Propósito: modificar los datos de un paciente.
-- Entrada:   p_id_usuario, p_id_paciente, p_nombre, p_apellido_paterno,
--            p_apellido_materno, p_fecha_nacimiento, p_sexo, p_curp
-- Salida:    ninguna
-- Tablas:    paciente_maestro, usuario, auditoria
-- Reglas:    solo el coordinador; solo pacientes activos (uno dado de baja o
--            fusionado ya no se edita); mismas validaciones que el alta; la CURP
--            no puede ser de otro paciente; se actualiza fecha_actualizacion.
-- Ejemplo:   CALL sp_actualiza_paciente(3, 1, 'José Luis', 'García', 'Treviño', '1985-03-12', 'masculino', 'GATJ850312HNLRRS01');
-- Resultado: aviso "Paciente 1 actualizado".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_actualiza_paciente;
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

-- ===== Demostración =====
\echo '--- Cambiar el apellido materno del paciente 1'
BEGIN;
CALL sp_actualiza_paciente(3, 1, 'José Luis', 'García', 'Treviño López', '1985-03-12', 'masculino', 'GATJ850312HNLRRS01');
SELECT id_paciente_maestro, nombre, apellido_paterno, apellido_materno, fecha_actualizacion
  FROM paciente_maestro WHERE id_paciente_maestro = 1;
ROLLBACK;


\echo
\echo '==================== 5. sp_borrar_paciente (baja lógica) ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_borrar_paciente
-- Propósito: dar de baja a un paciente. Es baja LÓGICA: no se borra la fila,
--            porque tiene consultas y datos clínicos que deben conservarse.
-- Entrada:   p_id_usuario, p_id_paciente, p_motivo
-- Salida:    p_consultas_canceladas (cuántas consultas planeadas se cancelaron)
-- Tablas:    paciente_maestro, encuentro_clinico, usuario, auditoria
-- Reglas:    solo el coordinador; motivo obligatorio; el paciente debe estar
--            activo; queda 'inactivo'; sus consultas planeadas se cancelan;
--            sus consultas pasadas y diagnósticos no se tocan.
-- Ejemplo:   CALL sp_borrar_paciente(3, 28, 'Cambio de residencia', NULL);
-- Resultado: p_consultas_canceladas = 0 y aviso "Paciente 28 dado de baja".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_borrar_paciente;
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

  -- Las consultas que tenía agendadas ya no se van a dar
  UPDATE encuentro_clinico SET estado = 'cancelado'
  WHERE id_paciente_maestro = p_id_paciente AND estado = 'planeado';
  GET DIAGNOSTICS p_consultas_canceladas = ROW_COUNT;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'eliminar', 'paciente_maestro', p_id_paciente, p_id_paciente, 'exito',
          'Baja lógica. Motivo: ' || p_motivo);

  RAISE NOTICE 'Paciente % dado de baja, % consultas canceladas', p_id_paciente, p_consultas_canceladas;
END;
$$;

-- ===== Demostración =====
\echo '--- El paciente 28 queda inactivo; NO se borra de la tabla'
BEGIN;
CALL sp_borrar_paciente(3, 28, 'Cambio de residencia', NULL);
SELECT id_paciente_maestro, nombre, apellido_paterno, estado
  FROM paciente_maestro WHERE id_paciente_maestro = 28;
ROLLBACK;


\echo
\echo '==================== 6. sp_inserta_medico ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_inserta_medico
-- Propósito: registrar un médico con su especialidad y la institución donde
--            trabaja. Son 3 inserciones relacionadas: si una falla, no se guarda ninguna.
-- Entrada:   p_id_usuario, p_cedula, p_nombre, p_apellido_paterno, p_apellido_materno,
--            p_especialidad, p_cedula_especialidad, p_id_institucion, p_rol_institucion
-- Salida:    p_id_medico (número que se le asignó)
-- Tablas:    profesional_salud, profesional_especialidad, profesional_organizacion,
--            organizacion, usuario, auditoria
-- Reglas:    solo el administrador; cédula de 7 u 8 dígitos y única; la
--            institución debe existir y estar activa; el vínculo inicia hoy.
-- Excepciones: RAISE EXCEPTION por cada regla; además, si la cédula de
--            especialidad ya existe, PostgreSQL lanza unique_violation y se
--            atrapa en el bloque EXCEPTION para dar un mensaje claro.
-- Ejemplo:   CALL sp_inserta_medico(1, '9100150', 'Sofía', 'Garza', 'Lee', 'Pediatría', 'E9205001', 1, 'medico_tratante', NULL);
-- Resultado: p_id_medico = 13 y aviso "Médico 13 registrado".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_inserta_medico;
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

  -- 1) El médico
  INSERT INTO profesional_salud (cedula_profesional, nombre, apellido_paterno, apellido_materno)
  VALUES (TRIM(p_cedula), TRIM(p_nombre), TRIM(p_apellido_paterno), NULLIF(TRIM(p_apellido_materno), ''))
  RETURNING id_profesional INTO p_id_medico;

  -- 2) Su especialidad (si la escribieron)
  IF NULLIF(TRIM(p_especialidad), '') IS NOT NULL THEN
    INSERT INTO profesional_especialidad (id_profesional, especialidad, cedula_especialidad)
    VALUES (p_id_medico, TRIM(p_especialidad), NULLIF(TRIM(p_cedula_especialidad), ''));
  END IF;

  -- 3) Dónde trabaja, desde hoy
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

-- ===== Demostración =====
\echo '--- Alta (administrador): se guarda en 3 tablas a la vez'
BEGIN;
CALL sp_inserta_medico(1, '9100150', 'Sofía', 'Garza', 'Lee', 'Pediatría', 'E9205001', 1, 'medico_tratante', NULL);
SELECT id_profesional, cedula_profesional, nombre, apellido_paterno, activo
  FROM profesional_salud WHERE cedula_profesional = '9100150';
SELECT pe.id_profesional, pe.especialidad, pe.cedula_especialidad
  FROM profesional_especialidad pe JOIN profesional_salud ps USING (id_profesional)
 WHERE ps.cedula_profesional = '9100150';
SELECT po.id_profesional, po.id_organizacion, po.rol, po.fecha_inicio
  FROM profesional_organizacion po JOIN profesional_salud ps USING (id_profesional)
 WHERE ps.cedula_profesional = '9100150';
ROLLBACK;

\echo '--- Error: la cédula 9100101 ya existe'
BEGIN;
CALL sp_inserta_medico(1, '9100101', 'Otro', 'Médico', NULL, NULL, NULL, 1, 'medico_tratante', NULL);
ROLLBACK;


\echo
\echo '==================== 7. sp_borrar_medico (baja lógica) ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_borrar_medico
-- Propósito: dar de baja a un médico. Es baja LÓGICA: sus consultas pasadas
--            se conservan.
-- Entrada:   p_id_usuario, p_id_medico
-- Salida:    ninguna
-- Tablas:    profesional_salud, profesional_organizacion, encuentro_clinico, usuario, auditoria
-- Reglas:    solo el administrador; no procede si el médico tiene consultas
--            planeadas o en curso; queda inactivo, se cierran sus vínculos con
--            las instituciones y se desactiva su cuenta de usuario.
-- Ejemplo:   CALL sp_borrar_medico(1, 12);
-- Resultado: aviso "Médico 12 dado de baja".
--            CALL sp_borrar_medico(1, 1); -> ERROR "El médico tiene 3 consulta(s) planeada(s)..."
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_borrar_medico;
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

-- ===== Demostración =====
\echo '--- Error: el médico 1 tiene consultas planeadas o en curso'
BEGIN;
CALL sp_borrar_medico(1, 1);
ROLLBACK;

\echo '--- El médico 12 sí se puede dar de baja: queda activo = false'
BEGIN;
CALL sp_borrar_medico(1, 12);
SELECT id_profesional, nombre, apellido_paterno, activo
  FROM profesional_salud WHERE id_profesional = 12;
SELECT id_profesional, id_organizacion, fecha_inicio, fecha_fin
  FROM profesional_organizacion WHERE id_profesional = 12;
ROLLBACK;


\echo
\echo '==================== 8. sp_inserta_consulta ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_inserta_consulta
-- Propósito: agendar una consulta. En el modelo todo dato clínico guarda de
--            dónde vino (procedencia), así que además de la consulta se crea
--            su rastro: paquete del portal -> detalle -> procedencia -> consulta.
-- Entrada:   p_id_usuario, p_id_paciente, p_id_institucion, p_id_medico,
--            p_tipo, p_motivo, p_fecha
-- Salida:    p_id_consulta (número que se le asignó)
-- Tablas:    encuentro_clinico, paquete_transaccion, detalle_transaccion,
--            procedencia_dato, sistema_origen, paciente_maestro, organizacion,
--            profesional_salud, profesional_organizacion, usuario, auditoria
-- Reglas:    coordinador o médico; un médico solo agenda a su nombre;
--            paciente activo; institución activa; médico activo y que trabaje
--            en esa institución; el médico no puede tener otra consulta a
--            menos de 30 minutos; fecha futura = 'planeado', si no = 'en_curso'.
-- Ejemplo:   CALL sp_inserta_consulta(5, 1, 1, 1, 'consulta_externa', 'Control', '2026-11-03 10:00', NULL);
-- Resultado: p_id_consulta = 51 y aviso "Consulta 51 registrada como planeado".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_inserta_consulta;
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

  -- Sistema "Portal" del hub: de ahí vienen las capturas hechas en la página
  SELECT id_sistema_origen INTO v_sistema FROM sistema_origen
    WHERE tipo_sistema = 'portal_hub' AND estado = 'activo'
    ORDER BY id_sistema_origen LIMIT 1;
  IF v_sistema IS NULL THEN
    RAISE EXCEPTION 'No hay un sistema de portal activo configurado.';
  END IF;

  -- 1) Paquete de captura del portal
  INSERT INTO paquete_transaccion (id_sistema_origen, id_usuario_captura, direccion, tipo_paquete, estado, hash_paquete)
  VALUES (v_sistema, p_id_usuario, 'entrante', 'captura_portal', 'procesado',
          encode(sha256(convert_to('captura|' || p_id_paciente || '|' || clock_timestamp() || '|' || gen_random_uuid(), 'UTF8')), 'hex'))
  RETURNING id_paquete INTO v_paquete;

  -- 2) Detalle del paquete (el recurso "Encounter")
  INSERT INTO detalle_transaccion (id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso,
                                   fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
  VALUES (v_paquete, p_id_paciente, 'Encounter', 'Encounter-portal-' || v_paquete, '1',
          CURRENT_TIMESTAMP, 'integrado',
          encode(sha256(convert_to('encuentro|' || v_paquete || '|' || clock_timestamp(), 'UTF8')), 'hex'),
          CURRENT_TIMESTAMP)
  RETURNING id_detalle INTO v_detalle;

  -- 3) Procedencia del dato
  INSERT INTO procedencia_dato (id_detalle, ruta_elemento, valor_original, fecha_origen)
  VALUES (v_detalle, 'Encounter', p_tipo || ' - ' || COALESCE(p_motivo, ''), CURRENT_TIMESTAMP)
  RETURNING id_procedencia INTO v_procedencia;

  -- 4) La consulta
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

-- ===== Demostración =====
\echo '--- Agendar consulta a futuro: queda planeada y con su origen (captura_portal)'
BEGIN;
CALL sp_inserta_consulta(3, 1, 1, 1, 'consulta_externa', 'Control', '2026-11-03 10:00', NULL);
SELECT e.id_encuentro, e.id_paciente_maestro, e.id_profesional, e.fecha_inicio, e.estado,
       pq.tipo_paquete
  FROM encuentro_clinico e
  JOIN procedencia_dato pr ON pr.id_procedencia = e.id_procedencia
  JOIN detalle_transaccion dt ON dt.id_detalle = pr.id_detalle
  JOIN paquete_transaccion pq ON pq.id_paquete = dt.id_paquete
 ORDER BY e.id_encuentro DESC LIMIT 1;
ROLLBACK;

\echo '--- Error: el mismo médico ya tiene una consulta a las 10:00 y se intenta otra a las 10:10'
BEGIN;
CALL sp_inserta_consulta(3, 1, 1, 1, 'consulta_externa', 'Control', '2026-11-03 10:00', NULL);
CALL sp_inserta_consulta(3, 2, 1, 1, 'consulta_externa', 'Control', '2026-11-03 10:10', NULL);
ROLLBACK;


\echo
\echo '==================== 9. sp_actualiza_consulta ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_actualiza_consulta
-- Propósito: cambiar motivo y fecha de una consulta, o avanzar su estado
--            (planeado -> en_curso -> finalizado). Cada cambio queda guardado
--            en el historial version_dato.
-- Entrada:   p_id_usuario, p_id_consulta, p_motivo, p_fecha, p_estado
-- Salida:    ninguna
-- Tablas:    encuentro_clinico, version_dato, usuario, auditoria
-- Reglas:    coordinador o el médico de la consulta; una consulta finalizada o
--            cancelada ya no se modifica; solo se permite planeado -> planeado|en_curso
--            y en_curso -> en_curso|finalizado; la fecha solo cambia mientras está
--            planeada; al finalizar se guarda la fecha de fin.
-- Ejemplo:   CALL sp_actualiza_consulta(5, 48, 'Control de glucosa', '2026-10-21 09:00', 'en_curso');
-- Resultado: aviso "Consulta 48: planeado -> en_curso" y filas nuevas en version_dato.
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_actualiza_consulta;
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

  -- Datos actuales de la consulta
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

  -- Historial: una fila por cada campo que cambió
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

-- ===== Demostración =====
\echo '--- La consulta 48 pasa de planeado a en_curso y el cambio queda en version_dato'
BEGIN;
CALL sp_actualiza_consulta(5, 48, 'Control de glucosa', '2026-10-21 09:00', 'en_curso');
SELECT id_encuentro, motivo, estado FROM encuentro_clinico WHERE id_encuentro = 48;
SELECT campo, valor_anterior, valor_nuevo, motivo
  FROM version_dato ORDER BY id_version DESC LIMIT 3;
ROLLBACK;

\echo '--- Error: una consulta finalizada ya no se modifica'
BEGIN;
CALL sp_actualiza_consulta(3, 1, 'Otro motivo', NULL, 'en_curso');
ROLLBACK;


\echo
\echo '==================== 10. sp_cancelar_consulta (baja lógica) ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_cancelar_consulta
-- Propósito: cancelar una consulta. Es baja LÓGICA: queda 'cancelado', no se borra.
-- Entrada:   p_id_usuario, p_id_consulta, p_motivo
-- Salida:    ninguna
-- Tablas:    encuentro_clinico, diagnostico, observacion, solicitud_medicamento,
--            version_dato, usuario, auditoria
-- Reglas:    coordinador o el médico de la consulta; motivo obligatorio; solo
--            consultas planeadas o en curso; no se cancela si ya tiene
--            diagnósticos, signos vitales o medicamentos registrados.
-- Ejemplo:   CALL sp_cancelar_consulta(3, 49, 'El paciente no podrá asistir');
-- Resultado: aviso "Consulta 49 cancelada".
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancelar_consulta;
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

-- ===== Demostración =====
\echo '--- La consulta 49 queda cancelada; NO se borra'
BEGIN;
CALL sp_cancelar_consulta(3, 49, 'El paciente no podrá asistir');
SELECT id_encuentro, motivo, estado FROM encuentro_clinico WHERE id_encuentro = 49;
ROLLBACK;


\echo
\echo '==================== 11. Reportes (COUNT y AVG) ===================='
-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_consultas_de_medico
-- Propósito: decir cuántas consultas (no canceladas) ha tenido un médico.
-- Entrada:   p_id_medico
-- Salida:    aviso con RAISE NOTICE
-- Tablas:    profesional_salud, encuentro_clinico
-- Reglas:    las consultas canceladas no cuentan; si el médico no existe se avisa con error.
-- Ejemplo:   CALL sp_consultas_de_medico(1);
-- Resultado: NOTICE: Carlos Garza tuvo 10 consultas
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_consultas_de_medico;
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

-- ===== Cómo está construido =====
-- ------------------------------------------------------------
-- sp_promedio_edad_pacientes
-- Propósito: calcular la edad promedio de los pacientes activos.
-- Entrada:   ninguna
-- Salida:    aviso con RAISE NOTICE
-- Tablas:    paciente_maestro
-- Ejemplo:   CALL sp_promedio_edad_pacientes();
-- Resultado: NOTICE: La edad promedio de los 30 pacientes activos es 42.83 años
-- ------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_promedio_edad_pacientes;
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

-- ===== Demostración =====
\echo '--- sp_consultas_de_medico: cuántas consultas tuvo el médico 1'
CALL sp_consultas_de_medico(1);
\echo '--- sp_promedio_edad_pacientes: edad promedio de los pacientes activos'
CALL sp_promedio_edad_pacientes();


\echo
\echo '==================== 12. sp_resolver_duplicado (hub) ===================='
-- ===== Cómo está construido =====
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

-- ===== Demostración =====
\echo '--- Candidatos a duplicado con su puntaje'
SELECT id_candidato, id_paciente_a, id_paciente_b, puntaje, estado FROM v_candidato_duplicado;

\echo '--- El coordinador fusiona el candidato 1: el paciente 31 se une al 5'
BEGIN;
CALL sp_resolver_duplicado(3, 1, 'fusionar', 'Mismo nombre, fecha de nacimiento y teléfono.');
SELECT id_candidato, estado, justificacion FROM candidato_duplicado WHERE id_candidato = 1;
SELECT id_paciente_maestro, nombre, apellido_paterno, estado, id_paciente_fusionado_en
  FROM paciente_maestro WHERE id_paciente_maestro IN (5, 31);
ROLLBACK;

\echo '--- Error: el administrador (usuario 1) no puede resolver duplicados'
BEGIN;
CALL sp_resolver_duplicado(1, 1, 'fusionar', 'Prueba sin permiso.');
ROLLBACK;

\echo
\echo '==================== Fin de la demostración ===================='
