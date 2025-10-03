CREATE OR REPLACE FUNCTION contabilidad.fn_audit_bu_simple()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.fecha_modificacion := now();
  NEW.version_registro   := COALESCE(OLD.version_registro, 1) + 1;
  RETURN NEW;
END$$;

-- =========================
-- PERSONA (padre) y USUARIO (hijo 1:1)
-- =========================
CREATE TABLE IF NOT EXISTS persona.persona (
  id_persona          bigserial PRIMARY KEY,
  nombres             varchar(100) NOT NULL,
  apellidos           varchar(100),
  telefono            varchar(100),
  fecha_nacimiento    date,
  email               varchar(200),
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_persona ON persona.persona;
CREATE TRIGGER bu_persona
BEFORE UPDATE ON persona.persona
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE TABLE IF NOT EXISTS persona.persona_usuario (
  id_persona          bigint PRIMARY KEY
                      REFERENCES persona.persona(id_persona) ON DELETE CASCADE,
  nombre_usuario      varchar(80) UNIQUE NOT NULL,
  contrasena_hash     varchar(255) NOT NULL,
  tipo_usuario        varchar(200),
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_persona_usuario ON persona.persona_usuario;
CREATE TRIGGER bu_persona_usuario
BEFORE UPDATE ON persona.persona_usuario
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE TABLE IF NOT EXISTS persona.proveedor (
  id_proveedor        bigserial PRIMARY KEY,
  nombre_proveedor    varchar(180) NOT NULL,
  categoria           varchar(100),
  telefono            varchar(100),
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_proveedor ON persona.proveedor;
CREATE TRIGGER bu_proveedor
BEFORE UPDATE ON persona.proveedor
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


	
CREATE TABLE IF NOT EXISTS contabilidad.grupo_cuenta (
  id_grupo_cuenta   bigserial PRIMARY KEY,
  codigo            varchar(30) UNIQUE NOT NULL,
  nombre            varchar(150) NOT NULL,
  id_parent         bigint REFERENCES contabilidad.grupo_cuenta(id_grupo_cuenta),
  tipo              varchar(15)  NOT NULL,        -- 'BALANCE'|'RESULTADOS'
  sub_tipo          varchar(15)  NOT NULL,        -- ACTIVO|PASIVO|PATRIMONIO|INGRESO|GASTO
  sub_grupo         varchar(20),                  -- BALANCE: CORRIENTE|NO_CORRIENTE; RESULTADOS: ORDINARIO|EXTRAORDINARIO
  orden_reporte     smallint,
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint,
  CONSTRAINT ck_tipo CHECK (tipo IN ('BALANCE','RESULTADOS')),
  CONSTRAINT ck_sub_tipo_por_tipo CHECK (
    (tipo='BALANCE'    AND sub_tipo IN ('ACTIVO','PASIVO','PATRIMONIO')) OR
    (tipo='RESULTADOS' AND sub_tipo IN ('INGRESO','GASTO'))
  ),
  CONSTRAINT ck_sub_grupo_por_clase CHECK (
    sub_grupo IS NULL
    OR (tipo='BALANCE' AND sub_tipo IN ('ACTIVO','PASIVO') AND sub_grupo IN ('CORRIENTE','NO_CORRIENTE'))
    OR (tipo='RESULTADOS' AND sub_tipo IN ('INGRESO','GASTO') AND sub_grupo IN ('ORDINARIO','EXTRAORDINARIO'))
  )
);
CREATE INDEX IF NOT EXISTS idx_grupo_cuenta_parent ON contabilidad.grupo_cuenta(id_parent);
DROP TRIGGER IF EXISTS bu_grupo_cuenta ON contabilidad.grupo_cuenta;
CREATE TRIGGER bu_grupo_cuenta
BEFORE UPDATE ON contabilidad.grupo_cuenta
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS contabilidad.cuenta (
  id_cuenta        bigserial PRIMARY KEY,
  codigo           varchar(40) UNIQUE NOT NULL,
  nombre_cuenta    varchar(180) NOT NULL,
  id_grupo_cuenta  bigint NOT NULL REFERENCES contabilidad.grupo_cuenta(id_grupo_cuenta),
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_cuenta ON contabilidad.cuenta;
CREATE TRIGGER bu_cuenta
BEFORE UPDATE ON contabilidad.cuenta
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS contabilidad.concepto_costo(
  id_concepto       bigserial PRIMARY KEY,
  codigo            varchar(50) UNIQUE NOT NULL,
  nombre            varchar(160) NOT NULL,
  tipo_concepto     varchar(15) NOT NULL CHECK (tipo_concepto IN ('BIEN','SERVICIO','OTRO')),
  unidad_medida     varchar(20),
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);

DROP TRIGGER IF EXISTS bu_concepto ON contabilidad.concepto_costo;
CREATE TRIGGER bu_concepto
BEFORE UPDATE ON contabilidad.concepto_costo
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS contabilidad.centro_costo (
  id_centro_costo   bigserial PRIMARY KEY,
  codigo            varchar(40) UNIQUE NOT NULL,
  nombre            varchar(150) NOT NULL,
  id_cuenta_ingreso bigint REFERENCES contabilidad.cuenta(id_cuenta),
  id_cuenta_costo   bigint REFERENCES contabilidad.cuenta(id_cuenta),
  observaciones     text,
  -- auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_ccosto ON contabilidad.centro_costo;
CREATE TRIGGER bu_ccosto
BEFORE UPDATE ON contabilidad.centro_costo
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();
-- Tipos de bien

create schema if not exists inventario;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_bien') THEN
    CREATE TYPE inventario.tipo_bien AS ENUM ('MERCADERIA','MATERIA_PRIMA','SUMINISTRO','SERVICIO','ACTIVO_FIJO');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='seguimiento_bien') THEN
    CREATE TYPE inventario.seguimiento_bien AS ENUM ('NINGUNO','LOTE','SERIE');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='metodo_valuacion') THEN
    CREATE TYPE inventario.metodo_valuacion AS ENUM ('PEPS','UEPS','PROM');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='metodo_depreciacion') THEN
    CREATE TYPE inventario.metodo_depreciacion AS ENUM ('LINEA_RECTA','SDD','UNIDADES');
  END IF;
END$$;




CREATE TABLE IF NOT EXISTS inventario.bien (
  id_bien                 bigserial PRIMARY KEY,
  sku 		              varchar(60) UNIQUE NOT NULL,         -- SKU interno
  nombre                  varchar(180) NOT NULL,
  descripcion             text,

  -- Clasificación
  tipo                    inventario.tipo_bien NOT NULL,       -- MERCADERIA / ACTIVO_FIJO / etc.
  categoria               varchar(100),
  subcategoria            varchar(100),

  -- Unidades y seguimiento
  unidad_compra           			varchar(20) DEFAULT 'unidad',
  unidad_venta            			varchar(20) DEFAULT 'unidad',
  factor_conversion       			numeric(18,6) DEFAULT 1 CHECK (factor_conversion > 0),
  controla_inventario_loteable     	boolean NOT NULL DEFAULT false,        -- false para SERVICIO, por ej.
  controla_inventario_no_loteable	boolean not null default false,
  es_producto_tienda 				boolean default false,

  -- Valuación y precios de referencia
  metodo_valuacion        inventario.metodo_valuacion DEFAULT 'PROM',
  costo_referencia        numeric(18,4) CHECK (costo_referencia IS NULL OR costo_referencia >= 0),
  precio_referencia       numeric(18,2) CHECK (precio_referencia IS NULL OR precio_referencia >= 0),
  moneda_referencia       varchar(3) DEFAULT 'BOB',

  -- Datos físicos opcionales
  marca                   varchar(80),
  modelo                  varchar(80),
  codigo_barras           varchar(80),
  peso_kg                 numeric(18,3) CHECK (peso_kg IS NULL OR peso_kg >= 0),
  largo_m				  numeric(18,4) CHECK (largo_m IS NULL OR largo_m >= 0),
  ancho_m				  numeric(18,4) CHECK (ancho_m IS NULL OR ancho_m >= 0),
  profundidad_m			  numeric(18,4) CHECK (profundidad_m IS NULL OR profundidad_m >= 0),
  volumen_m3              numeric(18,4) CHECK (volumen_m3 IS NULL OR volumen_m3 >= 0),

  -- Contabilidad (si quieres atar cuentas específicas por bien)
  id_cuenta_existencias   bigint REFERENCES contabilidad.cuenta(id_cuenta),
  id_cuenta_costo_venta   bigint REFERENCES contabilidad.cuenta(id_cuenta),
  id_cuenta_ingreso       bigint REFERENCES contabilidad.cuenta(id_cuenta),
  id_cuenta_depreciacion  bigint REFERENCES contabilidad.cuenta(id_cuenta),
  id_cuenta_depreciacion_acumulada	bigint REFERENCES contabilidad.cuenta(id_cuenta),
  

  -- Depreciación (solo si tipo='ACTIVO_FIJO'; se valida con CHECK)
  valor_origen            numeric(18,2) CHECK (valor_origen IS NULL OR valor_origen >= 0),
  vida_util_meses         int CHECK (vida_util_meses IS NULL OR vida_util_meses > 0),
  valor_residual          numeric(18,2) CHECK (valor_residual IS NULL OR valor_residual >= 0),
  metodo_depreciacion     inventario.metodo_depreciacion,

  -- Auditoría (solo UPDATE)
  estado_registro         varchar(20) DEFAULT 'Activo',
  fecha_registro          timestamptz  DEFAULT now(),
  fecha_modificacion      timestamptz,
  version_registro        int          DEFAULT 1,
  id_usuario_creador      bigint,
  id_usuario_modificacion bigint,

  CONSTRAINT ck_bien_flags_xor CHECK (
    -- para MERCADERIA: exactamente uno de los flags en true
    (tipo = 'MERCADERIA' AND (controla_inventario_loteable::int + controla_inventario_no_loteable::int) = 1)
    OR
    -- para ACTIVO_FIJO y SERVICIO: ambos en false
    (tipo IN ('ACTIVO_FIJO','SERVICIO') AND controla_inventario_loteable = false AND controla_inventario_no_loteable = false)
    OR
    -- otros tipos (si agregas más): ajustar según política
    (tipo NOT IN ('MERCADERIA','ACTIVO_FIJO','SERVICIO'))
  ),
  CONSTRAINT ck_bien_activo_fijo_dep CHECK (
    tipo <> 'ACTIVO_FIJO'
    OR (valor_origen IS NOT NULL AND vida_util_meses IS NOT NULL AND metodo_depreciacion IS NOT NULL)
  ),
  CONSTRAINT ck_bien_servicio_no_dep_no_inv CHECK (
    tipo <> 'SERVICIO'
    OR (
      controla_inventario_loteable = false
      AND controla_inventario_no_loteable = false
      AND valor_origen IS NULL AND vida_util_meses IS NULL AND valor_residual IS NULL AND metodo_depreciacion IS NULL
      AND peso_kg IS NULL AND volumen_m3 IS NULL
    )
  )
);


create schema if not exists servicios_educativos;
drop table servicios_educativos.producto_educativo cascade;

CREATE TABLE servicios_educativos.producto_educativo (
    id_producto_educativo  BIGSERIAL PRIMARY KEY,
    nombre                 VARCHAR(150) NOT NULL,
    descripcion            TEXT,
    tipo_producto          VARCHAR(50) NOT NULL, -- Ej: Curso, Taller, Paquete, etc.
    precio_base            NUMERIC(12,2) CHECK (precio_base IS NULL OR precio_base >= 0),
    lim_sup_estudiantes	   int not null default 30,
    lim_inf_estudiantes	   int not null default 1,
    id_producto_tienda	   int references inventario.bien(id_bien),				   
    link_bibliografia	   text,
    link_publicidad		   text,

    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    estado_registro        BOOLEAN DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT DEFAULT 1
);

CREATE TABLE servicios_educativos.horarios(
	id_horario				bigserial primary key,
	repeticion	    		text check(repeticion IN ('CADA SEMANA', 'CADA QUINCENA', 'CADA MES')),
	hora_inicio_lunes		time,
	hora_inicio_martes		time,
	hora_inicio_miercoles	time,
	hora_inicio_jueves		time,
	hora_inicio_viernes 	time,
	hora_inicio_sabado		time,
	hora_fin_lunes			time,
	hora_fin_martes			time,
	hora_fin_miercoles		time,
	hora_fin_jueves			time,
	hora_fin_viernes 		time,
	hora_fin_sabado			time,
		
    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    estado_registro        BOOLEAN DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT DEFAULT 1
);


CREATE TABLE servicios_educativos.curso_version (
    id_curso_version       BIGSERIAL PRIMARY KEY,
    id_producto_educativo  BIGINT NOT NULL
                            REFERENCES servicios_educativos.producto_educativo(id_producto_educativo) ON DELETE CASCADE,
    nombre_version         VARCHAR(150) NOT NULL, -- Ej: “Álgebra 2025 - Edición I”
	
    descripcion_version    TEXT,
    fecha_inicio           DATE,
    fecha_fin              DATE,
    precio_version         NUMERIC(12,2) CHECK (precio_version IS NULL OR precio_version >= 0),
    id_horario			   int references servicios_educativos.horarios(id_horario),

    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    estado_registro        BOOLEAN DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT DEFAULT 1
);


CREATE TABLE servicios_educativos.paquetes_producto_educativo (
    id_paquete             BIGSERIAL PRIMARY KEY,
    nombre_paquete         VARCHAR(150) NOT NULL,
    cantidad_horas_paquete int not null default 1 check (cantidad_horas_paquete >=1),
    precio_paquete         NUMERIC(12,2) NOT NULL CHECK (precio_paquete >= 0),

    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    estado_registro        BOOLEAN DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT DEFAULT 1
);



CREATE TABLE persona.unidad_educativa (
    id_unidad_educativa     bigserial PRIMARY KEY,
    
    -- Datos principales
    nombre                  varchar(150) NOT NULL,
    latitud                 decimal(9,6),   -- latitud en formato decimal
    longitud                decimal(9,6),   -- longitud en formato decimal
    categoria               varchar(20) NOT NULL
                             CHECK (categoria IN ('privada', 'convenio', 'fiscal')),
    
    -- Auditoría
    fecha_registro          timestamp DEFAULT now(),
    id_usuario              bigint,
    id_usuario_modificacion bigint,
    version_registro        int DEFAULT 1,
    estado_registro         boolean DEFAULT true
);

CREATE TABLE persona.persona_estudiante (
    id_persona              bigint primary key NOT NULL 
                             REFERENCES persona.persona(id_persona) ON DELETE CASCADE,
    
    codigo_estudiante       varchar(50) UNIQUE, 
    id_unidad_educativa     int REFERENCES persona.unidad_educativa(id_unidad_educativa),

    -- Tipo de estudiante
    tipo                    varchar(50) CHECK (tipo IN ('UNIVERSITARIO', 'COLEGIAL')),
    
    -- Solo colegiales
    nivel_actual            varchar(50) CHECK (nivel_actual IN ('PRIMARIA', 'SECUNDARIA')),
    curso_actual            varchar(50) CHECK (curso_actual IN ('PRIMERO', 'SEGUNDO', 'TERCERO', 'CUARTO', 'QUINTO', 'SEXTO')),            
    turno_actual            varchar(50) CHECK (turno_actual IN ('MAÑANA', 'TARDE', 'NOCHE')),
    
    -- Solo universitarios
    carrera                 varchar(100),       
    anio_ingreso            smallint,
    
    -- Auditoría
    fecha_registro          timestamp DEFAULT now(),
    id_usuario              bigint,
    id_usuario_modificacion bigint,
    version_registro        int DEFAULT 1,
    estado_registro         boolean DEFAULT true,

    -- Reglas de consistencia
    CONSTRAINT chk_tipo_colegial 
        CHECK (
            (tipo = 'COLEGIAL' AND nivel_actual IS NOT NULL AND curso_actual IS NOT NULL AND turno_actual IS NOT NULL 
             AND carrera IS NULL AND anio_ingreso IS NULL)
            OR 
            (tipo = 'UNIVERSITARIO' AND carrera IS NOT NULL AND anio_ingreso IS NOT NULL
             AND nivel_actual IS NULL AND curso_actual IS NULL AND turno_actual IS NULL)
        )
);

CREATE TABLE persona.persona_tutor (
    id_tutor                bigserial PRIMARY KEY,
    id_persona              bigint NOT NULL
                             REFERENCES persona.persona(id_persona) ON DELETE CASCADE,

    pago_por_hora           numeric(12,2) NOT NULL CHECK (pago_por_hora >= 0),
    nivel_experiencia       varchar(20)  NOT NULL
                             CHECK (nivel_experiencia IN ('RECLUTA', 'EXPERIMENTADO', 'SENIOR')),

    -- Especialidad por tipo/nivel
    tipo_estudiante_especialidad   varchar(20) NOT NULL
                                   CHECK (tipo_estudiante_especialidad IN ('UNIVERSITARIO','COLEGIAL')),
    nivel_estudiante_especialidad  varchar(20)
                                   CHECK (nivel_estudiante_especialidad IN ('PRIMARIA', 'SECUNDARIA')),

    -- Auditoría
    fecha_registro          timestamp DEFAULT now(),
    id_usuario              bigint,
    id_usuario_modificacion bigint,
    version_registro        int DEFAULT 1,
    estado_registro         boolean DEFAULT true,

    CONSTRAINT uq_tutor_persona UNIQUE (id_persona),

    CONSTRAINT chk_tipo_vs_nivel
      CHECK (
        (tipo_estudiante_especialidad = 'UNIVERSITARIO' AND nivel_estudiante_especialidad IS NULL)
        OR
        (tipo_estudiante_especialidad = 'COLEGIAL' AND nivel_estudiante_especialidad IS NOT NULL)
      )
);

-- 2) Catálogo simple de materias (ajústalo si ya tienes uno)
CREATE TABLE servicios_educativos.materia_tree (
    id_tree              bigserial PRIMARY KEY,
    nombre                  varchar(100) NOT NULL UNIQUE,
    tema                    varchar(100) NOT NULL,  
    subtema                 varchar(100) NOT NULL,  

    -- Auditoría
    fecha_registro          timestamp DEFAULT now(),
    id_usuario              bigint,
    id_usuario_modificacion bigint,
    version_registro        int DEFAULT 1,
    estado_registro         boolean DEFAULT true
);

-- 1) Asegurar columna fecha_modificacion en todas las tablas
ALTER TABLE servicios_educativos.producto_educativo         ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE servicios_educativos.curso_version               ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE servicios_educativos.paquetes_producto_educativo ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE persona.unidad_educativa                         ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE persona.persona_estudiante                       ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE persona.tutor                                    ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();
ALTER TABLE servicios_educativos.materia_tree                ADD COLUMN IF NOT EXISTS fecha_modificacion timestamp DEFAULT now();

