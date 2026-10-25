-- ============================================================
-- 09_pruebas_hub.sql
-- Evidencia de ejecución de los procedimientos SP-13 a SP-21.
-- Igual que 06: cada caso muestra esperado contra obtenido y al final
-- se deshace todo (ROLLBACK).
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

\o /dev/null

-- SP-13 sp_registrar_diagnostico (consulta 46 en curso, médico 7 -> sin cuenta; usa coordinador 3)
SELECT pg_temp.probar('SP-13a diagnóstico secundario', 'OK',
  $q$CALL sp_registrar_diagnostico(3,46,2,'secundario',NULL)$q$);
SELECT pg_temp.probar('SP-13b segundo principal', 'RECHAZADO',
  $q$CALL sp_registrar_diagnostico(3,46,4,'principal',NULL)$q$);
SELECT pg_temp.probar('SP-13c diagnóstico repetido', 'RECHAZADO',
  $q$CALL sp_registrar_diagnostico(3,46,2,'secundario',NULL)$q$);
SELECT pg_temp.probar('SP-13d código que no es CIE-10', 'RECHAZADO',
  $q$CALL sp_registrar_diagnostico(3,46,27,'secundario',NULL)$q$);
SELECT pg_temp.probar('SP-13e consulta finalizada', 'RECHAZADO',
  $q$CALL sp_registrar_diagnostico(3,1,3,'secundario',NULL)$q$);
SELECT pg_temp.probar('SP-13f médico en consulta ajena', 'RECHAZADO',
  $q$CALL sp_registrar_diagnostico(5,46,3,'secundario',NULL)$q$);

-- SP-14 sp_registrar_signo_vital
SELECT pg_temp.probar('SP-14a presión arterial alta', 'OK',
  $q$CALL sp_registrar_signo_vital(3,46,17,'145/95',NULL)$q$);
SELECT pg_temp.probar('SP-14b temperatura', 'OK',
  $q$CALL sp_registrar_signo_vital(3,46,14,'38.4',NULL)$q$);
SELECT pg_temp.probar('SP-14c presión con formato inválido', 'RECHAZADO',
  $q$CALL sp_registrar_signo_vital(3,46,17,'145-95',NULL)$q$);
SELECT pg_temp.probar('SP-14d frecuencia fuera de rango', 'RECHAZADO',
  $q$CALL sp_registrar_signo_vital(3,46,13,'300',NULL)$q$);
SELECT pg_temp.probar('SP-14e código de laboratorio', 'RECHAZADO',
  $q$CALL sp_registrar_signo_vital(3,46,18,'90',NULL)$q$);

-- SP-15 sp_indicar_medicamento
SELECT pg_temp.probar('SP-15a paracetamol 5 días', 'OK',
  $q$CALL sp_indicar_medicamento(3,46,27,'1 tableta','oral','cada 8 horas',5,NULL)$q$);
SELECT pg_temp.probar('SP-15b medicamento repetido', 'RECHAZADO',
  $q$CALL sp_indicar_medicamento(3,46,27,'1 tableta','oral','cada 8 horas',5,NULL)$q$);
SELECT pg_temp.probar('SP-15c fuera del cuadro básico', 'RECHAZADO',
  $q$CALL sp_indicar_medicamento(3,46,1,'1','oral','diario',5,NULL)$q$);
SELECT pg_temp.probar('SP-15d medicamento desactivado', 'RECHAZADO',
  $q$CALL sp_indicar_medicamento(3,46,36,'1 tableta','oral','cada 12 horas',5,NULL)$q$);
SELECT pg_temp.probar('SP-15e duración inválida', 'RECHAZADO',
  $q$CALL sp_indicar_medicamento(3,46,33,'1 tableta','oral','cada 8 horas',0,NULL)$q$);

-- SP-16 sp_resolver_conflicto (1 = alergia del paciente 3, pendiente)
SELECT pg_temp.probar('SP-16a descartar alergia sin justificar', 'RECHAZADO',
  $q$CALL sp_resolver_conflicto(3,1,'vigente_b','corto')$q$);
SELECT pg_temp.probar('SP-16b analista sin permiso', 'RECHAZADO',
  $q$CALL sp_resolver_conflicto(2,1,'vigente_a','x')$q$);
SELECT pg_temp.probar('SP-16c conservar alergia (vigente A)', 'OK',
  $q$CALL sp_resolver_conflicto(3,1,'vigente_a','El paciente confirmó la reacción a la penicilina.')$q$);
SELECT pg_temp.probar('SP-16d conflicto ya resuelto', 'RECHAZADO',
  $q$CALL sp_resolver_conflicto(3,1,'vigente_b','Prueba de conflicto ya resuelto.')$q$);

-- SP-17 sp_registrar_consentimiento
SELECT pg_temp.probar('SP-17a consentimiento nuevo (paciente 25)', 'OK',
  $q$CALL sp_registrar_consentimiento(3,25,'2026-10-17','2026-10-17','2027-10-17',1,ARRAY[1,2]::bigint[],ARRAY[1]::bigint[],NULL)$q$);
SELECT pg_temp.probar('SP-17b traslape con consentimiento activo', 'RECHAZADO',
  $q$CALL sp_registrar_consentimiento(3,1,'2026-10-17','2026-10-17','2027-10-17',1,ARRAY[1]::bigint[],ARRAY[]::bigint[],NULL)$q$);
