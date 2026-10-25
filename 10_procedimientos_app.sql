-- ============================================================
-- 10_procedimientos_app.sql
-- Procedimientos almacenados que usa la aplicación Flask (App03).
-- Misma estructura que vimos en clase:
--   CREATE PROCEDURE nombre( IN ..., OUT ... )
--   LANGUAGE plpgsql
--   AS $$
--   DECLARE ...
--   BEGIN ... END;
--   $$;
--
-- Ejecutar DESPUÉS de 05_programacion.sql y 08_programacion_hub.sql
-- (los de consulta leen sus vistas).
--
-- Contenido (20 procedimientos):
--   Sesión:     1  sp_iniciar_sesion
--   Pacientes:  2  sp_obtener_pacientes   3  sp_obtener_paciente
--               4  sp_inserta_paciente    5  sp_actualiza_paciente   6  sp_borrar_paciente
--   Médicos:    7  sp_obtener_medicos     8  sp_obtener_medico
--               9  sp_inserta_medico     10  sp_actualiza_medico    11  sp_borrar_medico
--   Consultas: 12  sp_obtener_consultas  13  sp_obtener_consulta
--              14  sp_inserta_consulta   15  sp_actualiza_consulta  16  sp_cancelar_consulta
--   Listas:    17  sp_obtener_instituciones  18  sp_obtener_medicos_institucion
--   Reportes:  19  sp_consultas_de_medico    20  sp_promedio_edad_pacientes
--
-- Manejo de excepciones: cuando no se cumple una regla se usa
-- RAISE EXCEPTION 'mensaje'. Eso cancela todo lo que hizo el procedimiento
-- y Flask muestra el mensaje en pantalla.
-- RAISE NOTICE solo imprime un aviso en psql (como en clase).
-- ============================================================

-- Para poder correr este archivo varias veces: borra los procedimientos si ya existen
DROP PROCEDURE IF EXISTS sp_iniciar_sesion;
DROP PROCEDURE IF EXISTS sp_obtener_pacientes;
DROP PROCEDURE IF EXISTS sp_obtener_paciente;
DROP PROCEDURE IF EXISTS sp_inserta_paciente;
DROP PROCEDURE IF EXISTS sp_actualiza_paciente;
DROP PROCEDURE IF EXISTS sp_borrar_paciente;
DROP PROCEDURE IF EXISTS sp_obtener_medicos;
DROP PROCEDURE IF EXISTS sp_obtener_medico;
DROP PROCEDURE IF EXISTS sp_inserta_medico;
DROP PROCEDURE IF EXISTS sp_actualiza_medico;
DROP PROCEDURE IF EXISTS sp_borrar_medico;
DROP PROCEDURE IF EXISTS sp_obtener_consultas;
DROP PROCEDURE IF EXISTS sp_obtener_consulta;
DROP PROCEDURE IF EXISTS sp_inserta_consulta;
DROP PROCEDURE IF EXISTS sp_actualiza_consulta;
DROP PROCEDURE IF EXISTS sp_cancelar_consulta;
DROP PROCEDURE IF EXISTS sp_obtener_instituciones;
DROP PROCEDURE IF EXISTS sp_obtener_medicos_institucion;
DROP PROCEDURE IF EXISTS sp_consultas_de_medico;
DROP PROCEDURE IF EXISTS sp_promedio_edad_pacientes;


-- ************************************************************
-- SESIÓN
-- ************************************************************

-- ------------------------------------------------------------
-- 1. sp_iniciar_sesion
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


-- ************************************************************
-- PACIENTES
-- ************************************************************

-- ------------------------------------------------------------
-- 2. sp_obtener_pacientes
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

