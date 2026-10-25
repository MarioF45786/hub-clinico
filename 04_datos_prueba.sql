-- ============================================================
-- 04_datos_prueba.sql
-- Datos de prueba ficticios para el hub de interoperabilidad clínica.
-- Todos los nombres, CURP, cédulas, teléfonos y domicilios son inventados.
--
-- Orden de ejecución:
--   1) 02_hub_interoperabilidad_schema.sql   (estructura, 34 tablas)
--   2) 03_ajustes_segundo_avance.sql         (pgcrypto y ajustes)
--   3) 04_datos_prueba.sql                   (este archivo)
--
-- El script es re-ejecutable: vacía todas las tablas y reinicia las llaves.
-- Contraseña de todos los usuarios de prueba: Flojorama2026!
--
-- Escenarios incluidos a propósito (para CRUD, JOIN y reglas de negocio):
--   * Pacientes 28-32 sin encuentros               -> LEFT JOIN / NOT EXISTS
--   * Profesionales 11 (inactivo) y 12 sin encuentros
--   * Organización 9 suspendida y 10 inactiva sin encuentros -> RIGHT / FULL JOIN
--   * Encuentro 44 de urgencias sin profesional asignado
--   * Encuentros 48-50 planeados (consultas pendientes, capturados en el portal)
--   * Encuentro 46 en curso y 47 cancelado
--   * Paciente 27 dado de baja lógica (inactivo) con historial
--   * Paciente 32 fusionado en el 6 (SELF JOIN en paciente_maestro)
--   * Candidatos a duplicado (5,31) y (17,30) pendientes
--   * Conflicto de alergia (pendiente) y de teléfono (resuelto)
--   * Paquetes con errores, rechazados, un reenvío duplicado y uno saliente
--   * Consentimiento revocado (paciente 21) y vencido (paciente 22);
--     pacientes 23-32 sin consentimiento
-- ============================================================

BEGIN;

TRUNCATE codigo_postal, organizacion, contacto_organizacion, sistema_origen,
         profesional_salud, profesional_organizacion, profesional_especialidad,
         usuario, credencial_sistema, paciente_maestro, identificador_paciente,
         paquete_transaccion, detalle_transaccion, error_validacion,
         procedencia_dato, nombre_paciente, contacto_paciente, direccion_paciente,
         candidato_duplicado, catalogo_codigo, mapeo_codigo, encuentro_clinico,
         diagnostico, estudio_diagnostico, observacion, solicitud_medicamento,
         alergia, version_dato, regla_autoridad, conflicto_dato,
         categoria_informacion, consentimiento, consentimiento_alcance, auditoria
RESTART IDENTITY CASCADE;


-- ------------------------------------------------------------
-- CATÁLOGOS
-- ------------------------------------------------------------

-- Códigos postales (12)
INSERT INTO codigo_postal (codigo_postal, municipio, entidad_federativa) VALUES
('64000','Monterrey','Nuevo León'),
('64460','Monterrey','Nuevo León'),
('64620','Monterrey','Nuevo León'),
('64700','Monterrey','Nuevo León'),
('66220','San Pedro Garza García','Nuevo León'),
('66260','San Pedro Garza García','Nuevo León'),
('66350','Santa Catarina','Nuevo León'),
('66400','San Nicolás de los Garza','Nuevo León'),
('66450','San Nicolás de los Garza','Nuevo León'),
('66600','Apodaca','Nuevo León'),
('67100','Guadalupe','Nuevo León'),
('66050','General Escobedo','Nuevo León');

-- Códigos estándar (46): CIE-10 1-12, LOINC 13-26, cuadro básico 27-36, sustancias 37-46.
-- Las claves de cuadro básico son ilustrativas.
INSERT INTO catalogo_codigo (id_codigo, sistema_codificacion, codigo, descripcion, categoria, unidad_sugerida)
OVERRIDING SYSTEM VALUE VALUES
( 1,'CIE-10','E11.9','Diabetes mellitus tipo 2 sin complicaciones',NULL,NULL),
( 2,'CIE-10','I10','Hipertensión esencial (primaria)',NULL,NULL),
( 3,'CIE-10','J06.9','Infección aguda de las vías respiratorias superiores',NULL,NULL),
( 4,'CIE-10','E78.5','Hiperlipidemia no especificada',NULL,NULL),
( 5,'CIE-10','K29.7','Gastritis no especificada',NULL,NULL),
( 6,'CIE-10','M54.5','Lumbago no especificado',NULL,NULL),
( 7,'CIE-10','J45.9','Asma no especificada',NULL,NULL),
( 8,'CIE-10','N39.0','Infección de vías urinarias, sitio no especificado',NULL,NULL),
( 9,'CIE-10','E66.9','Obesidad no especificada',NULL,NULL),
(10,'CIE-10','A09','Diarrea y gastroenteritis de presunto origen infeccioso',NULL,NULL),
(11,'CIE-10','R50.9','Fiebre no especificada',NULL,NULL),
(12,'CIE-10','S93.4','Esguince de tobillo',NULL,NULL),
(13,'LOINC','8867-4','Frecuencia cardiaca','signo_vital','lpm'),
(14,'LOINC','8310-5','Temperatura corporal','signo_vital','°C'),
(15,'LOINC','29463-7','Peso corporal','signo_vital','kg'),
(16,'LOINC','8302-2','Talla','signo_vital','cm'),
(17,'LOINC','85354-9','Presión arterial','signo_vital','mm[Hg]'),
(18,'LOINC','2345-7','Glucosa en suero o plasma','laboratorio','mg/dL'),
(19,'LOINC','2160-0','Creatinina en suero o plasma','laboratorio','mg/dL'),
(20,'LOINC','718-7','Hemoglobina en sangre','laboratorio','g/dL'),
(21,'LOINC','2093-3','Colesterol total','laboratorio','mg/dL'),
(22,'LOINC','4548-4','Hemoglobina glucosilada (HbA1c)','laboratorio','%'),
(23,'LOINC','2571-8','Triglicéridos','laboratorio','mg/dL'),
(24,'LOINC','6690-2','Leucocitos en sangre','laboratorio','10*3/uL'),
(25,'LOINC','24323-8','Panel metabólico completo','laboratorio',NULL),
(26,'LOINC','58410-2','Biometría hemática completa','laboratorio',NULL),
(27,'CUADRO_BASICO','010.000.0104.00','Paracetamol 500 mg tableta',NULL,NULL),
(28,'CUADRO_BASICO','010.000.5165.00','Metformina 850 mg tableta',NULL,NULL),
(29,'CUADRO_BASICO','010.000.2520.00','Losartán 50 mg tableta',NULL,NULL),
(30,'CUADRO_BASICO','010.000.2128.00','Amoxicilina 500 mg cápsula',NULL,NULL),
(31,'CUADRO_BASICO','010.000.5186.00','Omeprazol 20 mg cápsula',NULL,NULL),
(32,'CUADRO_BASICO','010.000.0429.00','Salbutamol 100 mcg suspensión en aerosol',NULL,NULL),
(33,'CUADRO_BASICO','010.000.3417.00','Ibuprofeno 400 mg tableta',NULL,NULL),
(34,'CUADRO_BASICO','010.000.5106.00','Atorvastatina 20 mg tableta',NULL,NULL),
(35,'CUADRO_BASICO','010.000.2145.00','Loratadina 10 mg tableta',NULL,NULL),
(36,'CUADRO_BASICO','010.000.3407.00','Naproxeno 250 mg tableta',NULL,NULL),
(37,'SUSTANCIA','SUS-001','Penicilina','medicamento',NULL),
(38,'SUSTANCIA','SUS-002','Sulfonamidas','medicamento',NULL),
(39,'SUSTANCIA','SUS-003','Ácido acetilsalicílico','medicamento',NULL),
(40,'SUSTANCIA','SUS-004','Ibuprofeno','medicamento',NULL),
(41,'SUSTANCIA','SUS-005','Cacahuate','alimento',NULL),
(42,'SUSTANCIA','SUS-006','Mariscos','alimento',NULL),
(43,'SUSTANCIA','SUS-007','Huevo','alimento',NULL),
(44,'SUSTANCIA','SUS-008','Polen','ambiental',NULL),
(45,'SUSTANCIA','SUS-009','Látex','ambiental',NULL),
(46,'SUSTANCIA','SUS-010','Ácaros del polvo','ambiental',NULL);

-- Un código desactivado del catálogo (para probar filtros de vigencia)
UPDATE catalogo_codigo SET activo = FALSE WHERE id_codigo = 36;