-- 2) Triggers BEFORE UPDATE usando tu función contabilidad.fn_audit_bu_simple()

DROP TRIGGER IF EXISTS trg_bu_producto_educativo_audit ON servicios_educativos.producto_educativo;
CREATE TRIGGER trg_bu_producto_educativo_audit
BEFORE UPDATE ON servicios_educativos.producto_educativo
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_curso_version_audit ON servicios_educativos.curso_version;
CREATE TRIGGER trg_bu_curso_version_audit
BEFORE UPDATE ON servicios_educativos.curso_version
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_paquetes_prod_educ_audit ON servicios_educativos.paquetes_producto_educativo;
CREATE TRIGGER trg_bu_paquetes_prod_educ_audit
BEFORE UPDATE ON servicios_educativos.paquetes_producto_educativo
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_unidad_educativa_audit ON persona.unidad_educativa;
CREATE TRIGGER trg_bu_unidad_educativa_audit
BEFORE UPDATE ON persona.unidad_educativa
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_persona_estudiante_audit ON persona.persona_estudiante;
CREATE TRIGGER trg_bu_persona_estudiante_audit
BEFORE UPDATE ON persona.persona_estudiante
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_tutor_audit ON persona.tutor;
CREATE TRIGGER trg_bu_tutor_audit
BEFORE UPDATE ON persona.persona_tutor
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


DROP TRIGGER IF EXISTS trg_bu_materia_tree_audit ON servicios_educativos.materia_tree;
CREATE TRIGGER trg_bu_materia_tree_audit
BEFORE UPDATE ON servicios_educativos.materia_tree
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();



create table servicios_educativos.clase_por_hora(
	id_clase	  bigserial primary key,
	id_aula	      int not null references infraestructura.espacio(id_espacio),
	id_estudiante int not null references persona.persona_estudiante(id_persona),
	id_tutor	  int not null references persona.persona_tutor(id_tutor),
	

	id_materia_tree int not null references servicios_educativos.materia_tree,
	
	hora_llegada timestamp not null,
	motivo		 text not null check (motivo in ('EXAMEN', 'NIVELACIÓN', 'PRÁCTICO')),
	modalidad	 text not null default 'PRESENCIAL' check (modalidad in ('PRESENCIAL','VIRTUAL')),
	
	estado_registro         varchar(20) DEFAULT 'Activo',
  	fecha_registro          timestamptz  DEFAULT now(),
  	fecha_modificacion      timestamptz,
  	version_registro        int          DEFAULT 1,
  	id_usuario_creador      bigint,
  	id_usuario_modificacion bigint
);

