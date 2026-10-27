-- Requisito PostgreSQL: CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- PROYECTO: A&J Connect - Sistema de Gestión y Portal PWA (A&J Automotriz)
-- AUTORES: Matías Baxman, Benjamín Ojeda, Benjamín Romero
-- CLIENTE: A&J Automotriz (Quilpué)
-- BASE DE DATOS: PostgreSQL 15+
-- NORMALIZACIÓN: Tercera Forma Normal (3FN Strict)
--
-- NOTAS DE ESTA VERSIÓN (respecto al script original):
--   - Nombres de tablas/columnas en INGLÉS (convención estándar de la industria),
--     con comentarios en ESPAÑOL para que el equipo lo entienda fácil.
--   - Se agregaron índices en TODAS las llaves foráneas (Postgres no los crea
--     automáticamente, solo indexa la PK).
--   - Se normalizaron 'movement_type' y 'preferred_notification_channel' en
--     catálogos propios (antes eran VARCHAR libres documentados solo en un
--     comentario), igual que ya estaba hecho con los demás estados.
--   - 'fuel_level' se dejó como texto libre A PROPÓSITO: es un dato que el
--     mecánico/recepcionista ingresa a su criterio en el check-in, no un
--     catálogo cerrado del negocio. Se valida en la aplicación, no en la BD.
--   - Se eliminó 'is_staff' de users: en este esquema la tabla es exclusiva
--     del personal del taller, por lo que siempre habría sido TRUE.
--   - Se agregó la tabla 'quote_items' para poder trazar de qué se compone
--     el total_amount de una cotización (antes no existía ese detalle).
--   - Se corrigió el ON DELETE de quotes.client_id de CASCADE a RESTRICT:
--     un documento financiero no debería borrarse en cascada solo porque
--     se elimina el cliente.
--   - Se agregaron triggers para mantener 'updated_at' automáticamente en
--     vez de depender de que la aplicación lo actualice a mano.
--   - Se quitó el 'COMMIT;' suelto sin 'BEGIN;' del script original y se
--     envolvió todo en una transacción explícita.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- 1. MÓDULO DE AUTENTICACIÓN Y SEGURIDAD INTERNA (USERS, ROLES & LOGS)
-- =============================================================================

-- Catálogo de Roles para el Dashboard Administrativo (RBAC)
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE, -- 'ADMIN', 'RECEPCIONISTA', 'MECANICO'
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Usuarios Administrativos / Personal del Taller (Desacoplado de Clientes)
-- Nota: se eliminó la columna 'is_staff' que traía el script original, porque
-- esta tabla es exclusiva del personal del taller y esa columna siempre
-- habría valido TRUE. Si en el futuro necesitan otro tipo de cuenta interna
-- que no sea "staff", ahí tendría sentido agregarla de nuevo.
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    rut VARCHAR(12) UNIQUE,
    phone VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Relación M:N entre Usuarios y Roles
CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (user_id, role_id)
);
-- Índice nuevo: la PK compuesta ya cubre búsquedas por user_id, pero no por
-- role_id solo (ej: "todos los usuarios con rol ADMIN"), por eso se agrega.
CREATE INDEX idx_user_roles_role ON user_roles(role_id);

-- Registro de Turnos del Personal
CREATE TABLE user_shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shift_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    shift_end TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_user_shifts_user ON user_shifts(user_id);

-- Tabla de Tipos de Acciones para Auditoría
CREATE TABLE audit_actions (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE, -- 'CREATE', 'UPDATE', 'DELETE', 'LOGIN', 'CHECKIN', etc.
    description VARCHAR(150),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Registro Centralizado de Logs de Auditoría (Audit Trail)
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL si es acción anónima
    action_id INT NOT NULL REFERENCES audit_actions(id),
    entity_name VARCHAR(100) NOT NULL, -- Tabla afectada (ej: 'work_orders', 'inventory_items')
    entity_id VARCHAR(100), -- ID de la entidad afectada
    old_values JSONB, -- Estado previo de los datos
    new_values JSONB, -- Estado nuevo de los datos
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC); -- ya venía en el original

-- =============================================================================
-- 2. MÓDULO DE CLIENTES, VEHÍCULOS Y CITAS (PORTAL PWA PÚBLICO)
-- =============================================================================

