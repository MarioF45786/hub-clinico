-- ============================================================
-- PostgreSQL 16 - Hub de interoperabilidad clínica (HL7 FHIR)
-- Bases de Datos Avanzadas (SC3303) · Equipo 05
-- Modelo relacional en 3FN: 34 tablas en 8 dominios
-- ============================================================
-- CONSTRAINT: regla que protege la integridad de los datos.
-- Nomenclatura: pk_=PRIMARY KEY, fk_=FOREIGN KEY, uq_=UNIQUE,
-- chk_=CHECK, idx_=índice, v_=vista.
-- REFERENCES indica la tabla/columna que valida una FOREIGN KEY.
--
-- Política de llaves foráneas:
-- ON UPDATE CASCADE en todas: si cambia una llave (por ejemplo,
--   un código postal) se propaga a quien la usa.
-- ON DELETE RESTRICT por defecto: nada con valor clínico, legal o
--   probatorio (pacientes, datos clínicos, procedencia, transacciones,
--   consentimientos, auditoría) se borra en cascada. Los pacientes
--   duplicados se fusionan, no se borran.
-- ON DELETE CASCADE solo en detalles que no existen sin su padre:
--   contactos de una institución, especialidades de un profesional,
--   alcances de un consentimiento y errores de un recurso.
--
-- Llaves: BIGINT GENERATED ALWAYS AS IDENTITY en todas las tablas,
-- salvo codigo_postal, cuya llave natural es el propio código.
-- UNIQUE representa una regla de negocio de unicidad o una llave
-- candidata. Las columnas UNIQUE que admiten nulo (curp,
-- cedula_especialidad, usuario.id_profesional) son llaves alternas.
--
-- Datos que NO se guardan porque romperían la 3FN y se calculan en
-- vistas: el puntaje de coincidencia (v_candidato_duplicado) y el
-- paciente y tipo de dato de un conflicto (v_conflicto_detalle).
--
-- Los procedimientos almacenados, triggers y vistas de reportes van
-- en un script aparte; este archivo crea solo la estructura.
-- ============================================================

BEGIN;


-- ------------------------------------------------------------
-- INSTITUCIONES
-- ------------------------------------------------------------

-- 1. CODIGO_POSTAL: Catálogo de códigos postales (SEPOMEX). El código postal determina el municipio y el estado; por eso viven aquí y no en cada dirección.
CREATE TABLE codigo_postal (
 codigo_postal CHAR(5) NOT NULL,
 municipio VARCHAR(100) NOT NULL,
 entidad_federativa VARCHAR(50) NOT NULL,
 CONSTRAINT pk_codigo_postal PRIMARY KEY (codigo_postal),
 CONSTRAINT chk_codigo_postal_formato CHECK (codigo_postal ~ '^[0-9]{5}$')
);

-- 2. ORGANIZACION: Hospital, clínica o laboratorio que aporta o consulta información.
CREATE TABLE organizacion (
 id_organizacion BIGINT GENERATED ALWAYS AS IDENTITY,
 clave_organizacion VARCHAR(20) NOT NULL,
 nombre VARCHAR(150) NOT NULL,
 tipo_organizacion VARCHAR(20) NOT NULL,
 telefono VARCHAR(20),
 calle VARCHAR(150) NOT NULL,
 numero_exterior VARCHAR(10) NOT NULL,
 colonia VARCHAR(100),
 codigo_postal CHAR(5) NOT NULL,
 estado VARCHAR(15) NOT NULL DEFAULT 'activa',
 fecha_registro TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT pk_organizacion PRIMARY KEY (id_organizacion),
 CONSTRAINT uq_organizacion_clave_organizacion UNIQUE (clave_organizacion),
 CONSTRAINT fk_organizacion_codigo_postal FOREIGN KEY (codigo_postal)
  REFERENCES codigo_postal(codigo_postal) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_organizacion_tipo_organizacion CHECK (tipo_organizacion IN ('hospital','clinica','laboratorio')),
 CONSTRAINT chk_organizacion_estado CHECK (estado IN ('activa','suspendida','inactiva'))
);

-- 3. CONTACTO_ORGANIZACION: Personas de contacto de cada institución; el puesto y los datos de contacto dependen de la persona, no de la institución.
CREATE TABLE contacto_organizacion (
 id_contacto_organizacion BIGINT GENERATED ALWAYS AS IDENTITY,
 id_organizacion BIGINT NOT NULL,
 nombre VARCHAR(150) NOT NULL,
 puesto VARCHAR(100),
 telefono VARCHAR(20),
 correo VARCHAR(150),
 es_principal BOOLEAN NOT NULL DEFAULT FALSE,
 CONSTRAINT pk_contacto_organizacion PRIMARY KEY (id_contacto_organizacion),
 CONSTRAINT fk_contacto_organizacion_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 4. SISTEMA_ORIGEN: Sistema informático de una institución (expediente, laboratorio, portal). La procedencia se registra a este nivel.
CREATE TABLE sistema_origen (
 id_sistema_origen BIGINT GENERATED ALWAYS AS IDENTITY,
 id_organizacion BIGINT NOT NULL,
 nombre_sistema VARCHAR(100) NOT NULL,
 tipo_sistema VARCHAR(25) NOT NULL,
 version_sistema VARCHAR(30),
 uri_identificador VARCHAR(200) NOT NULL,
 estado VARCHAR(10) NOT NULL DEFAULT 'activo',
 CONSTRAINT pk_sistema_origen PRIMARY KEY (id_sistema_origen),
 CONSTRAINT uq_sistema_origen_uri_identificador UNIQUE (uri_identificador),
 CONSTRAINT fk_sistema_origen_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_sistema_origen_tipo_sistema CHECK (tipo_sistema IN ('expediente_clinico','laboratorio','hospitalario','portal_hub')),
 CONSTRAINT chk_sistema_origen_estado CHECK (estado IN ('activo','inactivo')),
 CONSTRAINT uq_sistema_origen_nombre UNIQUE (id_organizacion, nombre_sistema)
);

-- ------------------------------------------------------------
-- PROFESIONALES
-- ------------------------------------------------------------

-- 5. PROFESIONAL_SALUD: Médico o profesional de salud, una sola vez aunque trabaje en varias instituciones.
CREATE TABLE profesional_salud (
 id_profesional BIGINT GENERATED ALWAYS AS IDENTITY,
 cedula_profesional VARCHAR(20) NOT NULL,
 nombre VARCHAR(100) NOT NULL,
 apellido_paterno VARCHAR(100) NOT NULL,
 apellido_materno VARCHAR(100),
 activo BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT pk_profesional_salud PRIMARY KEY (id_profesional),
 CONSTRAINT uq_profesional_salud_cedula_profesional UNIQUE (cedula_profesional)
);

-- 6. PROFESIONAL_ORGANIZACION: Rol y especialidad que un profesional ejerce en cada institución, con vigencia.
CREATE TABLE profesional_organizacion (
 id_profesional_organizacion BIGINT GENERATED ALWAYS AS IDENTITY,
 id_profesional BIGINT NOT NULL,
 id_organizacion BIGINT NOT NULL,
 rol VARCHAR(30) NOT NULL,
 fecha_inicio DATE NOT NULL,
 fecha_fin DATE,
 CONSTRAINT pk_profesional_organizacion PRIMARY KEY (id_profesional_organizacion),
 CONSTRAINT fk_profesional_organizacion_profesional FOREIGN KEY (id_profesional)
  REFERENCES profesional_salud(id_profesional) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_profesional_organizacion_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_profesional_organizacion_rol CHECK (rol IN ('medico_tratante','medico_guardia','jefe_servicio','quimico_laboratorista')),
 CONSTRAINT uq_profesional_organizacion_vinculo UNIQUE (id_profesional, id_organizacion, rol, fecha_inicio),
 CONSTRAINT chk_profesional_organizacion_fechas CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio)
);

-- 7. PROFESIONAL_ESPECIALIDAD: Especialidades del profesional. Pertenecen a la persona (cada una con su cédula de especialidad), no a la institución donde trabaja.
CREATE TABLE profesional_especialidad (
 id_profesional_especialidad BIGINT GENERATED ALWAYS AS IDENTITY,
 id_profesional BIGINT NOT NULL,
 especialidad VARCHAR(100) NOT NULL,
 cedula_especialidad VARCHAR(20),
 CONSTRAINT pk_profesional_especialidad PRIMARY KEY (id_profesional_especialidad),
 CONSTRAINT uq_profesional_especialidad_cedula_especialidad UNIQUE (cedula_especialidad),
 CONSTRAINT fk_profesional_especialidad_profesional FOREIGN KEY (id_profesional)
  REFERENCES profesional_salud(id_profesional) ON UPDATE CASCADE ON DELETE CASCADE,
 CONSTRAINT uq_profesional_especialidad UNIQUE (id_profesional, especialidad)
);

-- ------------------------------------------------------------
-- SEGURIDAD Y AUDITORÍA
-- ------------------------------------------------------------

-- 8. USUARIO: Persona que entra a la plataforma web, con un rol.
CREATE TABLE usuario (
 id_usuario BIGINT GENERATED ALWAYS AS IDENTITY,
 id_profesional BIGINT,
 nombre VARCHAR(100),
 apellido_paterno VARCHAR(100),
 apellido_materno VARCHAR(100),
 correo VARCHAR(150) NOT NULL,
 hash_contrasena CHAR(60) NOT NULL,
 rol VARCHAR(25) NOT NULL,
 activo BOOLEAN NOT NULL DEFAULT TRUE,
 fecha_registro TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT pk_usuario PRIMARY KEY (id_usuario),
 CONSTRAINT uq_usuario_profesional UNIQUE (id_profesional),
 CONSTRAINT uq_usuario_correo UNIQUE (correo),
 CONSTRAINT fk_usuario_profesional FOREIGN KEY (id_profesional)
  REFERENCES profesional_salud(id_profesional) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_usuario_rol CHECK (rol IN ('administrador','analista_integracion','coordinador','medico')),
 CONSTRAINT chk_usuario_medico_profesional CHECK ((rol = 'medico') = (id_profesional IS NOT NULL)),
 CONSTRAINT chk_usuario_nombre_segun_tipo CHECK ((id_profesional IS NULL) = (nombre IS NOT NULL AND apellido_paterno IS NOT NULL)),
 CONSTRAINT chk_usuario_medico_sin_apellido CHECK (id_profesional IS NULL OR apellido_materno IS NULL)
);

-- ------------------------------------------------------------
-- INSTITUCIONES
-- ------------------------------------------------------------

-- 9. CREDENCIAL_SISTEMA: Clave con la que un sistema de origen se autentica para enviar o consultar.
CREATE TABLE credencial_sistema (
 id_credencial BIGINT GENERATED ALWAYS AS IDENTITY,
 id_sistema_origen BIGINT NOT NULL,
 id_usuario_emision BIGINT NOT NULL,
 hash_clave CHAR(60) NOT NULL,
 fecha_emision DATE NOT NULL DEFAULT CURRENT_DATE,
 fecha_expiracion DATE NOT NULL,
 estado VARCHAR(10) NOT NULL DEFAULT 'activa',
 CONSTRAINT pk_credencial_sistema PRIMARY KEY (id_credencial),
 CONSTRAINT fk_credencial_sistema_sistema_origen FOREIGN KEY (id_sistema_origen)
  REFERENCES sistema_origen(id_sistema_origen) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_credencial_sistema_usuario_emision FOREIGN KEY (id_usuario_emision)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_credencial_sistema_estado CHECK (estado IN ('activa','revocada','expirada')),
 CONSTRAINT chk_credencial_vigencia CHECK (fecha_expiracion > fecha_emision)
);

-- ------------------------------------------------------------
-- IDENTIDAD DEL PACIENTE
-- ------------------------------------------------------------

-- 10. PACIENTE_MAESTRO: Representación consolidada de una persona, independiente de cuántas instituciones la conozcan.
CREATE TABLE paciente_maestro (
 id_paciente_maestro BIGINT GENERATED ALWAYS AS IDENTITY,
 curp VARCHAR(18),
 nombre VARCHAR(100) NOT NULL,
 apellido_paterno VARCHAR(100) NOT NULL,
 apellido_materno VARCHAR(100),
 fecha_nacimiento DATE NOT NULL,
 sexo VARCHAR(12) NOT NULL,
 estado VARCHAR(10) NOT NULL DEFAULT 'activo',
 id_paciente_fusionado_en BIGINT,
 fecha_registro TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT pk_paciente_maestro PRIMARY KEY (id_paciente_maestro),
 CONSTRAINT uq_paciente_maestro_curp UNIQUE (curp),
 CONSTRAINT fk_paciente_maestro_paciente_fusionado_en FOREIGN KEY (id_paciente_fusionado_en)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_paciente_maestro_sexo CHECK (sexo IN ('masculino','femenino','otro','desconocido')),
 CONSTRAINT chk_paciente_maestro_estado CHECK (estado IN ('activo','fusionado','inactivo')),
 CONSTRAINT chk_paciente_fecha_nacimiento CHECK (fecha_nacimiento <= CURRENT_DATE),
 CONSTRAINT chk_paciente_fusion CHECK ((estado = 'fusionado') = (id_paciente_fusionado_en IS NOT NULL)),
 CONSTRAINT chk_paciente_fusion_no_propia CHECK (id_paciente_fusionado_en IS NULL OR id_paciente_fusionado_en <> id_paciente_maestro)
);

