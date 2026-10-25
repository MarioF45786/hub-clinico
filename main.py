from flask import Flask, request, render_template, redirect, url_for, session, flash
from functools import wraps
from dotenv import load_dotenv
import psycopg
import os

app = Flask(__name__)

# Las credenciales NO van escritas en el código: se leen del archivo .env
# (variables de entorno). El .env no se sube a GitHub.
load_dotenv()
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
DB_NAME = os.environ.get("DB_NAME")

# Llave con la que Flask firma la sesión (la cookie del usuario)
app.secret_key = os.environ.get("SECRET_KEY")

print("Aplicacion conectada a la base de datos")


def conectar():
    # Cada consulta abre su conexión y la cierra al terminar
    return psycopg.connect(
                host=DB_HOST,
                port=DB_PORT,
                user=DB_USER,
                dbname=DB_NAME,
                password=DB_PASSWORD,
                options="-c timezone=America/Monterrey"
            )


def mensaje_error(e):
    # Mensaje de los RAISE EXCEPTION de los procedimientos
    if e.diag and e.diag.message_primary:
        return e.diag.message_primary
    return "Ocurrió un error en la base de datos."


# Si PostgreSQL no responde, mostramos un aviso en lugar de que truene la app
@app.errorhandler(psycopg.OperationalError)
def sin_conexion(e):
    return render_template("error.html", mensaje="No hay conexión con la base de datos. Intenta más tarde."), 503


# ------------------------------------------------------------
# CONTROL DE ACCESO
# requiere_rol() se pone arriba de una ruta:
#   - si no hay sesión, manda al login
#   - si el rol del usuario no está en la lista, no lo deja pasar
# Así los permisos se revisan en el servidor, no solo en el menú.
# ------------------------------------------------------------
def requiere_rol(*roles):
    def decorador(funcion):
        @wraps(funcion)
        def revisar(*args, **kwargs):
            if "id_usuario" not in session:
                flash("Inicia sesión para continuar.", "error")
                return redirect(url_for("login"))
            if roles and session["rol"] not in roles:
                flash("No tienes permiso para entrar a esa sección.", "error")
                return redirect(url_for("principal"))
            return funcion(*args, **kwargs)
        return revisar
    return decorador


# ------------------------------------------------------------
# INICIO Y CIERRE DE SESIÓN
# ------------------------------------------------------------
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template("login.html")

    correo = request.form["correo"].strip()
    contrasena = request.form["contrasena"]
    if correo == "" or contrasena == "":
        flash("Escribe tu correo y tu contraseña.", "error")
        return render_template("login.html", correo=correo)

    conexion = conectar()
    cur = conexion.cursor()

    # La contraseña se compara contra el hash en PostgreSQL (crypt / bcrypt)
    cur.execute("CALL sp_iniciar_sesion(%s, %s, NULL)", (correo, contrasena))
    cur.execute("FETCH ALL FROM cursor_usuario")
    Usuario = cur.fetchone()

    conexion.commit()
    cur.close()
    conexion.close()

    if Usuario is None:
        flash("Correo o contraseña incorrectos, o el usuario está inactivo.", "error")
        return render_template("login.html", correo=correo)

    # Guardamos en la sesión quién es y qué rol tiene
    session["id_usuario"] = Usuario[0]
    session["rol"] = Usuario[1]
    session["nombre"] = Usuario[2]
    session["id_profesional"] = Usuario[3]
    flash("Bienvenido(a), " + Usuario[2] + ".", "exito")
    return redirect(url_for("principal"))


@app.route("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada.", "exito")
    return redirect(url_for("login"))


# Landing page: indicadores generales (vista v_indicadores_atencion)
@app.route("/")
@requiere_rol()
def principal():
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("SELECT pacientes_activos, medicos_activos, consultas_finalizadas, consultas_pendientes, consultas_canceladas FROM v_indicadores_atencion")
    Indicadores = cur.fetchone()
    cur.close()
    conexion.close()
    return render_template("index.html", Indicadores=Indicadores)


