drop table contabilidad.cuenta;
	
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


CREATE TABLE servicios_educativos.curso_version (
    id_curso_version       BIGSERIAL PRIMARY KEY,
    id_producto_educativo  BIGINT NOT NULL
                            REFERENCES servicios_educativos.producto_educativo(id_producto_educativo) ON DELETE CASCADE,
    nombre_version         VARCHAR(150) NOT NULL, -- Ej: “Álgebra 2025 - Edición I”
    descripcion_version    TEXT,
    fecha_inicio           DATE,
    fecha_fin              DATE,
    precio_version         NUMERIC(12,2) CHECK (precio_version IS NULL OR precio_version >= 0),

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

    -- Evita duplicar el rol tutor para la misma persona
    CONSTRAINT uq_tutor_persona UNIQUE (id_persona),

    -- Regla clave solicitada:
    -- Si es UNIVERSITARIO => nivel_estudiante_especialidad debe ser NULL
    -- Si es COLEGIAL      => nivel_estudiante_especialidad debe ser NOT NULL
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
	id_clase	bigserial primary key,
	id_aula	    int not null references infraestructura.espacio(id_espacio),
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
    id_horario            BIGINT
                           REFERENCES servicios_educativos.horario(id_horario) ON DELETE SET NULL,

    -- Recursos
    id_aula               BIGINT
                           REFERENCES infraestructura.aula(id_aula) ON DELETE SET NULL,
    id_tutor   			  BIGINT
                           REFERENCES administracion.empleado(id_empleado) ON DELETE SET NULL,

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

    -- Control de duplicidad: una clase por horario y fecha
    CONSTRAINT uq_clase_por_horario_fecha UNIQUE (id_horario, fecha),

    -- Auditoría
    fecha_registro         TIMESTAMP DEFAULT now(),
    estado_registro        BOOLEAN   DEFAULT TRUE,
    id_usuario             BIGINT,
    id_usuario_modificacion BIGINT,
    version_registro       INT       DEFAULT 1
);


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
  id_tienda 		  int references infraestructura.tienda(id_tienda),
  id_producto		  int references 
  
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