DROP TRIGGER IF EXISTS trg_bu_clase_por_hora_audit ON servicios_educativos.clase_por_hora;
CREATE TRIGGER trg_bu_clase_por_hora_audit
BEFORE UPDATE ON servicios_educativos.clase_por_hora
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE servicios_educativos.clase_curso (
    id_clase_curso        BIGSERIAL PRIMARY KEY,

    -- Vínculos académicos
    id_curso_version      BIGINT NOT NULL
                           REFERENCES servicios_educativos.curso_version(id_curso_version) ON DELETE CASCADE,

    -- Recursos
    id_aula               BIGINT
                           REFERENCES infraestructura.espacio(id_espacio) ON DELETE SET NULL,
    id_tutor   			  BIGINT
                           REFERENCES persona.persona_tutor (id_tutor) ON DELETE SET NULL,

    -- Programación real del día
    fecha                 DATE NOT NULL,
    hora_inicio_real      TIME NOT NULL,
    hora_fin_real         TIME NOT NULL CHECK (hora_fin_real > hora_inicio_real),

    -- Estado y metadatos
    estado                VARCHAR(20) NOT NULL DEFAULT 'Programada'
                           CHECK (estado IN ('Programada','En curso','Dictada','Reprogramada','Cancelada')),
    modalidad             VARCHAR(30) DEFAULT 'Presencial'
                           CHECK (modalidad IN ('Presencial','Online','Híbrido')),
    detalle_temas_revisados                  VARCHAR(200),
    observaciones         VARCHAR(300),
    motivo_cancelacion    VARCHAR(200),

    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    fecha_modificacion 	   timestamptz,
    estado_registro        BOOLEAN   DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT       DEFAULT 1
);


DROP TRIGGER IF EXISTS trg_bu_clase_curso_audit ON servicios_educativos.clase_curso;
CREATE TRIGGER trg_bu_clase_curso_audit
BEFORE UPDATE ON servicios_educativos.clase_curso
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

-- Función de validación de AULA
CREATE OR REPLACE FUNCTION servicios_educativos.fn_validar_aula()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_tipo       infraestructura.tipo_espacio;
  v_categoria  infraestructura.categoria_sala;
BEGIN
  -- Si no se está seteando aula (nullable en algunas tablas), no validar
  IF NEW.id_aula IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT e.tipo, e.categoria_sala
    INTO v_tipo, v_categoria
    FROM infraestructura.espacio e
   WHERE e.id_espacio = NEW.id_aula;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El id_aula=% no existe en infraestructura.espacio.', NEW.id_aula
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_tipo <> 'SALA'::infraestructura.tipo_espacio THEN
    RAISE EXCEPTION 'El espacio % no es de tipo SALA (tipo=%).', NEW.id_aula, v_tipo;
  END IF;

  IF v_categoria <> 'AULA'::infraestructura.categoria_sala THEN
    RAISE EXCEPTION 'El espacio % no es categoría AULA (categoria=%).', NEW.id_aula, v_categoria;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger en clase_por_hora
DROP TRIGGER IF EXISTS trg_biud_validar_aula_cph ON servicios_educativos.clase_por_hora;
CREATE TRIGGER trg_biud_validar_aula_cph
BEFORE INSERT OR UPDATE OF id_aula ON servicios_educativos.clase_por_hora
FOR EACH ROW
EXECUTE FUNCTION servicios_educativos.fn_validar_aula();

-- Trigger en clase_curso
DROP TRIGGER IF EXISTS trg_biud_validar_aula_cc ON servicios_educativos.clase_curso;
CREATE TRIGGER trg_biud_validar_aula_cc
BEFORE INSERT OR UPDATE OF id_aula ON servicios_educativos.clase_curso
FOR EACH ROW
EXECUTE FUNCTION servicios_educativos.fn_validar_aula();


-- Tabla: asistencia a clase de curso
CREATE TABLE servicios_educativos.asistencia_clase_curso (
    id_asistencia              BIGSERIAL PRIMARY KEY,

    -- Vínculos
    id_clase_curso             BIGINT NOT NULL
                                REFERENCES servicios_educativos.clase_curso(id_clase_curso) ON DELETE CASCADE,
    id_estudiante              BIGINT NOT NULL
                                REFERENCES persona.persona_estudiante(id_persona) ON DELETE RESTRICT,

    -- Datos de control
    estado_asistencia          VARCHAR(15) NOT NULL
                                CHECK (estado_asistencia IN ('PRESENTE','AUSENTE','TARDANZA','RETIRADO','JUSTIFICADO')),
    hora_entrada               TIME,
    hora_salida                TIME,
    motivo_justificacion       VARCHAR(250),   -- requerido si JUSTIFICADO
    observaciones              VARCHAR(300),

    -- Auditoría
    fecha_registro             TIMESTAMP  DEFAULT now(),
    fecha_modificacion         timestamptz,
    estado_registro            BOOLEAN    DEFAULT TRUE,
    id_usuario                 BIGINT,
    id_usuario_modificacion    BIGINT,
    version_registro           INT        DEFAULT 1,

    -- Evitar duplicados: un registro por (clase, estudiante)
    CONSTRAINT uq_asistencia_clase_estudiante UNIQUE (id_clase_curso, id_estudiante),

    -- Reglas de consistencia:
    -- 1) Si PRESENTE/TARDANZA/RETIRADO => hora_entrada obligatoria
    -- 2) Si RETIRADO => hora_salida obligatoria y >= hora_entrada
    -- 3) Si AUSENTE => sin horas (opcionales, pero si hay salida debe haber entrada)
    -- 4) Si JUSTIFICADO => motivo_justificacion obligatorio (horas opcionales)
    CONSTRAINT chk_asistencia_horas_y_motivo CHECK (
        (estado_asistencia IN ('PRESENTE','TARDANZA') AND hora_entrada IS NOT NULL AND
            (hora_salida IS NULL OR hora_salida >= hora_entrada))
        OR
        (estado_asistencia = 'RETIRADO' AND hora_entrada IS NOT NULL AND hora_salida IS NOT NULL AND hora_salida >= hora_entrada)
        OR
        (estado_asistencia = 'AUSENTE' AND
            (hora_entrada IS NULL OR (hora_entrada IS NOT NULL AND (hora_salida IS NULL OR hora_salida >= hora_entrada))))
        OR
        (estado_asistencia = 'JUSTIFICADO' AND motivo_justificacion IS NOT NULL AND
            (hora_salida IS NULL OR hora_entrada IS NULL OR hora_salida >= hora_entrada))
    )
);

-- Índices útiles
CREATE INDEX idx_asistencia_clase_curso    ON servicios_educativos.asistencia_clase_curso(id_clase_curso);
CREATE INDEX idx_asistencia_estudiante     ON servicios_educativos.asistencia_clase_curso(id_estudiante);
CREATE INDEX idx_asistencia_estado         ON servicios_educativos.asistencia_clase_curso(estado_asistencia);

-- Trigger BEFORE UPDATE de auditoría (usa tu función existente)
DROP TRIGGER IF EXISTS trg_bu_asistencia_clase_curso_audit ON servicios_educativos.asistencia_clase_curso;
CREATE TRIGGER trg_bu_asistencia_clase_curso_audit
BEFORE UPDATE ON servicios_educativos.asistencia_clase_curso
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS inventario.bien_instancia (
  id_bien_instancia	    bigserial PRIMARY KEY,
  id_bien         		bigint NOT NULL REFERENCES inventario.bien(id_bien) ON DELETE CASCADE,
  descripcion_especificaciones 	text not null,
  fecha_compra	  				date not null,
  id_proveedor_compra			int references persona.proveedor(id_proveedor),
  
  costo_compra    numeric(18,4) CHECK (costo_compra IS NULL OR costo_compra >= 0),
  precio_compra   numeric(18,2) CHECK (precio_compra IS NULL OR precio_compra >= 0),
  
  serial_unico		varchar(120),
  fecha_fabricacion date,
  fecha_vencimiento date,
  
  -- Auditoria
  estado_registro         varchar(20) DEFAULT 'Activo',
  fecha_registro          timestamptz  DEFAULT now(),
  fecha_modificacion      timestamptz,
  version_registro        int          DEFAULT 1,
  id_usuario_creador      bigint,
  id_usuario_modificacion bigint
);


CREATE TABLE IF NOT EXISTS inventario.bien_lote (
  id_lote         		bigserial PRIMARY KEY,
  id_bien         		bigint NOT NULL REFERENCES inventario.bien(id_bien) ON DELETE CASCADE,
  lote_codigo     		varchar(80) NOT NULL,
  fecha_compra	  		date not null,
  id_proveedor_compra	int references persona.proveedor(id_proveedor),
  cantidad_compra 		int not null check (cantidad_compra > 0),
  
  -- Informacion compra
  costo_compra_unitario    numeric(18,4) CHECK (costo_compra_unitario IS NULL OR costo_compra_unitario >= 0),
  precio_compra_unitario   numeric(18,2) CHECK (precio_compra_unitario IS NULL OR precio_compra_unitario >= 0),
  fecha_fabricacion date,
  fecha_vencimiento date,
  
  -- Auditoria
  estado_registro         varchar(20) DEFAULT 'Activo',
  fecha_registro          timestamptz  DEFAULT now(),
  fecha_modificacion      timestamptz,
  version_registro        int          DEFAULT 1,
  id_usuario_creador      bigint,
  id_usuario_modificacion bigint,
  UNIQUE (id_bien, lote_codigo)
);


DROP TRIGGER IF EXISTS bu_bien ON inventario.bien;
CREATE TRIGGER bu_bien
BEFORE UPDATE ON inventario.bien
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE inventario.movimiento_detalle (
  id_movimiento           bigserial primary key,

  id_bien                 bigint NOT NULL REFERENCES inventario.bien(id_bien),
  id_lote                 bigint REFERENCES inventario.bien_lote(id_lote),
  id_bien_instancia       bigint REFERENCES inventario.bien_instancia(id_bien_instancia),

  cantidad                numeric(18,6) NOT NULL DEFAULT 1,

  -- Ubicación/tienda de ENTRADA (destino)
  id_espacio_entrada      bigint REFERENCES infraestructura.espacio(id_espacio),

  -- Ubicación/tienda de SALIDA (origen)
  id_espacio_salida       bigint REFERENCES infraestructura.espacio(id_espacio),

  -- Reglas estructurales
  CONSTRAINT ck_detalle_exclusividad CHECK (
    (id_lote IS NULL OR id_bien_instancia IS NULL)
  ),

  -- Cantidad > 0 (si manejas signo por tipo de movimiento, quita este check o cámbialo a <> 0)
  CONSTRAINT ck_cantidad_pos CHECK (cantidad > 0),

  -- Si es instancia, cantidad debe ser exactamente 1
  CONSTRAINT ck_instancia_cantidad_unidad CHECK (
    id_bien_instancia IS NULL OR cantidad = 1
  )
);


DROP TRIGGER IF EXISTS trg_bu_bien_instancia_audit ON inventario.bien_instancia;
CREATE TRIGGER trg_bu_bien_instancia_audit
BEFORE UPDATE ON inventario.bien_instancia
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

-- inventario.bien_lote
DROP TRIGGER IF EXISTS trg_bu_bien_lote_audit ON inventario.bien_lote;
CREATE TRIGGER trg_bu_bien_lote_audit
BEFORE UPDATE ON inventario.bien_lote
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

-- Evitar fechas incoherentes
ALTER TABLE inventario.bien_instancia
  ADD CONSTRAINT chk_instancia_fechas
  CHECK (
    (fecha_fabricacion IS NULL OR fecha_compra >= fecha_fabricacion) AND
    (fecha_vencimiento IS NULL OR fecha_vencimiento >= COALESCE(fecha_fabricacion, fecha_compra))
  );