# Reportes: datos que salen directamente de las vistas SQL
@app.route("/reportes")
@requiere_rol()
def reportes():
    conexion = conectar()
    cur = conexion.cursor()

    cur.execute("SELECT especialidad, total_consultas, finalizadas, pendientes, pacientes_distintos FROM v_consultas_por_especialidad ORDER BY total_consultas DESC")
    Especialidades = cur.fetchall()

    cur.execute("SELECT id_encuentro, fecha_inicio, paciente, telefono_paciente, medico, institucion, estado FROM v_consultas_pendientes ORDER BY fecha_inicio")
    Pendientes = cur.fetchall()

    cur.close()
    conexion.close()
    return render_template("reportes.html", Especialidades=Especialidades, Pendientes=Pendientes)


# ============================================================
# PACIENTES
# Ver: coordinador y médico. Registrar, editar y dar de baja: coordinador.
# ============================================================
@app.route("/pacientes")
@requiere_rol("coordinador", "medico")
def pacientes():
    buscar = request.args.get("buscar", "")
    estado = request.args.get("estado", "activo")

    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_pacientes(%s, %s, NULL)", (buscar, estado or None))
    cur.execute("FETCH ALL FROM cursor_pacientes")
    Pacientes = cur.fetchall()
    conexion.close()

    return render_template("pacientes.html", Pacientes=Pacientes, buscar=buscar, estado=estado)


@app.route("/pacientes/<int:id_paciente>")
@requiere_rol("coordinador", "medico")
def paciente(id_paciente):
    conexion = conectar()
    cur = conexion.cursor()

    cur.execute("CALL sp_obtener_paciente(%s, NULL)", (id_paciente,))
    cur.execute("FETCH ALL FROM cursor_paciente")
    Paciente = cur.fetchone()

    # Consultas del paciente (si es médico, el procedimiento solo regresa las suyas)
    cur.execute("CALL sp_obtener_consultas(%s, NULL, NULL, %s, NULL, NULL)", (session["id_usuario"], id_paciente))
    cur.execute("FETCH ALL FROM cursor_consultas")
    Consultas = cur.fetchall()
    conexion.close()

    if Paciente is None:
        flash("El paciente no existe.", "error")
        return redirect(url_for("pacientes"))
    return render_template("paciente.html", Paciente=Paciente, Consultas=Consultas)


@app.route("/pacientes/insertar")
@requiere_rol("coordinador")
def insertar_paciente():
    return render_template("insertar_paciente.html", Datos={})


@app.route("/pacientes/registra", methods=["POST"])
@requiere_rol("coordinador")
def registra_paciente():
    nombre = request.form["nombre"].strip()
    apellido_p = request.form["apellido_paterno"].strip()
    apellido_m = request.form["apellido_materno"].strip() or None
    fecha_n = request.form["fecha_nacimiento"]
    sexo = request.form["sexo"]
    curp = request.form["curp"].strip().upper() or None

    # Validación en el servidor (además de la de JavaScript)
    if nombre == "" or apellido_p == "" or fecha_n == "" or sexo == "":
        flash("Nombre, apellido paterno, fecha de nacimiento y sexo son obligatorios.", "error")
        return render_template("insertar_paciente.html", Datos=request.form)

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_registrar_paciente(%s, %s, %s, %s, %s, %s, %s, NULL)",
                    (session["id_usuario"], nombre, apellido_p, apellido_m, fecha_n, sexo, curp))
        id_nuevo = cur.fetchone()[0]
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return render_template("insertar_paciente.html", Datos=request.form)
    cur.close()
    conexion.close()

    flash("Paciente registrado con el número " + str(id_nuevo) + ".", "exito")
    return redirect(url_for("paciente", id_paciente=id_nuevo))


@app.route("/pacientes/editar/<int:id_paciente>")
@requiere_rol("coordinador")
def editar_paciente(id_paciente):
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_paciente(%s, NULL)", (id_paciente,))
    cur.execute("FETCH ALL FROM cursor_paciente")
    Paciente = cur.fetchone()
    conexion.close()

    if Paciente is None:
        flash("El paciente no existe.", "error")
        return redirect(url_for("pacientes"))
    return render_template("actualizar_paciente.html", Paciente=Paciente)