-- Catálogo de Canales de Notificación.
-- Antes 'clients.preferred_notification_channel' era un VARCHAR libre con
-- los valores válidos solo documentados en un comentario. Se normaliza acá
-- para ser consistente con el resto de los catálogos del sistema (evita que
-- alguien inserte un valor inválido, ej: 'SMS' sin querer).
CREATE TABLE notification_channels (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE, -- 'WHATSAPP', 'EMAIL'
    name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Clientes registrados o atención directa
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rut VARCHAR(12) NOT NULL UNIQUE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    password_hash VARCHAR(255) NOT NULL,
    notification_channel_id INT NOT NULL REFERENCES notification_channels(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_clients_notification_channel ON clients(notification_channel_id);

-- Normalización de Marcas y Modelos (Elimina dependencia transitiva - 3FN)
CREATE TABLE vehicle_brands (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE vehicle_models (
    id SERIAL PRIMARY KEY,
    brand_id INT NOT NULL REFERENCES vehicle_brands(id),
    name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_brand_model UNIQUE (brand_id, name)
);
CREATE INDEX idx_vehicle_models_brand ON vehicle_models(brand_id);

-- Vehículos vinculados a un Cliente
CREATE TABLE vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id),
    model_id INT NOT NULL REFERENCES vehicle_models(id),
    plate VARCHAR(10) NOT NULL UNIQUE, -- Patente única
    year INT NOT NULL CHECK (year >= 1900),
    color VARCHAR(30),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_vehicles_client ON vehicles(client_id);
CREATE INDEX idx_vehicles_model ON vehicles(model_id);
CREATE INDEX idx_vehicles_plate ON vehicles(plate); -- ya venía en el original

-- Agendamiento Web de Citas (Pre-Diagnóstico PWA)
CREATE TABLE appointment_statuses (
    id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE, -- 'PENDIENTE', 'CONFIRMADA', 'CANCELADA', 'ATENDIDA'
    name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
    status_id INT NOT NULL REFERENCES appointment_statuses(id),
    scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
    reported_symptoms TEXT NOT NULL, -- Síntomas / Pre-diagnóstico ingresado o por Chatbot
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_appointments_client ON appointments(client_id);
CREATE INDEX idx_appointments_vehicle ON appointments(vehicle_id);
CREATE INDEX idx_appointments_status ON appointments(status_id);

-- =============================================================================
-- 3. MÓDULO DE INVENTARIO Y CATÁLOGO DE REPUESTOS / ACEITES
-- =============================================================================

CREATE TABLE item_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE, -- 'ACEITES', 'REPUESTOS', 'FILTROS', 'SERVICIOS'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id INT NOT NULL REFERENCES item_categories(id),
    sku VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    current_stock INT NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
    minimum_stock INT NOT NULL DEFAULT 5 CHECK (minimum_stock >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_inventory_items_category ON inventory_items(category_id);
CREATE INDEX idx_inventory_sku ON inventory_items(sku); -- ya venía en el original

-- Catálogo de Tipos de Movimiento.
-- Antes 'inventory_movements.movement_type' era un VARCHAR libre. Se
-- normaliza igual que 'notification_channels', por consistencia y para
-- evitar valores inválidos en el kárdex.
CREATE TABLE movement_types (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE, -- 'ENTRADA', 'SALIDA_OT', 'AJUSTE'
    name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Kárdex / Registro de Movimientos de Inventario (Auditoría de Stock)
CREATE TABLE inventory_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES inventory_items(id),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    movement_type_id INT NOT NULL REFERENCES movement_types(id),
    quantity INT NOT NULL,
    previous_stock INT NOT NULL,
    new_stock INT NOT NULL,
    reference_id UUID, -- Ej: ID de la Orden de Trabajo que provocó la salida
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_inventory_movements_item ON inventory_movements(item_id);
CREATE INDEX idx_inventory_movements_user ON inventory_movements(user_id);
CREATE INDEX idx_inventory_movements_type ON inventory_movements(movement_type_id);

-- =============================================================================
-- 4. MÓDULO DE ÓRDENES DE TRABAJO (OT), CHECK-IN Y SEGUIMIENTO POR TOKEN
-- =============================================================================

CREATE TABLE work_order_statuses (
    id SERIAL PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE, -- 'RECEPCIONADO', 'DIAGNOSTICO', 'REPARACION', 'LISTO', 'ENTREGADO'
    name VARCHAR(50) NOT NULL,
    sequence_order INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Orden de Trabajo Principal
CREATE TABLE work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio_number SERIAL UNIQUE, -- Folio único visible de la OT
    tracking_token VARCHAR(32) NOT NULL UNIQUE, -- Token seguro para consultar en la PWA
    vehicle_id UUID NOT NULL REFERENCES vehicles(id),
    assigned_mechanic_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status_id INT NOT NULL REFERENCES work_order_statuses(id),
    client_observations TEXT,
    technical_diagnosis TEXT,
    estimated_delivery_date TIMESTAMP WITH TIME ZONE,
    closed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_work_orders_token ON work_orders(tracking_token); -- ya venía en el original
CREATE INDEX idx_work_orders_vehicle ON work_orders(vehicle_id);
CREATE INDEX idx_work_orders_mechanic ON work_orders(assigned_mechanic_id);
CREATE INDEX idx_work_orders_status ON work_orders(status_id);

-- Registro Específico de Check-in Digital Vehicular
CREATE TABLE work_order_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID NOT NULL UNIQUE REFERENCES work_orders(id) ON DELETE CASCADE,
    receptionist_id UUID REFERENCES users(id) ON DELETE SET NULL,
    initial_odometer INT NOT NULL CHECK (initial_odometer >= 0),
    -- Texto libre A PROPÓSITO: lo define el mecánico/recepcionista en el
    -- formulario de check-in según lo que ve en el vehículo. No es un
    -- catálogo cerrado del negocio, por eso NO lleva FK a otra tabla; los
    -- valores sugeridos ('VACIO', '1/4', '1/2', '3/4', 'LLENO') se validan
    -- en la aplicación (ej: un <select> en el formulario), no en la BD.
    fuel_level VARCHAR(20) NOT NULL,
    has_spare_tire BOOLEAN DEFAULT TRUE,
    has_jack_and_tools BOOLEAN DEFAULT TRUE,
    bodywork_details TEXT, -- Observaciones de rayones o abolladuras
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_work_order_checkins_receptionist ON work_order_checkins(receptionist_id);

-- Fotos del Check-In (1FN: Múltiples fotos sin arreglos en celdas)
CREATE TABLE work_order_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checkin_id UUID NOT NULL REFERENCES work_order_checkins(id) ON DELETE CASCADE,
    photo_cloudinary_url TEXT NOT NULL,
    public_id VARCHAR(100), -- ID de Cloudinary para gestión de archivos
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_work_order_photos_checkin ON work_order_photos(checkin_id);

-- Detalle de Repuestos / Insumos / Servicios aplicados a la OT (2FN/3FN)
CREATE TABLE work_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES inventory_items(id),
    added_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0), -- Se congela el precio histórico
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_work_order_items_work_order ON work_order_items(work_order_id);
CREATE INDEX idx_work_order_items_item ON work_order_items(item_id);
CREATE INDEX idx_work_order_items_user ON work_order_items(added_by_user_id);

-- Historial de Cambios de Estado de la OT (Línea de Tiempo de Trazabilidad)
CREATE TABLE work_order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    status_id INT NOT NULL REFERENCES work_order_statuses(id),
    changed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_work_order_status_history_wo ON work_order_status_history(work_order_id);
CREATE INDEX idx_work_order_status_history_status ON work_order_status_history(status_id);

-- Cotizaciones y Presupuestos Generados
CREATE TABLE quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES work_orders(id) ON DELETE SET NULL,
    -- RESTRICT en vez de CASCADE (como estaba en el original): una
    -- cotización es un documento financiero y no debería borrarse en
    -- cascada solo porque se elimina el cliente asociado.
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    is_approved BOOLEAN DEFAULT FALSE,
    pdf_cloudinary_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_quotes_work_order ON quotes(work_order_id);
CREATE INDEX idx_quotes_client ON quotes(client_id);

-- Detalle de una Cotización.
-- Tabla NUEVA: en el script original 'quotes.total_amount' se guardaba
-- directo, sin ningún detalle de qué ítems lo componían. Si la cotización
-- no coincidía 1:1 con 'work_order_items', no había forma de saber de
-- dónde salía ese total. Esta tabla lo deja trazable.
CREATE TABLE quote_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id UUID NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES inventory_items(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX idx_quote_items_quote ON quote_items(quote_id);
CREATE INDEX idx_quote_items_item ON quote_items(item_id);

-- =============================================================================
-- 5. TRIGGERS: MANTENCIÓN AUTOMÁTICA DE 'updated_at'
-- =============================================================================
-- El script original tenía la columna 'updated_at' en varias tablas, pero
-- nada la actualizaba automáticamente (quedaba a criterio de la app). Esta
-- función + triggers aseguran que SIEMPRE se actualice sola en cada UPDATE,
-- sin depender de que el backend se acuerde de hacerlo.

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_vehicles_updated_at
    BEFORE UPDATE ON vehicles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_inventory_items_updated_at
    BEFORE UPDATE ON inventory_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_work_orders_updated_at
    BEFORE UPDATE ON work_orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_quotes_updated_at
    BEFORE UPDATE ON quotes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