-- 11. IDENTIFICADOR_PACIENTE: Cada identificador que una institución asigna al paciente; N por paciente maestro.
CREATE TABLE identificador_paciente (
 id_identificador BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_sistema_origen BIGINT NOT NULL,
 valor_identificador VARCHAR(64) NOT NULL,
 tipo_identificador VARCHAR(15) NOT NULL,
 uso VARCHAR(10) NOT NULL,
 fecha_alta TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT pk_identificador_paciente PRIMARY KEY (id_identificador),
 CONSTRAINT fk_identificador_paciente_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_identificador_paciente_sistema_origen FOREIGN KEY (id_sistema_origen)
  REFERENCES sistema_origen(id_sistema_origen) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_identificador_paciente_tipo_identificador CHECK (tipo_identificador IN ('expediente','laboratorio','nss','otro')),
 CONSTRAINT chk_identificador_paciente_uso CHECK (uso IN ('oficial','secundario','antiguo')),
 CONSTRAINT uq_identificador_sistema_valor UNIQUE (id_sistema_origen, valor_identificador)
);

-- ------------------------------------------------------------
-- TRANSACCIONES DE INTEROPERABILIDAD
-- ------------------------------------------------------------

-- 12. PAQUETE_TRANSACCION: Envío completo que entra o sale del hub (bundle FHIR o captura desde el portal).
CREATE TABLE paquete_transaccion (
 id_paquete BIGINT GENERATED ALWAYS AS IDENTITY,
 id_sistema_origen BIGINT NOT NULL,
 id_usuario_captura BIGINT,
 direccion VARCHAR(10) NOT NULL,
 tipo_paquete VARCHAR(20) NOT NULL,
 fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 estado VARCHAR(25) NOT NULL,
 hash_paquete CHAR(64) NOT NULL,
 ref_documento_mongo VARCHAR(24),
 ref_respuesta_mongo VARCHAR(24),
 CONSTRAINT pk_paquete_transaccion PRIMARY KEY (id_paquete),
 CONSTRAINT uq_paquete_transaccion_hash_paquete UNIQUE (hash_paquete),
 CONSTRAINT fk_paquete_transaccion_sistema_origen FOREIGN KEY (id_sistema_origen)
  REFERENCES sistema_origen(id_sistema_origen) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_paquete_transaccion_usuario_captura FOREIGN KEY (id_usuario_captura)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_paquete_transaccion_direccion CHECK (direccion IN ('entrante','saliente')),
 CONSTRAINT chk_paquete_transaccion_tipo_paquete CHECK (tipo_paquete IN ('mensaje','transaccion','consulta','captura_portal')),
 CONSTRAINT chk_paquete_transaccion_estado CHECK (estado IN ('recibido','procesando','procesado','procesado_con_errores','rechazado','enviado')),
 CONSTRAINT chk_paquete_captura_usuario CHECK ((tipo_paquete = 'captura_portal') = (id_usuario_captura IS NOT NULL))
);

-- 13. DETALLE_TRANSACCION: Cada recurso dentro de un paquete y su estado de procesamiento.
CREATE TABLE detalle_transaccion (
 id_detalle BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paquete BIGINT NOT NULL,
 id_paciente_maestro BIGINT,
 tipo_recurso VARCHAR(25) NOT NULL,
 id_recurso_externo VARCHAR(64) NOT NULL,
 version_recurso VARCHAR(20),
 fecha_recurso_origen TIMESTAMPTZ,
 id_detalle_original BIGINT,
 estado VARCHAR(12) NOT NULL,
 hash_recurso CHAR(64) NOT NULL,
 ref_original_mongo VARCHAR(24) NOT NULL,
 ref_transformado_mongo VARCHAR(24),
 fecha_procesamiento TIMESTAMPTZ,
 CONSTRAINT pk_detalle_transaccion PRIMARY KEY (id_detalle),
 CONSTRAINT fk_detalle_transaccion_paquete FOREIGN KEY (id_paquete)
  REFERENCES paquete_transaccion(id_paquete) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_detalle_transaccion_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_detalle_transaccion_detalle_original FOREIGN KEY (id_detalle_original)
  REFERENCES detalle_transaccion(id_detalle) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_detalle_transaccion_tipo_recurso CHECK (tipo_recurso IN ('Patient','Practitioner','Organization','Encounter','Condition','Observation','DiagnosticReport','MedicationRequest','AllergyIntolerance')),
 CONSTRAINT chk_detalle_transaccion_estado CHECK (estado IN ('recibido','validado','integrado','rechazado','duplicado','enviado')),
 CONSTRAINT chk_detalle_duplicado_original CHECK ((estado = 'duplicado') = (id_detalle_original IS NOT NULL)),
 CONSTRAINT chk_detalle_original_no_propio CHECK (id_detalle_original IS NULL OR id_detalle_original <> id_detalle)
);

-- 14. ERROR_VALIDACION: Error o advertencia detectado al validar un recurso.
CREATE TABLE error_validacion (
 id_error BIGINT GENERATED ALWAYS AS IDENTITY,
 id_detalle BIGINT NOT NULL,
 codigo_error VARCHAR(25) NOT NULL,
 severidad VARCHAR(12) NOT NULL,
 ruta_elemento VARCHAR(150),
 descripcion TEXT NOT NULL,
 CONSTRAINT pk_error_validacion PRIMARY KEY (id_error),
 CONSTRAINT fk_error_validacion_detalle FOREIGN KEY (id_detalle)
  REFERENCES detalle_transaccion(id_detalle) ON UPDATE CASCADE ON DELETE CASCADE,
 CONSTRAINT chk_error_validacion_codigo_error CHECK (codigo_error IN ('requerido','formato','codigo_desconocido','referencia_invalida','duplicado','sin_consentimiento','estructura')),
 CONSTRAINT chk_error_validacion_severidad CHECK (severidad IN ('fatal','error','advertencia','informativo'))
);

-- ------------------------------------------------------------
-- PROCEDENCIA Y CONFLICTOS
-- ------------------------------------------------------------