-- Categorías de información para consentimientos (10)
INSERT INTO categoria_informacion (id_categoria, clave, nombre, descripcion) OVERRIDING SYSTEM VALUE VALUES
( 1,'demograficos','Datos demográficos','nombre_paciente, contacto_paciente, direccion_paciente'),
( 2,'diagnosticos','Diagnósticos','diagnostico'),
( 3,'alergias','Alergias','alergia'),
( 4,'medicamentos','Medicamentos','solicitud_medicamento'),
( 5,'resultados_laboratorio','Resultados de laboratorio','estudio_diagnostico, observacion de laboratorio'),
( 6,'signos_vitales','Signos vitales','observacion de signos vitales'),
( 7,'encuentros','Encuentros clínicos','encuentro_clinico'),
( 8,'identificadores','Identificadores institucionales','identificador_paciente'),
( 9,'salud_reproductiva','Salud reproductiva','diagnósticos y estudios de ginecología y obstetricia'),
(10,'historial_completo','Historial clínico completo','todas las categorías anteriores');


-- ------------------------------------------------------------
-- INSTITUCIONES
-- ------------------------------------------------------------

-- Organizaciones (10). La 9 está suspendida y la 10 inactiva.
INSERT INTO organizacion (id_organizacion, clave_organizacion, nombre, tipo_organizacion, telefono, calle, numero_exterior, colonia, codigo_postal, estado, fecha_registro)
OVERRIDING SYSTEM VALUE VALUES
( 1,'NLSSA900001','Hospital Universitario del Norte','hospital','8183001000','Av. Madero','1500','Centro','64000','activa','2025-11-03 09:00-06'),
( 2,'NLSSA900002','Hospital San Gabriel','hospital','8183002000','Av. Gonzalitos','320','Mitras Centro','64460','activa','2025-11-05 09:00-06'),
( 3,'NLSSA900003','Hospital La Ribera','hospital','8183003000','Av. Constitución','2100','Obispado','64620','activa','2025-11-10 09:00-06'),
( 4,'NLSSA900004','Clínica Familiar Apodaca','clinica','8183004000','Av. Miguel Alemán','455','Centro de Apodaca','66600','activa','2025-11-12 09:00-06'),
( 5,'NLSSA900005','Clínica Cumbres','clinica','8183005000','Av. Paseo de los Leones','880','Cumbres','64700','activa','2025-11-15 09:00-06'),
( 6,'NLSSA900006','Clínica del Valle','clinica','8183006000','Calzada del Valle','410','Del Valle','66220','activa','2025-11-20 09:00-06'),
( 7,'NLSSA900007','Laboratorio Diagnóstica del Norte','laboratorio','8183007000','Av. Universidad','1200','Anáhuac','66450','activa','2025-12-01 09:00-06'),
( 8,'NLSSA900008','Laboratorio BioAnálisis','laboratorio','8183008000','Av. Benito Juárez','760','Centro de Guadalupe','67100','activa','2025-12-03 09:00-06'),
( 9,'NLSSA900009','Clínica Santa Catarina','clinica','8183009000','Blvd. Díaz Ordaz','300','La Fama','66350','suspendida','2025-12-10 09:00-06'),
(10,'NLSSA900010','Hospital General Escobedo','hospital','8183010000','Av. Raúl Salinas','150','Centro de Escobedo','66050','inactiva','2025-12-15 09:00-06');

-- Contactos de organización (11): la organización 1 tiene dos contactos.
INSERT INTO contacto_organizacion (id_organizacion, nombre, puesto, telefono, correo, es_principal) VALUES
( 1,'Ing. Samuel Garza Ochoa','Jefe de Sistemas','8183001010','sistemas@hun.example.mx',TRUE),
( 1,'Lic. Rocío Peña Villarreal','Archivo Clínico','8183001020','archivo@hun.example.mx',FALSE),
( 2,'Ing. Paola Treviño Ríos','Coordinadora de TI','8183002010','ti@hsg.example.mx',TRUE),
( 3,'Ing. Mauricio Leal Cantú','Jefe de Informática','8183003010','informatica@hlr.example.mx',TRUE),
( 4,'Dra. Irma Salazar Ibarra','Directora Médica','8183004010','direccion@cfa.example.mx',TRUE),
( 5,'Lic. Óscar Rangel Paz','Administrador','8183005010','admin@ccu.example.mx',TRUE),
( 6,'Ing. Carolina Ruiz Garza','Analista de Sistemas','8183006010','sistemas@cdv.example.mx',TRUE),
( 7,'QFB. Hugo Morales Lara','Gerente de Calidad','8183007010','calidad@ldn.example.mx',TRUE),
( 8,'QFB. Nadia Ortega Sáenz','Jefa de Laboratorio','8183008010','lab@lba.example.mx',TRUE),
( 9,'Lic. Tomás Ávila Rocha','Administrador','8183009010','admin@csc.example.mx',TRUE),
(10,'Ing. Fabiola Durán Cruz','Sistemas','8183010010','sistemas@hge.example.mx',TRUE);

-- Sistemas de origen (12): uno por organización, más el portal del hub (11)
-- y el sistema de laboratorio interno del hospital 1 (12).
INSERT INTO sistema_origen (id_sistema_origen, id_organizacion, nombre_sistema, tipo_sistema, version_sistema, uri_identificador, estado)
OVERRIDING SYSTEM VALUE VALUES
( 1, 1,'HIS Norte','hospitalario','4.2','urn:hun:expediente','activo'),
( 2, 2,'MediSys San Gabriel','hospitalario','2.8','urn:hsg:expediente','activo'),
( 3, 3,'Ribera ECE','expediente_clinico','1.9','urn:hlr:expediente','activo'),
( 4, 4,'ECE Apodaca','expediente_clinico','3.1','urn:cfa:expediente','activo'),
( 5, 5,'Cumbres Clínico','expediente_clinico','1.4','urn:ccu:expediente','activo'),
( 6, 6,'ValleMed','expediente_clinico','2.0','urn:cdv:expediente','activo'),
( 7, 7,'LIS Diagnóstica','laboratorio','5.0','urn:ldn:laboratorio','activo'),
( 8, 8,'BioLIS','laboratorio','3.3','urn:lba:laboratorio','activo'),
( 9, 9,'SC Expediente','expediente_clinico','1.0','urn:csc:expediente','inactivo'),
(10,10,'HGE Hospitalario','hospitalario','2.2','urn:hge:expediente','inactivo'),
(11, 1,'Portal Flojorama','portal_hub','1.0','urn:flojorama:portal','activo'),
(12, 1,'LIS Norte','laboratorio','2.5','urn:hun:laboratorio','activo');


-- ------------------------------------------------------------
-- PROFESIONALES
-- ------------------------------------------------------------

-- Profesionales (12). El 11 está inactivo; el 12 no tiene encuentros.
INSERT INTO profesional_salud (id_profesional, cedula_profesional, nombre, apellido_paterno, apellido_materno, activo)
OVERRIDING SYSTEM VALUE VALUES
( 1,'9100101','Carlos','Garza','Treviño',TRUE),
( 2,'9100102','Laura','Salinas','Cantú',TRUE),
( 3,'9100103','Javier','Elizondo','Leal',TRUE),
( 4,'9100104','Rosa María','Villarreal','Garza',TRUE),
( 5,'9100105','Antonio','Cavazos','Ríos',TRUE),
( 6,'9100106','Silvia','Montemayor','Sada',TRUE),
( 7,'9100107','Manuel','Zambrano','Lozano',TRUE),
( 8,'9100108','Teresa','Benavides','Garza',TRUE),
( 9,'9100109','Francisco','Quiroga','Treviño',TRUE),
(10,'9100110','Beatriz','Saldaña','Ochoa',TRUE),
(11,'9100111','Ernesto','Tamez','Garza',FALSE),
(12,'9100112','Andrea','Lozano','Cárdenas',TRUE);

-- Vínculos profesional-organización (15). El profesional 1 trabaja en dos instituciones.
INSERT INTO profesional_organizacion (id_profesional, id_organizacion, rol, fecha_inicio, fecha_fin) VALUES
( 1, 1,'medico_tratante','2020-02-01',NULL),
( 1, 4,'medico_tratante','2023-08-15',NULL),
( 2, 1,'medico_guardia','2021-05-10',NULL),
( 3, 2,'medico_tratante','2019-01-07',NULL),
( 4, 2,'jefe_servicio','2018-03-01',NULL),
( 5, 3,'medico_tratante','2022-06-20',NULL),
( 5, 9,'medico_tratante','2021-01-01','2025-12-31'),
( 6, 4,'medico_tratante','2020-09-01',NULL),
( 7, 5,'medico_tratante','2021-11-15',NULL),
( 8, 6,'medico_tratante','2017-04-03',NULL),
( 9, 3,'medico_guardia','2023-02-01',NULL),
(10, 7,'quimico_laboratorista','2019-10-01',NULL),
(10, 8,'quimico_laboratorista','2024-01-15',NULL),
(11, 2,'medico_tratante','2015-03-01','2025-06-30'),
(12, 5,'medico_guardia','2025-09-01',NULL);