@app.route("/pacientes/actualizar", methods=["POST"])
@requiere_rol("coordinador")
def actualizar_paciente():
    id_paciente = int(request.form["id_paciente"])
    nombre = request.form["nombre"].strip()
    apellido_p = request.form["apellido_paterno"].strip()
    apellido_m = request.form["apellido_materno"].strip() or None
    fecha_n = request.form["fecha_nacimiento"]
    sexo = request.form["sexo"]
    curp = request.form["curp"].strip().upper() or None

    if nombre == "" or apellido_p == "" or fecha_n == "":
        flash("Nombre, apellido paterno y fecha de nacimiento son obligatorios.", "error")
        return redirect(url_for("editar_paciente", id_paciente=id_paciente))

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_actualizar_paciente(%s, %s, %s, %s, %s, %s, %s, %s)",
                    (session["id_usuario"], id_paciente, nombre, apellido_p, apellido_m, fecha_n, sexo, curp))
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("editar_paciente", id_paciente=id_paciente))
    cur.close()
    conexion.close()

    flash("Datos del paciente actualizados.", "exito")
    return redirect(url_for("paciente", id_paciente=id_paciente))


@app.route("/pacientes/borrar/<int:id_paciente>")
@requiere_rol("coordinador")
def borrar_paciente(id_paciente):
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_paciente(%s, NULL)", (id_paciente,))
    cur.execute("FETCH ALL FROM cursor_paciente")
    Paciente = cur.fetchone()
    conexion.close()

    if Paciente is None:
        flash("El paciente no existe.", "error")
        return redirect(url_for("pacientes"))
    return render_template("borrar_paciente.html", Paciente=Paciente)


# Baja LÓGICA: el paciente queda 'inactivo', su historial no se borra
@app.route("/pacientes/baja", methods=["POST"])
@requiere_rol("coordinador")
def baja_paciente():
    id_paciente = int(request.form["id_paciente"])
    motivo = request.form["motivo"].strip()

    if motivo == "":
        flash("Escribe el motivo de la baja.", "error")
        return redirect(url_for("borrar_paciente", id_paciente=id_paciente))

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_baja_paciente(%s, %s, %s, NULL)", (session["id_usuario"], id_paciente, motivo))
        canceladas = cur.fetchone()[0]
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("paciente", id_paciente=id_paciente))
    cur.close()
    conexion.close()

    flash("Paciente dado de baja. Consultas planeadas canceladas: " + str(canceladas) + ".", "exito")
    return redirect(url_for("pacientes"))


# ============================================================
# MÉDICOS
# Ver: administrador y coordinador. Registrar, editar y dar de baja: administrador.
# ============================================================
@app.route("/medicos")
@requiere_rol("administrador", "coordinador")
def medicos():
    buscar = request.args.get("buscar", "")
    estado = request.args.get("estado", "activos")
    activo = None
    if estado == "activos":
        activo = True
    elif estado == "baja":
        activo = False

    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_medicos(%s, %s, NULL)", (buscar, activo))
    cur.execute("FETCH ALL FROM cursor_medicos")
    Medicos = cur.fetchall()
    conexion.close()

    return render_template("medicos.html", Medicos=Medicos, buscar=buscar, estado=estado)


@app.route("/medicos/<int:id_medico>")
@requiere_rol("administrador", "coordinador")
def medico(id_medico):
    conexion = conectar()
    cur = conexion.cursor()

    cur.execute("CALL sp_obtener_medico(%s, NULL)", (id_medico,))
    cur.execute("FETCH ALL FROM cursor_medico")
    Medico = cur.fetchone()

    cur.execute("CALL sp_obtener_consultas(%s, NULL, NULL, NULL, %s, NULL)", (session["id_usuario"], id_medico))
    cur.execute("FETCH ALL FROM cursor_consultas")
    Consultas = cur.fetchall()
    conexion.close()

    if Medico is None:
        flash("El médico no existe.", "error")
        return redirect(url_for("medicos"))
    return render_template("medico.html", Medico=Medico, Consultas=Consultas)