ALTER TABLE inventario.bien_lote
  ADD CONSTRAINT chk_lote_fechas
  CHECK (
    (fecha_fabricacion IS NULL OR fecha_compra >= fecha_fabricacion) AND
    (fecha_vencimiento IS NULL OR fecha_vencimiento >= COALESCE(fecha_fabricacion, fecha_compra))
  );


CREATE INDEX IF NOT EXISTS ix_mvdet_mov     ON inventario.movimiento_detalle(id_movimiento);
CREATE INDEX IF NOT EXISTS ix_mvdet_bien    ON inventario.movimiento_detalle(id_bien);
CREATE INDEX IF NOT EXISTS ix_mvdet_lote    ON inventario.movimiento_detalle(id_lote) WHERE id_lote IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_mvdet_inst    ON inventario.movimiento_detalle(id_bien_instancia) WHERE id_bien_instancia IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_mvdet_esp_in  ON inventario.movimiento_detalle(id_espacio_entrada);
CREATE INDEX IF NOT EXISTS ix_mvdet_esp_out ON inventario.movimiento_detalle(id_espacio_salida);


CREATE SCHEMA IF NOT EXISTS administracion;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_contrato') THEN
    CREATE TYPE administracion.tipo_contrato AS ENUM ('INDEFINIDO','PLAZO_FIJO','HONORARIOS');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='jornada_laboral') THEN
    CREATE TYPE administracion.jornada_laboral AS ENUM ('FULL_TIME','PART_TIME');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='frecuencia_pago') THEN
    CREATE TYPE administracion.frecuencia_pago AS ENUM ('MENSUAL','QUINCENAL','SEMANAL');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_esquema_pago') THEN
    CREATE TYPE administracion.tipo_esquema_pago AS ENUM ('SUELDO','POR_HORA','COMISION','MIXTO');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_kpi') THEN
    CREATE TYPE administracion.tipo_kpi AS ENUM ('INPUT','OUTPUT','OUTCOME');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='frecuencia_kpi') THEN
    CREATE TYPE administracion.frecuencia_kpi AS ENUM ('DIARIA','SEMANAL','MENSUAL','TRIMESTRAL');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='estado_okr') THEN
    CREATE TYPE administracion.estado_okr AS ENUM ('PLANIFICADO','EN_PROGRESO','COMPLETADO','CANCELADO');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='direccion_kpi') THEN
    CREATE TYPE administracion.direccion_kpi AS ENUM ('ASC','DESC'); -- mayor es mejor | menor es mejor
  END IF;
END$$;


CREATE TABLE IF NOT EXISTS administracion.posicion (
  id_posicion         bigserial PRIMARY KEY,
  codigo              varchar(40) UNIQUE NOT NULL,
  nombre              varchar(150) NOT NULL,
  id_posicion_parent  bigint REFERENCES administracion.posicion(id_posicion),
  descripcion         text,

  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);

DROP TRIGGER IF EXISTS bu_posicion ON administracion.posicion;
CREATE TRIGGER bu_posicion
BEFORE UPDATE ON administracion.posicion
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE INDEX IF NOT EXISTS idx_posicion_parent   ON administracion.posicion(id_posicion_parent);


--bigint REFERENCES infraestructura.sucursal(id_sucursal)

CREATE TABLE IF NOT EXISTS administracion.empleado (
  id_empleado         bigserial PRIMARY KEY,
  id_persona          bigint NOT NULL UNIQUE
                       REFERENCES persona.persona(id_persona) ON DELETE RESTRICT,
  fecha_ingreso       date NOT NULL,
  fecha_salida        date,
  tipo_contrato       administracion.tipo_contrato NOT NULL DEFAULT 'INDEFINIDO',
  jornada             administracion.jornada_laboral NOT NULL DEFAULT 'FULL_TIME',
  email_corporativo   varchar(200),
  telefono_corporativo varchar(100),

  id_sucursal         bigint,
  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint,

  CONSTRAINT ck_empleado_fechas CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);


DROP TRIGGER IF EXISTS bu_empleado ON administracion.empleado;
CREATE TRIGGER bu_empleado
BEFORE UPDATE ON administracion.empleado
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE INDEX IF NOT EXISTS idx_empleado_sucursal ON administracion.empleado(id_sucursal);


create table if not exists administracion.empleado_posicion_pago(
	id_empleado_posicion	bigserial primary key,
	id_empleado				bigint NOT NULL REFERENCES administracion.empleado(id_empleado) ON DELETE CASCADE,
  	id_posicion          	bigint NOT NULL REFERENCES administracion.posicion(id_posicion) ON DELETE RESTRICT,

  	vigente_desde        date NOT NULL DEFAULT CURRENT_DATE,
  	vigente_hasta        date,
	
  	tipo_esquema_pago    administracion.tipo_esquema_pago NOT NULL,
  	frecuencia_pago      administracion.frecuencia_pago NOT NULL DEFAULT 'MENSUAL',
  	moneda               varchar(3) DEFAULT 'BOB',
  	
  	pago_por_hora		 numeric(18,2) check (pago_por_hora >0),
  	sueldo_mensual       numeric(18,2) CHECK (sueldo_mensual IS NULL OR sueldo_mensual >= 0),
  	porcentaje_comision  numeric(5,2)  CHECK (porcentaje_comision IS NULL OR (porcentaje_comision >= 0 AND porcentaje_comision <= 100)),
	comision_fija		 numeric(18,2)	check (comision_fija >= 0),
  	tipo_comisionable	 text check (tipo_comisionable in ('Fija', 'Variable')),
  	tipo_calculo_comisionable	 text check(tipo_comisionable in ('Directa', 'Indirecta')),
  	
  estado_registro      varchar(20) DEFAULT 'Activo',
  fecha_registro       timestamptz  DEFAULT now(),
  fecha_modificacion   timestamptz,
  version_registro     int          DEFAULT 1,
  id_usuario_creador   bigint,
  id_usuario_modificacion bigint,

  CONSTRAINT ck_periodo_vigente CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),

  -- Guardrails por tipo de esquema
  CONSTRAINT ck_esquema_pago_valores CHECK (
    (tipo_esquema_pago = 'SUELDO'   AND sueldo_mensual IS NOT NULL AND pago_por_hora IS NULL AND porcentaje_comision IS NULL) OR
    (tipo_esquema_pago = 'POR_HORA' AND pago_por_hora  IS NOT NULL AND sueldo_mensual IS NULL AND porcentaje_comision IS NULL) OR
    (tipo_esquema_pago = 'COMISION' AND porcentaje_comision IS NOT NULL AND sueldo_mensual IS NULL AND pago_por_hora IS NULL) OR
    (tipo_esquema_pago = 'MIXTO'    AND ( (sueldo_mensual IS NOT NULL AND porcentaje_comision IS NOT NULL) OR
                                          (pago_por_hora IS NOT NULL AND porcentaje_comision IS NOT NULL) ) )
  )
);
  	
DROP TRIGGER IF EXISTS trg_empleado_posicion_pago ON administracion.empleado_posicion_pago;
CREATE TRIGGER trg_empleado_posicion_pago 
BEFORE UPDATE ON administracion.empleado_posicion_pago
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();



create table if not exists administracion.empleado_registro_pago(
	id_pago 		bigserial primary key,
	fecha_pago		date not null,
	
	--Pagos
	haber_basico_pagado   		float8 not null default 0,
	comisiones_totales_pagadas 	float8 not null default 0,
	aguinaldos_totales_pagados  float8 not null default 0,
	indemnizacion_total_pagada  float8 not null default 0,
	otros_cargos_pagados        float8 not null default 0,
	descripcion_otros_cargos_pagados text,
	
	-- Notas
	notas_pago					text,
		
	-- Auditoria
	estado_registro       varchar(20) DEFAULT 'Activo',
	fecha_registro        timestamptz  DEFAULT now(),
	fecha_modificacion    timestamptz,
	version_registro      int          DEFAULT 1,
	id_usuario_creador    bigint,
	id_usuario_modificacion bigint
);

DROP TRIGGER IF EXISTS trg_bu_empleado_registro_pago_audit ON administracion.empleado_registro_pago;
CREATE TRIGGER trg_bu_empleado_registro_pago_audit
BEFORE UPDATE ON administracion.empleado_registro_pago
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE TABLE IF NOT EXISTS administracion.departamento (
  id_departamento          bigserial PRIMARY KEY,

  -- Identificación
  codigo                   varchar(30)  NOT NULL,                 -- ej. "FIN", "ACAD-ALGB"
  nombre                   varchar(120) NOT NULL,
  descripcion_funciones    varchar(240),

  -- Jerarquía y vínculos
  id_departamento_padre    bigint
                            REFERENCES administracion.departamento(id_departamento)
                            ON DELETE SET NULL,
  id_sucursal              bigint
                            REFERENCES infraestructura.sucursal(id_sucursal)
                            ON DELETE SET NULL,
  id_jefe_empleado         bigint
                            REFERENCES administracion.empleado(id_empleado)
                            ON DELETE SET NULL,

  -- Vigencia / estado funcional
  es_activo                boolean      NOT NULL DEFAULT true,
  fecha_inicio             date,
  fecha_fin                date,
  CONSTRAINT ck_dep_vigencia CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),

  -- Unicidades útiles
  CONSTRAINT uq_dep_codigo UNIQUE (codigo),
  CONSTRAINT uq_dep_sucursal_nombre UNIQUE (id_sucursal, nombre),

  -- Auditoría
  estado_registro          varchar(20)  DEFAULT 'Activo',
  fecha_registro           timestamptz  DEFAULT now(),
  fecha_modificacion       timestamptz,
  version_registro         int          DEFAULT 1,
  id_usuario_creador       bigint,
  id_usuario_modificacion  bigint
);

-- Índices recomendados
CREATE INDEX IF NOT EXISTS ix_dep_padre     ON administracion.departamento(id_departamento_padre);
CREATE INDEX IF NOT EXISTS ix_dep_sucursal  ON administracion.departamento(id_sucursal);
CREATE INDEX IF NOT EXISTS ix_dep_jefe      ON administracion.departamento(id_jefe_empleado);
CREATE INDEX IF NOT EXISTS ix_dep_activo    ON administracion.departamento(es_activo) WHERE es_activo;


CREATE SCHEMA IF NOT EXISTS infraestructura;

-- =========================
-- ENUMs de apoyo
-- =========================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_espacio') THEN
    CREATE TYPE infraestructura.tipo_espacio AS ENUM ('AULA','SALA');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='categoria_sala') THEN
    CREATE TYPE infraestructura.categoria_sala AS ENUM
      ('OFICINA','CONFERENCIA','REUNION','ESPERA','TIENDA','OTRA');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='categoria_sala') THEN
    CREATE TYPE infraestructura.categoria_sala AS ENUM
      ('OFICINA','CONFERENCIA','REUNION','ESPERA','TIENDA','OTRA');
  END IF;

END$$;