-- ------------------------------------------------------------
-- 3. sp_obtener_paciente
-- Propósito: datos de un solo paciente (detalle y formulario de editar).
-- Entrada:   p_id_paciente
-- Salida:    p_paciente REFCURSOR ('cursor_paciente')
--            Columnas: 0 id, 1 nombre, 2 apellido paterno, 3 apellido materno,
--            4 fecha de nacimiento, 5 sexo, 6 curp, 7 estado, 8 edad,
--            9 número de consultas, 10 última consulta, 11 consentimiento vigente
-- Tablas:    vista v_paciente_resumen
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_paciente(1, NULL);
--            FETCH ALL FROM cursor_paciente;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_paciente(
  IN p_id_paciente BIGINT,
  OUT p_paciente REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_paciente := 'cursor_paciente';

  OPEN p_paciente FOR
    SELECT id_paciente_maestro, nombre,
           apellido_paterno, apellido_materno,
           fecha_nacimiento, sexo, curp, estado,
           edad, total_consultas, ultima_consulta,
           consentimiento_vigente
    FROM v_paciente_resumen WHERE id_paciente_maestro = p_id_paciente;
END;
$$;

-- ------------------------------------------------------------
-- 4. sp_inserta_paciente
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

-- ------------------------------------------------------------
-- 5. sp_actualiza_paciente
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

-- ------------------------------------------------------------
-- 6. sp_borrar_paciente
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


-- ************************************************************
-- MÉDICOS
-- ************************************************************

-- ------------------------------------------------------------
-- 7. sp_obtener_medicos
-- Propósito: listado de médicos con búsqueda y filtro activos / de baja.
-- Entrada:   p_buscar (nombre, cédula o especialidad), p_activo (TRUE, FALSE o NULL = todos)
-- Salida:    p_medicos REFCURSOR ('cursor_medicos')
--            Columnas: 0 id, 1 cédula, 2 nombre completo, 3 especialidades,
--            4 instituciones, 5 número de consultas, 6 activo
-- Tablas:    vista v_profesional_resumen (profesional_salud, profesional_especialidad,
--            profesional_organizacion, organizacion, encuentro_clinico)
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_medicos('', TRUE, NULL);
--            FETCH ALL FROM cursor_medicos;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_medicos(
  IN p_buscar VARCHAR(100),
  IN p_activo BOOLEAN,
  OUT p_medicos REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_medicos := 'cursor_medicos';

  OPEN p_medicos FOR
    SELECT id_profesional, cedula_profesional,
           nombre_completo, especialidades,
           instituciones_vigentes, total_consultas,
           activo
    FROM v_profesional_resumen
    WHERE (p_activo IS NULL OR activo = p_activo)
      AND (p_buscar IS NULL OR p_buscar = ''
           OR nombre_completo ILIKE '%' || p_buscar || '%'
           OR cedula_profesional ILIKE '%' || p_buscar || '%'
           OR especialidades ILIKE '%' || p_buscar || '%')
    ORDER BY apellido_paterno, nombre;
END;
$$;

-- ------------------------------------------------------------
-- 8. sp_obtener_medico
-- Propósito: datos de un solo médico (detalle y formulario de editar).
-- Entrada:   p_id_profesional
-- Salida:    p_medico REFCURSOR ('cursor_medico')
--            Columnas: 0 id, 1 cédula, 2 nombre, 3 apellido paterno, 4 apellido materno,
--            5 activo, 6 especialidades, 7 instituciones, 8 número de consultas, 9 última consulta
-- Tablas:    vista v_profesional_resumen
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_medico(1, NULL);
--            FETCH ALL FROM cursor_medico;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_medico(
  IN p_id_profesional BIGINT,
  OUT p_medico REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_medico := 'cursor_medico';

  OPEN p_medico FOR
    SELECT id_profesional, cedula_profesional,
           nombre, apellido_paterno, apellido_materno,
           activo, especialidades, instituciones_vigentes,
           total_consultas, ultima_consulta
    FROM v_profesional_resumen WHERE id_profesional = p_id_profesional;
END;
$$;

-- ------------------------------------------------------------
-- 9. sp_inserta_medico
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

-- ------------------------------------------------------------
-- 10. sp_actualiza_medico
-- Propósito: modificar cédula, nombre y apellidos de un médico.
-- Entrada:   p_id_usuario, p_id_medico, p_cedula, p_nombre, p_apellido_paterno, p_apellido_materno
-- Salida:    ninguna
-- Tablas:    profesional_salud, usuario, auditoria
-- Reglas:    solo el administrador; el médico debe estar activo; la cédula
--            conserva su formato y no puede ser de otro médico.
-- Ejemplo:   CALL sp_actualiza_medico(1, 2, '9100102', 'Laura', 'Salinas', 'Cantú');
-- Resultado: aviso "Médico 2 actualizado".
-- ------------------------------------------------------------
CREATE PROCEDURE sp_actualiza_medico(
  IN p_id_usuario BIGINT,
  IN p_id_medico BIGINT,
  IN p_cedula VARCHAR(20),
  IN p_nombre VARCHAR(100),
  IN p_apellido_paterno VARCHAR(100),
  IN p_apellido_materno VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_activo BOOLEAN;
BEGIN
  SELECT rol INTO v_rol FROM usuario WHERE id_usuario = p_id_usuario AND activo = TRUE;
  IF v_rol IS DISTINCT FROM 'administrador' THEN
    RAISE EXCEPTION 'Solo el administrador puede modificar médicos.';
  END IF;

  SELECT activo INTO v_activo FROM profesional_salud WHERE id_profesional = p_id_medico;
  IF v_activo IS NULL THEN
    RAISE EXCEPTION 'El médico % no existe.', p_id_medico;
  END IF;
  IF v_activo = FALSE THEN
    RAISE EXCEPTION 'No se puede modificar un médico dado de baja.';
  END IF;

  IF COALESCE(TRIM(p_cedula), '') !~ '^[0-9]{7,8}$' THEN
    RAISE EXCEPTION 'La cédula profesional debe tener 7 u 8 dígitos.';
  END IF;
  IF EXISTS (SELECT 1 FROM profesional_salud WHERE cedula_profesional = TRIM(p_cedula) AND id_profesional <> p_id_medico) THEN
    RAISE EXCEPTION 'La cédula % ya pertenece a otro médico.', TRIM(p_cedula);
  END IF;
  IF COALESCE(TRIM(p_nombre), '') = '' OR COALESCE(TRIM(p_apellido_paterno), '') = '' THEN
    RAISE EXCEPTION 'El nombre y el apellido paterno son obligatorios.';
  END IF;

  UPDATE profesional_salud SET
    cedula_profesional = TRIM(p_cedula),
    nombre = TRIM(p_nombre),
    apellido_paterno = TRIM(p_apellido_paterno),
    apellido_materno = NULLIF(TRIM(p_apellido_materno), '')
  WHERE id_profesional = p_id_medico;

  INSERT INTO auditoria (id_usuario, rol_en_evento, accion, tabla_afectada, id_registro_afectado, resultado, detalle)
  VALUES (p_id_usuario, v_rol, 'actualizar', 'profesional_salud', p_id_medico, 'exito', 'Actualización de médico.');

  RAISE NOTICE 'Médico % actualizado', p_id_medico;
END;
$$;

-- ------------------------------------------------------------
-- 11. sp_borrar_medico
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


-- ************************************************************
-- CONSULTAS
-- ************************************************************

-- ------------------------------------------------------------
-- 12. sp_obtener_consultas
-- Propósito: listado de consultas con búsqueda y filtros. Un médico solo
--            ve sus propias consultas.
-- Entrada:   p_id_usuario (quien consulta), p_buscar (paciente, médico o número),
--            p_estado (NULL = todos), p_id_paciente (NULL = todos), p_id_medico (NULL = todos)
-- Salida:    p_consultas REFCURSOR ('cursor_consultas')
--            Columnas: 0 id, 1 fecha, 2 paciente, 3 médico, 4 institución, 5 tipo,
--            6 motivo, 7 estado, 8 diagnóstico principal, 9 id paciente, 10 id médico
-- Tablas:    vista v_historial_consultas, usuario
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_consultas(5, '', 'planeado', NULL, NULL, NULL);
--            FETCH ALL FROM cursor_consultas;
--            COMMIT;
-- Resultado: solo las consultas planeadas del médico del usuario 5.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_consultas(
  IN p_id_usuario BIGINT,
  IN p_buscar VARCHAR(100),
  IN p_estado VARCHAR(12),
  IN p_id_paciente BIGINT,
  IN p_id_medico BIGINT,
  OUT p_consultas REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_rol VARCHAR(25);
  v_id_profesional BIGINT;
BEGIN
  SELECT rol, id_profesional INTO v_rol, v_id_profesional FROM usuario WHERE id_usuario = p_id_usuario;

  p_consultas := 'cursor_consultas';

  OPEN p_consultas FOR
    SELECT id_encuentro, fecha_inicio,
           paciente, medico, institucion,
           tipo_encuentro, motivo, estado,
           diagnostico_principal,
           id_paciente_maestro, id_profesional
    FROM v_historial_consultas
    WHERE (v_rol <> 'medico' OR id_profesional = v_id_profesional)
      AND (p_estado IS NULL OR estado = p_estado)
      AND (p_id_paciente IS NULL OR id_paciente_maestro = p_id_paciente)
      AND (p_id_medico IS NULL OR id_profesional = p_id_medico)
      AND (p_buscar IS NULL OR p_buscar = ''
           OR paciente ILIKE '%' || p_buscar || '%'
           OR medico ILIKE '%' || p_buscar || '%'
           OR id_encuentro::TEXT = p_buscar)
    ORDER BY fecha_inicio DESC;
END;
$$;

-- ------------------------------------------------------------
-- 13. sp_obtener_consulta
-- Propósito: datos de una sola consulta (detalle y formulario de editar).
-- Entrada:   p_id_consulta
-- Salida:    p_consulta REFCURSOR ('cursor_consulta')
--            Columnas: 0 id, 1 id paciente, 2 paciente, 3 id médico, 4 médico,
--            5 institución, 6 tipo, 7 motivo, 8 inicio, 9 fin, 10 estado,
--            11 código CIE-10, 12 diagnóstico principal
-- Tablas:    vista v_historial_consultas
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_consulta(48, NULL);
--            FETCH ALL FROM cursor_consulta;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_consulta(
  IN p_id_consulta BIGINT,
  OUT p_consulta REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_consulta := 'cursor_consulta';

  OPEN p_consulta FOR
    SELECT id_encuentro, id_paciente_maestro, paciente,
           id_profesional, medico, institucion,
           tipo_encuentro, motivo, fecha_inicio,
           fecha_fin, estado, codigo_diagnostico,
           diagnostico_principal
    FROM v_historial_consultas WHERE id_encuentro = p_id_consulta;
END;
$$;

-- ------------------------------------------------------------
-- 14. sp_inserta_consulta
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

-- ------------------------------------------------------------
-- 15. sp_actualiza_consulta
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

-- ------------------------------------------------------------
-- 16. sp_cancelar_consulta
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


-- ************************************************************
-- LISTAS PARA LOS FORMULARIOS
-- ************************************************************

-- ------------------------------------------------------------
-- 17. sp_obtener_instituciones
-- Propósito: instituciones activas para la lista del formulario de médicos.
-- Salida:    p_instituciones REFCURSOR ('cursor_instituciones')
--            Columnas: 0 id, 1 nombre, 2 tipo
-- Tablas:    organizacion
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_instituciones(NULL);
--            FETCH ALL FROM cursor_instituciones;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_instituciones(
  OUT p_instituciones REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_instituciones := 'cursor_instituciones';

  OPEN p_instituciones FOR
    SELECT id_organizacion, nombre, tipo_organizacion
    FROM organizacion
    WHERE estado = 'activa'
    ORDER BY nombre;
END;
$$;

-- ------------------------------------------------------------
-- 18. sp_obtener_medicos_institucion
-- Propósito: combinaciones médico + institución donde el médico trabaja hoy.
--            Se usan en el formulario de nueva consulta para que solo se pueda
--            elegir una combinación válida.
-- Entrada:   p_id_medico (NULL = todos; un médico solo ve las suyas)
-- Salida:    p_vinculos REFCURSOR ('cursor_vinculos')
--            Columnas: 0 id médico, 1 médico, 2 id institución, 3 institución, 4 especialidades
-- Tablas:    profesional_organizacion, profesional_salud, organizacion, profesional_especialidad
-- Ejemplo:   BEGIN;
--            CALL sp_obtener_medicos_institucion(NULL, NULL);
--            FETCH ALL FROM cursor_vinculos;
--            COMMIT;
-- ------------------------------------------------------------
CREATE PROCEDURE sp_obtener_medicos_institucion(
  IN p_id_medico BIGINT,
  OUT p_vinculos REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN
  p_vinculos := 'cursor_vinculos';

  OPEN p_vinculos FOR
    SELECT DISTINCT ps.id_profesional,
           ps.nombre || ' ' || ps.apellido_paterno || COALESCE(' ' || ps.apellido_materno, '') AS medico,
           o.id_organizacion, o.nombre AS institucion,
           (SELECT STRING_AGG(pe.especialidad, ', ') FROM profesional_especialidad pe
             WHERE pe.id_profesional = ps.id_profesional) AS especialidades
    FROM profesional_organizacion po
    INNER JOIN profesional_salud ps ON ps.id_profesional = po.id_profesional
    INNER JOIN organizacion o ON o.id_organizacion = po.id_organizacion
    WHERE ps.activo = TRUE
      AND o.estado = 'activa'
      AND po.fecha_inicio <= CURRENT_DATE
      AND (po.fecha_fin IS NULL OR po.fecha_fin >= CURRENT_DATE)
      AND (p_id_medico IS NULL OR ps.id_profesional = p_id_medico)
    ORDER BY medico, institucion;
END;
$$;


-- ************************************************************
-- REPORTES RÁPIDOS (para correr en psql, como los de clase)
-- ************************************************************

-- ------------------------------------------------------------
-- 19. sp_consultas_de_medico
-- Propósito: decir cuántas consultas (no canceladas) ha tenido un médico.
-- Entrada:   p_id_medico
-- Salida:    aviso con RAISE NOTICE
-- Tablas:    profesional_salud, encuentro_clinico
-- Reglas:    las consultas canceladas no cuentan; si el médico no existe se avisa con error.
-- Ejemplo:   CALL sp_consultas_de_medico(1);
-- Resultado: NOTICE: Carlos Garza tuvo 10 consultas
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- 20. sp_promedio_edad_pacientes
-- Propósito: calcular la edad promedio de los pacientes activos.
-- Entrada:   ninguna
-- Salida:    aviso con RAISE NOTICE
-- Tablas:    paciente_maestro
-- Ejemplo:   CALL sp_promedio_edad_pacientes();
-- Resultado: NOTICE: La edad promedio de los 30 pacientes activos es 42.83 años
-- ------------------------------------------------------------
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