@app.route("/medicos/insertar")
@requiere_rol("administrador")
def insertar_medico():
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_instituciones(NULL)")
    cur.execute("FETCH ALL FROM cursor_instituciones")
    Instituciones = cur.fetchall()
    conexion.close()
    return render_template("insertar_medico.html", Instituciones=Instituciones, Datos={})


@app.route("/medicos/registra", methods=["POST"])
@requiere_rol("administrador")
def registra_medico():
    cedula = request.form["cedula"].strip()
    nombre = request.form["nombre"].strip()
    apellido_p = request.form["apellido_paterno"].strip()
    apellido_m = request.form["apellido_materno"].strip() or None
    especialidad = request.form["especialidad"].strip() or None
    cedula_esp = request.form["cedula_especialidad"].strip() or None
    id_institucion = request.form["id_institucion"]
    rol_institucion = request.form["rol_institucion"]

    error = None
    if cedula == "" or nombre == "" or apellido_p == "" or id_institucion == "":
        error = "Cédula, nombre, apellido paterno e institución son obligatorios."
    elif not cedula.isdigit() or len(cedula) not in (7, 8):
        error = "La cédula profesional debe tener 7 u 8 dígitos."

    conexion = conectar()
    cur = conexion.cursor()
    if error is None:
        try:
            cur.execute("CALL sp_registrar_profesional(%s, %s, %s, %s, %s, %s, %s, %s, %s, NULL)",
                        (session["id_usuario"], cedula, nombre, apellido_p, apellido_m,
                         especialidad, cedula_esp, int(id_institucion), rol_institucion))
            id_nuevo = cur.fetchone()[0]
            conexion.commit()
            conexion.close()
            flash("Médico registrado con el número " + str(id_nuevo) + ".", "exito")
            return redirect(url_for("medico", id_medico=id_nuevo))
        except psycopg.Error as e:
            conexion.rollback()
            error = mensaje_error(e)

    # Si hubo error regresamos al formulario con lo que había escrito
    cur.execute("CALL sp_obtener_instituciones(NULL)")
    cur.execute("FETCH ALL FROM cursor_instituciones")
    Instituciones = cur.fetchall()
    conexion.close()
    flash(error, "error")
    return render_template("insertar_medico.html", Instituciones=Instituciones, Datos=request.form)


@app.route("/medicos/editar/<int:id_medico>")
@requiere_rol("administrador")
def editar_medico(id_medico):
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_medico(%s, NULL)", (id_medico,))
    cur.execute("FETCH ALL FROM cursor_medico")
    Medico = cur.fetchone()
    conexion.close()

    if Medico is None:
        flash("El médico no existe.", "error")
        return redirect(url_for("medicos"))
    return render_template("actualizar_medico.html", Medico=Medico)


@app.route("/medicos/actualizar", methods=["POST"])
@requiere_rol("administrador")
def actualizar_medico():
    id_medico = int(request.form["id_medico"])
    cedula = request.form["cedula"].strip()
    nombre = request.form["nombre"].strip()
    apellido_p = request.form["apellido_paterno"].strip()
    apellido_m = request.form["apellido_materno"].strip() or None

    if cedula == "" or nombre == "" or apellido_p == "":
        flash("Cédula, nombre y apellido paterno son obligatorios.", "error")
        return redirect(url_for("editar_medico", id_medico=id_medico))

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_actualizar_profesional(%s, %s, %s, %s, %s, %s)",
                    (session["id_usuario"], id_medico, cedula, nombre, apellido_p, apellido_m))
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("editar_medico", id_medico=id_medico))
    cur.close()
    conexion.close()

    flash("Datos del médico actualizados.", "exito")
    return redirect(url_for("medico", id_medico=id_medico))


@app.route("/medicos/borrar/<int:id_medico>")
@requiere_rol("administrador")
def borrar_medico(id_medico):
    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_medico(%s, NULL)", (id_medico,))
    cur.execute("FETCH ALL FROM cursor_medico")
    Medico = cur.fetchone()
    conexion.close()

    if Medico is None:
        flash("El médico no existe.", "error")
        return redirect(url_for("medicos"))
    return render_template("borrar_medico.html", Medico=Medico)


