-- ============================================================
-- 06_pruebas_procedimientos.sql
-- Evidencia de ejecución de los 12 procedimientos almacenados.
-- Cada caso indica el resultado ESPERADO y muestra el OBTENIDO como NOTICE.
-- Todo corre dentro de una transacción que se deshace al final (ROLLBACK),
-- así que la base queda igual que antes. Para conservar los cambios,
-- cambie el ROLLBACK final por COMMIT.
--
-- Usuarios de prueba: 1 administrador, 2 analista, 3 coordinador,
-- 4 coordinador inactivo, 5 médico (profesional 1), 6 médico (profesional 3).
-- ============================================================
\set ON_ERROR_STOP off
SET client_min_messages = notice;
BEGIN;

-- Ejecuta un CALL y reporta OK o RECHAZADO con el mensaje del procedimiento.
CREATE OR REPLACE FUNCTION pg_temp.probar(p_caso TEXT, p_esperado TEXT, p_sql TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_res TEXT;
BEGIN
  -- Los procedimientos con parámetro INOUT (terminan en NULL) devuelven un valor.
  IF p_sql ~ 'NULL\)$' THEN
    EXECUTE p_sql INTO v_res;
  ELSE
    EXECUTE p_sql;
  END IF;
  RAISE NOTICE '% | esperado: % | obtenido: OK %', p_caso, p_esperado, coalesce('(resultado ' || v_res || ')', '');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '% | esperado: % | obtenido: RECHAZADO -> %', p_caso, p_esperado, SQLERRM;
END $$;

-- Oculta las filas vacías de cada SELECT; los resultados salen como NOTICE.
\o /dev/null

-- SP-01 sp_registrar_paciente
SELECT pg_temp.probar('SP-01a alta válida', 'OK',
  $q$CALL sp_registrar_paciente(3,'Laura','Pérez','Soto','1990-05-01','femenino','PESL900501MNLRTR09',NULL)$q$);
SELECT pg_temp.probar('SP-01b fecha futura', 'RECHAZADO',
  $q$CALL sp_registrar_paciente(3,'Ana','Ruiz',NULL,'2030-01-01','femenino',NULL,NULL)$q$);
SELECT pg_temp.probar('SP-01c CURP repetida', 'RECHAZADO',
  $q$CALL sp_registrar_paciente(3,'Otro','Nombre',NULL,'1980-01-01','masculino','GATJ850312HNLRRS01',NULL)$q$);
SELECT pg_temp.probar('SP-01d posible duplicado', 'RECHAZADO',
  $q$CALL sp_registrar_paciente(3,'José Luis','García','X','1985-03-12','masculino',NULL,NULL)$q$);
SELECT pg_temp.probar('SP-01e rol médico', 'RECHAZADO',
  $q$CALL sp_registrar_paciente(5,'Mario','Luna',NULL,'1970-01-01','masculino',NULL,NULL)$q$);
SELECT pg_temp.probar('SP-01f usuario inactivo', 'RECHAZADO',
  $q$CALL sp_registrar_paciente(4,'Mario','Luna',NULL,'1970-01-01','masculino',NULL,NULL)$q$);

-- SP-02 sp_actualizar_paciente
SELECT pg_temp.probar('SP-02a edición válida', 'OK',
  $q$CALL sp_actualizar_paciente(3,2,'María Fernanda','López','Garza','1990-07-25','femenino','LOGM900725MNLPRR02')$q$);
SELECT pg_temp.probar('SP-02b paciente fusionado', 'RECHAZADO',
  $q$CALL sp_actualizar_paciente(3,32,'Patricia','González','Villarreal','1975-04-14','femenino',NULL)$q$);
SELECT pg_temp.probar('SP-02c CURP de otro paciente', 'RECHAZADO',
  $q$CALL sp_actualizar_paciente(3,2,'María Fernanda','López','Garza','1990-07-25','femenino','GATJ850312HNLRRS01')$q$);

-- SP-03 sp_baja_paciente
SELECT pg_temp.probar('SP-03a baja con consulta planeada', 'OK (1 cancelada)',
  $q$CALL sp_baja_paciente(3,23,'Cambio de residencia',NULL)$q$);
SELECT pg_temp.probar('SP-03b paciente ya inactivo', 'RECHAZADO',
  $q$CALL sp_baja_paciente(3,27,'Prueba',NULL)$q$);
SELECT pg_temp.probar('SP-03c sin motivo', 'RECHAZADO',
  $q$CALL sp_baja_paciente(3,28,'',NULL)$q$);

-- SP-04 sp_registrar_profesional
SELECT pg_temp.probar('SP-04a alta válida', 'OK',
  $q$CALL sp_registrar_profesional(1,'9100150','Sofía','Garza','Lee','Pediatría','E9205001',1,'medico_tratante',NULL)$q$);
SELECT pg_temp.probar('SP-04b cédula repetida', 'RECHAZADO',
  $q$CALL sp_registrar_profesional(1,'9100101','X','Y',NULL,NULL,NULL,1,'medico_tratante',NULL)$q$);
SELECT pg_temp.probar('SP-04c cédula con letras', 'RECHAZADO',
  $q$CALL sp_registrar_profesional(1,'ABC123','X','Y',NULL,NULL,NULL,1,'medico_tratante',NULL)$q$);
SELECT pg_temp.probar('SP-04d institución suspendida', 'RECHAZADO',
  $q$CALL sp_registrar_profesional(1,'9100151','X','Y',NULL,NULL,NULL,9,'medico_tratante',NULL)$q$);
SELECT pg_temp.probar('SP-04e rol coordinador', 'RECHAZADO',
  $q$CALL sp_registrar_profesional(3,'9100152','X','Y',NULL,NULL,NULL,1,'medico_tratante',NULL)$q$);

-- SP-05 sp_actualizar_profesional
SELECT pg_temp.probar('SP-05a edición válida', 'OK',
  $q$CALL sp_actualizar_profesional(1,2,'9100102','Laura','Salinas','Cantú de León')$q$);
SELECT pg_temp.probar('SP-05b profesional inactivo', 'RECHAZADO',
  $q$CALL sp_actualizar_profesional(1,11,'9100111','Ernesto','Tamez','Garza')$q$);

-- SP-06 sp_baja_profesional
SELECT pg_temp.probar('SP-06a baja sin pendientes', 'OK',
  $q$CALL sp_baja_profesional(1,12)$q$);
SELECT pg_temp.probar('SP-06b con consultas pendientes', 'RECHAZADO',
  $q$CALL sp_baja_profesional(1,7)$q$);

-- SP-07 sp_registrar_encuentro
SELECT pg_temp.probar('SP-07a médico registra consulta propia', 'OK',
  $q$CALL sp_registrar_encuentro(5,1,1,1,'consulta_externa','Control','2026-12-03 10:00-06',NULL)$q$);
SELECT pg_temp.probar('SP-07b horario ocupado', 'RECHAZADO',
  $q$CALL sp_registrar_encuentro(5,2,1,1,'consulta_externa','Control','2026-12-03 10:15-06',NULL)$q$);
SELECT pg_temp.probar('SP-07c médico a nombre de otro', 'RECHAZADO',
  $q$CALL sp_registrar_encuentro(5,1,1,2,'consulta_externa','Control','2026-12-04 10:00-06',NULL)$q$);
SELECT pg_temp.probar('SP-07d sin vínculo con la institución', 'RECHAZADO',
  $q$CALL sp_registrar_encuentro(3,1,5,1,'consulta_externa','Control','2026-12-05 10:00-06',NULL)$q$);
SELECT pg_temp.probar('SP-07e paciente inactivo', 'RECHAZADO',
  $q$CALL sp_registrar_encuentro(3,27,1,1,'consulta_externa','Control','2026-12-06 10:00-06',NULL)$q$);
SELECT pg_temp.probar('SP-07f analista sin permiso', 'RECHAZADO',
  $q$CALL sp_registrar_encuentro(2,1,1,1,'consulta_externa','Control','2026-12-07 10:00-06',NULL)$q$);

-- SP-08 sp_actualizar_encuentro
SELECT pg_temp.probar('SP-08a planeado -> en_curso', 'OK',
  $q$CALL sp_actualizar_encuentro(5,48,'Control de glucosa','2026-10-21 09:00-06','en_curso')$q$);
SELECT pg_temp.probar('SP-08b en_curso -> finalizado', 'OK',
  $q$CALL sp_actualizar_encuentro(5,48,'Control de glucosa','2026-10-21 09:00-06','finalizado')$q$);
SELECT pg_temp.probar('SP-08c editar finalizada', 'RECHAZADO',
  $q$CALL sp_actualizar_encuentro(3,1,'X','2026-01-09 09:00-06','finalizado')$q$);
SELECT pg_temp.probar('SP-08d médico ajeno', 'RECHAZADO',
  $q$CALL sp_actualizar_encuentro(6,49,'X','2026-10-22 09:00-06','planeado')$q$);

-- SP-09 sp_cancelar_encuentro
SELECT pg_temp.probar('SP-09a cancelar planeada', 'OK',
  $q$CALL sp_cancelar_encuentro(3,49,'El paciente no podrá asistir')$q$);
SELECT pg_temp.probar('SP-09b con información clínica', 'RECHAZADO',
  $q$CALL sp_cancelar_encuentro(3,46,'Prueba')$q$);
SELECT pg_temp.probar('SP-09c ya finalizada', 'RECHAZADO',
  $q$CALL sp_cancelar_encuentro(3,1,'Prueba')$q$);

-- SP-10 sp_resolver_duplicado
SELECT pg_temp.probar('SP-10a fusionar 5 y 31', 'OK',
  $q$CALL sp_resolver_duplicado(3,1,'fusionar','Misma persona confirmada con el paciente.')$q$);
SELECT pg_temp.probar('SP-10b candidato ya resuelto', 'RECHAZADO',
  $q$CALL sp_resolver_duplicado(3,2,'descartar','Prueba')$q$);
SELECT pg_temp.probar('SP-10c descartar 17 y 30', 'OK',
  $q$CALL sp_resolver_duplicado(3,3,'descartar','Personas distintas: padre e hijo.')$q$);

-- SP-11 sp_revocar_consentimiento
SELECT pg_temp.probar('SP-11a revocar activo', 'OK',
  $q$CALL sp_revocar_consentimiento(3,5,'Solicitud del paciente')$q$);
SELECT pg_temp.probar('SP-11b ya revocado', 'RECHAZADO',
  $q$CALL sp_revocar_consentimiento(3,21,'Prueba')$q$);

-- SP-12 sp_registrar_usuario
SELECT pg_temp.probar('SP-12a usuario médico', 'OK',
  $q$CALL sp_registrar_usuario(1,'medico3@flojorama.mx','Segura2026!','medico',NULL,NULL,NULL,2,NULL)$q$);
SELECT pg_temp.probar('SP-12b correo repetido', 'RECHAZADO',
  $q$CALL sp_registrar_usuario(1,'admin@flojorama.mx','Segura2026!','coordinador','A','B',NULL,NULL,NULL)$q$);
SELECT pg_temp.probar('SP-12c contraseña corta', 'RECHAZADO',
  $q$CALL sp_registrar_usuario(1,'nuevo@flojorama.mx','123','coordinador','A','B',NULL,NULL,NULL)$q$);

\o
-- Verificación de efectos dentro de la transacción
SELECT id_paciente_maestro, estado, id_paciente_fusionado_en FROM paciente_maestro WHERE id_paciente_maestro IN (23,31);
SELECT id_encuentro, estado, fecha_fin FROM encuentro_clinico WHERE id_encuentro IN (48,49,50);
SELECT id_procedencia, campo, numero_version, valor_anterior, valor_nuevo FROM version_dato WHERE id_procedencia IN (48,49) ORDER BY 1,2,3;
SELECT accion, tabla_afectada, id_registro_afectado, detalle FROM auditoria ORDER BY id_auditoria DESC LIMIT 5;

ROLLBACK;
