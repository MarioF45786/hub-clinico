-- ============================================================
-- 03_ajustes_segundo_avance.sql
-- Ajustes al modelo para la segunda entrega (Flask + PostgreSQL).
-- Ejecutar DESPUÉS de 02_hub_interoperabilidad_schema.sql y ANTES
-- de 04_datos_prueba.sql.
-- ============================================================

BEGIN;

-- [AJUSTE 1] Extensión pgcrypto: hashes bcrypt de contraseñas
-- (crypt + gen_salt('bf')). Cloud SQL for PostgreSQL la soporta.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [AJUSTE 2] Se elimina MongoDB del proyecto.
-- Razón técnica: el proyecto usará únicamente PostgreSQL. Las columnas que
-- guardaban referencias a documentos de MongoDB ya no tienen uso y la de
-- detalle_transaccion (NOT NULL) impedía registrar encuentros desde la app.
-- El contenido original de cada dato sigue guardado en procedencia_dato
-- (valor_original, codigo_original), y la integridad del envío en los hashes.
ALTER TABLE paquete_transaccion DROP COLUMN ref_documento_mongo;
ALTER TABLE paquete_transaccion DROP COLUMN ref_respuesta_mongo;
ALTER TABLE detalle_transaccion DROP COLUMN ref_original_mongo;
ALTER TABLE detalle_transaccion DROP COLUMN ref_transformado_mongo;

COMMIT;