CREATE TABLE IF NOT EXISTS infraestructura.sucursal (
  id_sucursal         bigserial PRIMARY KEY,
  codigo              varchar(40) UNIQUE NOT NULL,
  nombre              varchar(150) NOT NULL,
  telefono            varchar(100),
  email               varchar(200),
  direccion_linea1    varchar(180),
  ciudad              varchar(80),
  departamento        varchar(80),
  pais                varchar(80),
  horario_texto       varchar(240),
  largo_m			  float8,
  ancho_m			  float8,
  
  
  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_sucursal ON infraestructura.sucursal;
CREATE TRIGGER bu_sucursal
BEFORE UPDATE ON infraestructura.sucursal
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

alter table administracion.empleado
add constraint fgk_id_sucursal foreign key (id_sucursal) references infraestructura.sucursal(id_sucursal);


create table if not exists infraestructura.encargado(
	id_asignacion	bigserial primary key,
	id_sucursal		int not null references infraestructura.sucursal(id_sucursal),
	id_empleado		int not null references administracion.empleado(id_empleado),
	fecha_inicio	date not null,
	fecha_fin		date not null,
	
	  -- Auditoría
	 estado_registro     varchar(20) DEFAULT 'Activo',
	 fecha_registro      timestamptz  DEFAULT now(),
	 fecha_modificacion  timestamptz,
	 version_registro    int          DEFAULT 1,
	 id_usuario_creador  bigint,
	 id_usuario_modificacion bigint
);
DROP TRIGGER IF EXISTS bu_encargado ON infraestructura.encargado;
CREATE TRIGGER bu_encargado
BEFORE UPDATE ON infraestructura.encargado
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS infraestructura.edificio (
  id_edificio         bigserial PRIMARY KEY,
  id_sucursal         bigint NOT NULL
                      REFERENCES infraestructura.sucursal(id_sucursal) ON DELETE CASCADE,
  codigo              varchar(40) NOT NULL,
  nombre              varchar(150) NOT NULL,
  direccion_linea1    varchar(180),
  ciudad              varchar(80),
  departamento        varchar(80),
  pais                varchar(80),
  latitud             numeric(9,6)  CHECK (latitud  IS NULL OR (latitud  BETWEEN -90 AND 90)),
  longitud            numeric(9,6)  CHECK (longitud IS NULL OR (longitud BETWEEN -180 AND 180)),
  pisos               smallint CHECK (pisos IS NULL OR pisos > 0),
  largo_m			  float8 check (largo_m > 0),
  ancho_m			  float8 check (ancho_m >0),
  id_administrador    bigint REFERENCES administracion.empleado (id_empleado),

  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint,

  CONSTRAINT uq_edificio_sucursal_codigo UNIQUE (id_sucursal, codigo)
);
CREATE INDEX IF NOT EXISTS idx_edificio_sucursal ON infraestructura.edificio(id_sucursal);

DROP TRIGGER IF EXISTS bu_edificio ON infraestructura.edificio;
CREATE TRIGGER bu_edificio
BEFORE UPDATE ON infraestructura.edificio
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE TABLE IF NOT EXISTS infraestructura.espacio (
  id_espacio          bigserial PRIMARY KEY,
  id_edificio         bigint NOT NULL
                      REFERENCES infraestructura.edificio(id_edificio) ON DELETE CASCADE,

  -- Tipo general del espacio (SALA, PASILLO, BODEGA, etc.)
  tipo                infraestructura.tipo_espacio NOT NULL,

  -- Especialización (sólo aplica si tipo = 'SALA')
  categoria_sala      infraestructura.categoria_sala,   -- AULA, TIENDA, OFICINA, ...
  tipo_aula           infraestructura.tipo_aula,         -- TEORIA, LABORATORIO, ...
  es_privada          boolean DEFAULT false,

  -- Datos comunes
  nombre              varchar(150),
  piso                smallint,
  capacidad           smallint CHECK (capacidad IS NULL OR capacidad >= 0),
  largo_m             double precision CHECK (largo_m IS NULL OR largo_m > 0),
  ancho_m             double precision CHECK (ancho_m IS NULL OR ancho_m > 0),
  observaciones       varchar(240),

  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz  DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int          DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint,

  -- Reglas de consistencia (STI)
  -- 1) Si NO es SALA => categoria_sala y tipo_aula deben ser NULL
  CONSTRAINT ck_espacio_no_sala
    CHECK (
      (tipo <> 'SALA' AND categoria_sala IS NULL AND tipo_aula IS NULL)
      OR (tipo = 'SALA')
    ),

  -- 2) Si ES SALA => categoria_sala obligatoria
  CONSTRAINT ck_espacio_sala_categoria
    CHECK (
      tipo <> 'SALA'
      OR categoria_sala IS NOT NULL
    )
);

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_espacio_tipo       ON infraestructura.espacio(tipo);
CREATE INDEX IF NOT EXISTS idx_espacio_categoria  ON infraestructura.espacio(categoria_sala);
CREATE INDEX IF NOT EXISTS idx_espacio_edificio   ON infraestructura.espacio(id_edificio);

DROP TRIGGER IF EXISTS bu_espacio ON infraestructura.espacio;
CREATE TRIGGER bu_espacio
BEFORE UPDATE ON infraestructura.espacio
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();



CREATE TABLE IF NOT EXISTS infraestructura.tienda (
  id_tienda              bigserial PRIMARY KEY,
  id_espacio             bigint UNIQUE
                         REFERENCES infraestructura.espacio(id_espacio) ON DELETE SET NULL,
  codigo                 varchar(40) UNIQUE NOT NULL,
  nombre                 varchar(150) not null,
  horario_texto          varchar(240),

  -- Gestión
  id_responsable         bigint REFERENCES persona.persona(id_persona),

  -- Auditoría (solo UPDATE)
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint
);

ALTER TABLE infraestructura.tienda
  ADD CONSTRAINT uq_tienda_espacio UNIQUE (id_espacio);

DROP TRIGGER IF EXISTS bu_tienda ON infraestructura.tienda;
CREATE TRIGGER bu_tienda
BEFORE UPDATE ON infraestructura.tienda
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE OR REPLACE FUNCTION infraestructura.fn_guard_tienda()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tipo infraestructura.tipo_espacio;
  v_cat  infraestructura.categoria_sala;
BEGIN
  IF NEW.id_espacio IS NOT NULL THEN
    SELECT e.tipo, e.id_sucursal
      INTO v_tipo
      FROM infraestructura.espacio e
     WHERE e.id_espacio = NEW.id_espacio;

    IF v_tipo IS DISTINCT FROM 'SALA' THEN
      RAISE EXCEPTION 'La tienda debe enlazar a un ESPACIO tipo SALA (espacio=%)', NEW.id_espacio;
    END IF;

    SELECT s.categoria
      INTO v_cat
      FROM infraestructura.sala_ext s
     WHERE s.id_espacio = NEW.id_espacio;

    IF v_cat IS DISTINCT FROM 'TIENDA' THEN
      RAISE EXCEPTION 'El ESPACIO enlazado debe ser SALA de categoría TIENDA (espacio=%)', NEW.id_espacio;
    END IF;
END IF;
RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_tienda ON infraestructura.tienda;
CREATE TRIGGER trg_guard_tienda
BEFORE INSERT OR UPDATE ON infraestructura.tienda
FOR EACH ROW EXECUTE FUNCTION infraestructura.fn_guard_tienda();



--  Tabla principal de deudas
create schema if not exists deuda;
CREATE TABLE IF NOT EXISTS deuda.deuda (
    id_deuda            BIGSERIAL PRIMARY KEY,
    id_proveedor        BIGINT NOT NULL
                        REFERENCES persona.proveedor(id_proveedor) ON DELETE RESTRICT,

    monto_inicial       NUMERIC(18,2) NOT NULL CHECK (monto_inicial > 0),

    tasa_anual          NUMERIC(6,4) NOT NULL CHECK (tasa_anual >= 0),  -- 0.0850 = 8.5%
    tipo_tasa           VARCHAR(20) NOT NULL CHECK (tipo_tasa IN ('SIMPLE','COMPUESTA')),
    capitalizacion      VARCHAR(20) CHECK (capitalizacion IN ('ANUAL', 'SEMESTRAL', 'TRIMESTRAL', 'BIMESTRAL', 'MENSUAL')),

    plazo_meses         INT NOT NULL CHECK (plazo_meses > 0),
    
    seguro_desgravamen_fijo numeric(18,2) check (seguro_desgravamen_fijo >=0),
    seguro_desgravamen_variable numeric(18,2) check (seguro_desgravamen_variable >=0),

    -- ⬇️ Corrección solicitada
    tipo_calculo_cuotas VARCHAR(10) not null default 'FRANCES' check (tipo_calculo_cuotas in ('FRANCES', 'ALEMAN', 'AMERICANO')),
    frecuencia_cuotas	VARCHAR not null default 'MENSUAL' check ( frecuencia_cuotas in('ANUAL', 'SEMESTRAL', 'TRIMESTRAL', 'BIMESTRAL', 'MENSUAL')),
    tipo_pago           VARCHAR(20) NOT null default 'VENCIDAS'
                        CHECK (tipo_pago IN ('VENCIDAS','ANTICIPADAS')),
    tipo_primer_pago    VARCHAR(20) NOT NULL DEFAULT 'INMEDIATA'
                        CHECK (tipo_primer_pago IN ('INMEDIATA','DIFERIDA')),

    anualidad_acordada  NUMERIC(18,2), -- opcional, si se pactó cuota fija

    fecha_inicio        DATE NOT NULL DEFAULT CURRENT_DATE,

    observaciones       TEXT
);



CREATE TABLE IF NOT EXISTS deuda.pago (
    id_pago             BIGSERIAL PRIMARY KEY,
    id_deuda            BIGINT NOT NULL
                        REFERENCES deuda.deuda(id_deuda) ON DELETE CASCADE,

    fecha_pago          DATE NOT NULL DEFAULT CURRENT_DATE,

    interes_pagado      		NUMERIC(18,2) DEFAULT 0 CHECK (interes_pagado >= 0),
    capital_amortizado  		NUMERIC(18,2) DEFAULT 0 CHECK (capital_amortizado >= 0),
    seguro_desgravamen_pagado 	numeric(18,2) default 0 check (seguro_desgravamen_pagado >=0),
    otros_recargos_pagados	    numeric(18,2) default 0 check (otros_recargos_pagados >=0),

    observaciones       TEXT
);


ALTER TABLE deuda.deuda
  ADD COLUMN IF NOT EXISTS fecha_modificacion timestamptz,
  ADD COLUMN IF NOT EXISTS version_registro   int DEFAULT 1;

ALTER TABLE deuda.pago
  ADD COLUMN IF NOT EXISTS fecha_modificacion timestamptz,
  ADD COLUMN IF NOT EXISTS version_registro   int DEFAULT 1;

/* === Reglas de consistencia recomendadas === */
ALTER TABLE deuda.deuda
  ADD CONSTRAINT chk_capitalizacion_vs_tipo_tasa
  CHECK (
    (tipo_tasa = 'COMPUESTA' AND capitalizacion IS NOT NULL)
    OR
    (tipo_tasa = 'SIMPLE'    AND capitalizacion IS NULL)
  );