# Baja LÓGICA: el médico queda inactivo; sus consultas pasadas se conservan
@app.route("/medicos/baja", methods=["POST"])
@requiere_rol("administrador")
def baja_medico():
    id_medico = int(request.form["id_medico"])

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_baja_profesional(%s, %s)", (session["id_usuario"], id_medico))
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("medico", id_medico=id_medico))
    cur.close()
    conexion.close()

    flash("Médico dado de baja. Su cuenta de usuario también se desactivó.", "exito")
    return redirect(url_for("medicos"))


# ============================================================
# CONSULTAS
# Coordinador: todas. Médico: solo las suyas (lo revisan los procedimientos).
# ============================================================
@app.route("/consultas")
@requiere_rol("coordinador", "medico")
def consultas():
    buscar = request.args.get("buscar", "")
    estado = request.args.get("estado", "")

    conexion = conectar()
    cur = conexion.cursor()
    cur.execute("CALL sp_obtener_consultas(%s, %s, %s, NULL, NULL, NULL)",
                (session["id_usuario"], buscar, estado or None))
    cur.execute("FETCH ALL FROM cursor_consultas")
    Consultas = cur.fetchall()
    conexion.close()

    return render_template("consultas.html", Consultas=Consultas, buscar=buscar, estado=estado)


def obtener_consulta_permitida(cur, id_consulta):
    # Lee una consulta y revisa que un médico no abra la de otro médico
    cur.execute("CALL sp_obtener_consulta(%s, NULL)", (id_consulta,))
    cur.execute("FETCH ALL FROM cursor_consulta")
    Consulta = cur.fetchone()
    if Consulta is None:
        return None, "La consulta no existe."
    if session["rol"] == "medico" and Consulta[3] != session["id_profesional"]:
        return None, "Solo puedes ver tus propias consultas."
    return Consulta, None


@app.route("/consultas/<int:id_consulta>")
@requiere_rol("coordinador", "medico")
def consulta(id_consulta):
    conexion = conectar()
    cur = conexion.cursor()
    Consulta, error = obtener_consulta_permitida(cur, id_consulta)
    conexion.close()

    if error:
        flash(error, "error")
        return redirect(url_for("consultas"))
    return render_template("consulta.html", Consulta=Consulta)


def datos_formulario_consulta(cur):
    # Listas para el formulario: pacientes activos y combinaciones médico-institución
    cur.execute("CALL sp_obtener_pacientes(NULL, 'activo', NULL)")
    cur.execute("FETCH ALL FROM cursor_pacientes")
    Pacientes = cur.fetchall()

    # Un médico solo puede agendar a su nombre
    id_prof = session["id_profesional"] if session["rol"] == "medico" else None
    cur.execute("CALL sp_obtener_medicos_institucion(%s, NULL)", (id_prof,))
    cur.execute("FETCH ALL FROM cursor_vinculos")
    Vinculos = cur.fetchall()
    return Pacientes, Vinculos


@app.route("/consultas/insertar")
@requiere_rol("coordinador", "medico")
def insertar_consulta():
    conexion = conectar()
    cur = conexion.cursor()
    Pacientes, Vinculos = datos_formulario_consulta(cur)
    conexion.close()

    # Si venimos del expediente de un paciente, ya viene seleccionado
    Datos = {"id_paciente": request.args.get("paciente", "")}
    return render_template("insertar_consulta.html", Pacientes=Pacientes, Vinculos=Vinculos, Datos=Datos)


