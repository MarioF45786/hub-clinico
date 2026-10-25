# Hub Clínico

Plataforma web de interoperabilidad clínica. Reúne en un solo expediente la información de un paciente que se atiende en varios hospitales, clínicas y laboratorios, y guarda de qué institución salió cada dato.

Proyecto final de **Bases de Datos Avanzadas (SC3303)** · Universidad de Monterrey · Equipo 05

---

## Qué hace

- Inicio y cierre de sesión con contraseñas guardadas con hash bcrypt.
- Permisos por rol, revisados en el servidor: administrador, coordinador, médico y analista.
- Alta, consulta, edición y baja lógica de **pacientes**, **médicos** y **consultas médicas**.
- Indicadores y reportes generados a partir de vistas SQL.
- Toda la lógica del negocio vive en procedimientos almacenados de PostgreSQL; Flask solo los llama.

## Tecnologías

| Capa | Herramientas |
|---|---|
| Presentación | HTML5, CSS3, JavaScript, Jinja2 |
| Lógica | Python 3 + Flask |
| Datos | PostgreSQL 16 (34 tablas en 3FN), psycopg 3, `pgcrypto` |

## Puesta en marcha

**Paso 1 · Dependencias**

```bash
pip install -r requirements.txt
```

**Paso 2 · Base de datos**

Crea el usuario y la base (como `postgres`):

```sql
CREATE USER user_proy WITH PASSWORD 'tu_contrasena';
CREATE DATABASE proyecto OWNER user_proy;
\c proyecto
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

Los scripts de la base de datos están en la carpeta `sql/` de este repositorio. Entra a esa carpeta y cárgalos en este orden:

```bash
cd sql
psql -h localhost -U user_proy -d proyecto -f 02_hub_interoperabilidad_schema.sql
psql -h localhost -U user_proy -d proyecto -f 03_ajustes_segundo_avance.sql
psql -h localhost -U user_proy -d proyecto -f 04_datos_prueba.sql
psql -h localhost -U user_proy -d proyecto -f 05_programacion.sql
psql -h localhost -U user_proy -d proyecto -f 08_programacion_hub.sql
psql -h localhost -U user_proy -d proyecto -f 10_procedimientos_app.sql
```

**Paso 3 · Credenciales**

La app lee la conexión de un archivo `.env`, que no se sube al repositorio. Crea el tuyo a partir de la plantilla:

```bash
cp .env.ejemplo .env
```

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=proyecto
DB_USER=user_proy
DB_PASSWORD=tu_contrasena
SECRET_KEY=llave_secreta
```

**Paso 4 · Correr**

```bash
export FLASK_APP=main.py
flask run --host=0.0.0.0
```

La app queda en `http://localhost:5000`.

## Cuentas para probar

Contraseña de todas: `Flojorama2026!`

| Rol | Correo | Pacientes | Médicos | Consultas | Inicio y reportes |
|---|---|:---:|:---:|:---:|:---:|
| Administrador | `admin@flojorama.mx` | — | Todo | — | Sí |
| Coordinador | `coordinador@flojorama.mx` | Todo | Ver | Todas | Sí |
| Médico | `medico1@flojorama.mx`, `medico2@flojorama.mx` | Ver | — | Solo las suyas | Sí |
| Analista | `analista@flojorama.mx` | — | — | — | Sí |

`coordinador2@flojorama.mx` está inactivo, para comprobar que no lo deja entrar.

## Organización del código

```
├── main.py            rutas, sesión, @requiere_rol y llamadas a los procedimientos
├── requirements.txt
├── .env.ejemplo
├── static/css/        estilos (hub.css, app.css)
├── templates/         páginas Jinja2; nav.html es el menú común
└── sql/               scripts de la base de datos (02 a 12)
```

## Scripts SQL

| Script | Para qué |
|---|---|
| `02` | Crea las 34 tablas con llaves, restricciones, índices y comentarios |
| `03` | Ajustes al modelo para la segunda entrega |
| `04` | Datos de prueba ficticios; se puede volver a correr |
| `05` y `08` | Funciones, procedimientos y vistas del sistema |
| `06` y `09` | Pruebas de los procedimientos (terminan en `ROLLBACK`) |
| `07` | Consultas con todos los tipos de JOIN y consultas complementarias |
| `10` | Los 20 procedimientos que usa la app |
| `11` | Demostración de los procedimientos |
| `12` | Código (`CREATE PROCEDURE`) de los procedimientos de la demostración |

## Qué usa cada pantalla de la base de datos

| Pantalla | Ruta | Procedimientos y vistas |
|---|---|---|
| Inicio de sesión | `/login` | `sp_iniciar_sesion` |
| Inicio | `/` | vista `v_indicadores_atencion` |
| Reportes | `/reportes` | vistas `v_consultas_por_especialidad`, `v_consultas_pendientes` |
| Pacientes | `/pacientes` | `sp_obtener_pacientes`, `sp_obtener_paciente`, `sp_inserta_paciente`, `sp_actualiza_paciente`, `sp_borrar_paciente` |
| Médicos | `/medicos` | `sp_obtener_medicos`, `sp_obtener_medico`, `sp_inserta_medico`, `sp_actualiza_medico`, `sp_borrar_medico`, `sp_obtener_instituciones` |
| Consultas | `/consultas` | `sp_obtener_consultas`, `sp_obtener_consulta`, `sp_inserta_consulta`, `sp_actualiza_consulta`, `sp_cancelar_consulta`, `sp_obtener_medicos_institucion` |

Los listados leen las vistas `v_paciente_resumen`, `v_historial_consultas` y `v_profesional_resumen` dentro de sus procedimientos. Las bajas son lógicas: el registro cambia de estado y se conserva su historial.