/* (Opcional) coherencia de montos en pago: al menos uno > 0 */
ALTER TABLE deuda.pago
  ADD CONSTRAINT chk_pago_tiene_movimiento
  CHECK (
    (COALESCE(interes_pagado,0)
    + COALESCE(capital_amortizado,0)
    + COALESCE(seguro_desgravamen_pagado,0)
    + COALESCE(otros_recargos_pagados,0)) > 0
  );

/* === Triggers BEFORE UPDATE con tu función de auditoría === */
DROP TRIGGER IF EXISTS trg_bu_deuda_audit ON deuda.deuda;
CREATE TRIGGER trg_bu_deuda_audit
BEFORE UPDATE ON deuda.deuda
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_bu_pago_audit ON deuda.pago;
CREATE TRIGGER trg_bu_pago_audit
BEFORE UPDATE ON deuda.pago
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS administracion.kpi (
  id_kpi              bigserial PRIMARY KEY,
  nombre              varchar(150) NOT NULL,
  descripcion         text,
  unidad_medida       varchar(50) NOT NULL,    -- Ej: %, Bs, horas, etc.
  frecuencia          varchar(30),             -- Ej: mensual, trimestral, anual

  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);

CREATE TABLE IF NOT EXISTS administracion.objetivo_kpi (
  id_objetivo_kpi     bigserial PRIMARY KEY,
  id_kpi              bigint NOT NULL
                      REFERENCES administracion.kpi(id_kpi) ON DELETE CASCADE,

  periodo             varchar(30) NOT NULL,        -- Ej: 2025-Q1, 2025-M03, etc.
  valor_meta          numeric(18,4) NOT NULL,
  valor_minimo        numeric(18,4),
  valor_maximo        numeric(18,4),
  
  responsable		  int references administracion.empleado(id_empleado),
  id_sucursal		  int references infraestructura.sucursal(id_sucursal),
  id_tienda 		  int references infraestructura.tienda(id_tienda),
  id_producto		  int references servicios_educativos.producto_educativo(id_producto_educativo),  
  id_producto_tienda  int references inventario.bien(id_bien),
  
  -- Estado de cumplimiento / tracking
  cumplido            boolean DEFAULT false,

  -- Auditoría
  estado_registro     varchar(20) DEFAULT 'Activo',
  fecha_registro      timestamptz DEFAULT now(),
  fecha_modificacion  timestamptz,
  version_registro    int DEFAULT 1,
  id_usuario_creador  bigint,
  id_usuario_modificacion bigint
);

CREATE OR REPLACE FUNCTION inventario.check_es_producto_tienda()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_es_producto_tienda boolean;
BEGIN
    SELECT b.es_producto_tienda
      INTO v_es_producto_tienda
      FROM inventario.bien b
     WHERE b.id_bien = NEW.id_bien;

    IF v_es_producto_tienda THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'El bien % no es producto de tienda', NEW.id_bien
            USING ERRCODE = 'check_violation';
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_kpi_audit ON administracion.kpi;
CREATE TRIGGER trg_kpi_audit
BEFORE UPDATE ON administracion.kpi
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_objetivo_kpi_audit ON administracion.objetivo_kpi;
CREATE TRIGGER trg_objetivo_kpi_audit
BEFORE UPDATE ON administracion.objetivo_kpi
FOR EACH ROW
EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

DROP TRIGGER IF EXISTS trg_objetivo_kpi_check_es_producto_tienda ON administracion.objetivo_kpi;
create  TRIGGER trg_objetivo_kpi_check_es_producto_tienda
BEFORE UPDATE ON administracion.objetivo_kpi
FOR EACH ROW
EXECUTE FUNCTION inventario.check_es_producto_tienda();


-- ==========================================================
-- Centro de Costos -> asociación a: DEUDA, BIEN, SUCURSAL, TIENDA, EMPLEADO, POSICION
-- ==========================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_costo') THEN
    CREATE TYPE contabilidad.tipo_costo AS ENUM ('DIRECTO','INDIRECTO');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='naturaleza_costo') THEN
    CREATE TYPE contabilidad.naturaleza_costo AS ENUM ('FIJO','VARIABLE');
  END IF;
END$$;


CREATE TABLE IF NOT EXISTS contabilidad.centro_costo_mapa (
  id_cc_mapa            bigserial PRIMARY KEY,
  id_centro_costo       bigint NOT NULL REFERENCES contabilidad.centro_costo(id_centro_costo),

  -- Clasificacion y naturaleza
  tipo             contabilidad.tipo_costo NOT NULL,
  naturaleza       contabilidad.naturaleza_costo NOT NULL,
      
  -- Vigencias
  vigente_desde         date NOT NULL DEFAULT CURRENT_DATE,
  vigente_hasta         date,
  CONSTRAINT ck_ccm_periodo CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),

  -- Destinos posibles (exactamente UNO)
  id_deuda              bigint REFERENCES deuda.deuda(id_deuda),
  id_bien               bigint REFERENCES inventario.bien(id_bien),
  id_sucursal           bigint REFERENCES infraestructura.sucursal(id_sucursal),
  id_tienda             bigint REFERENCES infraestructura.tienda(id_tienda),
  id_empleado           bigint REFERENCES administracion.empleado(id_empleado),
  id_posicion           bigint REFERENCES administracion.posicion(id_posicion),
  id_departamento       bigint references administracion.departamento (id_departamento),
  
  
  CONSTRAINT ck_ccm_un_solo_destino CHECK (
    num_nonnulls(id_deuda, id_bien, id_sucursal, id_tienda, id_empleado, id_posicion) = 1
  ),

  -- Auditoría
  estado_registro       varchar(20) DEFAULT 'Activo',
  fecha_registro        timestamptz  DEFAULT now(),
  fecha_modificacion    timestamptz,
  version_registro      int          DEFAULT 1,
  id_usuario_creador    bigint,
  id_usuario_modificacion bigint
);

-- Índices parciales
CREATE INDEX IF NOT EXISTS ix_ccm_deuda    ON contabilidad.centro_costo_mapa(id_deuda)    WHERE id_deuda    IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ccm_bien     ON contabilidad.centro_costo_mapa(id_bien)     WHERE id_bien     IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ccm_sucursal ON contabilidad.centro_costo_mapa(id_sucursal) WHERE id_sucursal IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ccm_tienda   ON contabilidad.centro_costo_mapa(id_tienda)   WHERE id_tienda   IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ccm_empleado ON contabilidad.centro_costo_mapa(id_empleado) WHERE id_empleado IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ccm_posicion ON contabilidad.centro_costo_mapa(id_posicion) WHERE id_posicion IS NOT NULL;

DROP TRIGGER IF EXISTS bu_ccm ON contabilidad.centro_costo_mapa;
CREATE TRIGGER bu_ccm
BEFORE UPDATE ON contabilidad.centro_costo_mapa
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


create schema if not exists societario;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_titulo_societario') THEN
    CREATE TYPE societario.tipo_titulo_societario AS ENUM
      ('ACCION', 'CUOTA', 'PARTICIPACION', 'BONO_CONVERTIBLE', 'SAFE', 'WARRANT', 'OPCION');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_ronda') THEN
    CREATE TYPE societario.tipo_ronda AS ENUM
      ('FOUNDERS','ANGEL','SEED','A','B','C','D','PUENTE','OTRA');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'instrumento_emision') THEN
    CREATE TYPE societario.instrumento_emision AS ENUM
      ('AUMENTO_CAPITAL','CONVERSION','PLAN_OPCIONES','EMISION_SECUNDARIA','OTRO');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_origen_tenencia') THEN
    CREATE TYPE societario.tipo_origen_tenencia AS ENUM
      ('EMISION','TRANSFERENCIA','CONVERSION','EJERCICIO_OPCION','AJUSTE');
  END IF;

END$$;


CREATE TABLE IF NOT EXISTS societario.clase_titulo (
  id_clase_titulo        bigserial PRIMARY KEY,
  tipo                   societario.tipo_titulo_societario NOT NULL DEFAULT 'ACCION',
  sub_tipo				 varchar(60) NOT NULL,         -- p.ej., 'Clase A', 'Ordinaria', 'Preferida'
  descripcion            text,
  valor_nominal          numeric(18,6) CHECK (valor_nominal IS NULL OR valor_nominal >= 0),
  derechos_voto_por_titulo numeric(18,6) DEFAULT 1.0 CHECK (derechos_voto_por_titulo >= 0),
  prioridad_dividendo_bp integer,                      -- basis points de preferencia (si aplica)
  pref_liquidacion_x     numeric(18,6),                -- múltiplo de preferencia de liquidación
  es_convertible         boolean DEFAULT false,        -- si la clase per se es convertible
  es_participante        boolean DEFAULT false,        -- preferida participante (si aplica)

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  UNIQUE (tipo, sub_tipo)
);


CREATE TABLE IF NOT EXISTS societario.emision_titulo (
  id_emision             bigserial PRIMARY KEY,
  id_clase_titulo        bigint NOT NULL
                         REFERENCES societario.clase_titulo(id_clase_titulo) ON DELETE CASCADE,
  ronda                  societario.tipo_ronda DEFAULT 'OTRA',
  instrumento            societario.instrumento_emision NOT NULL DEFAULT 'AUMENTO_CAPITAL',
  serie                  varchar(30),
  fecha_emision          date NOT NULL,
  cantidad_autorizada    numeric(28,6) NOT NULL CHECK (cantidad_autorizada > 0),
  cantidad_emitida       numeric(28,6) NOT NULL CHECK (cantidad_emitida >= 0),
  precio_emision         numeric(18,6) CHECK (precio_emision IS NULL OR precio_emision >= 0),
  observaciones          text,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  CHECK (cantidad_emitida <= cantidad_autorizada)
);


CREATE TABLE IF NOT EXISTS societario.titular (
  id_titular             bigserial PRIMARY KEY,
  id_persona             bigint NOT NULL
                         REFERENCES persona.persona(id_persona) ON DELETE RESTRICT,
  es_beneficial_owner    boolean DEFAULT true, -- Beneficial vs nominee/custodio
  observaciones          text,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  UNIQUE (id_persona)
);