@app.route("/consultas/registra", methods=["POST"])
@requiere_rol("coordinador", "medico")
def registra_consulta():
    id_paciente = request.form["id_paciente"]
    vinculo = request.form["vinculo"]          # viene como "id_medico|id_institucion"
    tipo = request.form["tipo_encuentro"]
    motivo = request.form["motivo"].strip() or None
    fecha = request.form["fecha_inicio"]

    error = None
    if id_paciente == "" or vinculo == "" or tipo == "" or fecha == "":
        error = "Paciente, médico, tipo y fecha son obligatorios."

    conexion = conectar()
    cur = conexion.cursor()
    if error is None:
        id_medico, id_institucion = vinculo.split("|")
        try:
            cur.execute("CALL sp_registrar_encuentro(%s, %s, %s, %s, %s, %s, %s, NULL)",
                        (session["id_usuario"], int(id_paciente), int(id_institucion), int(id_medico),
                         tipo, motivo, fecha))
            id_nuevo = cur.fetchone()[0]
            conexion.commit()
            conexion.close()
            flash("Consulta registrada con el número " + str(id_nuevo) + ".", "exito")
            return redirect(url_for("consulta", id_consulta=id_nuevo))
        except psycopg.Error as e:
            conexion.rollback()
            error = mensaje_error(e)

    Pacientes, Vinculos = datos_formulario_consulta(cur)
    conexion.close()
    flash(error, "error")
    return render_template("insertar_consulta.html", Pacientes=Pacientes, Vinculos=Vinculos, Datos=request.form)


@app.route("/consultas/editar/<int:id_consulta>")
@requiere_rol("coordinador", "medico")
def editar_consulta(id_consulta):
    conexion = conectar()
    cur = conexion.cursor()
    Consulta, error = obtener_consulta_permitida(cur, id_consulta)
    conexion.close()

    if error:
        flash(error, "error")
        return redirect(url_for("consultas"))
    if Consulta[10] not in ("planeado", "en_curso"):
        flash("La consulta ya está " + Consulta[10] + " y no se puede modificar.", "error")
        return redirect(url_for("consulta", id_consulta=id_consulta))
    return render_template("actualizar_consulta.html", Consulta=Consulta)


@app.route("/consultas/actualizar", methods=["POST"])
@requiere_rol("coordinador", "medico")
def actualizar_consulta():
    id_consulta = int(request.form["id_consulta"])
    motivo = request.form["motivo"].strip() or None
    estado = request.form["estado"]
    # Si la consulta ya está en curso el campo de fecha viene bloqueado,
    # entonces usamos la fecha original (campo oculto)
    fecha = request.form.get("fecha_inicio") or request.form["fecha_original"]

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_actualizar_encuentro(%s, %s, %s, %s, %s)",
                    (session["id_usuario"], id_consulta, motivo, fecha, estado))
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("editar_consulta", id_consulta=id_consulta))
    cur.close()
    conexion.close()

    flash("Consulta actualizada.", "exito")
    return redirect(url_for("consulta", id_consulta=id_consulta))


@app.route("/consultas/borrar/<int:id_consulta>")
@requiere_rol("coordinador", "medico")
def borrar_consulta(id_consulta):
    conexion = conectar()
    cur = conexion.cursor()
    Consulta, error = obtener_consulta_permitida(cur, id_consulta)
    conexion.close()

    if error:
        flash(error, "error")
        return redirect(url_for("consultas"))
    return render_template("cancelar_consulta.html", Consulta=Consulta)


# Baja LÓGICA: la consulta queda 'cancelada', no se borra
@app.route("/consultas/cancelar", methods=["POST"])
@requiere_rol("coordinador", "medico")
def cancelar_consulta():
    id_consulta = int(request.form["id_consulta"])
    motivo = request.form["motivo"].strip()

    if motivo == "":
        flash("Escribe el motivo de la cancelación.", "error")
        return redirect(url_for("borrar_consulta", id_consulta=id_consulta))

    conexion = conectar()
    cur = conexion.cursor()
    try:
        cur.execute("CALL sp_cancelar_encuentro(%s, %s, %s)", (session["id_usuario"], id_consulta, motivo))
        conexion.commit()
    except psycopg.Error as e:
        conexion.rollback()
        conexion.close()
        flash(mensaje_error(e), "error")
        return redirect(url_for("consulta", id_consulta=id_consulta))
    cur.close()
    conexion.close()

    flash("Consulta cancelada.", "exito")
    return redirect(url_for("consulta", id_consulta=id_consulta))