-- 15. PROCEDENCIA_DATO: De qué recurso recibido salió cada dato clínico, cuándo ocurrió en el origen y cuál era su valor original.
CREATE TABLE procedencia_dato (
 id_procedencia BIGINT GENERATED ALWAYS AS IDENTITY,
 id_detalle BIGINT NOT NULL,
 ruta_elemento VARCHAR(150),
 valor_original TEXT NOT NULL,
 codigo_original VARCHAR(40),
 fecha_origen TIMESTAMPTZ,
 fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT pk_procedencia_dato PRIMARY KEY (id_procedencia),
 CONSTRAINT fk_procedencia_dato_detalle FOREIGN KEY (id_detalle)
  REFERENCES detalle_transaccion(id_detalle) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- IDENTIDAD DEL PACIENTE
-- ------------------------------------------------------------

-- 16. NOMBRE_PACIENTE: Cada forma en que una institución registró el nombre del paciente (Patient.name). El paciente maestro guarda solo el nombre consolidado.
CREATE TABLE nombre_paciente (
 id_nombre BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 nombre VARCHAR(100) NOT NULL,
 apellido_paterno VARCHAR(100) NOT NULL,
 apellido_materno VARCHAR(100),
 uso VARCHAR(10) NOT NULL,
 vigente BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT pk_nombre_paciente PRIMARY KEY (id_nombre),
 CONSTRAINT uq_nombre_paciente_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_nombre_paciente_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_nombre_paciente_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_nombre_paciente_uso CHECK (uso IN ('oficial','usual','alias','anterior'))
);

-- 17. CONTACTO_PACIENTE: Teléfono o correo del paciente según lo reporta cada institución.
CREATE TABLE contacto_paciente (
 id_contacto BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 tipo_contacto VARCHAR(10) NOT NULL,
 valor VARCHAR(150) NOT NULL,
 uso VARCHAR(10) NOT NULL,
 vigente BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT pk_contacto_paciente PRIMARY KEY (id_contacto),
 CONSTRAINT uq_contacto_paciente_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_contacto_paciente_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_contacto_paciente_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_contacto_paciente_tipo_contacto CHECK (tipo_contacto IN ('telefono','correo')),
 CONSTRAINT chk_contacto_paciente_uso CHECK (uso IN ('casa','movil','trabajo'))
);

-- 18. DIRECCION_PACIENTE: Domicilio del paciente según lo reporta cada institución.
CREATE TABLE direccion_paciente (
 id_direccion BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 calle VARCHAR(150) NOT NULL,
 numero_exterior VARCHAR(10) NOT NULL,
 numero_interior VARCHAR(10),
 colonia VARCHAR(100),
 codigo_postal CHAR(5) NOT NULL,
 uso VARCHAR(10) NOT NULL,
 vigente BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT pk_direccion_paciente PRIMARY KEY (id_direccion),
 CONSTRAINT uq_direccion_paciente_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_direccion_paciente_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_direccion_paciente_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_direccion_paciente_codigo_postal FOREIGN KEY (codigo_postal)
  REFERENCES codigo_postal(codigo_postal) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_direccion_paciente_uso CHECK (uso IN ('domicilio','trabajo'))
);

-- 19. CANDIDATO_DUPLICADO: Par de pacientes maestros que podrían ser la misma persona, con los criterios en que coinciden y la decisión del coordinador.
CREATE TABLE candidato_duplicado (
 id_candidato BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_a BIGINT NOT NULL,
 id_paciente_b BIGINT NOT NULL,
 coincide_identificador BOOLEAN NOT NULL DEFAULT FALSE,
 coincide_nombre_fecha BOOLEAN NOT NULL DEFAULT FALSE,
 coincide_telefono BOOLEAN NOT NULL DEFAULT FALSE,
 coincide_correo BOOLEAN NOT NULL DEFAULT FALSE,
 coincide_direccion BOOLEAN NOT NULL DEFAULT FALSE,
 fecha_deteccion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 estado VARCHAR(10) NOT NULL DEFAULT 'pendiente',
 id_usuario_resolucion BIGINT,
 fecha_resolucion TIMESTAMPTZ,
 justificacion TEXT,
 CONSTRAINT pk_candidato_duplicado PRIMARY KEY (id_candidato),
 CONSTRAINT fk_candidato_duplicado_paciente_a FOREIGN KEY (id_paciente_a)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_candidato_duplicado_paciente_b FOREIGN KEY (id_paciente_b)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_candidato_duplicado_usuario_resolucion FOREIGN KEY (id_usuario_resolucion)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_candidato_duplicado_estado CHECK (estado IN ('pendiente','fusionado','descartado')),
 CONSTRAINT chk_candidato_par_ordenado CHECK (id_paciente_a < id_paciente_b),
 CONSTRAINT uq_candidato_par UNIQUE (id_paciente_a, id_paciente_b),
 CONSTRAINT chk_candidato_puntaje_revision CHECK ((CASE WHEN coincide_identificador THEN 100 ELSE 0 END + CASE WHEN coincide_nombre_fecha THEN 70 ELSE 0 END + CASE WHEN coincide_telefono THEN 20 ELSE 0 END + CASE WHEN coincide_correo THEN 20 ELSE 0 END + CASE WHEN coincide_direccion THEN 10 ELSE 0 END) BETWEEN 70 AND 99),
 CONSTRAINT chk_candidato_resolucion CHECK ((estado = 'pendiente') = (id_usuario_resolucion IS NULL))
);

-- ------------------------------------------------------------
-- INFORMACIÓN CLÍNICA
-- ------------------------------------------------------------

-- 20. CATALOGO_CODIGO: Códigos estándar: CIE-10 (diagnósticos), LOINC (estudios y observaciones), cuadro básico (medicamentos), sustancias.
CREATE TABLE catalogo_codigo (
 id_codigo BIGINT GENERATED ALWAYS AS IDENTITY,
 sistema_codificacion VARCHAR(15) NOT NULL,
 codigo VARCHAR(20) NOT NULL,
 descripcion VARCHAR(250) NOT NULL,
 categoria VARCHAR(15),
 unidad_sugerida VARCHAR(20),
 activo BOOLEAN NOT NULL DEFAULT TRUE,
 CONSTRAINT pk_catalogo_codigo PRIMARY KEY (id_codigo),
 CONSTRAINT chk_catalogo_codigo_sistema_codificacion CHECK (sistema_codificacion IN ('CIE-10','LOINC','CUADRO_BASICO','SUSTANCIA')),
 CONSTRAINT chk_catalogo_codigo_categoria CHECK (categoria IN ('signo_vital','laboratorio','medicamento','alimento','ambiental')),
 CONSTRAINT uq_catalogo_sistema_codigo UNIQUE (sistema_codificacion, codigo)
);

-- 21. MAPEO_CODIGO: Traducción de un código local de un sistema al código estándar.
CREATE TABLE mapeo_codigo (
 id_mapeo BIGINT GENERATED ALWAYS AS IDENTITY,
 id_sistema_origen BIGINT NOT NULL,
 codigo_local VARCHAR(40) NOT NULL,
 descripcion_local VARCHAR(250),
 id_codigo BIGINT NOT NULL,
 CONSTRAINT pk_mapeo_codigo PRIMARY KEY (id_mapeo),
 CONSTRAINT fk_mapeo_codigo_sistema_origen FOREIGN KEY (id_sistema_origen)
  REFERENCES sistema_origen(id_sistema_origen) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_mapeo_codigo_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT uq_mapeo_sistema_codigo_local UNIQUE (id_sistema_origen, codigo_local)
);

-- 22. ENCUENTRO_CLINICO: Consulta, urgencia, hospitalización o toma de muestra; agrupa los datos clínicos de una atención.
CREATE TABLE encuentro_clinico (
 id_encuentro BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_organizacion BIGINT NOT NULL,
 id_profesional BIGINT,
 id_procedencia BIGINT NOT NULL,
 tipo_encuentro VARCHAR(20) NOT NULL,
 motivo VARCHAR(250),
 fecha_inicio TIMESTAMPTZ NOT NULL,
 fecha_fin TIMESTAMPTZ,
 estado VARCHAR(12) NOT NULL,
 CONSTRAINT pk_encuentro_clinico PRIMARY KEY (id_encuentro),
 CONSTRAINT uq_encuentro_clinico_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_encuentro_clinico_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_encuentro_clinico_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_encuentro_clinico_profesional FOREIGN KEY (id_profesional)
  REFERENCES profesional_salud(id_profesional) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_encuentro_clinico_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_encuentro_clinico_tipo_encuentro CHECK (tipo_encuentro IN ('consulta_externa','urgencias','hospitalizacion','toma_muestra')),
 CONSTRAINT chk_encuentro_clinico_estado CHECK (estado IN ('planeado','en_curso','finalizado','cancelado')),
 CONSTRAINT chk_encuentro_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

-- 23. DIAGNOSTICO: Condición del paciente registrada en un encuentro, codificada con CIE-10.
CREATE TABLE diagnostico (
 id_diagnostico BIGINT GENERATED ALWAYS AS IDENTITY,
 id_encuentro BIGINT NOT NULL,
 id_codigo BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 tipo VARCHAR(10) NOT NULL,
 estado_clinico VARCHAR(10) NOT NULL,
 fecha_diagnostico DATE NOT NULL,
 CONSTRAINT pk_diagnostico PRIMARY KEY (id_diagnostico),
 CONSTRAINT uq_diagnostico_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_diagnostico_encuentro FOREIGN KEY (id_encuentro)
  REFERENCES encuentro_clinico(id_encuentro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_diagnostico_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_diagnostico_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_diagnostico_tipo CHECK (tipo IN ('principal','secundario')),
 CONSTRAINT chk_diagnostico_estado_clinico CHECK (estado_clinico IN ('activo','resuelto','descartado'))
);

-- 24. ESTUDIO_DIAGNOSTICO: Reporte de un estudio (por ejemplo, química sanguínea) que agrupa varios resultados.
CREATE TABLE estudio_diagnostico (
 id_estudio BIGINT GENERATED ALWAYS AS IDENTITY,
 id_encuentro BIGINT NOT NULL,
 id_codigo BIGINT NOT NULL,
 id_profesional_responsable BIGINT,
 id_procedencia BIGINT NOT NULL,
 fecha_emision TIMESTAMPTZ NOT NULL,
 estado VARCHAR(12) NOT NULL,
 conclusion TEXT,
 CONSTRAINT pk_estudio_diagnostico PRIMARY KEY (id_estudio),
 CONSTRAINT uq_estudio_diagnostico_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_estudio_diagnostico_encuentro FOREIGN KEY (id_encuentro)
  REFERENCES encuentro_clinico(id_encuentro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_estudio_diagnostico_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_estudio_diagnostico_profesional_responsable FOREIGN KEY (id_profesional_responsable)
  REFERENCES profesional_salud(id_profesional) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_estudio_diagnostico_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_estudio_diagnostico_estado CHECK (estado IN ('preliminar','final','corregido','cancelado'))
);

-- 25. OBSERVACION: Signo vital o resultado de laboratorio con valor, unidad y rango de referencia, codificado con LOINC.
CREATE TABLE observacion (
 id_observacion BIGINT GENERATED ALWAYS AS IDENTITY,
 id_encuentro BIGINT,
 id_estudio BIGINT,
 id_codigo BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 valor_numerico NUMERIC(12,4),
 valor_texto VARCHAR(100),
 unidad VARCHAR(20),
 rango_ref_min NUMERIC(12,4),
 rango_ref_max NUMERIC(12,4),
 interpretacion VARCHAR(10),
 fecha_observacion TIMESTAMPTZ NOT NULL,
 CONSTRAINT pk_observacion PRIMARY KEY (id_observacion),
 CONSTRAINT uq_observacion_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_observacion_encuentro FOREIGN KEY (id_encuentro)
  REFERENCES encuentro_clinico(id_encuentro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_observacion_estudio FOREIGN KEY (id_estudio)
  REFERENCES estudio_diagnostico(id_estudio) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_observacion_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_observacion_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_observacion_interpretacion CHECK (interpretacion IN ('normal','alto','bajo','critico')),
 CONSTRAINT chk_observacion_valor CHECK (valor_numerico IS NOT NULL OR valor_texto IS NOT NULL),
 CONSTRAINT chk_observacion_estudio_o_encuentro CHECK ((id_encuentro IS NULL) <> (id_estudio IS NULL))
);

-- 26. SOLICITUD_MEDICAMENTO: Medicamento indicado en un encuentro, con dosis y vigencia.
CREATE TABLE solicitud_medicamento (
 id_solicitud BIGINT GENERATED ALWAYS AS IDENTITY,
 id_encuentro BIGINT NOT NULL,
 id_codigo BIGINT NOT NULL,
 id_procedencia BIGINT NOT NULL,
 dosis VARCHAR(50) NOT NULL,
 via VARCHAR(15) NOT NULL,
 frecuencia VARCHAR(50) NOT NULL,
 duracion_dias SMALLINT,
 fecha_solicitud TIMESTAMPTZ NOT NULL,
 estado VARCHAR(12) NOT NULL,
 CONSTRAINT pk_solicitud_medicamento PRIMARY KEY (id_solicitud),
 CONSTRAINT uq_solicitud_medicamento_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_solicitud_medicamento_encuentro FOREIGN KEY (id_encuentro)
  REFERENCES encuentro_clinico(id_encuentro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_solicitud_medicamento_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_solicitud_medicamento_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_solicitud_medicamento_via CHECK (via IN ('oral','intravenosa','intramuscular','subcutanea','topica','inhalada')),
 CONSTRAINT chk_solicitud_medicamento_estado CHECK (estado IN ('activa','completada','suspendida','cancelada')),
 CONSTRAINT chk_solicitud_duracion CHECK (duracion_dias IS NULL OR duracion_dias > 0)
);

-- 27. ALERGIA: Alergia o ausencia declarada de alergias. Pertenece al paciente, no a un encuentro.
CREATE TABLE alergia (
 id_alergia BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_codigo BIGINT,
 id_procedencia BIGINT NOT NULL,
 sin_alergias_conocidas BOOLEAN NOT NULL DEFAULT FALSE,
 reaccion VARCHAR(150),
 criticidad VARCHAR(15),
 estado_verificacion VARCHAR(15) NOT NULL,
 vigente BOOLEAN NOT NULL DEFAULT TRUE,
 fecha_registro DATE NOT NULL,
 CONSTRAINT pk_alergia PRIMARY KEY (id_alergia),
 CONSTRAINT uq_alergia_procedencia UNIQUE (id_procedencia),
 CONSTRAINT fk_alergia_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_alergia_codigo FOREIGN KEY (id_codigo)
  REFERENCES catalogo_codigo(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_alergia_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_alergia_criticidad CHECK (criticidad IN ('baja','alta','indeterminada')),
 CONSTRAINT chk_alergia_estado_verificacion CHECK (estado_verificacion IN ('confirmada','no_confirmada','refutada')),
 CONSTRAINT chk_alergia_sustancia CHECK (sin_alergias_conocidas = (id_codigo IS NULL)),
 CONSTRAINT chk_alergia_sin_alergias CHECK (NOT sin_alergias_conocidas OR (reaccion IS NULL AND criticidad IS NULL))
);

-- ------------------------------------------------------------
-- PROCEDENCIA Y CONFLICTOS
-- ------------------------------------------------------------

-- 28. VERSION_DATO: Historial de cambios de un dato clínico; el dato se identifica por su procedencia.
CREATE TABLE version_dato (
 id_version BIGINT GENERATED ALWAYS AS IDENTITY,
 id_procedencia BIGINT NOT NULL,
 campo VARCHAR(50) NOT NULL,
 numero_version SMALLINT NOT NULL,
 valor_anterior TEXT,
 valor_nuevo TEXT,
 id_usuario BIGINT,
 id_detalle_correccion BIGINT,
 fecha_cambio TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 motivo VARCHAR(200),
 CONSTRAINT pk_version_dato PRIMARY KEY (id_version),
 CONSTRAINT fk_version_dato_procedencia FOREIGN KEY (id_procedencia)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_version_dato_usuario FOREIGN KEY (id_usuario)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_version_dato_detalle_correccion FOREIGN KEY (id_detalle_correccion)
  REFERENCES detalle_transaccion(id_detalle) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT uq_version_dato UNIQUE (id_procedencia, campo, numero_version),
 CONSTRAINT chk_version_numero CHECK (numero_version > 0),
 CONSTRAINT chk_version_origen_cambio CHECK (id_usuario IS NOT NULL OR id_detalle_correccion IS NOT NULL)
);

-- 29. REGLA_AUTORIDAD: Criterio sugerido para resolver conflictos según el tipo de dato y, opcionalmente, la institución con autoridad.
CREATE TABLE regla_autoridad (
 id_regla BIGINT GENERATED ALWAYS AS IDENTITY,
 tipo_dato VARCHAR(15) NOT NULL,
 id_organizacion BIGINT,
 criterio VARCHAR(25) NOT NULL,
 prioridad SMALLINT NOT NULL,
 activa BOOLEAN NOT NULL DEFAULT TRUE,
 descripcion VARCHAR(250),
 CONSTRAINT pk_regla_autoridad PRIMARY KEY (id_regla),
 CONSTRAINT fk_regla_autoridad_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_regla_autoridad_tipo_dato CHECK (tipo_dato IN ('alergia','diagnostico','observacion','medicamento','contacto','direccion','demografico')),
 CONSTRAINT chk_regla_autoridad_criterio CHECK (criterio IN ('mas_reciente','autoridad_institucion','conservar_ambos','revision_manual'))
);

-- 30. CONFLICTO_DATO: Dos valores contradictorios del mismo dato de un paciente, reportados por fuentes distintas, y su resolución.
CREATE TABLE conflicto_dato (
 id_conflicto BIGINT GENERATED ALWAYS AS IDENTITY,
 id_procedencia_a BIGINT NOT NULL,
 id_procedencia_b BIGINT NOT NULL,
 campo VARCHAR(50) NOT NULL,
 id_regla_sugerida BIGINT,
 fecha_deteccion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 estado VARCHAR(10) NOT NULL DEFAULT 'pendiente',
 resolucion VARCHAR(15),
 justificacion TEXT,
 id_usuario_resolucion BIGINT,
 fecha_resolucion TIMESTAMPTZ,
 CONSTRAINT pk_conflicto_dato PRIMARY KEY (id_conflicto),
 CONSTRAINT fk_conflicto_dato_procedencia_a FOREIGN KEY (id_procedencia_a)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_conflicto_dato_procedencia_b FOREIGN KEY (id_procedencia_b)
  REFERENCES procedencia_dato(id_procedencia) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_conflicto_dato_regla_sugerida FOREIGN KEY (id_regla_sugerida)
  REFERENCES regla_autoridad(id_regla) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_conflicto_dato_usuario_resolucion FOREIGN KEY (id_usuario_resolucion)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_conflicto_dato_estado CHECK (estado IN ('pendiente','resuelto','descartado')),
 CONSTRAINT chk_conflicto_dato_resolucion CHECK (resolucion IN ('vigente_a','vigente_b','ambos_vigentes')),
 CONSTRAINT chk_conflicto_procedencias_distintas CHECK (id_procedencia_a <> id_procedencia_b),
 CONSTRAINT uq_conflicto_procedencias_campo UNIQUE (id_procedencia_a, id_procedencia_b, campo),
 CONSTRAINT chk_conflicto_resolucion CHECK ((estado = 'resuelto') = (resolucion IS NOT NULL)),
 CONSTRAINT chk_conflicto_responsable CHECK ((estado = 'pendiente') = (id_usuario_resolucion IS NULL))
);

-- ------------------------------------------------------------
-- CONSENTIMIENTO
-- ------------------------------------------------------------

-- 31. CATEGORIA_INFORMACION: Categorías de información que un paciente puede autorizar compartir.
CREATE TABLE categoria_informacion (
 id_categoria BIGINT GENERATED ALWAYS AS IDENTITY,
 clave VARCHAR(30) NOT NULL,
 nombre VARCHAR(100) NOT NULL,
 descripcion VARCHAR(250),
 CONSTRAINT pk_categoria_informacion PRIMARY KEY (id_categoria),
 CONSTRAINT uq_categoria_informacion_clave UNIQUE (clave)
);

-- 32. CONSENTIMIENTO: Autorización del paciente con vigencia y estado.
CREATE TABLE consentimiento (
 id_consentimiento BIGINT GENERATED ALWAYS AS IDENTITY,
 id_paciente_maestro BIGINT NOT NULL,
 id_usuario_registro BIGINT NOT NULL,
 fecha_otorgamiento DATE NOT NULL,
 fecha_inicio DATE NOT NULL,
 fecha_fin DATE NOT NULL,
 estado VARCHAR(10) NOT NULL DEFAULT 'activo',
 fecha_revocacion DATE,
 motivo_revocacion VARCHAR(250),
 ref_documento VARCHAR(200),
 CONSTRAINT pk_consentimiento PRIMARY KEY (id_consentimiento),
 CONSTRAINT fk_consentimiento_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_consentimiento_usuario_registro FOREIGN KEY (id_usuario_registro)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_consentimiento_estado CHECK (estado IN ('activo','revocado','vencido')),
 CONSTRAINT chk_consentimiento_vigencia CHECK (fecha_fin > fecha_inicio),
 CONSTRAINT chk_consentimiento_revocacion CHECK ((estado = 'revocado') = (fecha_revocacion IS NOT NULL))
);

-- 33. CONSENTIMIENTO_ALCANCE: Qué categoría de información cubre un consentimiento, con qué institución y para qué: enviarla al hub o consultarla.
CREATE TABLE consentimiento_alcance (
 id_alcance BIGINT GENERATED ALWAYS AS IDENTITY,
 id_consentimiento BIGINT NOT NULL,
 id_categoria BIGINT NOT NULL,
 id_organizacion BIGINT NOT NULL,
 permiso VARCHAR(10) NOT NULL,
 CONSTRAINT pk_consentimiento_alcance PRIMARY KEY (id_alcance),
 CONSTRAINT fk_consentimiento_alcance_consentimiento FOREIGN KEY (id_consentimiento)
  REFERENCES consentimiento(id_consentimiento) ON UPDATE CASCADE ON DELETE CASCADE,
 CONSTRAINT fk_consentimiento_alcance_categoria FOREIGN KEY (id_categoria)
  REFERENCES categoria_informacion(id_categoria) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_consentimiento_alcance_organizacion FOREIGN KEY (id_organizacion)
  REFERENCES organizacion(id_organizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_consentimiento_alcance_permiso CHECK (permiso IN ('enviar','consultar')),
 CONSTRAINT uq_consentimiento_alcance UNIQUE (id_consentimiento, id_categoria, id_organizacion, permiso)
);

-- ------------------------------------------------------------
-- SEGURIDAD Y AUDITORÍA
-- ------------------------------------------------------------

-- 34. AUDITORIA: Registro de solo inserción de quién consultó, modificó o resolvió algo.
CREATE TABLE auditoria (
 id_auditoria BIGINT GENERATED ALWAYS AS IDENTITY,
 fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 id_usuario BIGINT,
 id_sistema_origen BIGINT,
 rol_en_evento VARCHAR(25),
 accion VARCHAR(15) NOT NULL,
 tabla_afectada VARCHAR(50) NOT NULL,
 id_registro_afectado BIGINT NOT NULL,
 id_paciente_maestro BIGINT,
 resultado VARCHAR(10) NOT NULL,
 detalle TEXT,
 CONSTRAINT pk_auditoria PRIMARY KEY (id_auditoria),
 CONSTRAINT fk_auditoria_usuario FOREIGN KEY (id_usuario)
  REFERENCES usuario(id_usuario) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_auditoria_sistema_origen FOREIGN KEY (id_sistema_origen)
  REFERENCES sistema_origen(id_sistema_origen) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT fk_auditoria_paciente_maestro FOREIGN KEY (id_paciente_maestro)
  REFERENCES paciente_maestro(id_paciente_maestro) ON UPDATE CASCADE ON DELETE RESTRICT,
 CONSTRAINT chk_auditoria_accion CHECK (accion IN ('consultar','crear','actualizar','eliminar','fusionar','resolver','enviar','recibir')),
 CONSTRAINT chk_auditoria_resultado CHECK (resultado IN ('exito','denegado','error')),
 CONSTRAINT chk_auditoria_actor CHECK (id_usuario IS NOT NULL OR id_sistema_origen IS NOT NULL)
);

-- ------------------------------------------------------------
-- ÍNDICES
-- PostgreSQL crea índice automático para PRIMARY KEY y UNIQUE, pero
-- no para FOREIGN KEY: se indexan para acelerar los JOIN y para que
-- RESTRICT/CASCADE no recorran la tabla completa.
-- ------------------------------------------------------------
CREATE INDEX idx_organizacion_codigo_postal ON organizacion(codigo_postal);
CREATE INDEX idx_contacto_organizacion_organizacion ON contacto_organizacion(id_organizacion);
CREATE INDEX idx_sistema_origen_organizacion ON sistema_origen(id_organizacion);
CREATE INDEX idx_profesional_organizacion_profesional ON profesional_organizacion(id_profesional);
CREATE INDEX idx_profesional_organizacion_organizacion ON profesional_organizacion(id_organizacion);
CREATE INDEX idx_profesional_especialidad_profesional ON profesional_especialidad(id_profesional);
CREATE INDEX idx_credencial_sistema_sistema_origen ON credencial_sistema(id_sistema_origen);
CREATE INDEX idx_credencial_sistema_usuario_emision ON credencial_sistema(id_usuario_emision);
CREATE INDEX idx_paciente_maestro_paciente_fusionado_en ON paciente_maestro(id_paciente_fusionado_en);
CREATE INDEX idx_identificador_paciente_paciente_maestro ON identificador_paciente(id_paciente_maestro);
CREATE INDEX idx_identificador_paciente_sistema_origen ON identificador_paciente(id_sistema_origen);
CREATE INDEX idx_paquete_transaccion_sistema_origen ON paquete_transaccion(id_sistema_origen);
CREATE INDEX idx_paquete_transaccion_usuario_captura ON paquete_transaccion(id_usuario_captura);
CREATE INDEX idx_detalle_transaccion_paquete ON detalle_transaccion(id_paquete);
CREATE INDEX idx_detalle_transaccion_paciente_maestro ON detalle_transaccion(id_paciente_maestro);
CREATE INDEX idx_detalle_transaccion_detalle_original ON detalle_transaccion(id_detalle_original);
CREATE INDEX idx_error_validacion_detalle ON error_validacion(id_detalle);
CREATE INDEX idx_procedencia_dato_detalle ON procedencia_dato(id_detalle);
CREATE INDEX idx_nombre_paciente_paciente_maestro ON nombre_paciente(id_paciente_maestro);
CREATE INDEX idx_contacto_paciente_paciente_maestro ON contacto_paciente(id_paciente_maestro);
CREATE INDEX idx_direccion_paciente_paciente_maestro ON direccion_paciente(id_paciente_maestro);
CREATE INDEX idx_direccion_paciente_codigo_postal ON direccion_paciente(codigo_postal);
CREATE INDEX idx_candidato_duplicado_paciente_a ON candidato_duplicado(id_paciente_a);
CREATE INDEX idx_candidato_duplicado_paciente_b ON candidato_duplicado(id_paciente_b);
CREATE INDEX idx_candidato_duplicado_usuario_resolucion ON candidato_duplicado(id_usuario_resolucion);
CREATE INDEX idx_mapeo_codigo_sistema_origen ON mapeo_codigo(id_sistema_origen);
CREATE INDEX idx_mapeo_codigo_codigo ON mapeo_codigo(id_codigo);
CREATE INDEX idx_encuentro_clinico_paciente_maestro ON encuentro_clinico(id_paciente_maestro);
CREATE INDEX idx_encuentro_clinico_organizacion ON encuentro_clinico(id_organizacion);
CREATE INDEX idx_encuentro_clinico_profesional ON encuentro_clinico(id_profesional);
CREATE INDEX idx_diagnostico_encuentro ON diagnostico(id_encuentro);
CREATE INDEX idx_diagnostico_codigo ON diagnostico(id_codigo);
CREATE INDEX idx_estudio_diagnostico_encuentro ON estudio_diagnostico(id_encuentro);
CREATE INDEX idx_estudio_diagnostico_codigo ON estudio_diagnostico(id_codigo);
CREATE INDEX idx_estudio_diagnostico_profesional_responsable ON estudio_diagnostico(id_profesional_responsable);
CREATE INDEX idx_observacion_encuentro ON observacion(id_encuentro);
CREATE INDEX idx_observacion_estudio ON observacion(id_estudio);
CREATE INDEX idx_observacion_codigo ON observacion(id_codigo);
CREATE INDEX idx_solicitud_medicamento_encuentro ON solicitud_medicamento(id_encuentro);
CREATE INDEX idx_solicitud_medicamento_codigo ON solicitud_medicamento(id_codigo);
CREATE INDEX idx_alergia_paciente_maestro ON alergia(id_paciente_maestro);
CREATE INDEX idx_alergia_codigo ON alergia(id_codigo);
CREATE INDEX idx_version_dato_procedencia ON version_dato(id_procedencia);
CREATE INDEX idx_version_dato_usuario ON version_dato(id_usuario);
CREATE INDEX idx_version_dato_detalle_correccion ON version_dato(id_detalle_correccion);
CREATE INDEX idx_regla_autoridad_organizacion ON regla_autoridad(id_organizacion);
CREATE INDEX idx_conflicto_dato_procedencia_a ON conflicto_dato(id_procedencia_a);
CREATE INDEX idx_conflicto_dato_procedencia_b ON conflicto_dato(id_procedencia_b);
CREATE INDEX idx_conflicto_dato_regla_sugerida ON conflicto_dato(id_regla_sugerida);
CREATE INDEX idx_conflicto_dato_usuario_resolucion ON conflicto_dato(id_usuario_resolucion);
CREATE INDEX idx_consentimiento_paciente_maestro ON consentimiento(id_paciente_maestro);
CREATE INDEX idx_consentimiento_usuario_registro ON consentimiento(id_usuario_registro);
CREATE INDEX idx_consentimiento_alcance_consentimiento ON consentimiento_alcance(id_consentimiento);
CREATE INDEX idx_consentimiento_alcance_categoria ON consentimiento_alcance(id_categoria);
CREATE INDEX idx_consentimiento_alcance_organizacion ON consentimiento_alcance(id_organizacion);
CREATE INDEX idx_auditoria_usuario ON auditoria(id_usuario);
CREATE INDEX idx_auditoria_sistema_origen ON auditoria(id_sistema_origen);
CREATE INDEX idx_auditoria_paciente_maestro ON auditoria(id_paciente_maestro);

-- Índices únicos parciales: reglas de unicidad que aplican solo a algunas filas.
CREATE UNIQUE INDEX uq_identificador_oficial_por_sistema ON identificador_paciente (id_paciente_maestro, id_sistema_origen) WHERE uso = 'oficial';
CREATE UNIQUE INDEX uq_credencial_activa_por_sistema ON credencial_sistema (id_sistema_origen) WHERE estado = 'activa';
CREATE UNIQUE INDEX uq_contacto_principal_por_organizacion ON contacto_organizacion (id_organizacion) WHERE es_principal;

-- Índices de consulta: algoritmo de coincidencia, detección de reenvíos y tableros.
CREATE INDEX idx_paciente_maestro_fecha_nacimiento ON paciente_maestro (fecha_nacimiento);
CREATE INDEX idx_detalle_transaccion_recurso ON detalle_transaccion (tipo_recurso, id_recurso_externo, version_recurso);
CREATE INDEX idx_paquete_transaccion_fecha ON paquete_transaccion (fecha_recepcion);
CREATE INDEX idx_auditoria_fecha ON auditoria (fecha_hora);
CREATE INDEX idx_conflicto_dato_estado ON conflicto_dato (estado);
CREATE INDEX idx_candidato_duplicado_estado ON candidato_duplicado (estado);

-- ------------------------------------------------------------
-- VISTAS DERIVADAS (3FN)
-- Datos que dependen de otros y por eso no se guardan como columna.
-- ------------------------------------------------------------

-- Puntaje de coincidencia: depende de los criterios (RN-16).
CREATE VIEW v_candidato_duplicado AS
SELECT c.*,
       (CASE WHEN c.coincide_identificador THEN 100 ELSE 0 END
      + CASE WHEN c.coincide_nombre_fecha  THEN  70 ELSE 0 END
      + CASE WHEN c.coincide_telefono      THEN  20 ELSE 0 END
      + CASE WHEN c.coincide_correo        THEN  20 ELSE 0 END
      + CASE WHEN c.coincide_direccion     THEN  10 ELSE 0 END) AS puntaje
FROM candidato_duplicado c;

-- Paciente y tipo de dato de cada procedencia, sin importar en qué tabla clínica está el dato.
CREATE VIEW v_procedencia_paciente AS
SELECT id_procedencia, 'nombre'::VARCHAR(15) AS tipo_dato, id_paciente_maestro FROM nombre_paciente
UNION ALL SELECT id_procedencia, 'contacto', id_paciente_maestro FROM contacto_paciente
UNION ALL SELECT id_procedencia, 'direccion', id_paciente_maestro FROM direccion_paciente
UNION ALL SELECT id_procedencia, 'alergia', id_paciente_maestro FROM alergia
UNION ALL SELECT id_procedencia, 'encuentro', id_paciente_maestro FROM encuentro_clinico
UNION ALL SELECT d.id_procedencia, 'diagnostico', e.id_paciente_maestro
          FROM diagnostico d JOIN encuentro_clinico e ON e.id_encuentro = d.id_encuentro
UNION ALL SELECT s.id_procedencia, 'medicamento', e.id_paciente_maestro
          FROM solicitud_medicamento s JOIN encuentro_clinico e ON e.id_encuentro = s.id_encuentro
UNION ALL SELECT x.id_procedencia, 'estudio', e.id_paciente_maestro
          FROM estudio_diagnostico x JOIN encuentro_clinico e ON e.id_encuentro = x.id_encuentro
UNION ALL SELECT o.id_procedencia, 'observacion', e.id_paciente_maestro
          FROM observacion o
          LEFT JOIN estudio_diagnostico x ON x.id_estudio = o.id_estudio
          JOIN encuentro_clinico e ON e.id_encuentro = COALESCE(o.id_encuentro, x.id_encuentro);

-- Conflicto con su paciente y tipo de dato (se obtienen por la procedencia A).
CREATE VIEW v_conflicto_detalle AS
SELECT c.*, p.id_paciente_maestro, p.tipo_dato
FROM conflicto_dato c
JOIN v_procedencia_paciente p ON p.id_procedencia = c.id_procedencia_a;

-- Municipio y estado de cada dirección de paciente (salen del catálogo de códigos postales).
CREATE VIEW v_direccion_paciente AS
SELECT d.*, cp.municipio, cp.entidad_federativa
FROM direccion_paciente d
JOIN codigo_postal cp ON cp.codigo_postal = d.codigo_postal;

-- ------------------------------------------------------------
-- DICCIONARIO DE DATOS: comentarios de tablas
-- ------------------------------------------------------------
COMMENT ON TABLE codigo_postal IS 'Catálogo de códigos postales (SEPOMEX). El código postal determina el municipio y el estado; por eso viven aquí y no en cada dirección.';
COMMENT ON TABLE organizacion IS 'Hospital, clínica o laboratorio que aporta o consulta información.';
COMMENT ON TABLE contacto_organizacion IS 'Personas de contacto de cada institución; el puesto y los datos de contacto dependen de la persona, no de la institución.';
COMMENT ON TABLE sistema_origen IS 'Sistema informático de una institución (expediente, laboratorio, portal). La procedencia se registra a este nivel.';
COMMENT ON TABLE profesional_salud IS 'Médico o profesional de salud, una sola vez aunque trabaje en varias instituciones.';
COMMENT ON TABLE profesional_organizacion IS 'Rol y especialidad que un profesional ejerce en cada institución, con vigencia.';
COMMENT ON TABLE profesional_especialidad IS 'Especialidades del profesional. Pertenecen a la persona (cada una con su cédula de especialidad), no a la institución donde trabaja.';
COMMENT ON TABLE usuario IS 'Persona que entra a la plataforma web, con un rol.';
COMMENT ON TABLE credencial_sistema IS 'Clave con la que un sistema de origen se autentica para enviar o consultar.';
COMMENT ON TABLE paciente_maestro IS 'Representación consolidada de una persona, independiente de cuántas instituciones la conozcan.';
COMMENT ON TABLE identificador_paciente IS 'Cada identificador que una institución asigna al paciente; N por paciente maestro.';
COMMENT ON TABLE paquete_transaccion IS 'Envío completo que entra o sale del hub (bundle FHIR o captura desde el portal).';
COMMENT ON TABLE detalle_transaccion IS 'Cada recurso dentro de un paquete y su estado de procesamiento.';
COMMENT ON TABLE error_validacion IS 'Error o advertencia detectado al validar un recurso.';
COMMENT ON TABLE procedencia_dato IS 'De qué recurso recibido salió cada dato clínico, cuándo ocurrió en el origen y cuál era su valor original.';
COMMENT ON TABLE nombre_paciente IS 'Cada forma en que una institución registró el nombre del paciente (Patient.name). El paciente maestro guarda solo el nombre consolidado.';
COMMENT ON TABLE contacto_paciente IS 'Teléfono o correo del paciente según lo reporta cada institución.';
COMMENT ON TABLE direccion_paciente IS 'Domicilio del paciente según lo reporta cada institución.';
COMMENT ON TABLE candidato_duplicado IS 'Par de pacientes maestros que podrían ser la misma persona, con los criterios en que coinciden y la decisión del coordinador.';
COMMENT ON TABLE catalogo_codigo IS 'Códigos estándar: CIE-10 (diagnósticos), LOINC (estudios y observaciones), cuadro básico (medicamentos), sustancias.';
COMMENT ON TABLE mapeo_codigo IS 'Traducción de un código local de un sistema al código estándar.';
COMMENT ON TABLE encuentro_clinico IS 'Consulta, urgencia, hospitalización o toma de muestra; agrupa los datos clínicos de una atención.';
COMMENT ON TABLE diagnostico IS 'Condición del paciente registrada en un encuentro, codificada con CIE-10.';
COMMENT ON TABLE estudio_diagnostico IS 'Reporte de un estudio (por ejemplo, química sanguínea) que agrupa varios resultados.';
COMMENT ON TABLE observacion IS 'Signo vital o resultado de laboratorio con valor, unidad y rango de referencia, codificado con LOINC.';
COMMENT ON TABLE solicitud_medicamento IS 'Medicamento indicado en un encuentro, con dosis y vigencia.';
COMMENT ON TABLE alergia IS 'Alergia o ausencia declarada de alergias. Pertenece al paciente, no a un encuentro.';
COMMENT ON TABLE version_dato IS 'Historial de cambios de un dato clínico; el dato se identifica por su procedencia.';
COMMENT ON TABLE regla_autoridad IS 'Criterio sugerido para resolver conflictos según el tipo de dato y, opcionalmente, la institución con autoridad.';
COMMENT ON TABLE conflicto_dato IS 'Dos valores contradictorios del mismo dato de un paciente, reportados por fuentes distintas, y su resolución.';
COMMENT ON TABLE categoria_informacion IS 'Categorías de información que un paciente puede autorizar compartir.';
COMMENT ON TABLE consentimiento IS 'Autorización del paciente con vigencia y estado.';
COMMENT ON TABLE consentimiento_alcance IS 'Qué categoría de información cubre un consentimiento, con qué institución y para qué: enviarla al hub o consultarla.';
COMMENT ON TABLE auditoria IS 'Registro de solo inserción de quién consultó, modificó o resolvió algo.';

-- Diccionario: columnas.
COMMENT ON COLUMN codigo_postal.codigo_postal IS 'PK. Código postal.';
COMMENT ON COLUMN codigo_postal.municipio IS 'Municipio.';
COMMENT ON COLUMN codigo_postal.entidad_federativa IS 'Estado.';
COMMENT ON COLUMN organizacion.id_organizacion IS 'PK. Identificador interno de la institución.';
COMMENT ON COLUMN organizacion.clave_organizacion IS 'Clave oficial (CLUES) de la institución.';
COMMENT ON COLUMN organizacion.nombre IS 'Nombre de la institución.';
COMMENT ON COLUMN organizacion.tipo_organizacion IS 'Tipo de institución.';
COMMENT ON COLUMN organizacion.telefono IS 'Teléfono general (conmutador).';
COMMENT ON COLUMN organizacion.calle IS 'Calle de la sede.';
COMMENT ON COLUMN organizacion.numero_exterior IS 'Número exterior.';
COMMENT ON COLUMN organizacion.colonia IS 'Colonia (un código postal puede tener varias).';
COMMENT ON COLUMN organizacion.codigo_postal IS 'FK. Código postal; de ahí salen municipio y estado.';
COMMENT ON COLUMN organizacion.estado IS 'Una institución suspendida no puede enviar paquetes (RN-11).';
COMMENT ON COLUMN organizacion.fecha_registro IS 'Alta en el hub.';
COMMENT ON COLUMN contacto_organizacion.id_contacto_organizacion IS 'PK. Identificador del contacto.';
COMMENT ON COLUMN contacto_organizacion.id_organizacion IS 'FK. Institución.';
COMMENT ON COLUMN contacto_organizacion.nombre IS 'Nombre completo.';
COMMENT ON COLUMN contacto_organizacion.puesto IS 'Puesto.';
COMMENT ON COLUMN contacto_organizacion.telefono IS 'Teléfono directo.';
COMMENT ON COLUMN contacto_organizacion.correo IS 'Correo.';
COMMENT ON COLUMN contacto_organizacion.es_principal IS 'Contacto principal para la integración.';
COMMENT ON COLUMN sistema_origen.id_sistema_origen IS 'PK. Identificador interno del sistema.';
COMMENT ON COLUMN sistema_origen.id_organizacion IS 'FK. Institución dueña del sistema.';
COMMENT ON COLUMN sistema_origen.nombre_sistema IS 'Nombre del sistema.';
COMMENT ON COLUMN sistema_origen.tipo_sistema IS 'portal_hub = captura manual desde la plataforma.';
COMMENT ON COLUMN sistema_origen.version_sistema IS 'Versión reportada.';
COMMENT ON COLUMN sistema_origen.uri_identificador IS 'Espacio de nombres de los identificadores que emite el sistema.';
COMMENT ON COLUMN sistema_origen.estado IS 'Estado del sistema.';
COMMENT ON COLUMN profesional_salud.id_profesional IS 'PK. Identificador interno del profesional.';
COMMENT ON COLUMN profesional_salud.cedula_profesional IS 'Cédula profesional (identifica a la persona).';
COMMENT ON COLUMN profesional_salud.nombre IS 'Nombre(s).';
COMMENT ON COLUMN profesional_salud.apellido_paterno IS 'Primer apellido.';
COMMENT ON COLUMN profesional_salud.apellido_materno IS 'Segundo apellido.';
COMMENT ON COLUMN profesional_salud.activo IS 'Si sigue ejerciendo.';
COMMENT ON COLUMN profesional_organizacion.id_profesional_organizacion IS 'PK. Identificador del vínculo.';
COMMENT ON COLUMN profesional_organizacion.id_profesional IS 'FK. Profesional.';
COMMENT ON COLUMN profesional_organizacion.id_organizacion IS 'FK. Institución donde ejerce.';
COMMENT ON COLUMN profesional_organizacion.rol IS 'Rol en la institución.';
COMMENT ON COLUMN profesional_organizacion.fecha_inicio IS 'Inicio del vínculo.';
COMMENT ON COLUMN profesional_organizacion.fecha_fin IS 'Fin del vínculo; nulo si sigue vigente.';
COMMENT ON COLUMN profesional_especialidad.id_profesional_especialidad IS 'PK. Identificador del registro.';
COMMENT ON COLUMN profesional_especialidad.id_profesional IS 'FK. Profesional.';
COMMENT ON COLUMN profesional_especialidad.especialidad IS 'Especialidad.';
COMMENT ON COLUMN profesional_especialidad.cedula_especialidad IS 'Cédula de especialidad.';
COMMENT ON COLUMN usuario.id_usuario IS 'PK. Identificador del usuario.';
COMMENT ON COLUMN usuario.id_profesional IS 'FK. Profesional asociado cuando el usuario es médico.';
COMMENT ON COLUMN usuario.nombre IS 'Nombre del usuario que no es profesional de salud.';
COMMENT ON COLUMN usuario.apellido_paterno IS 'Primer apellido.';
COMMENT ON COLUMN usuario.apellido_materno IS 'Segundo apellido.';
COMMENT ON COLUMN usuario.correo IS 'Correo de inicio de sesión.';
COMMENT ON COLUMN usuario.hash_contrasena IS 'Hash bcrypt; nunca la contraseña legible.';
COMMENT ON COLUMN usuario.rol IS 'Determina qué puede hacer.';
COMMENT ON COLUMN usuario.activo IS 'Usuario habilitado.';
COMMENT ON COLUMN usuario.fecha_registro IS 'Alta del usuario.';
COMMENT ON COLUMN credencial_sistema.id_credencial IS 'PK. Identificador de la credencial.';
COMMENT ON COLUMN credencial_sistema.id_sistema_origen IS 'FK. Sistema dueño de la credencial.';
COMMENT ON COLUMN credencial_sistema.id_usuario_emision IS 'FK. Administrador que la emitió.';
COMMENT ON COLUMN credencial_sistema.hash_clave IS 'Hash de la clave de acceso.';
COMMENT ON COLUMN credencial_sistema.fecha_emision IS 'Inicio de vigencia.';
COMMENT ON COLUMN credencial_sistema.fecha_expiracion IS 'Fin de vigencia.';
COMMENT ON COLUMN credencial_sistema.estado IS 'Estado de la credencial.';
COMMENT ON COLUMN paciente_maestro.id_paciente_maestro IS 'PK. Identificador maestro del paciente.';
COMMENT ON COLUMN paciente_maestro.curp IS 'CURP cuando se conoce.';
COMMENT ON COLUMN paciente_maestro.nombre IS 'Nombre(s) consolidado.';
COMMENT ON COLUMN paciente_maestro.apellido_paterno IS 'Primer apellido.';
COMMENT ON COLUMN paciente_maestro.apellido_materno IS 'Segundo apellido.';
COMMENT ON COLUMN paciente_maestro.fecha_nacimiento IS 'Fecha de nacimiento normalizada.';
COMMENT ON COLUMN paciente_maestro.sexo IS 'Sexo normalizado (M, H, Masculino → masculino).';
COMMENT ON COLUMN paciente_maestro.estado IS 'fusionado = absorbido por otro paciente maestro.';
COMMENT ON COLUMN paciente_maestro.id_paciente_fusionado_en IS 'FK. Paciente que lo absorbió en una fusión (autorrelación).';
COMMENT ON COLUMN paciente_maestro.fecha_registro IS 'Alta en el hub.';
COMMENT ON COLUMN paciente_maestro.fecha_actualizacion IS 'Último cambio.';
COMMENT ON COLUMN identificador_paciente.id_identificador IS 'PK. Identificador del registro.';
COMMENT ON COLUMN identificador_paciente.id_paciente_maestro IS 'FK. Paciente al que resuelve.';
COMMENT ON COLUMN identificador_paciente.id_sistema_origen IS 'FK. Sistema que lo emitió.';
COMMENT ON COLUMN identificador_paciente.valor_identificador IS 'Valor tal como lo usa la institución.';
COMMENT ON COLUMN identificador_paciente.tipo_identificador IS 'Qué clase de identificador es.';
COMMENT ON COLUMN identificador_paciente.uso IS 'Uso del identificador (RN-02).';
COMMENT ON COLUMN identificador_paciente.fecha_alta IS 'Cuándo se vinculó.';
COMMENT ON COLUMN paquete_transaccion.id_paquete IS 'PK. Identificador del paquete.';
COMMENT ON COLUMN paquete_transaccion.id_sistema_origen IS 'FK. Sistema que envía (entrante) o que recibe (saliente).';
COMMENT ON COLUMN paquete_transaccion.id_usuario_captura IS 'FK. Médico que capturó desde el portal.';
COMMENT ON COLUMN paquete_transaccion.direccion IS 'Sentido del intercambio.';
COMMENT ON COLUMN paquete_transaccion.tipo_paquete IS 'Tipo de envío.';
COMMENT ON COLUMN paquete_transaccion.fecha_recepcion IS 'Llegada o salida.';
COMMENT ON COLUMN paquete_transaccion.estado IS 'Estado del paquete.';
COMMENT ON COLUMN paquete_transaccion.hash_paquete IS 'SHA-256 del contenido; evita procesar dos veces el mismo envío.';
COMMENT ON COLUMN paquete_transaccion.ref_documento_mongo IS 'ObjectId del bundle original en MongoDB (colección recursos_originales).';
COMMENT ON COLUMN paquete_transaccion.ref_respuesta_mongo IS 'ObjectId de la respuesta completa enviada a la institución (colección respuestas).';
COMMENT ON COLUMN detalle_transaccion.id_detalle IS 'PK. Identificador del recurso dentro del paquete.';
COMMENT ON COLUMN detalle_transaccion.id_paquete IS 'FK. Paquete al que pertenece.';
COMMENT ON COLUMN detalle_transaccion.id_paciente_maestro IS 'FK. Paciente al que se vinculó (resultado del emparejamiento).';
COMMENT ON COLUMN detalle_transaccion.tipo_recurso IS 'Tipo de recurso recibido (varía por fila: sí es un dato).';
COMMENT ON COLUMN detalle_transaccion.id_recurso_externo IS 'Id del recurso en el sistema de origen.';
COMMENT ON COLUMN detalle_transaccion.version_recurso IS 'Versión del recurso en el origen (meta.versionId).';
COMMENT ON COLUMN detalle_transaccion.fecha_recurso_origen IS 'Última actualización del recurso en el origen (meta.lastUpdated).';
COMMENT ON COLUMN detalle_transaccion.id_detalle_original IS 'FK. Primera copia recibida, cuando este recurso es un reenvío (autorrelación).';
COMMENT ON COLUMN detalle_transaccion.estado IS 'Etapa del procesamiento; duplicado = reenvío del mismo recurso y versión.';
COMMENT ON COLUMN detalle_transaccion.hash_recurso IS 'SHA-256 del recurso original.';
COMMENT ON COLUMN detalle_transaccion.ref_original_mongo IS 'ObjectId del recurso tal como llegó (colección recursos_originales).';
COMMENT ON COLUMN detalle_transaccion.ref_transformado_mongo IS 'ObjectId del resultado de la transformación o del recurso FHIR generado para envío (colección recursos_transformados).';
COMMENT ON COLUMN detalle_transaccion.fecha_procesamiento IS 'Fin del procesamiento.';
COMMENT ON COLUMN error_validacion.id_error IS 'PK. Identificador del error.';
COMMENT ON COLUMN error_validacion.id_detalle IS 'FK. Recurso que lo provocó.';
COMMENT ON COLUMN error_validacion.codigo_error IS 'Clase de error.';
COMMENT ON COLUMN error_validacion.severidad IS 'Un error fatal impide integrar el recurso (RN-12).';
COMMENT ON COLUMN error_validacion.ruta_elemento IS 'Elemento del recurso donde se detectó.';
COMMENT ON COLUMN error_validacion.descripcion IS 'Mensaje legible.';
COMMENT ON COLUMN procedencia_dato.id_procedencia IS 'PK. Identificador de la procedencia.';
COMMENT ON COLUMN procedencia_dato.id_detalle IS 'FK. Recurso del que salió el dato (da paquete → sistema → institución).';
COMMENT ON COLUMN procedencia_dato.ruta_elemento IS 'Elemento del recurso de donde se extrajo.';
COMMENT ON COLUMN procedencia_dato.valor_original IS 'Valor tal como llegó, antes de normalizar.';
COMMENT ON COLUMN procedencia_dato.codigo_original IS 'Código local tal como llegó.';
COMMENT ON COLUMN procedencia_dato.fecha_origen IS 'Cuándo se registró el dato en la institución.';
COMMENT ON COLUMN procedencia_dato.fecha_recepcion IS 'Cuándo llegó al hub.';
COMMENT ON COLUMN nombre_paciente.id_nombre IS 'PK. Identificador del nombre.';
COMMENT ON COLUMN nombre_paciente.id_paciente_maestro IS 'FK. Paciente.';
COMMENT ON COLUMN nombre_paciente.id_procedencia IS 'FK. Quién lo reportó.';
COMMENT ON COLUMN nombre_paciente.nombre IS 'Nombre(s) tal como se reportó, ya separado.';
COMMENT ON COLUMN nombre_paciente.apellido_paterno IS 'Primer apellido.';
COMMENT ON COLUMN nombre_paciente.apellido_materno IS 'Segundo apellido.';
COMMENT ON COLUMN nombre_paciente.uso IS 'Uso del nombre (Patient.name.use).';
COMMENT ON COLUMN nombre_paciente.vigente IS 'Falso cuando queda como histórico.';
COMMENT ON COLUMN contacto_paciente.id_contacto IS 'PK. Identificador del contacto.';
COMMENT ON COLUMN contacto_paciente.id_paciente_maestro IS 'FK. Paciente.';
COMMENT ON COLUMN contacto_paciente.id_procedencia IS 'FK. Quién lo reportó.';
COMMENT ON COLUMN contacto_paciente.tipo_contacto IS 'Canal.';
COMMENT ON COLUMN contacto_paciente.valor IS 'Número o correo.';
COMMENT ON COLUMN contacto_paciente.uso IS 'Ámbito de uso.';
COMMENT ON COLUMN contacto_paciente.vigente IS 'Falso cuando una resolución lo deja como histórico.';
COMMENT ON COLUMN direccion_paciente.id_direccion IS 'PK. Identificador de la dirección.';
COMMENT ON COLUMN direccion_paciente.id_paciente_maestro IS 'FK. Paciente.';
COMMENT ON COLUMN direccion_paciente.id_procedencia IS 'FK. Quién la reportó.';
COMMENT ON COLUMN direccion_paciente.calle IS 'Calle.';
COMMENT ON COLUMN direccion_paciente.numero_exterior IS 'Número exterior.';
COMMENT ON COLUMN direccion_paciente.numero_interior IS 'Número interior.';
COMMENT ON COLUMN direccion_paciente.colonia IS 'Colonia.';
COMMENT ON COLUMN direccion_paciente.codigo_postal IS 'FK. Código postal; de ahí salen municipio y estado. El texto tal como llegó queda en procedencia_dato.valor_original.';
COMMENT ON COLUMN direccion_paciente.uso IS 'Tipo de domicilio.';
COMMENT ON COLUMN direccion_paciente.vigente IS 'Falso cuando queda como histórico.';
COMMENT ON COLUMN candidato_duplicado.id_candidato IS 'PK. Identificador del candidato.';
COMMENT ON COLUMN candidato_duplicado.id_paciente_a IS 'FK. Paciente con id menor del par.';
COMMENT ON COLUMN candidato_duplicado.id_paciente_b IS 'FK. Paciente con id mayor del par.';
COMMENT ON COLUMN candidato_duplicado.coincide_identificador IS 'Mismo identificador oficial (CURP o NSS): 100 puntos.';
COMMENT ON COLUMN candidato_duplicado.coincide_nombre_fecha IS 'Mismo primer nombre, apellido paterno y fecha de nacimiento: 70 puntos.';
COMMENT ON COLUMN candidato_duplicado.coincide_telefono IS 'Mismo teléfono: 20 puntos.';
COMMENT ON COLUMN candidato_duplicado.coincide_correo IS 'Mismo correo: 20 puntos.';
COMMENT ON COLUMN candidato_duplicado.coincide_direccion IS 'Misma dirección: 10 puntos.';
COMMENT ON COLUMN candidato_duplicado.fecha_deteccion IS 'Cuándo se detectó.';
COMMENT ON COLUMN candidato_duplicado.estado IS 'Decisión tomada.';
COMMENT ON COLUMN candidato_duplicado.id_usuario_resolucion IS 'FK. Coordinador que decidió (RN-07).';
COMMENT ON COLUMN candidato_duplicado.fecha_resolucion IS 'Cuándo se decidió.';
COMMENT ON COLUMN candidato_duplicado.justificacion IS 'Razón de la decisión.';
COMMENT ON COLUMN catalogo_codigo.id_codigo IS 'PK. Identificador del código.';
COMMENT ON COLUMN catalogo_codigo.sistema_codificacion IS 'Catálogo al que pertenece.';
COMMENT ON COLUMN catalogo_codigo.codigo IS 'Código en ese catálogo.';
COMMENT ON COLUMN catalogo_codigo.descripcion IS 'Descripción estándar.';
COMMENT ON COLUMN catalogo_codigo.categoria IS 'Clase del código: LOINC (signo_vital, laboratorio) o sustancia (medicamento, alimento, ambiental). Depende del código, por eso vive aquí.';
COMMENT ON COLUMN catalogo_codigo.unidad_sugerida IS 'Unidad esperada (observaciones).';
COMMENT ON COLUMN catalogo_codigo.activo IS 'Si sigue vigente en el catálogo.';
COMMENT ON COLUMN mapeo_codigo.id_mapeo IS 'PK. Identificador del mapeo.';
COMMENT ON COLUMN mapeo_codigo.id_sistema_origen IS 'FK. Sistema que usa el código local.';
COMMENT ON COLUMN mapeo_codigo.codigo_local IS 'Código como lo envía la institución.';
COMMENT ON COLUMN mapeo_codigo.descripcion_local IS 'Descripción local.';
COMMENT ON COLUMN mapeo_codigo.id_codigo IS 'FK. Código estándar equivalente.';
COMMENT ON COLUMN encuentro_clinico.id_encuentro IS 'PK. Identificador del encuentro.';
COMMENT ON COLUMN encuentro_clinico.id_paciente_maestro IS 'FK. Paciente atendido.';
COMMENT ON COLUMN encuentro_clinico.id_organizacion IS 'FK. Lugar donde ocurrió la atención (puede diferir de quien lo reporta).';
COMMENT ON COLUMN encuentro_clinico.id_profesional IS 'FK. Profesional que atendió.';
COMMENT ON COLUMN encuentro_clinico.id_procedencia IS 'FK. De dónde llegó el encuentro.';
COMMENT ON COLUMN encuentro_clinico.tipo_encuentro IS 'Tipo de atención.';
COMMENT ON COLUMN encuentro_clinico.motivo IS 'Motivo de la atención.';
COMMENT ON COLUMN encuentro_clinico.fecha_inicio IS 'Inicio de la atención.';
COMMENT ON COLUMN encuentro_clinico.fecha_fin IS 'Fin de la atención.';
COMMENT ON COLUMN encuentro_clinico.estado IS 'Estado del encuentro.';
COMMENT ON COLUMN diagnostico.id_diagnostico IS 'PK. Identificador del diagnóstico.';
COMMENT ON COLUMN diagnostico.id_encuentro IS 'FK. Encuentro donde se registró (de ahí sale el paciente).';
COMMENT ON COLUMN diagnostico.id_codigo IS 'FK. Código CIE-10.';
COMMENT ON COLUMN diagnostico.id_procedencia IS 'FK. De dónde llegó.';
COMMENT ON COLUMN diagnostico.tipo IS 'Principal o secundario.';
COMMENT ON COLUMN diagnostico.estado_clinico IS 'Situación del diagnóstico.';
COMMENT ON COLUMN diagnostico.fecha_diagnostico IS 'Fecha del diagnóstico.';
COMMENT ON COLUMN estudio_diagnostico.id_estudio IS 'PK. Identificador del estudio.';
COMMENT ON COLUMN estudio_diagnostico.id_encuentro IS 'FK. Encuentro (toma de muestra) al que pertenece.';
COMMENT ON COLUMN estudio_diagnostico.id_codigo IS 'FK. Código LOINC del estudio.';
COMMENT ON COLUMN estudio_diagnostico.id_profesional_responsable IS 'FK. Químico o médico que firma.';
COMMENT ON COLUMN estudio_diagnostico.id_procedencia IS 'FK. De dónde llegó.';
COMMENT ON COLUMN estudio_diagnostico.fecha_emision IS 'Emisión del reporte.';
COMMENT ON COLUMN estudio_diagnostico.estado IS 'Estado del reporte.';
COMMENT ON COLUMN estudio_diagnostico.conclusion IS 'Interpretación del responsable.';
COMMENT ON COLUMN observacion.id_observacion IS 'PK. Identificador de la observación.';
COMMENT ON COLUMN observacion.id_encuentro IS 'FK. Encuentro donde se midió (signos vitales); nulo si pertenece a un estudio.';
COMMENT ON COLUMN observacion.id_estudio IS 'FK. Estudio al que pertenece (resultados de laboratorio); el encuentro se obtiene por el estudio.';
COMMENT ON COLUMN observacion.id_codigo IS 'FK. Qué se midió (su categoría está en el catálogo).';
COMMENT ON COLUMN observacion.id_procedencia IS 'FK. De dónde llegó.';
COMMENT ON COLUMN observacion.valor_numerico IS 'Valor medido.';
COMMENT ON COLUMN observacion.valor_texto IS 'Valor no numérico (p. ej. 135/85).';
COMMENT ON COLUMN observacion.unidad IS 'Unidad del valor.';
COMMENT ON COLUMN observacion.rango_ref_min IS 'Límite inferior de referencia.';
COMMENT ON COLUMN observacion.rango_ref_max IS 'Límite superior de referencia.';
COMMENT ON COLUMN observacion.interpretacion IS 'Interpretación.';
COMMENT ON COLUMN observacion.fecha_observacion IS 'Momento de la medición o toma.';
COMMENT ON COLUMN solicitud_medicamento.id_solicitud IS 'PK. Identificador de la indicación.';
COMMENT ON COLUMN solicitud_medicamento.id_encuentro IS 'FK. Encuentro donde se indicó.';
COMMENT ON COLUMN solicitud_medicamento.id_codigo IS 'FK. Medicamento.';
COMMENT ON COLUMN solicitud_medicamento.id_procedencia IS 'FK. De dónde llegó.';
COMMENT ON COLUMN solicitud_medicamento.dosis IS 'Dosis.';
COMMENT ON COLUMN solicitud_medicamento.via IS 'Vía de administración.';
COMMENT ON COLUMN solicitud_medicamento.frecuencia IS 'Frecuencia.';
COMMENT ON COLUMN solicitud_medicamento.duracion_dias IS 'Duración del tratamiento.';
COMMENT ON COLUMN solicitud_medicamento.fecha_solicitud IS 'Cuándo se indicó.';
COMMENT ON COLUMN solicitud_medicamento.estado IS 'Estado de la indicación.';
COMMENT ON COLUMN alergia.id_alergia IS 'PK. Identificador de la alergia.';
COMMENT ON COLUMN alergia.id_paciente_maestro IS 'FK. Paciente.';
COMMENT ON COLUMN alergia.id_codigo IS 'FK. Sustancia (su categoría está en el catálogo).';
COMMENT ON COLUMN alergia.id_procedencia IS 'FK. Quién la reportó.';
COMMENT ON COLUMN alergia.sin_alergias_conocidas IS 'Verdadero cuando la institución reporta "Ninguna".';
COMMENT ON COLUMN alergia.reaccion IS 'Reacción observada.';
COMMENT ON COLUMN alergia.criticidad IS 'Riesgo de reacción grave.';
COMMENT ON COLUMN alergia.estado_verificacion IS 'Qué tan segura es.';
COMMENT ON COLUMN alergia.vigente IS 'Falso cuando una resolución la deja como histórica.';
COMMENT ON COLUMN alergia.fecha_registro IS 'Fecha en que se registró en el origen.';
COMMENT ON COLUMN version_dato.id_version IS 'PK. Identificador de la versión.';
COMMENT ON COLUMN version_dato.id_procedencia IS 'FK. Dato que cambió.';
COMMENT ON COLUMN version_dato.campo IS 'Atributo modificado.';
COMMENT ON COLUMN version_dato.numero_version IS 'Versión resultante.';
COMMENT ON COLUMN version_dato.valor_anterior IS 'Valor antes del cambio.';
COMMENT ON COLUMN version_dato.valor_nuevo IS 'Valor después del cambio.';
COMMENT ON COLUMN version_dato.id_usuario IS 'FK. Quién lo cambió; nulo si llegó corregido de la institución.';
COMMENT ON COLUMN version_dato.id_detalle_correccion IS 'FK. Recurso que trajo la corrección.';
COMMENT ON COLUMN version_dato.fecha_cambio IS 'Cuándo cambió.';
COMMENT ON COLUMN version_dato.motivo IS 'Razón del cambio.';
COMMENT ON COLUMN regla_autoridad.id_regla IS 'PK. Identificador de la regla.';
COMMENT ON COLUMN regla_autoridad.tipo_dato IS 'Tipo de dato al que aplica.';
COMMENT ON COLUMN regla_autoridad.id_organizacion IS 'FK. Institución con autoridad; nulo = cualquiera.';
COMMENT ON COLUMN regla_autoridad.criterio IS 'Criterio que se sugiere.';
COMMENT ON COLUMN regla_autoridad.prioridad IS 'Orden de evaluación (menor primero).';
COMMENT ON COLUMN regla_autoridad.activa IS 'Si se aplica.';
COMMENT ON COLUMN regla_autoridad.descripcion IS 'Explicación de la regla.';
COMMENT ON COLUMN conflicto_dato.id_conflicto IS 'PK. Identificador del conflicto.';
COMMENT ON COLUMN conflicto_dato.id_procedencia_a IS 'FK. Dato A: identifica la fila, su origen y, por ella, el paciente y el tipo de dato (vista v_conflicto_detalle).';
COMMENT ON COLUMN conflicto_dato.id_procedencia_b IS 'FK. Dato B.';
COMMENT ON COLUMN conflicto_dato.campo IS 'Atributo en conflicto.';
COMMENT ON COLUMN conflicto_dato.id_regla_sugerida IS 'FK. Regla que el sistema sugiere.';
COMMENT ON COLUMN conflicto_dato.fecha_deteccion IS 'Cuándo se detectó.';
COMMENT ON COLUMN conflicto_dato.estado IS 'Estado del conflicto.';
COMMENT ON COLUMN conflicto_dato.resolucion IS 'Qué valor quedó vigente.';
COMMENT ON COLUMN conflicto_dato.justificacion IS 'Razón de la decisión.';
COMMENT ON COLUMN conflicto_dato.id_usuario_resolucion IS 'FK. Coordinador que resolvió.';
COMMENT ON COLUMN conflicto_dato.fecha_resolucion IS 'Cuándo se resolvió.';
COMMENT ON COLUMN categoria_informacion.id_categoria IS 'PK. Identificador de la categoría.';
COMMENT ON COLUMN categoria_informacion.clave IS 'Clave corta.';
COMMENT ON COLUMN categoria_informacion.nombre IS 'Nombre.';
COMMENT ON COLUMN categoria_informacion.descripcion IS 'Qué tablas cubre.';
COMMENT ON COLUMN consentimiento.id_consentimiento IS 'PK. Identificador del consentimiento.';
COMMENT ON COLUMN consentimiento.id_paciente_maestro IS 'FK. Titular de los datos.';
COMMENT ON COLUMN consentimiento.id_usuario_registro IS 'FK. Coordinador que lo registró.';
COMMENT ON COLUMN consentimiento.fecha_otorgamiento IS 'Fecha de firma.';
COMMENT ON COLUMN consentimiento.fecha_inicio IS 'Inicio de vigencia.';
COMMENT ON COLUMN consentimiento.fecha_fin IS 'Fin de vigencia.';
COMMENT ON COLUMN consentimiento.estado IS 'Estado (vencido lo asigna una tarea programada, RN-10).';
COMMENT ON COLUMN consentimiento.fecha_revocacion IS 'Fecha de revocación.';
COMMENT ON COLUMN consentimiento.motivo_revocacion IS 'Motivo.';
COMMENT ON COLUMN consentimiento.ref_documento IS 'Ubicación del formato firmado.';
COMMENT ON COLUMN consentimiento_alcance.id_alcance IS 'PK. Identificador del alcance.';
COMMENT ON COLUMN consentimiento_alcance.id_consentimiento IS 'FK. Consentimiento.';
COMMENT ON COLUMN consentimiento_alcance.id_categoria IS 'FK. Categoría autorizada.';
COMMENT ON COLUMN consentimiento_alcance.id_organizacion IS 'FK. Institución autorizada.';
COMMENT ON COLUMN consentimiento_alcance.permiso IS 'enviar = la institución puede mandar esa información al hub; consultar = puede recibirla.';
COMMENT ON COLUMN auditoria.id_auditoria IS 'PK. Identificador del evento.';
COMMENT ON COLUMN auditoria.fecha_hora IS 'Momento del evento.';
COMMENT ON COLUMN auditoria.id_usuario IS 'FK. Usuario que actuó.';
COMMENT ON COLUMN auditoria.id_sistema_origen IS 'FK. Sistema externo que actuó (consultas por API).';
COMMENT ON COLUMN auditoria.rol_en_evento IS 'Rol que tenía al momento (fotografía histórica).';
COMMENT ON COLUMN auditoria.accion IS 'Acción realizada.';
COMMENT ON COLUMN auditoria.tabla_afectada IS 'Tabla sobre la que se actuó.';
COMMENT ON COLUMN auditoria.id_registro_afectado IS 'Llave del registro afectado.';
COMMENT ON COLUMN auditoria.id_paciente_maestro IS 'FK. Paciente involucrado, para responder quién vio a quién.';
COMMENT ON COLUMN auditoria.resultado IS 'Desenlace.';
COMMENT ON COLUMN auditoria.detalle IS 'Descripción ampliada.';

-- Diccionario: constraints de reglas de negocio.
COMMENT ON CONSTRAINT chk_codigo_postal_formato ON codigo_postal IS 'CHECK: el código postal tiene exactamente 5 dígitos.';
COMMENT ON CONSTRAINT uq_organizacion_clave_organizacion ON organizacion IS 'UNIQUE: Clave oficial (CLUES) de la institución. Llave candidata.';
COMMENT ON CONSTRAINT uq_sistema_origen_uri_identificador ON sistema_origen IS 'UNIQUE: Espacio de nombres de los identificadores que emite el sistema. Llave candidata.';
COMMENT ON CONSTRAINT uq_sistema_origen_nombre ON sistema_origen IS 'UNIQUE compuesto: una institución no registra dos sistemas con el mismo nombre.';
COMMENT ON CONSTRAINT uq_profesional_salud_cedula_profesional ON profesional_salud IS 'UNIQUE: Cédula profesional (identifica a la persona). Llave candidata.';
COMMENT ON CONSTRAINT uq_profesional_organizacion_vinculo ON profesional_organizacion IS 'UNIQUE compuesto (llave candidata): un profesional no repite el mismo rol en la misma institución desde la misma fecha.';
COMMENT ON CONSTRAINT chk_profesional_organizacion_fechas ON profesional_organizacion IS 'CHECK: la fecha de fin, si existe, es posterior a la de inicio.';
COMMENT ON CONSTRAINT uq_profesional_especialidad_cedula_especialidad ON profesional_especialidad IS 'UNIQUE: Cédula de especialidad. Llave alterna: admite nulo.';
COMMENT ON CONSTRAINT uq_profesional_especialidad ON profesional_especialidad IS 'UNIQUE compuesto (llave candidata): un profesional no repite una especialidad.';
COMMENT ON CONSTRAINT uq_usuario_profesional ON usuario IS 'UNIQUE: Profesional asociado cuando el usuario es médico. Llave alterna: admite nulo.';
COMMENT ON CONSTRAINT uq_usuario_correo ON usuario IS 'UNIQUE: Correo de inicio de sesión. Llave candidata.';
COMMENT ON CONSTRAINT chk_usuario_medico_profesional ON usuario IS 'CHECK: un usuario es médico si y solo si está ligado a un profesional de salud.';
COMMENT ON CONSTRAINT chk_usuario_nombre_segun_tipo ON usuario IS 'CHECK (3FN): el nombre se guarda en usuario solo si no es médico; el de un médico vive en profesional_salud.';
COMMENT ON CONSTRAINT chk_usuario_medico_sin_apellido ON usuario IS 'CHECK (3FN): un usuario médico no repite su segundo apellido.';
COMMENT ON CONSTRAINT chk_credencial_vigencia ON credencial_sistema IS 'CHECK: la expiración es posterior a la emisión.';
COMMENT ON CONSTRAINT uq_paciente_maestro_curp ON paciente_maestro IS 'UNIQUE: CURP cuando se conoce. Llave alterna: admite nulo.';
COMMENT ON CONSTRAINT chk_paciente_fecha_nacimiento ON paciente_maestro IS 'CHECK: la fecha de nacimiento no puede ser futura.';
COMMENT ON CONSTRAINT chk_paciente_fusion ON paciente_maestro IS 'CHECK: un paciente fusionado indica en qué paciente quedó absorbido, y solo él (RN-07).';
COMMENT ON CONSTRAINT chk_paciente_fusion_no_propia ON paciente_maestro IS 'CHECK: un paciente no puede fusionarse consigo mismo.';
COMMENT ON CONSTRAINT uq_identificador_sistema_valor ON identificador_paciente IS 'UNIQUE compuesto (RN-01): un identificador de un sistema pertenece a un solo paciente maestro.';
COMMENT ON CONSTRAINT uq_paquete_transaccion_hash_paquete ON paquete_transaccion IS 'UNIQUE: SHA-256 del contenido; evita procesar dos veces el mismo envío. Llave candidata.';
COMMENT ON CONSTRAINT chk_paquete_captura_usuario ON paquete_transaccion IS 'CHECK: solo las capturas del portal tienen usuario capturista, y siempre lo tienen.';
COMMENT ON CONSTRAINT chk_detalle_duplicado_original ON detalle_transaccion IS 'CHECK (RN-15): un recurso duplicado apunta a la primera copia recibida, y solo él.';
COMMENT ON CONSTRAINT chk_detalle_original_no_propio ON detalle_transaccion IS 'CHECK: un recurso no es duplicado de sí mismo.';
COMMENT ON CONSTRAINT uq_nombre_paciente_procedencia ON nombre_paciente IS 'UNIQUE: Quién lo reportó. Llave candidata.';
COMMENT ON CONSTRAINT uq_contacto_paciente_procedencia ON contacto_paciente IS 'UNIQUE: Quién lo reportó. Llave candidata.';
COMMENT ON CONSTRAINT uq_direccion_paciente_procedencia ON direccion_paciente IS 'UNIQUE: Quién la reportó. Llave candidata.';
COMMENT ON CONSTRAINT chk_candidato_par_ordenado ON candidato_duplicado IS 'CHECK: el par se guarda ordenado (a < b) para que no exista dos veces invertido.';
COMMENT ON CONSTRAINT uq_candidato_par ON candidato_duplicado IS 'UNIQUE compuesto (llave candidata): un par de pacientes se evalúa una sola vez.';
COMMENT ON CONSTRAINT chk_candidato_puntaje_revision ON candidato_duplicado IS 'CHECK (RN-16): los criterios suman entre 70 y 99 puntos (zona de revisión manual). El puntaje no se guarda: se calcula en v_candidato_duplicado.';
COMMENT ON CONSTRAINT chk_candidato_resolucion ON candidato_duplicado IS 'CHECK (RN-07): un candidato decidido tiene coordinador; uno pendiente no.';
COMMENT ON CONSTRAINT uq_catalogo_sistema_codigo ON catalogo_codigo IS 'UNIQUE compuesto (llave candidata): un código no se repite dentro de su sistema de codificación.';
COMMENT ON CONSTRAINT uq_mapeo_sistema_codigo_local ON mapeo_codigo IS 'UNIQUE compuesto (llave candidata): un código local de un sistema se traduce a un solo código estándar.';
COMMENT ON CONSTRAINT uq_encuentro_clinico_procedencia ON encuentro_clinico IS 'UNIQUE: De dónde llegó el encuentro. Llave candidata.';
COMMENT ON CONSTRAINT chk_encuentro_fechas ON encuentro_clinico IS 'CHECK: el fin de la atención no es anterior al inicio.';
COMMENT ON CONSTRAINT uq_diagnostico_procedencia ON diagnostico IS 'UNIQUE: De dónde llegó. Llave candidata.';
COMMENT ON CONSTRAINT uq_estudio_diagnostico_procedencia ON estudio_diagnostico IS 'UNIQUE: De dónde llegó. Llave candidata.';
COMMENT ON CONSTRAINT uq_observacion_procedencia ON observacion IS 'UNIQUE: De dónde llegó. Llave candidata.';
COMMENT ON CONSTRAINT chk_observacion_valor ON observacion IS 'CHECK: toda observación tiene valor numérico o de texto.';
COMMENT ON CONSTRAINT chk_observacion_estudio_o_encuentro ON observacion IS 'CHECK (3FN): la observación pertenece a un estudio o a un encuentro, nunca a ambos; así id_estudio no determina a id_encuentro dentro de la tabla.';
COMMENT ON CONSTRAINT uq_solicitud_medicamento_procedencia ON solicitud_medicamento IS 'UNIQUE: De dónde llegó. Llave candidata.';
COMMENT ON CONSTRAINT chk_solicitud_duracion ON solicitud_medicamento IS 'CHECK: la duración, si existe, es positiva.';
COMMENT ON CONSTRAINT uq_alergia_procedencia ON alergia IS 'UNIQUE: Quién la reportó. Llave candidata.';
COMMENT ON CONSTRAINT chk_alergia_sustancia ON alergia IS 'CHECK: hay sustancia si y solo si no es un registro de ''sin alergias conocidas''.';
COMMENT ON CONSTRAINT chk_alergia_sin_alergias ON alergia IS 'CHECK: un registro de ''sin alergias conocidas'' no tiene reacción ni criticidad.';
COMMENT ON CONSTRAINT uq_version_dato ON version_dato IS 'UNIQUE compuesto (llave candidata): una versión por dato y campo.';
COMMENT ON CONSTRAINT chk_version_numero ON version_dato IS 'CHECK: el número de versión es positivo.';
COMMENT ON CONSTRAINT chk_version_origen_cambio ON version_dato IS 'CHECK (RN-04): todo cambio tiene autor: un usuario o un recurso corregido de la institución.';
COMMENT ON CONSTRAINT chk_conflicto_procedencias_distintas ON conflicto_dato IS 'CHECK: un dato no entra en conflicto consigo mismo.';
COMMENT ON CONSTRAINT uq_conflicto_procedencias_campo ON conflicto_dato IS 'UNIQUE compuesto (llave candidata): el mismo par de datos no genera dos conflictos sobre el mismo campo.';
COMMENT ON CONSTRAINT chk_conflicto_resolucion ON conflicto_dato IS 'CHECK (RN-05): un conflicto resuelto indica qué valor quedó vigente, y solo él.';
COMMENT ON CONSTRAINT chk_conflicto_responsable ON conflicto_dato IS 'CHECK (RN-06): todo conflicto decidido tiene un coordinador responsable.';
COMMENT ON CONSTRAINT uq_categoria_informacion_clave ON categoria_informacion IS 'UNIQUE: Clave corta. Llave candidata.';
COMMENT ON CONSTRAINT chk_consentimiento_vigencia ON consentimiento IS 'CHECK: el fin de vigencia es posterior al inicio.';
COMMENT ON CONSTRAINT chk_consentimiento_revocacion ON consentimiento IS 'CHECK (RN-10): un consentimiento revocado tiene fecha de revocación, y solo él.';
COMMENT ON CONSTRAINT uq_consentimiento_alcance ON consentimiento_alcance IS 'UNIQUE compuesto (llave candidata): una autorización por consentimiento, categoría, institución y permiso.';
COMMENT ON CONSTRAINT chk_auditoria_actor ON auditoria IS 'CHECK: todo evento tiene un actor, sea usuario o sistema externo.';

-- Diccionario: vistas.
COMMENT ON VIEW v_candidato_duplicado IS 'Candidatos a duplicado con su puntaje calculado a partir de los criterios (RN-16).';
COMMENT ON VIEW v_procedencia_paciente IS 'Paciente y tipo de dato al que pertenece cada procedencia.';
COMMENT ON VIEW v_conflicto_detalle IS 'Conflictos de dato con su paciente y tipo de dato, para la cola del coordinador.';
COMMENT ON VIEW v_direccion_paciente IS 'Direcciones de pacientes con municipio y estado tomados del catálogo de códigos postales.';

COMMIT;