CREATE TABLE IF NOT EXISTS societario.tenencia (
  id_tenencia            bigserial PRIMARY KEY,
  id_emision             bigint NOT NULL
                         REFERENCES societario.emision_titulo(id_emision) ON DELETE CASCADE,
  id_titular             bigint NOT NULL
                         REFERENCES societario.titular(id_titular) ON DELETE RESTRICT,
  cantidad               numeric(28,6) NOT NULL CHECK (cantidad >= 0),
  fecha_adquisicion      date NOT NULL,
  origen                 societario.tipo_origen_tenencia NOT NULL DEFAULT 'EMISION',
  es_nominativa          boolean DEFAULT true, -- vs. al portador (si aplica legalmente)
  observaciones          text,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  UNIQUE (id_emision, id_titular) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE IF NOT EXISTS societario.transferencia_titulo (
  id_transferencia       bigserial PRIMARY KEY,
  id_emision             bigint NOT NULL
                         REFERENCES societario.emision_titulo(id_emision) ON DELETE CASCADE,
  id_titular_origen      bigint NOT NULL
                         REFERENCES societario.titular(id_titular) ON DELETE RESTRICT,
  id_titular_destino     bigint NOT NULL
                         REFERENCES societario.titular(id_titular) ON DELETE RESTRICT,
  cantidad               numeric(28,6) NOT NULL CHECK (cantidad > 0),
  precio_unitario        numeric(18,6) CHECK (precio_unitario IS NULL OR precio_unitario >= 0),
  fecha_transferencia    date NOT NULL,
  motivo                 text,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  CHECK (id_titular_origen <> id_titular_destino)
);

CREATE TABLE IF NOT EXISTS societario.dividendo (
  id_dividendo           bigserial PRIMARY KEY,
  id_clase_titulo        bigint NOT NULL REFERENCES societario.clase_titulo(id_clase_titulo) ON DELETE RESTRICT,
  fecha_declaracion      date NOT NULL,
  fecha_pago             date,
  monto_total            numeric(18,6) NOT NULL CHECK (monto_total >= 0),
  observaciones          text,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint
);

CREATE TABLE IF NOT EXISTS societario.dividendo_pago (
  id_dividendo_pago      bigserial PRIMARY KEY,
  id_dividendo           bigint NOT NULL REFERENCES societario.dividendo(id_dividendo) ON DELETE CASCADE,
  id_titular             bigint NOT NULL REFERENCES societario.titular(id_titular) ON DELETE RESTRICT,
  monto_pagado           numeric(18,6) NOT NULL CHECK (monto_pagado >= 0),
  fecha_pago_real        date,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  UNIQUE (id_dividendo, id_titular)
);


CREATE TABLE IF NOT EXISTS contabilidad.transaccion (
  id_transaccion        bigserial PRIMARY KEY,

  fecha_transaccion     date NOT NULL DEFAULT now(),
  
  tipo_transaccion      contabilidad.tipo_transaccion NOT NULL,
  sub_tipo_transaccion	text, 
  glosa 				varchar(300),

  -- Centro de costos (se resuelve por trigger si es NULL)
  id_centro_costo_mapa   bigint REFERENCES contabilidad.centro_costo_mapa(id_cc_mapa),

  -- Enlaces (opcionales, validados por tipo)
  -- Inventario
  id_bien				bigint references inventario.bien(id_bien),
  id_movimiento_detalle bigint REFERENCES inventario.movimiento_detalle(id_movimiento),

  -- Deuda
  id_deuda              bigint REFERENCES deuda.deuda(id_deuda),
  id_pago_deuda         bigint REFERENCES deuda.pago(id_pago),

  -- Empleados / Nómina
  id_empleado            bigint REFERENCES administracion.empleado(id_empleado),
  id_empleado_pago       bigint references administracion.empleado_registro_pago(id_pago),
  id_departamento       bigint references administracion.departamento (id_departamento),


  -- Ventas
  id_cliente 			bigint references persona.persona (id_persona),
  id_clase_por_hora		bigint references servicios_educativos.clase_por_hora(id_clase),
  id_producto_educativo bigint references servicios_educativos.producto_educativo(id_producto_educativo),
  id_curso_version      bigint references servicios_educativos.curso_version(id_curso_version),

  -- Infraestructura / Comercial
  id_sucursal           bigint REFERENCES infraestructura.sucursal(id_sucursal),
  id_tienda             bigint REFERENCES infraestructura.tienda(id_tienda),

  -- Proveedor / Compras
  id_proveedor          bigint REFERENCES persona.proveedor(id_proveedor),
  	
  -- Societario
  id_dividendo_pago		bigint references societario.dividendo_pago(id_dividendo_pago),
  id_emision_titulo		bigint references societario.emision_titulo(id_emision),
  
  -- Auditoría
  estado_registro       varchar(20) DEFAULT 'Activo',
  fecha_registro        timestamptz  DEFAULT now(),
  fecha_modificacion    timestamptz,
  version_registro      int          DEFAULT 1,
  id_usuario_creador    bigint,
  id_usuario_modificacion bigint
);

CREATE INDEX IF NOT EXISTS ix_transaccion_tipo_fecha  ON contabilidad.transaccion(tipo_transaccion, fecha_transaccion);
CREATE INDEX IF NOT EXISTS ix_transaccion_ccosto      ON contabilidad.transaccion(id_centro_costo_mapa);
CREATE INDEX IF NOT EXISTS ix_transaccion_mov         ON contabilidad.transaccion(id_movimiento_detalle);
CREATE INDEX IF NOT EXISTS ix_transaccion_pago_deuda  ON contabilidad.transaccion(id_pago_deuda);
CREATE INDEX IF NOT EXISTS ix_transaccion_empleado    ON contabilidad.transaccion(id_empleado);
CREATE INDEX IF NOT EXISTS ix_transaccion_tienda      ON contabilidad.transaccion(id_tienda);
CREATE INDEX IF NOT EXISTS ix_transaccion_sucursal    ON contabilidad.transaccion(id_sucursal);

DROP TRIGGER IF EXISTS bu_transaccion ON contabilidad.transaccion;
CREATE TRIGGER bu_transaccion
BEFORE UPDATE ON contabilidad.transaccion
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


CREATE TABLE IF NOT EXISTS contabilidad.cuenta_asignacion (
  id_cuenta_asignacion  bigserial PRIMARY KEY,
  entidad_tipo          text NOT NULL,

  id_empleado			bigint references administracion.empleado(id_empleado),
  
  id_persona_estudiante bigint references persona.persona_estudiante(id_persona),
  id_persona_tutor 		bigint references persona.persona_tutor(id_tutor),
  
 
  id_sucursal           bigint REFERENCES infraestructura.sucursal(id_sucursal),
  id_edificio		    bigint REFERENCES infraestructura.edificio(id_edificio),
  id_tienda             bigint REFERENCES infraestructura.tienda(id_tienda),
  id_bien				bigint references inventario.bien(id_bien),
  id_deuda              bigint REFERENCES deuda.deuda(id_deuda),
  id_proveedor          bigint REFERENCES persona.proveedor(id_proveedor),  
  id_departamento       bigint references administracion.departamento (id_departamento),

  
  id_cuenta              bigint NOT NULL REFERENCES contabilidad.cuenta(id_cuenta),
  prioridad              smallint NOT NULL DEFAULT 1,  -- para “fallbacks”/preferencias

  vigente_desde          date NOT NULL DEFAULT CURRENT_DATE,
  vigente_hasta          date,

  -- Auditoría
  estado_registro        varchar(20) DEFAULT 'Activo',
  fecha_registro         timestamptz  DEFAULT now(),
  fecha_modificacion     timestamptz,
  version_registro       int          DEFAULT 1,
  id_usuario_creador     bigint,
  id_usuario_modificacion bigint,

  CONSTRAINT ck_cta_asig_periodo CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);

DROP TRIGGER IF EXISTS bu_cuenta_asignacion ON contabilidad.cuenta_asignacion;
CREATE TRIGGER bu_cuenta_asignacion
BEFORE UPDATE ON contabilidad.cuenta_asignacion
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

create table if not exists contabilidad.archivos_transaccion(
	id_archivo bigserial primary key,
	id_transaccion int not null references contabilidad.transaccion(id_transaccion),
	link_achivo text not null,
	

	 estado_registro        varchar(20) DEFAULT 'Activo',
	 fecha_registro         timestamptz  DEFAULT now(),
	 fecha_modificacion     timestamptz,
	 version_registro       int          DEFAULT 1,
	 id_usuario_creador     bigint,
	 id_usuario_modificacion bigint
);


DROP TRIGGER IF EXISTS bu_archivos_transaccion ON contabilidad.archivos_transaccion;
CREATE TRIGGER bu_archivos_transaccion 
BEFORE UPDATE ON contabilidad.archivos_transaccion 
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();


create table if not exists contabilidad.transaccion_movimiento_cuenta(
	id_movimiento bigserial primary key,
	id_transaccion int not null references contabilidad.transaccion(id_transaccion),
	id_cuenta int not null references contabilidad.cuenta(id_cuenta),
	debe float8 not null default 0,
	haber float8 not null default 0,
	
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint	
);

DROP TRIGGER IF EXISTS bu_transaccion_movimiento_cuenta ON contabilidad.transaccion_movimiento_cuenta ;
CREATE TRIGGER bu_transaccion_movimiento_cuenta 
BEFORE UPDATE ON contabilidad.transaccion_movimiento_cuenta 
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

create table if not exists persona.estudiante_padre(
	id_asociacion bigserial primary key,
	id_padre int references persona.persona (id_persona),
	id_estudiante int references persona.persona_estudiante(id_persona),
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint	
);

DROP TRIGGER IF EXISTS bu_estudiante_padre ON persona.estudiante_padre;
CREATE TRIGGER bu_estudiante_padre 
BEFORE UPDATE ON persona.estudiante_padre
FOR EACH ROW EXECUTE FUNCTION contabilidad.fn_audit_bu_simple();

CREATE OR REPLACE FUNCTION persona.registrar_persona_estudiante(
    p_id_persona              bigint,
    p_nombres                 varchar(100),
    p_apellidos               varchar(100),
    p_telefono                varchar(100),
    p_fecha_nacimiento        date,
    p_email                   varchar(200),

    p_codigo_estudiante       varchar(50),
    p_id_unidad_educativa     int,
    p_tipo                    varchar(50),  -- 'UNIVERSITARIO' o 'COLEGIAL'
    p_nivel_actual            varchar(50), -- PRIMARIA/SECUNDARIA (solo COLEGIAL)
    p_curso_actual            varchar(50), -- PRIMERO..SEXTO (solo COLEGIAL)
    p_turno_actual            varchar(50), -- MAÑANA/TARDE/NOCHE (solo COLEGIAL)
    p_carrera                 varchar(100), -- solo UNIVERSITARIO
    p_anio_ingreso            smallint ,     -- solo UNIVERSITARIO

    -- Auditoría
    p_id_usuario              bigint
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_persona    bigint;
    v_codigo        varchar(50);
    v_exists        boolean;
BEGIN
    -- 0) Si se pasa id_persona, validar que exista
    IF p_id_persona IS NOT NULL THEN
        SELECT TRUE
        INTO v_exists
        FROM persona.persona
        WHERE id_persona = p_id_persona;

        IF NOT v_exists THEN
            RAISE EXCEPTION 'No existe persona.id_persona=%', p_id_persona;
        END IF;

        v_id_persona := p_id_persona;
    ELSE
        -- 1) Crear persona base
        INSERT INTO persona.persona(
            nombres, apellidos, telefono, fecha_nacimiento, email,
            estado_registro, fecha_registro, version_registro,
            id_usuario_creador
        )
        VALUES (
            p_nombres, p_apellidos, p_telefono, p_fecha_nacimiento, p_email,
            'Activo', now(), 1,
            p_id_usuario
        )
        RETURNING id_persona INTO v_id_persona;
    END IF;

    -- 2) Evitar duplicidad en persona_estudiante
    IF EXISTS (SELECT 1 FROM persona.persona_estudiante e WHERE e.id_persona = v_id_persona) THEN
        RAISE EXCEPTION 'La persona % ya está registrada como ESTUDIANTE', v_id_persona;
    END IF;

    -- 3) Validaciones por tipo
    IF p_tipo NOT IN ('UNIVERSITARIO','COLEGIAL') THEN
        RAISE EXCEPTION 'p_tipo debe ser UNIVERSITARIO o COLEGIAL';
    END IF;

    IF p_tipo = 'COLEGIAL' THEN
        IF p_nivel_actual IS NULL OR p_curso_actual IS NULL OR p_turno_actual IS NULL THEN
            RAISE EXCEPTION 'Para COLEGIAL: nivel_actual, curso_actual y turno_actual son obligatorios';
        END IF;
        IF p_carrera IS NOT NULL OR p_anio_ingreso IS NOT NULL THEN
            RAISE EXCEPTION 'Para COLEGIAL no se admiten carrera ni anio_ingreso';
        END IF;
    ELSIF p_tipo = 'UNIVERSITARIO' THEN
        IF p_carrera IS NULL OR p_anio_ingreso IS NULL THEN
            RAISE EXCEPTION 'Para UNIVERSITARIO: carrera y anio_ingreso son obligatorios';
        END IF;
        IF p_nivel_actual IS NOT NULL OR p_curso_actual IS NOT NULL OR p_turno_actual IS NOT NULL THEN
            RAISE EXCEPTION 'Para UNIVERSITARIO no se admiten nivel/curso/turno';
        END IF;
    END IF;

    -- 4) Generar código si no se envió
    v_codigo := COALESCE(
        p_codigo_estudiante,
        'STD-' || to_char(now(), 'YYMM') || '-' || lpad(v_id_persona::text, 6, '0')
    );

    -- 5) Insertar en persona_estudiante
    INSERT INTO persona.persona_estudiante(
        id_persona, codigo_estudiante, id_unidad_educativa, tipo,
        nivel_actual, curso_actual, turno_actual,
        carrera, anio_ingreso,
        fecha_registro, id_usuario, version_registro, estado_registro
    )
    VALUES(
        v_id_persona, v_codigo, p_id_unidad_educativa, p_tipo,
        p_nivel_actual, p_curso_actual, p_turno_actual,
        p_carrera, p_anio_ingreso,
        now(), p_id_usuario, 1, TRUE
    );

    RETURN v_id_persona;