-- Especialidades (13). El profesional 1 tiene dos.
INSERT INTO profesional_especialidad (id_profesional, especialidad, cedula_especialidad) VALUES
( 1,'Medicina Interna','E9200101'),
( 1,'Endocrinología','E9200102'),
( 2,'Urgencias Médicas','E9200201'),
( 3,'Cardiología','E9200301'),
( 4,'Pediatría','E9200401'),
( 5,'Neumología','E9200501'),
( 6,'Medicina Familiar','E9200601'),
( 7,'Medicina Familiar','E9200701'),
( 8,'Ginecología y Obstetricia','E9200801'),
( 9,'Ortopedia y Traumatología','E9200901'),
(10,'Química Clínica',NULL),
(11,'Cirugía General','E9201101'),
(12,'Endocrinología','E9201201');


-- ------------------------------------------------------------
-- USUARIOS Y CREDENCIALES
-- ------------------------------------------------------------

-- Usuarios (6) con los cuatro roles. Contraseña: Flojorama2026!
-- El usuario 4 está inactivo (para probar acceso denegado).
-- Los médicos (5 y 6) toman su nombre de profesional_salud (3FN).
INSERT INTO usuario (id_usuario, id_profesional, nombre, apellido_paterno, apellido_materno, correo, hash_contrasena, rol, activo, fecha_registro)
OVERRIDING SYSTEM VALUE VALUES
(1,NULL,'Laura','Méndez','Garza','admin@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'administrador',TRUE,'2025-11-01 09:00-06'),
(2,NULL,'Jorge','Treviño','Salinas','analista@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'analista_integracion',TRUE,'2025-11-01 09:05-06'),
(3,NULL,'Mariana','Cantú','Leal','coordinador@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'coordinador',TRUE,'2025-11-01 09:10-06'),
(4,NULL,'Ricardo','Elizondo','Ríos','coordinador2@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'coordinador',FALSE,'2025-11-01 09:15-06'),
(5,1,NULL,NULL,NULL,'medico1@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'medico',TRUE,'2025-11-02 10:00-06'),
(6,3,NULL,NULL,NULL,'medico2@flojorama.mx',crypt('Flojorama2026!',gen_salt('bf',12)),'medico',TRUE,'2025-11-02 10:05-06');

-- Credenciales de sistemas (11). Una activa por sistema como máximo.
INSERT INTO credencial_sistema (id_sistema_origen, id_usuario_emision, hash_clave, fecha_emision, fecha_expiracion, estado) VALUES
( 1,1,crypt('clave-sistema-1-2025',gen_salt('bf')),'2025-01-01','2026-01-01','revocada'),
( 1,1,crypt('clave-sistema-1',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 2,1,crypt('clave-sistema-2',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 3,1,crypt('clave-sistema-3',gen_salt('bf')),'2026-01-01','2026-11-10','activa'),
( 4,1,crypt('clave-sistema-4',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 5,1,crypt('clave-sistema-5',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 6,1,crypt('clave-sistema-6',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 7,1,crypt('clave-sistema-7',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 8,1,crypt('clave-sistema-8',gen_salt('bf')),'2026-01-01','2027-01-01','activa'),
( 9,1,crypt('clave-sistema-9',gen_salt('bf')),'2026-01-01','2027-01-01','revocada'),
(10,1,crypt('clave-sistema-10',gen_salt('bf')),'2025-01-01','2026-01-01','expirada'),
(12,1,crypt('clave-sistema-12',gen_salt('bf')),'2026-01-01','2027-01-01','activa');


-- ------------------------------------------------------------
-- PACIENTES
-- ------------------------------------------------------------

-- Pacientes maestros (32).
--  27 = baja lógica (inactivo) con historial clínico.
--  30 = posible duplicado de 17; 31 = posible duplicado de 5.
--  32 = ya fusionado en 6.
INSERT INTO paciente_maestro (id_paciente_maestro, curp, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, estado, id_paciente_fusionado_en, fecha_registro)
OVERRIDING SYSTEM VALUE VALUES
( 1,'GATJ850312HNLRRS01','José Luis','García','Treviño','1985-03-12','masculino','activo',NULL,'2026-01-02 09:00-06'),
( 2,'LOGM900725MNLPRR02','María Fernanda','López','Garza','1990-07-25','femenino','activo',NULL,'2026-01-02 09:05-06'),
( 3,'MASJ781102HNLRLN03','Juan Carlos','Martínez','Salinas','1978-11-02','masculino','activo',NULL,'2026-01-02 09:10-06'),
( 4,'HECA950118MNLRNN04','Ana Sofía','Hernández','Cantú','1995-01-18','femenino','activo',NULL,'2026-01-02 09:15-06'),
( 5,'ROLL820930HNLDLS05','Luis Alberto','Rodríguez','Leal','1982-09-30','masculino','activo',NULL,'2026-01-02 09:20-06'),
( 6,'GOVP750414MNLNLT06','Patricia','González','Villarreal','1975-04-14','femenino','activo',NULL,'2026-01-02 09:25-06'),
( 7,'PEEM681205HNLRLG07','Miguel Ángel','Pérez','Elizondo','1968-12-05','masculino','activo',NULL,'2026-01-02 09:30-06'),
( 8,'SARD010621MNLNSN08','Daniela','Sánchez','Ríos','2001-06-21','femenino','activo',NULL,'2026-01-02 09:35-06'),
( 9,'RAGR590208HNLMRB09','Roberto','Ramírez','Guerra','1959-02-08','masculino','activo',NULL,'2026-01-02 09:40-06'),
(10,'TOMG881011MNLRDB10','Gabriela','Torres','Medina','1988-10-11','femenino','activo',NULL,'2026-01-02 09:45-06'),
(11,'FOGF720819HNLLRR11','Fernando','Flores','Garza','1972-08-19','masculino','activo',NULL,'2026-01-02 09:50-06'),
(12,'RIMC930303MNLVNL12','Claudia','Rivera','Montemayor','1993-03-03','femenino','activo',NULL,'2026-01-02 09:55-06'),
(13,'GOZH640527HNLMMC13','Héctor','Gómez','Zambrano','1964-05-27','masculino','activo',NULL,'2026-01-02 10:00-06'),
(14,'DIOV801216MNLZCR14','Verónica','Díaz','Ochoa','1980-12-16','femenino','activo',NULL,'2026-01-02 10:05-06'),
(15,'CUBA050909HNLRNL15','Alejandro','Cruz','Benavides','2005-09-09','masculino','activo',NULL,'2026-01-02 10:10-06'),
(16,'MOSM990404MNLRLN16','Mónica','Morales','Saldaña','1999-04-04','femenino','activo',NULL,'2026-01-02 10:15-06'),
(17,'OICR550707HNLRVC17','Ricardo','Ortiz','Cavazos','1955-07-07','masculino','activo',NULL,'2026-01-03 09:00-06'),
(18,'RETL100214MNLYMC18','Lucía','Reyes','Tamez','2010-02-14','femenino','activo',NULL,'2026-01-03 09:05-06'),
(19,'JIRE871123HNLMCD19','Eduardo','Jiménez','Rocha','1987-11-23','masculino','activo',NULL,'2026-01-03 09:10-06'),
(20,'VAMS700129MNLZLN20','Sandra','Vázquez','Maldonado','1970-01-29','femenino','activo',NULL,'2026-01-03 09:15-06'),
(21,'CAPA920606HNLSXR21','Arturo','Castillo','Peña','1992-06-06','masculino','activo',NULL,'2026-01-03 09:20-06'),
(22,'NAGE830808MNLVTL22','Elena','Navarro','Gutiérrez','1983-08-08','femenino','activo',NULL,'2026-01-03 09:25-06'),
(23,'MEAO770321HNLNGS23','Óscar','Mendoza','Aguilar','1977-03-21','masculino','activo',NULL,'2026-01-03 09:30-06'),
(24,'HELK981201MNLRNR24','Karla','Herrera','Luna','1998-12-01','femenino','activo',NULL,'2026-01-03 09:35-06'),
(25,'MESR611030HNLDLL25','Raúl','Medina','Solís','1961-10-30','masculino','activo',NULL,'2026-01-03 09:40-06'),
(26,'CAPA860515MNLSND26','Adriana','Castro','Pineda','1986-05-15','femenino','activo',NULL,'2026-01-03 09:45-06'),
(27,'VAFS500917HNLRNR27','Sergio','Vargas','Fuentes','1950-09-17','masculino','inactivo',NULL,'2026-01-03 09:50-06'),
(28,'ROIP030712MNLMBL28','Paola','Romero','Ibarra','2003-07-12','femenino','activo',NULL,'2026-01-03 09:55-06'),
(29,'AURD960228HNLGBG29','Diego','Aguilar','Robles','1996-02-28','masculino','activo',NULL,'2026-01-03 10:00-06'),
(30,NULL,'Ricardo','Ortiz',NULL,'1955-07-07','masculino','activo',NULL,'2026-01-03 10:05-06'),
(31,NULL,'Luis','Rodríguez','Leal','1982-09-30','masculino','activo',NULL,'2026-01-03 10:10-06'),
(32,NULL,'Patricia','Gonzalez','Villarreal','1975-04-14','femenino','fusionado',6,'2026-01-03 10:15-06');


-- ------------------------------------------------------------
-- ENCUENTROS (tabla de trabajo temporal)
-- 50 encuentros generados con reglas fijas, para que el script siempre
-- produzca los mismos datos:
--   * paciente = ciclo 1..27
--   * cada 5.º encuentro es toma de muestra en laboratorio (org 7 u 8)
--   * 44 = urgencias sin profesional; 46 = en curso; 47 = cancelado
--   * 48-50 = consultas planeadas capturadas en el portal por el médico 1
-- ------------------------------------------------------------
CREATE TEMP TABLE tmp_enc ON COMMIT DROP AS
WITH base AS (
  SELECT i,
         ((i - 1) % 27) + 1                         AS paciente,
         (i % 5 = 0 AND i < 48)                     AS es_lab,
         (i >= 48)                                  AS es_planeado,
         ((i - i / 5 - 1) % 10) + 1                 AS k
  FROM generate_series(1, 50) AS i
), asignado AS (
  SELECT b.*,
         CASE WHEN es_planeado THEN 1
              WHEN es_lab THEN 10
              WHEN i = 44 THEN NULL
              ELSE (ARRAY[1,2,3,4,5,6,7,8,9,1])[k] END            AS profesional,
         CASE WHEN es_planeado THEN 1
              WHEN es_lab THEN CASE WHEN (i / 5) % 2 = 1 THEN 7 ELSE 8 END
              ELSE (ARRAY[1,1,2,2,3,4,5,6,3,4])[k] END             AS organizacion,
         CASE WHEN es_lab THEN 'toma_muestra'
              WHEN i = 13 THEN 'hospitalizacion'
              WHEN i % 7 = 0 OR i = 44 THEN 'urgencias'
              ELSE 'consulta_externa' END                           AS tipo,
         CASE WHEN es_planeado THEN 'planeado'
              WHEN i = 47 THEN 'cancelado'
              WHEN i = 46 THEN 'en_curso'
              ELSE 'finalizado' END                                 AS estado,
         CASE WHEN es_planeado THEN TIMESTAMPTZ '2026-10-21 09:00-06' + (i - 48) * INTERVAL '1 day'
              WHEN i = 46 THEN TIMESTAMPTZ '2026-10-16 10:30-06'
              ELSE TIMESTAMPTZ '2026-01-05 08:00-06' + i * INTERVAL '4 days' + (i % 8) * INTERVAL '1 hour'
         END                                                        AS fecha_inicio
  FROM base b
)
SELECT a.*,
       CASE WHEN es_planeado THEN 11 ELSE organizacion END          AS sistema,
       CASE WHEN estado <> 'finalizado' THEN NULL
            WHEN tipo = 'hospitalizacion' THEN fecha_inicio + INTERVAL '3 days'
            WHEN tipo = 'urgencias' THEN fecha_inicio + INTERVAL '4 hours'
            WHEN tipo = 'toma_muestra' THEN fecha_inicio + INTERVAL '20 minutes'
            ELSE fecha_inicio + INTERVAL '45 minutes' END           AS fecha_fin,
       CASE WHEN es_planeado THEN TIMESTAMPTZ '2026-10-15 12:00-06' + (i - 48) * INTERVAL '1 hour'
            WHEN i = 46 THEN fecha_inicio + INTERVAL '30 minutes'
            ELSE fecha_inicio + INTERVAL '2 hours' END              AS fecha_recepcion,
       CASE WHEN es_lab THEN 'Toma de muestra para estudios de laboratorio'
            WHEN tipo = 'hospitalizacion' THEN 'Ingreso por descontrol glucémico'
            WHEN tipo = 'urgencias' THEN (ARRAY['Dolor abdominal agudo','Fiebre persistente','Crisis asmática','Torcedura de tobillo'])[(i % 4) + 1]
            ELSE (ARRAY['Control de enfermedad crónica','Revisión de resultados','Malestar general','Dolor lumbar','Tos y dolor de garganta','Seguimiento de tratamiento','Chequeo anual','Molestias gástricas'])[(i % 8) + 1]
       END                                                          AS motivo
FROM asignado a;

-- Recursos clínicos (temporal): un registro por cada dato que llegó en
-- algún paquete. El id se usa igual para detalle_transaccion y procedencia_dato.
--   1-50 Encounter | 101-150 / 151-200 Condition | 201-250 Observation (signo vital)
--   255-295 / 355-395 Observation (laboratorio) | 305-345 DiagnosticReport
--   401-450 MedicationRequest | 453-495 Observation (presión arterial)
CREATE TEMP TABLE tmp_rec (
  id BIGINT PRIMARY KEY, i INT, tipo_recurso VARCHAR(25), ruta VARCHAR(150),
  valor TEXT, codigo VARCHAR(40)
) ON COMMIT DROP;

-- Encuentros
INSERT INTO tmp_rec
SELECT i, i, 'Encounter', 'Encounter', tipo || ' - ' || motivo, NULL FROM tmp_enc;

-- Diagnóstico principal y secundario (encuentros clínicos finalizados o en curso)
INSERT INTO tmp_rec
SELECT 100 + i, i, 'Condition', 'Condition.code', c.descripcion, c.codigo
FROM tmp_enc e JOIN catalogo_codigo c ON c.id_codigo = (i % 10) + 1
WHERE NOT es_lab AND estado IN ('finalizado','en_curso');

INSERT INTO tmp_rec
SELECT 150 + i, i, 'Condition', 'Condition.code', c.descripcion, c.codigo
FROM tmp_enc e JOIN catalogo_codigo c ON c.id_codigo = ((i + 4) % 10) + 1
WHERE NOT es_lab AND estado IN ('finalizado','en_curso') AND i % 3 = 0;

-- Signos vitales
INSERT INTO tmp_rec
SELECT 200 + i, i, 'Observation', 'Observation.valueQuantity', 'FC ' || (62 + (i * 7) % 45) || ' lpm', 'FC'
FROM tmp_enc WHERE NOT es_lab AND estado IN ('finalizado','en_curso');

INSERT INTO tmp_rec
SELECT 450 + i, i, 'Observation', 'Observation.valueString', 'TA ' || (110 + i % 30) || '/' || (70 + i % 15), 'TA'
FROM tmp_enc WHERE NOT es_lab AND estado IN ('finalizado','en_curso') AND i % 3 = 0;

-- Estudios de laboratorio y sus resultados
INSERT INTO tmp_rec
SELECT 300 + i, i, 'DiagnosticReport', 'DiagnosticReport.code',
       CASE WHEN organizacion = 7 THEN 'Panel metabólico' ELSE 'Biometría hemática' END,
       CASE WHEN organizacion = 7 THEN 'PMC' ELSE 'BH' END
FROM tmp_enc WHERE es_lab;

INSERT INTO tmp_rec
SELECT 250 + i, i, 'Observation', 'Observation.valueQuantity',
       CASE WHEN organizacion = 7 THEN 'Glucosa' ELSE 'Hemoglobina' END,
       CASE WHEN organizacion = 7 THEN 'GLU' ELSE 'HB' END
FROM tmp_enc WHERE es_lab;

INSERT INTO tmp_rec
SELECT 350 + i, i, 'Observation', 'Observation.valueQuantity',
       CASE WHEN organizacion = 7 THEN 'Creatinina' ELSE 'Leucocitos' END,
       CASE WHEN organizacion = 7 THEN 'CREA' ELSE 'LEUCO' END
FROM tmp_enc WHERE es_lab;

-- Medicamentos (encuentros finalizados pares)
INSERT INTO tmp_rec
SELECT 400 + i, i, 'MedicationRequest', 'MedicationRequest.medicationCodeableConcept', c.descripcion, c.codigo
FROM tmp_enc e
JOIN catalogo_codigo c ON c.id_codigo = (ARRAY[28,29,27,34,31,33,32,30,28,27])[(i % 10) + 1]
WHERE NOT es_lab AND estado = 'finalizado' AND i % 2 = 0;


-- ------------------------------------------------------------
-- TRANSACCIONES DE INTEROPERABILIDAD
-- ------------------------------------------------------------

-- Paquetes 1-50: uno por encuentro (los 48-50 son capturas del portal).
INSERT INTO paquete_transaccion (id_paquete, id_sistema_origen, id_usuario_captura, direccion, tipo_paquete, fecha_recepcion, estado, hash_paquete)
OVERRIDING SYSTEM VALUE
SELECT i, sistema,
       CASE WHEN es_planeado THEN 5 END,
       'entrante',
       CASE WHEN es_planeado THEN 'captura_portal' ELSE 'transaccion' END,
       fecha_recepcion, 'procesado',
       encode(sha256(convert_to('paquete-' || i, 'UTF8')), 'hex')
FROM tmp_enc;

-- Paquetes 51-58: datos demográficos, conflictos, errores, reenvío y salida.
INSERT INTO paquete_transaccion (id_paquete, id_sistema_origen, id_usuario_captura, direccion, tipo_paquete, fecha_recepcion, estado, hash_paquete)
OVERRIDING SYSTEM VALUE VALUES
(51, 1,NULL,'entrante','transaccion','2026-01-02 08:30-06','procesado',            encode(sha256(convert_to('paquete-51','UTF8')),'hex')),
(52, 4,NULL,'entrante','transaccion','2026-01-03 08:30-06','procesado',            encode(sha256(convert_to('paquete-52','UTF8')),'hex')),
(53, 2,NULL,'entrante','mensaje',    '2026-08-10 11:00-06','procesado',            encode(sha256(convert_to('paquete-53','UTF8')),'hex')),
(54, 5,NULL,'entrante','transaccion','2026-09-01 13:20-06','procesado_con_errores',encode(sha256(convert_to('paquete-54','UTF8')),'hex')),
(55, 6,NULL,'entrante','transaccion','2026-09-05 16:45-06','rechazado',            encode(sha256(convert_to('paquete-55','UTF8')),'hex')),
(56, 1,NULL,'entrante','transaccion','2026-09-12 07:10-06','procesado',            encode(sha256(convert_to('paquete-56','UTF8')),'hex')),
(57, 3,NULL,'saliente','consulta',   '2026-09-20 12:00-06','enviado',              encode(sha256(convert_to('paquete-57','UTF8')),'hex')),
(58, 9,NULL,'entrante','transaccion','2026-09-25 09:00-06','rechazado',            encode(sha256(convert_to('paquete-58','UTF8')),'hex'));
-- El paquete 58 se rechazó completo (institución suspendida): no tiene detalles.

-- Detalles de los recursos clínicos (uno por recurso de tmp_rec).
INSERT INTO detalle_transaccion (id_detalle, id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso, fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
OVERRIDING SYSTEM VALUE
SELECT r.id, e.i, e.paciente, r.tipo_recurso,
       r.tipo_recurso || '-' || e.sistema || '-' || r.id, '1', e.fecha_inicio,
       'integrado',
       encode(sha256(convert_to('recurso-' || r.id, 'UTF8')), 'hex'),
       e.fecha_recepcion + INTERVAL '1 minute'
FROM tmp_rec r JOIN tmp_enc e ON e.i = r.i;

-- Detalles Patient (501-532) y AllergyIntolerance (801-827) de los paquetes 51 y 52.
INSERT INTO detalle_transaccion (id_detalle, id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso, fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
OVERRIDING SYSTEM VALUE
SELECT 500 + p, CASE WHEN p <= 16 THEN 51 ELSE 52 END,
       CASE WHEN p = 32 THEN 6 ELSE p END,
       'Patient', 'Patient-' || CASE WHEN p <= 16 THEN 1 ELSE 4 END || '-' || p, '1',
       TIMESTAMPTZ '2025-12-15 10:00-06', 'integrado',
       encode(sha256(convert_to('recurso-' || (500 + p), 'UTF8')), 'hex'),
       CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 32) AS p;

INSERT INTO detalle_transaccion (id_detalle, id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso, fecha_recurso_origen, estado, hash_recurso, fecha_procesamiento)
OVERRIDING SYSTEM VALUE
SELECT 800 + p, CASE WHEN p <= 16 THEN 51 ELSE 52 END, p,
       'AllergyIntolerance', 'AllergyIntolerance-' || CASE WHEN p <= 16 THEN 1 ELSE 4 END || '-' || p, '1',
       TIMESTAMPTZ '2025-12-15 10:00-06', 'integrado',
       encode(sha256(convert_to('recurso-' || (800 + p), 'UTF8')), 'hex'),
       CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 27) AS p;

-- Detalles especiales (901-908).
INSERT INTO detalle_transaccion (id_detalle, id_paquete, id_paciente_maestro, tipo_recurso, id_recurso_externo, version_recurso, fecha_recurso_origen, id_detalle_original, estado, hash_recurso, fecha_procesamiento)
OVERRIDING SYSTEM VALUE VALUES
-- Paquete 53 (Hospital San Gabriel): datos que contradicen lo ya integrado.
(901,53,3,'AllergyIntolerance','AllergyIntolerance-2-3','1','2026-08-09 18:00-06',NULL,'integrado',encode(sha256(convert_to('recurso-901','UTF8')),'hex'),'2026-08-10 11:01-06'),
(902,53,8,'Patient','Patient-2-8','3','2026-08-09 18:00-06',NULL,'integrado',encode(sha256(convert_to('recurso-902','UTF8')),'hex'),'2026-08-10 11:01-06'),
-- Paquete 54 (Clínica Cumbres): dos recursos con errores, pendientes de decisión del analista.
(903,54,NULL,'Observation','Observation-5-X1','1','2026-09-01 12:00-06',NULL,'recibido',encode(sha256(convert_to('recurso-903','UTF8')),'hex'),NULL),
(904,54,NULL,'Condition','Condition-5-X2','1','2026-09-01 12:00-06',NULL,'recibido',encode(sha256(convert_to('recurso-904','UTF8')),'hex'),NULL),
-- Paquete 55 (Clínica del Valle): paciente sin fecha de nacimiento y sin consentimiento.
(905,55,NULL,'Patient','Patient-6-X3','1','2026-09-05 16:00-06',NULL,'rechazado',encode(sha256(convert_to('recurso-905','UTF8')),'hex'),'2026-09-05 16:46-06'),
-- Paquete 56 (Hospital Universitario del Norte): reenvío del encuentro 1 y corrección de una observación.
(906,56,1,'Encounter','Encounter-1-1','1','2026-01-09 09:00-06',1,'duplicado',encode(sha256(convert_to('recurso-1','UTF8')),'hex'),'2026-09-12 07:11-06'),
(908,56,1,'Observation','Observation-1-201','2','2026-09-11 18:00-06',NULL,'integrado',encode(sha256(convert_to('recurso-908','UTF8')),'hex'),'2026-09-12 07:11-06'),
-- Paquete 57: consulta saliente del expediente del paciente 1 hacia Hospital La Ribera.
(907,57,1,'Patient','Patient-hub-1','1','2026-09-20 12:00-06',NULL,'enviado',encode(sha256(convert_to('recurso-907','UTF8')),'hex'),'2026-09-20 12:00-06');

-- Errores de validación (7)
INSERT INTO error_validacion (id_detalle, codigo_error, severidad, ruta_elemento, descripcion) VALUES
(903,'codigo_desconocido','fatal','Observation.code','El código local GLX-99 no tiene mapeo a LOINC.'),
(903,'formato','advertencia','Observation.valueQuantity.unit','Unidad "mgdl" sin formato UCUM.'),
(904,'formato','error','Condition.onsetDateTime','Fecha "31/02/2026" inválida.'),
(905,'requerido','fatal','Patient.birthDate','Falta la fecha de nacimiento.'),
(905,'sin_consentimiento','fatal','Patient','El paciente no tiene consentimiento vigente para enviar información.'),
(906,'duplicado','informativo','Encounter','Reenvío del mismo recurso y versión; se conserva la primera copia.'),
(201,'formato','advertencia','Observation.valueQuantity.unit','Unidad "LPM" normalizada a "lpm".');


-- ------------------------------------------------------------
-- PROCEDENCIA DE LOS DATOS
-- ------------------------------------------------------------

-- Procedencia de cada recurso clínico (mismo id que su detalle).
INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, codigo_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE
SELECT r.id, r.id, r.ruta, r.valor, r.codigo, e.fecha_inicio, e.fecha_recepcion
FROM tmp_rec r JOIN tmp_enc e ON e.i = r.i;

-- Procedencia de datos demográficos: nombre (501-532), teléfono (601-632),
-- dirección (701-732) y alergia (801-827).
INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE
SELECT 500 + p, 500 + p, 'Patient.name', upper(nombre || ' ' || apellido_paterno || coalesce(' ' || apellido_materno, '')),
       TIMESTAMPTZ '2025-12-15 10:00-06', CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM paciente_maestro pm JOIN generate_series(1, 32) AS p ON p = pm.id_paciente_maestro;

INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE
SELECT 600 + p, 500 + p, 'Patient.telecom', 'tel: ' || CASE WHEN p = 31 THEN 5 ELSE p END,
       TIMESTAMPTZ '2025-12-15 10:00-06', CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 32) AS p;

INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE
SELECT 700 + p, 500 + p, 'Patient.address', 'domicilio ' || CASE WHEN p = 30 THEN 17 ELSE p END,
       TIMESTAMPTZ '2025-12-15 10:00-06', CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 32) AS p;

INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, codigo_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE
SELECT 800 + p, 800 + p, 'AllergyIntolerance.code',
       CASE WHEN p % 4 = 0 THEN 'NINGUNA' ELSE c.descripcion END,
       CASE WHEN p % 4 = 0 THEN NULL ELSE c.codigo END,
       TIMESTAMPTZ '2025-12-15 10:00-06', CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 27) AS p
JOIN catalogo_codigo c ON c.id_codigo = 37 + ((p + 7) % 10);

-- Procedencias especiales: correo de 6 y 32 (633, 634) y datos del paquete 53 (901, 902).
INSERT INTO procedencia_dato (id_procedencia, id_detalle, ruta_elemento, valor_original, codigo_original, fecha_origen, fecha_recepcion)
OVERRIDING SYSTEM VALUE VALUES
(633,506,'Patient.telecom','paty.gonzalez@correo.example','', '2025-12-15 10:00-06','2026-01-02 08:31-06'),
(634,532,'Patient.telecom','PATY.GONZALEZ@CORREO.EXAMPLE','', '2025-12-15 10:00-06','2026-01-03 08:31-06'),
(901,901,'AllergyIntolerance.code','NEGADAS',NULL,'2026-08-09 18:00-06','2026-08-10 11:01-06'),
(902,902,'Patient.telecom','tel: 8187654321',NULL,'2026-08-09 18:00-06','2026-08-10 11:01-06');

-- Teléfono del paciente 31 = teléfono del 5; dirección del 30 = dirección del 17.
-- (valor_original ya lo refleja arriba).


-- ------------------------------------------------------------
-- IDENTIDAD DEL PACIENTE
-- ------------------------------------------------------------

-- Nombres reportados (32). El nombre del 32 quedó ligado al 6 tras la fusión.
INSERT INTO nombre_paciente (id_paciente_maestro, id_procedencia, nombre, apellido_paterno, apellido_materno, uso)
SELECT CASE WHEN id_paciente_maestro = 32 THEN 6 ELSE id_paciente_maestro END,
       500 + id_paciente_maestro, nombre, apellido_paterno, apellido_materno,
       CASE WHEN id_paciente_maestro = 32 THEN 'alias' ELSE 'oficial' END
FROM paciente_maestro;

-- Teléfonos (32) y correos (2). El teléfono del 8 quedó como histórico (conflicto resuelto).
INSERT INTO contacto_paciente (id_paciente_maestro, id_procedencia, tipo_contacto, valor, uso, vigente)
SELECT CASE WHEN p = 32 THEN 6 ELSE p END, 600 + p, 'telefono',
       '81' || lpad(((CASE WHEN p = 31 THEN 5 ELSE p END) * 7919 % 100000000)::text, 8, '0'),
       CASE WHEN p % 3 = 0 THEN 'casa' ELSE 'movil' END,
       (p <> 8)
FROM generate_series(1, 32) AS p;

INSERT INTO contacto_paciente (id_paciente_maestro, id_procedencia, tipo_contacto, valor, uso, vigente) VALUES
(6,633,'correo','paty.gonzalez@correo.example','casa',TRUE),
(6,634,'correo','paty.gonzalez@correo.example','casa',FALSE),
(8,902,'telefono','8187654321','movil',TRUE);

-- Direcciones (32). La del 30 es la misma que la del 17.
INSERT INTO direccion_paciente (id_paciente_maestro, id_procedencia, calle, numero_exterior, numero_interior, colonia, codigo_postal, uso)
SELECT CASE WHEN p = 32 THEN 6 ELSE p END, 700 + p,
       (ARRAY['Calle Hidalgo','Av. Lincoln','Calle Zaragoza','Av. Ruiz Cortines','Calle Morelos','Av. Sendero','Calle Allende','Av. Las Torres','Calle Juárez','Av. Fidel Velázquez'])[(q % 10) + 1],
       ((q * 37) % 900 + 100)::text,
       CASE WHEN q % 6 = 0 THEN 'A' END,
       (ARRAY['Centro','Mitras Centro','Obispado','Cumbres','Del Valle','La Fama','Anáhuac','Las Puentes','Centro de Apodaca','Centro de Guadalupe','Centro de Escobedo','Lomas'])[(q % 12) + 1],
       (ARRAY['64000','64460','64620','64700','66220','66350','66450','66400','66600','67100','66050','66260'])[(q % 12) + 1],
       'domicilio'
FROM (SELECT p, CASE WHEN p = 30 THEN 17 ELSE p END AS q FROM generate_series(1, 32) AS p) s;

-- Identificadores institucionales.
-- a) Expediente de alta: sistema 1 para pacientes 1-16 y sistema 4 para 17-32.
INSERT INTO identificador_paciente (id_paciente_maestro, id_sistema_origen, valor_identificador, tipo_identificador, uso, fecha_alta)
SELECT CASE WHEN p = 32 THEN 6 ELSE p END,
       CASE WHEN p <= 16 THEN 1 ELSE 4 END,
       CASE WHEN p <= 16 THEN 'HUN-' ELSE 'CFA-' END || lpad(p::text, 6, '0'),
       'expediente', 'oficial',
       CASE WHEN p <= 16 THEN TIMESTAMPTZ '2026-01-02 08:31-06' ELSE TIMESTAMPTZ '2026-01-03 08:31-06' END
FROM generate_series(1, 32) AS p;

-- b) Identificador en cada otra institución donde el paciente tuvo un encuentro.
INSERT INTO identificador_paciente (id_paciente_maestro, id_sistema_origen, valor_identificador, tipo_identificador, uso, fecha_alta)
SELECT DISTINCT ON (e.paciente, e.sistema)
       e.paciente, e.sistema,
       (ARRAY['HUN','HSG','HLR','CFA','CCU','CDV','LDN','LBA'])[e.sistema] || '-' || lpad(e.paciente::text, 6, '0'),
       CASE WHEN e.sistema IN (7, 8) THEN 'laboratorio' ELSE 'expediente' END,
       'oficial', e.fecha_recepcion
FROM tmp_enc e
WHERE e.sistema <> 11
  AND NOT (e.sistema = 1 AND e.paciente <= 16)
  AND NOT (e.sistema = 4 AND e.paciente > 16)
ORDER BY e.paciente, e.sistema, e.fecha_recepcion;

-- c) NSS de los pacientes 1-10 y un expediente antiguo del paciente 2.
INSERT INTO identificador_paciente (id_paciente_maestro, id_sistema_origen, valor_identificador, tipo_identificador, uso, fecha_alta)
SELECT p, 1, '4318' || lpad((p * 104729)::text, 7, '0'), 'nss', 'secundario', TIMESTAMPTZ '2026-01-02 08:31-06'
FROM generate_series(1, 10) AS p;

INSERT INTO identificador_paciente (id_paciente_maestro, id_sistema_origen, valor_identificador, tipo_identificador, uso, fecha_alta)
VALUES (2, 1, 'HUN-OLD-8812', 'expediente', 'antiguo', '2026-01-02 08:31-06');

-- Candidatos a duplicado (3).
INSERT INTO candidato_duplicado (id_paciente_a, id_paciente_b, coincide_identificador, coincide_nombre_fecha, coincide_telefono, coincide_correo, coincide_direccion, fecha_deteccion, estado, id_usuario_resolucion, fecha_resolucion, justificacion) VALUES
( 5,31,FALSE,TRUE,TRUE,FALSE,FALSE,'2026-01-03 10:11-06','pendiente',NULL,NULL,NULL),
( 6,32,FALSE,TRUE,FALSE,TRUE,FALSE,'2026-01-03 10:16-06','fusionado',3,'2026-01-05 12:00-06','Mismo nombre, fecha de nacimiento y correo; se confirmó con la paciente por teléfono.'),
(17,30,FALSE,TRUE,FALSE,FALSE,TRUE,'2026-01-03 10:06-06','pendiente',NULL,NULL,NULL);


-- ------------------------------------------------------------
-- INFORMACIÓN CLÍNICA
-- ------------------------------------------------------------

-- Mapeos de códigos locales (12)
INSERT INTO mapeo_codigo (id_sistema_origen, codigo_local, descripcion_local, id_codigo) VALUES
(1,'DM2','Diabetes tipo 2',1),
(1,'HTA','Hipertensión arterial',2),
(1,'FC','Frecuencia cardiaca',13),
(1,'TA','Tensión arterial',17),
(2,'DIAB-T2','Diabetes mellitus 2',1),
(3,'ASMA','Asma bronquial',7),
(5,'IVU','Infección urinaria',8),
(6,'LUMB','Lumbalgia',6),
(7,'GLU','Glucosa sérica',18),
(7,'CREA','Creatinina',19),
(8,'HB','Hemoglobina',20),
(8,'LEUCO','Leucocitos',24);

-- Encuentros clínicos (50)
INSERT INTO encuentro_clinico (id_encuentro, id_paciente_maestro, id_organizacion, id_profesional, id_procedencia, tipo_encuentro, motivo, fecha_inicio, fecha_fin, estado)
OVERRIDING SYSTEM VALUE
SELECT i, paciente, organizacion, profesional, i, tipo, motivo, fecha_inicio, fecha_fin, estado
FROM tmp_enc;

-- Diagnósticos principales y secundarios
INSERT INTO diagnostico (id_encuentro, id_codigo, id_procedencia, tipo, estado_clinico, fecha_diagnostico)
SELECT e.i, (e.i % 10) + 1, 100 + e.i, 'principal',
       CASE WHEN (e.i % 10) + 1 IN (1,2,4,7,9) OR e.estado = 'en_curso' THEN 'activo' ELSE 'resuelto' END,
       e.fecha_inicio::date
FROM tmp_enc e WHERE EXISTS (SELECT 1 FROM tmp_rec r WHERE r.id = 100 + e.i);

INSERT INTO diagnostico (id_encuentro, id_codigo, id_procedencia, tipo, estado_clinico, fecha_diagnostico)
SELECT e.i, ((e.i + 4) % 10) + 1, 150 + e.i, 'secundario',
       CASE WHEN ((e.i + 4) % 10) + 1 IN (1,2,4,7,9) THEN 'activo' ELSE 'resuelto' END,
       e.fecha_inicio::date
FROM tmp_enc e WHERE EXISTS (SELECT 1 FROM tmp_rec r WHERE r.id = 150 + e.i);

-- Estudios de laboratorio
INSERT INTO estudio_diagnostico (id_estudio, id_encuentro, id_codigo, id_profesional_responsable, id_procedencia, fecha_emision, estado, conclusion)
OVERRIDING SYSTEM VALUE
SELECT 300 + i, i, CASE WHEN organizacion = 7 THEN 25 ELSE 26 END, 10, 300 + i,
       fecha_inicio + INTERVAL '1 day',
       CASE WHEN i = 45 THEN 'preliminar' ELSE 'final' END,
       CASE WHEN i = 45 THEN NULL ELSE 'Resultados revisados por química responsable.' END
FROM tmp_enc WHERE es_lab;

-- Observaciones: frecuencia cardiaca (signo vital ligado al encuentro)
INSERT INTO observacion (id_encuentro, id_codigo, id_procedencia, valor_numerico, unidad, rango_ref_min, rango_ref_max, interpretacion, fecha_observacion)
SELECT i, 13, 200 + i, 62 + (i * 7) % 45, 'lpm', 60, 100,
       CASE WHEN 62 + (i * 7) % 45 > 100 THEN 'alto' ELSE 'normal' END,
       fecha_inicio + INTERVAL '10 minutes'
FROM tmp_enc e WHERE EXISTS (SELECT 1 FROM tmp_rec r WHERE r.id = 200 + e.i);

-- Observaciones: presión arterial (valor de texto)
INSERT INTO observacion (id_encuentro, id_codigo, id_procedencia, valor_texto, unidad, interpretacion, fecha_observacion)
SELECT i, 17, 450 + i, (110 + i % 30) || '/' || (70 + i % 15), 'mm[Hg]',
       CASE WHEN 110 + i % 30 >= 130 THEN 'alto' ELSE 'normal' END,
       fecha_inicio + INTERVAL '10 minutes'
FROM tmp_enc e WHERE EXISTS (SELECT 1 FROM tmp_rec r WHERE r.id = 450 + e.i);

-- Observaciones de laboratorio (ligadas al estudio, no al encuentro)
INSERT INTO observacion (id_estudio, id_codigo, id_procedencia, valor_numerico, unidad, rango_ref_min, rango_ref_max, interpretacion, fecha_observacion)
SELECT 300 + i,
       CASE WHEN organizacion = 7 THEN 18 ELSE 20 END,
       250 + i,
       CASE WHEN organizacion = 7 THEN 85 + (i * 3) % 90 ELSE 11.5 + (i % 7) * 0.6 END,
       CASE WHEN organizacion = 7 THEN 'mg/dL' ELSE 'g/dL' END,
       CASE WHEN organizacion = 7 THEN 70 ELSE 12 END,
       CASE WHEN organizacion = 7 THEN 100 ELSE 17.5 END,
       CASE WHEN organizacion = 7 AND 85 + (i * 3) % 90 > 100 THEN 'alto'
            WHEN organizacion = 8 AND 11.5 + (i % 7) * 0.6 < 12 THEN 'bajo'
            ELSE 'normal' END,
       fecha_inicio + INTERVAL '5 minutes'
FROM tmp_enc WHERE es_lab;

INSERT INTO observacion (id_estudio, id_codigo, id_procedencia, valor_numerico, unidad, rango_ref_min, rango_ref_max, interpretacion, fecha_observacion)
SELECT 300 + i,
       CASE WHEN organizacion = 7 THEN 19 ELSE 24 END,
       350 + i,
       CASE WHEN organizacion = 7 THEN 0.7 + (i % 10) * 0.08 ELSE 5 + (i % 9) * 0.9 END,
       CASE WHEN organizacion = 7 THEN 'mg/dL' ELSE '10*3/uL' END,
       CASE WHEN organizacion = 7 THEN 0.6 ELSE 4.5 END,
       CASE WHEN organizacion = 7 THEN 1.3 ELSE 11 END,
       'normal',
       fecha_inicio + INTERVAL '5 minutes'
FROM tmp_enc WHERE es_lab;

-- Medicamentos indicados
INSERT INTO solicitud_medicamento (id_encuentro, id_codigo, id_procedencia, dosis, via, frecuencia, duracion_dias, fecha_solicitud, estado)
SELECT i, m.med, 400 + i,
       CASE WHEN m.med = 32 THEN '2 disparos' ELSE '1 tableta' END,
       CASE WHEN m.med = 32 THEN 'inhalada' ELSE 'oral' END,
       CASE WHEN m.med IN (28,29,34) THEN 'cada 24 horas' ELSE 'cada 8 horas' END,
       CASE WHEN m.med IN (28,29,34) THEN NULL ELSE 7 END,
       fecha_inicio + INTERVAL '30 minutes',
       CASE WHEN m.med IN (28,29,34) THEN 'activa' ELSE 'completada' END
FROM tmp_enc e
CROSS JOIN LATERAL (SELECT (ARRAY[28,29,27,34,31,33,32,30,28,27])[(e.i % 10) + 1] AS med) m
WHERE EXISTS (SELECT 1 FROM tmp_rec r WHERE r.id = 400 + e.i);

-- Alergias (27 + 1 contradictoria). Cada 4.º paciente reporta "sin alergias conocidas".
-- Pacientes 28-32 sin registro de alergias.
INSERT INTO alergia (id_paciente_maestro, id_codigo, id_procedencia, sin_alergias_conocidas, reaccion, criticidad, estado_verificacion, fecha_registro)
SELECT p,
       CASE WHEN p % 4 = 0 THEN NULL ELSE 37 + ((p + 7) % 10) END,
       800 + p,
       (p % 4 = 0),
       CASE WHEN p % 4 = 0 THEN NULL
            ELSE (ARRAY['Urticaria','Exantema','Broncoespasmo','Angioedema','Anafilaxia','Prurito','Rinitis','Dermatitis de contacto','Edema labial','Estornudos'])[((p + 7) % 10) + 1] END,
       CASE WHEN p % 4 = 0 THEN NULL
            WHEN 37 + ((p + 7) % 10) <= 40 THEN 'alta' ELSE 'baja' END,
       CASE WHEN p % 5 = 0 THEN 'no_confirmada' ELSE 'confirmada' END,
       DATE '2025-12-15'
FROM generate_series(1, 27) AS p;

INSERT INTO alergia (id_paciente_maestro, id_codigo, id_procedencia, sin_alergias_conocidas, estado_verificacion, fecha_registro)
VALUES (3, NULL, 901, TRUE, 'no_confirmada', '2026-08-09');


-- ------------------------------------------------------------
-- CONFLICTOS Y VERSIONES
-- ------------------------------------------------------------

-- Reglas de autoridad (10)
INSERT INTO regla_autoridad (id_regla, tipo_dato, id_organizacion, criterio, prioridad, activa, descripcion)
OVERRIDING SYSTEM VALUE VALUES
( 1,'alergia',NULL,'conservar_ambos',1,TRUE,'Ante alergias contradictorias se conservan ambas hasta revisión (seguridad del paciente).'),
( 2,'alergia',NULL,'revision_manual',2,TRUE,'Si una fuente niega alergias y otra las confirma, decide el coordinador.'),
( 3,'diagnostico',NULL,'mas_reciente',1,TRUE,'Prevalece el diagnóstico registrado más recientemente.'),
( 4,'observacion',7,'autoridad_institucion',1,TRUE,'Para resultados de laboratorio prevalece Laboratorio Diagnóstica del Norte.'),
( 5,'observacion',8,'autoridad_institucion',2,TRUE,'Segunda autoridad de laboratorio: BioAnálisis.'),
( 6,'medicamento',NULL,'mas_reciente',1,TRUE,'Prevalece la indicación más reciente.'),
( 7,'contacto',NULL,'mas_reciente',1,TRUE,'Prevalece el teléfono o correo reportado más recientemente.'),
( 8,'direccion',NULL,'mas_reciente',1,TRUE,'Prevalece el domicilio reportado más recientemente.'),
( 9,'demografico',1,'autoridad_institucion',1,TRUE,'Para datos demográficos prevalece el Hospital Universitario del Norte.'),
(10,'demografico',NULL,'revision_manual',2,FALSE,'Regla anterior, desactivada.');

-- Conflictos (2): alergia del paciente 3 (pendiente) y teléfono del paciente 8 (resuelto).
INSERT INTO conflicto_dato (id_procedencia_a, id_procedencia_b, campo, id_regla_sugerida, fecha_deteccion, estado, resolucion, justificacion, id_usuario_resolucion, fecha_resolucion) VALUES
(803,901,'sustancia',2,'2026-08-10 11:02-06','pendiente',NULL,NULL,NULL,NULL),
(608,902,'valor',7,'2026-08-10 11:02-06','resuelto','vigente_b','El hospital San Gabriel reportó el teléfono más reciente; confirmado con la paciente.',3,'2026-08-12 09:30-06');

-- Historial de cambios (3)
INSERT INTO version_dato (id_procedencia, campo, numero_version, valor_anterior, valor_nuevo, id_usuario, id_detalle_correccion, fecha_cambio, motivo) VALUES
(608,'vigente',1,'true','false',3,NULL,'2026-08-12 09:30-06','Resolución del conflicto de teléfono.'),
(201,'valor_numerico',1,'69','71',NULL,908,'2026-09-12 07:11-06','Corrección enviada por la institución.'),
(501,'apellido_materno',1,'Trevino','Treviño',3,NULL,'2026-02-01 10:00-06','Corrección ortográfica solicitada por el paciente.');

UPDATE observacion SET valor_numerico = 71 WHERE id_procedencia = 201;


-- ------------------------------------------------------------
-- CONSENTIMIENTO
-- ------------------------------------------------------------

-- Consentimientos de los pacientes 1-22. 21 revocado, 22 vencido.
INSERT INTO consentimiento (id_consentimiento, id_paciente_maestro, id_usuario_registro, fecha_otorgamiento, fecha_inicio, fecha_fin, estado, fecha_revocacion, motivo_revocacion, ref_documento)
OVERRIDING SYSTEM VALUE
SELECT p, p, 3,
       CASE WHEN p = 22 THEN DATE '2025-01-10' ELSE DATE '2026-01-02' + p END,
       CASE WHEN p = 22 THEN DATE '2025-01-10' ELSE DATE '2026-01-02' + p END,
       CASE WHEN p = 22 THEN DATE '2026-01-10' ELSE DATE '2027-01-02' + p END,
       CASE WHEN p = 21 THEN 'revocado' WHEN p = 22 THEN 'vencido' ELSE 'activo' END,
       CASE WHEN p = 21 THEN DATE '2026-08-15' END,
       CASE WHEN p = 21 THEN 'Solicitud del paciente.' END,
       'consentimientos/CONS-' || lpad(p::text, 5, '0') || '.pdf'
FROM generate_series(1, 22) AS p;

-- Alcances: enviar demográficos, diagnósticos y alergias desde su institución de alta;
-- consultar demográficos y diagnósticos desde Hospital San Gabriel;
-- cada 3.er paciente también autoriza enviar resultados de laboratorio desde Diagnóstica del Norte.
INSERT INTO consentimiento_alcance (id_consentimiento, id_categoria, id_organizacion, permiso)
SELECT c.id_consentimiento, a.cat, CASE WHEN a.org = 0 THEN CASE WHEN c.id_paciente_maestro <= 16 THEN 1 ELSE 4 END ELSE a.org END, a.permiso
FROM consentimiento c
CROSS JOIN (VALUES (1,0,'enviar'),(2,0,'enviar'),(3,0,'enviar'),(1,2,'consultar'),(2,2,'consultar')) AS a(cat, org, permiso);

INSERT INTO consentimiento_alcance (id_consentimiento, id_categoria, id_organizacion, permiso)
SELECT id_consentimiento, 5, 7, 'enviar' FROM consentimiento WHERE id_paciente_maestro % 3 = 0;


-- ------------------------------------------------------------
-- AUDITORÍA
-- ------------------------------------------------------------
INSERT INTO auditoria (fecha_hora, id_usuario, id_sistema_origen, rol_en_evento, accion, tabla_afectada, id_registro_afectado, id_paciente_maestro, resultado, detalle) VALUES
('2026-01-01 09:00-06',1,NULL,'administrador','crear','credencial_sistema',2,NULL,'exito','Emisión de credencial anual para HIS Norte.'),
('2026-01-02 08:31-06',NULL,1,NULL,'recibir','paquete_transaccion',51,NULL,'exito','Carga inicial de pacientes del Hospital Universitario del Norte.'),
('2026-01-03 08:31-06',NULL,4,NULL,'recibir','paquete_transaccion',52,NULL,'exito','Carga inicial de pacientes de Clínica Familiar Apodaca.'),
('2026-01-05 12:00-06',3,NULL,'coordinador','fusionar','paciente_maestro',32,6,'exito','Paciente 32 fusionado en 6.'),
('2026-01-06 10:00-06',3,NULL,'coordinador','crear','consentimiento',1,1,'exito','Registro de consentimiento.'),
('2026-02-01 10:00-06',3,NULL,'coordinador','actualizar','nombre_paciente',1,1,'exito','Corrección ortográfica de apellido.'),
('2026-03-10 09:15-06',5,NULL,'medico','consultar','paciente_maestro',3,3,'exito','Consulta de expediente consolidado.'),
('2026-03-10 09:20-06',6,NULL,'medico','consultar','paciente_maestro',27,27,'denegado','Paciente sin consentimiento de consulta para la institución del médico.'),
('2026-05-04 11:00-06',2,NULL,'analista_integracion','actualizar','sistema_origen',3,NULL,'denegado','El analista no puede modificar sistemas de origen.'),
('2026-08-12 09:30-06',3,NULL,'coordinador','resolver','conflicto_dato',2,8,'exito','Conflicto de teléfono resuelto: vigente B.'),
('2026-08-15 10:00-06',3,NULL,'coordinador','actualizar','consentimiento',21,21,'exito','Revocación de consentimiento.'),
('2026-09-01 13:21-06',NULL,5,NULL,'recibir','paquete_transaccion',54,NULL,'error','Paquete procesado con errores de validación.'),
('2026-09-02 09:00-06',2,NULL,'analista_integracion','consultar','paquete_transaccion',54,NULL,'exito','Revisión de errores de validación.'),
('2026-09-05 16:46-06',NULL,6,NULL,'recibir','paquete_transaccion',55,NULL,'denegado','Paquete rechazado: sin consentimiento.'),
('2026-09-20 12:00-06',NULL,3,NULL,'enviar','paquete_transaccion',57,1,'exito','Envío del expediente del paciente 1 a Hospital La Ribera.'),
('2026-09-25 09:00-06',NULL,9,NULL,'recibir','paquete_transaccion',58,NULL,'denegado','Institución suspendida.'),
('2026-10-15 12:00-06',5,NULL,'medico','crear','encuentro_clinico',48,21,'exito','Consulta planeada capturada en el portal.'),
('2026-10-16 18:00-06',4,NULL,'coordinador','consultar','paciente_maestro',5,5,'denegado','Usuario inactivo.');


-- ------------------------------------------------------------
-- Sincronizar las secuencias IDENTITY con los ids cargados
-- (para que los INSERT desde Flask continúen después del último id).
-- ------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND is_identity = 'YES'
  LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE((SELECT MAX(%I) FROM %I), 0) + 1, false)',
      r.table_name, r.column_name, r.column_name, r.table_name);
  END LOOP;
END $$;

COMMIT;

-- ------------------------------------------------------------
-- Verificación rápida: registros por tabla
-- ------------------------------------------------------------
SELECT 'usuario' AS tabla, COUNT(*) FROM usuario
UNION ALL SELECT 'paciente_maestro', COUNT(*) FROM paciente_maestro
UNION ALL SELECT 'profesional_salud', COUNT(*) FROM profesional_salud
UNION ALL SELECT 'encuentro_clinico', COUNT(*) FROM encuentro_clinico
UNION ALL SELECT 'organizacion', COUNT(*) FROM organizacion
UNION ALL SELECT 'catalogo_codigo', COUNT(*) FROM catalogo_codigo
UNION ALL SELECT 'diagnostico', COUNT(*) FROM diagnostico
UNION ALL SELECT 'observacion', COUNT(*) FROM observacion
UNION ALL SELECT 'paquete_transaccion', COUNT(*) FROM paquete_transaccion
UNION ALL SELECT 'detalle_transaccion', COUNT(*) FROM detalle_transaccion
UNION ALL SELECT 'consentimiento', COUNT(*) FROM consentimiento;