SELECT pg_temp.probar('SP-17c sin categorías', 'RECHAZADO',
  $q$CALL sp_registrar_consentimiento(3,26,'2026-10-17','2026-10-17','2027-10-17',1,ARRAY[]::bigint[],ARRAY[]::bigint[],NULL)$q$);
SELECT pg_temp.probar('SP-17d fin antes del inicio', 'RECHAZADO',
  $q$CALL sp_registrar_consentimiento(3,26,'2026-10-17','2026-10-17','2026-01-01',1,ARRAY[1]::bigint[],ARRAY[]::bigint[],NULL)$q$);
SELECT pg_temp.probar('SP-17e institución suspendida', 'RECHAZADO',
  $q$CALL sp_registrar_consentimiento(3,26,'2026-10-17','2026-10-17','2027-10-17',9,ARRAY[1]::bigint[],ARRAY[]::bigint[],NULL)$q$);

-- SP-18 sp_gestionar_error (903 y 904 pendientes)
SELECT pg_temp.probar('SP-18a reprocesar recurso', 'OK',
  $q$CALL sp_gestionar_error(2,903,'reprocesar','El laboratorio corrigió el código.')$q$);
SELECT pg_temp.probar('SP-18b rechazar sin motivo', 'RECHAZADO',
  $q$CALL sp_gestionar_error(2,904,'rechazar','')$q$);
SELECT pg_temp.probar('SP-18c rechazar con motivo', 'OK',
  $q$CALL sp_gestionar_error(2,904,'rechazar','Fecha imposible en el origen.')$q$);
SELECT pg_temp.probar('SP-18d recurso ya gestionado', 'RECHAZADO',
  $q$CALL sp_gestionar_error(2,903,'rechazar','Prueba de doble gestión.')$q$);
SELECT pg_temp.probar('SP-18e coordinador sin permiso', 'RECHAZADO',
  $q$CALL sp_gestionar_error(3,905,'reprocesar','x')$q$);

-- SP-19 sp_registrar_organizacion
SELECT pg_temp.probar('SP-19a alta de institución', 'OK',
  $q$CALL sp_registrar_organizacion(1,'NLSSA900011','Clínica Linda Vista','clinica','8183011000','Av. Linda Vista','500','Linda Vista','67100','Dra. Ana Ruiz','aruiz@clv.example.mx','CLV Expediente','expediente_clinico',NULL)$q$);
SELECT pg_temp.probar('SP-19b clave repetida', 'RECHAZADO',
  $q$CALL sp_registrar_organizacion(1,'NLSSA900001','X','clinica',NULL,'C','1',NULL,'64000','Y',NULL,NULL,NULL,NULL)$q$);
SELECT pg_temp.probar('SP-19c código postal fuera del catálogo', 'RECHAZADO',
  $q$CALL sp_registrar_organizacion(1,'NLSSA900012','X','clinica',NULL,'C','1',NULL,'99999','Y',NULL,NULL,NULL,NULL)$q$);
SELECT pg_temp.probar('SP-19d clave con formato inválido', 'RECHAZADO',
  $q$CALL sp_registrar_organizacion(1,'ABC1','X','clinica',NULL,'C','1',NULL,'64000','Y',NULL,NULL,NULL,NULL)$q$);

-- SP-20 sp_cambiar_estado_organizacion
SELECT pg_temp.probar('SP-20a suspender institución 6', 'OK',
  $q$CALL sp_cambiar_estado_organizacion(1,6,'suspendida','Credencial comprometida')$q$);
SELECT pg_temp.probar('SP-20b reactivar institución 6', 'OK',
  $q$CALL sp_cambiar_estado_organizacion(1,6,'activa','Regularizó su credencial')$q$);
SELECT pg_temp.probar('SP-20c inactiva no cambia', 'RECHAZADO',
  $q$CALL sp_cambiar_estado_organizacion(1,10,'activa',NULL)$q$);
SELECT pg_temp.probar('SP-20d inactivar con consultas planeadas', 'RECHAZADO',
  $q$CALL sp_cambiar_estado_organizacion(1,1,'inactiva','Cierre del hospital')$q$);

-- SP-21 sp_cambiar_estado_usuario
SELECT pg_temp.probar('SP-21a reactivar coordinador 2', 'OK',
  $q$CALL sp_cambiar_estado_usuario(1,4,TRUE)$q$);
SELECT pg_temp.probar('SP-21b autodesactivarse', 'RECHAZADO',
  $q$CALL sp_cambiar_estado_usuario(1,1,FALSE)$q$);

\o
-- Verificación de efectos dentro de la transacción
SELECT id_conflicto, estado, resolucion FROM conflicto_dato ORDER BY 1;
SELECT id_procedencia, sin_alergias_conocidas, vigente FROM alergia WHERE id_paciente_maestro = 3;
SELECT id_detalle, estado FROM detalle_transaccion WHERE id_detalle IN (903, 904);
SELECT c.descripcion, o.valor_numerico, o.valor_texto, o.interpretacion
  FROM observacion o JOIN catalogo_codigo c USING (id_codigo) WHERE o.id_encuentro = 46 ORDER BY o.id_observacion;
SELECT cs.id_credencial, cs.estado FROM credencial_sistema cs WHERE cs.id_sistema_origen = 6;

ROLLBACK;