END;
$$;



CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE UNIQUE INDEX IF NOT EXISTS uq_persona_usuario_nombre_usuario_lower
ON persona.persona_usuario (lower(nombre_usuario));


CREATE OR REPLACE FUNCTION persona.registrar_persona_y_usuario(
    -- PERSONA (obligatorios: nombres, apellidos)
    p_nombres              varchar(100),
    p_apellidos            varchar(100),
    p_telefono             varchar(100),
    p_fecha_nacimiento     date,
    p_email                varchar(200),

    -- USUARIO
    p_nombre_usuario       varchar(80),
    p_contrasena_plana     text,
    p_tipo_usuario         varchar(200),

    -- Auditoría
    p_id_usuario_creador   bigint,

    -- OUT
    OUT o_id_persona       bigint,
    OUT o_nombre_usuario   varchar
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash text;
BEGIN
    -- Validaciones mínimas de persona
    IF coalesce(trim(p_nombres),'') = '' THEN
        RAISE EXCEPTION 'nombres es obligatorio';
    END IF;
    IF coalesce(trim(p_apellidos),'') = '' THEN
        RAISE EXCEPTION 'apellidos es obligatorio';
    END IF;

    -- Validaciones de usuario
    IF coalesce(trim(p_nombre_usuario),'') = '' THEN
        RAISE EXCEPTION 'El nombre de usuario es obligatorio';
    END IF;
    IF p_contrasena_plana IS NULL OR length(p_contrasena_plana) < 6 THEN
        RAISE EXCEPTION 'La contraseña es obligatoria y debe tener al menos 6 caracteres';
    END IF;

    -- Unicidad case-insensitive
    IF EXISTS (
        SELECT 1
          FROM persona.persona_usuario u
         WHERE lower(u.nombre_usuario) = lower(p_nombre_usuario)
    ) THEN
        RAISE EXCEPTION 'El nombre de usuario "%" ya está en uso', p_nombre_usuario;
    END IF;

    -- 1) Insertar PERSONA
    INSERT INTO persona.persona(
        nombres, apellidos, telefono, fecha_nacimiento, email,
        estado_registro, fecha_registro, version_registro, id_usuario_creador
    )
    VALUES (
        p_nombres, p_apellidos, p_telefono, p_fecha_nacimiento, p_email,
        'Activo', now(), 1, p_id_usuario_creador
    )
    RETURNING id_persona INTO o_id_persona;

    -- 2) Hash de contraseña (bcrypt con cost 12)
    v_hash := crypt(p_contrasena_plana, gen_salt('bf', 12));

    -- 3) Insertar USUARIO
    INSERT INTO persona.persona_usuario(
        id_persona, nombre_usuario, contrasena_hash, tipo_usuario,
        estado_registro, fecha_registro, version_registro, id_usuario_creador
    )
    VALUES (
        o_id_persona, p_nombre_usuario, v_hash, p_tipo_usuario,
        'Activo', now(), 1, p_id_usuario_creador
    );

    o_nombre_usuario := p_nombre_usuario;
END;
$$;

CREATE OR REPLACE FUNCTION persona.cambiar_contrasena_usuario(
    p_nombre_usuario          varchar(80),
    p_contrasena_actual      text,
    p_contrasena_nueva       text,
    p_id_usuario_modificacion bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash_actual text;
    v_ok          boolean;
BEGIN
    IF coalesce(trim(p_nombre_usuario), '') = '' THEN
        RAISE EXCEPTION 'El nombre de usuario es obligatorio';
    END IF;
    IF p_contrasena_nueva IS NULL OR length(p_contrasena_nueva) < 6 THEN
        RAISE EXCEPTION 'La nueva contraseña debe tener al menos 6 caracteres';
    END IF;

    SELECT contrasena_hash
      INTO v_hash_actual
      FROM persona.persona_usuario
     WHERE lower(nombre_usuario) = lower(p_nombre_usuario);

    IF v_hash_actual IS NULL THEN
        RAISE EXCEPTION 'Usuario "%" no encontrado', p_nombre_usuario;
    END IF;

    -- Validar contraseña actual
    v_ok := (v_hash_actual = crypt(p_contrasena_actual, v_hash_actual));
    IF NOT v_ok THEN
        RAISE EXCEPTION 'La contraseña actual no es correcta';
    END IF;

    -- Actualizar con nuevo hash
    UPDATE persona.persona_usuario
       SET contrasena_hash      = crypt(p_contrasena_nueva, gen_salt('bf', 12)),
           fecha_modificacion   = now(),
           version_registro     = coalesce(version_registro, 1) + 1,
           id_usuario_modificacion = p_id_usuario_modificacion
     WHERE lower(nombre_usuario) = lower(p_nombre_usuario);

    RETURN TRUE;
END;
$$;


SELECT *
FROM persona.registrar_persona_y_usuario(
  'Pablo', 'Arauz', '777377232', DATE '2001-12-07', 'pabliarca@gmail.com',
  'pablo.arauz', '72107014Casa', 'ADMIN',
);

select * from persona.persona_usuario;


create schema if not exists auditoria;

drop table if exists auditoria.sesion;
create table auditoria.sesion(
	id_sesion bigserial primary key,
	ip_usuario text not null,
	id_usuario int not null references persona.persona_usuario(id_persona),
	timestamp_entrada		timestamptz  DEFAULT now(),
	timestamp_salida		timestamptz  DEFAULT now(),
	
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint		
);



create table auditoria.tipo_accion(
	id_tipo_accion  bigserial primary key,
	nombre_accion text not null,
	tipo_accion text not null,
	tipo_controller text,
	html_id_controller text,
	
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint			
);


create table auditoria.solicitudes_web(
	id_solicitud bigserial primary key,
	http_code text not null,
	solicitud json not null,
	cod_solicitud_respuesta text,
	tam_bytes_solicitud int,
	
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint			
);


create table auditoria.action_logger(
	id_accion bigserial primary key,
	id_sesion int not null references auditoria.sesion(id_sesion),
	id_tipo_accion int not null references auditoria.tipo_accion(id_tipo_accion),
	
	estado_registro        varchar(20) DEFAULT 'Activo',
	fecha_registro         timestamptz  DEFAULT now(),
	fecha_modificacion     timestamptz,
	version_registro       int          DEFAULT 1,
	id_usuario_creador     bigint,
	id_usuario_modificacion bigint		
);


CREATE OR REPLACE FUNCTION persona.autenticar_usuario(
    p_nombre_usuario   varchar(80),
    p_contrasena_plana text
)
RETURNS TABLE (
    ok              boolean,
    id_persona      bigint,
    nombre          varchar,
    apellidos       varchar,
    nombre_usuario  varchar,
    tipo_usuario    varchar
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash_db   text;
    v_id_persona bigint;
    v_tipo       varchar;
    v_user_norm  varchar;
    v_estado_u   varchar(20);
    v_estado_p   varchar(20);
BEGIN
    -- 1) Traer (si existe) el registro del usuario
    SELECT u.contrasena_hash,
           u.id_persona,
           u.tipo_usuario,
           u.nombre_usuario,
           u.estado_registro
    INTO   v_hash_db, v_id_persona, v_tipo, v_user_norm, v_estado_u
    FROM persona.persona_usuario u
    WHERE lower(u.nombre_usuario) = lower(p_nombre_usuario)
    LIMIT 1;

    -- 2) Comparación de contraseña en tiempo "constante"
    --    (si no existe el usuario, usamos un salt aleatorio para evitar filtrado por timing)
    IF v_hash_db IS NULL THEN
        PERFORM crypt(p_contrasena_plana, gen_salt('bf'));
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::varchar, NULL::varchar, NULL::varchar, NULL::varchar;
        RETURN;
    END IF;

    -- 3) Validación de contraseña
    IF v_hash_db <> crypt(p_contrasena_plana, v_hash_db) THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::varchar, NULL::varchar, NULL::varchar, NULL::varchar;
        RETURN;
    END IF;

    -- 4) Validar estado 'Activo' en usuario y persona
    SELECT p.estado_registro
      INTO v_estado_p
      FROM persona.persona p
     WHERE p.id_persona = v_id_persona;

    IF v_estado_u IS DISTINCT FROM 'Activo' OR v_estado_p IS DISTINCT FROM 'Activo' THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::varchar, NULL::varchar, NULL::varchar, NULL::varchar;
        RETURN;
    END IF;

    -- 5) Devolver datos mínimos para sesión
    RETURN QUERY
    SELECT TRUE,
           p.id_persona,
           p.nombres,
           p.apellidos,
           v_user_norm,
           v_tipo
    FROM persona.persona p
    WHERE p.id_persona = v_id_persona;
END;
$$;

SELECT * FROM persona.autenticar_usuario('pablo.arauz', '72107014Casa');