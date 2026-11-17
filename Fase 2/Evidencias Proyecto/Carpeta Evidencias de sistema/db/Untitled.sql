CREATE TABLE `auth_user` (
  `id` int PRIMARY KEY AUTO_INCREMENT,
  `password` varchar(128) NOT NULL,
  `last_login` timestamptz,
  `is_superuser` boolean NOT NULL,
  `username` varchar(150) UNIQUE NOT NULL,
  `first_name` varchar(150) NOT NULL,
  `last_name` varchar(150) NOT NULL,
  `email` varchar(254) NOT NULL,
  `is_staff` boolean NOT NULL,
  `is_active` boolean NOT NULL,
  `date_joined` timestamptz NOT NULL
);

CREATE TABLE `roles` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `code` varchar(30) UNIQUE NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `user_roles` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `role_id` bigint NOT NULL,
  `assigned_at` timestamptz NOT NULL
);

CREATE TABLE `authentication_userprofile` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `user_id` int UNIQUE NOT NULL,
  `rut` varchar(12) UNIQUE,
  `phone` varchar(20)
);

CREATE TABLE `notification_channels` (
  `id` int PRIMARY KEY AUTO_INCREMENT,
  `code` varchar(20) UNIQUE NOT NULL,
  `name` varchar(50) NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `clients` (
  `id` uuid PRIMARY KEY,
  `rut` varchar(12) UNIQUE NOT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `email` varchar(255),
  `password_hash` varchar(255) NOT NULL,
  `notification_channel_id` int NOT NULL,
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `client_otps` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `client_id` uuid UNIQUE NOT NULL,
  `code_hash` varchar(128) NOT NULL,
  `expires_at` timestamptz NOT NULL,
  `last_sent_at` timestamptz NOT NULL,
  `attempts` smallint NOT NULL,
  `consumed_at` timestamptz,
  `verified_at` timestamptz
);

CREATE TABLE `clientprofilechange` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `client_id` uuid UNIQUE NOT NULL,
  `payload` jsonb NOT NULL,
  `email_at_request` varchar(254) NOT NULL,
  `code_hash` varchar(128) NOT NULL,
  `expires_at` timestamptz NOT NULL,
  `last_sent_at` timestamptz NOT NULL,
  `attempts` smallint NOT NULL,
  `consumed_at` timestamptz
);

CREATE TABLE `vehicle_brands` (
  `id` int PRIMARY KEY AUTO_INCREMENT,
  `name` varchar(50) UNIQUE NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `vehicle_models` (
  `id` int PRIMARY KEY AUTO_INCREMENT,
  `brand_id` int NOT NULL,
  `name` varchar(50) NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `vehicles` (
  `id` uuid PRIMARY KEY,
  `client_id` uuid NOT NULL,
  `model_id` int NOT NULL,
  `plate` varchar(10) UNIQUE NOT NULL,
  `year` int NOT NULL,
  `color` varchar(30),
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `services` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `name` varchar(150) UNIQUE NOT NULL,
  `description` text NOT NULL,
  `base_price` numeric(12,2),
  `estimated_duration_minutes` int,
  `is_active` boolean NOT NULL
);

CREATE TABLE `workshop_appointmentslot` (
  `scheduled_date` timestamptz PRIMARY KEY
);

CREATE TABLE `appointments` (
  `id` uuid PRIMARY KEY,
  `client_id` uuid NOT NULL,
  `vehicle_id` uuid,
  `service_id` bigint,
  `status` varchar(10) NOT NULL DEFAULT 'PENDIENTE' COMMENT 'Choices: PENDIENTE, CONFIRMADA, CANCELADA, RECHAZADA, ATENDIDA',
  `scheduled_date` timestamptz NOT NULL,
  `slot_number` smallint NOT NULL DEFAULT 1,
  `reported_symptoms` text NOT NULL,
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `work_order_statuses` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `code` varchar(30) UNIQUE NOT NULL,
  `name` varchar(50) NOT NULL,
  `sequence_order` int NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `work_orders` (
  `id` uuid PRIMARY KEY,
  `appointment_id` uuid UNIQUE,
  `folio_number` int UNIQUE NOT NULL,
  `tracking_code` varchar(14) UNIQUE NOT NULL,
  `tracking_token` varchar(32) UNIQUE NOT NULL,
  `vehicle_id` uuid NOT NULL,
  `assigned_mechanic_id` int,
  `status_id` bigint NOT NULL,
  `client_observations` text,
  `technical_diagnosis` text,
  `ai_diagnostic_suggestion` text,
  `estimated_delivery_date` timestamptz,
  `closed_at` timestamptz,
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `work_order_checkins` (
  `id` uuid PRIMARY KEY,
  `work_order_id` uuid UNIQUE NOT NULL,
  `receptionist_id` int,
  `initial_odometer` int,
  `fuel_level` varchar(20) NOT NULL,
  `has_spare_tire` boolean,
  `has_jack_and_tools` boolean,
  `bodywork_details` text,
  `additional_equipment` jsonb NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `work_order_photos` (
  `id` uuid PRIMARY KEY,
  `checkin_id` uuid NOT NULL,
  `photo_cloudinary_url` text NOT NULL,
  `public_id` varchar(100),
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `work_order_items` (
  `id` uuid PRIMARY KEY,
  `work_order_id` uuid NOT NULL,
  `item_id` uuid NOT NULL,
  `added_by_user_id` int,
  `quantity` int NOT NULL,
  `request_id` uuid,
  `unit_price` numeric(12,2) NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `work_order_status_history` (
  `id` uuid PRIMARY KEY,
  `work_order_id` uuid NOT NULL,
  `from_status_id` bigint,
  `to_status_id` bigint NOT NULL,
  `changed_by_id` int,
  `notes` text,
  `changed_at` timestamptz NOT NULL
);

CREATE TABLE `quotes` (
  `id` uuid PRIMARY KEY,
  `work_order_id` uuid,
  `client_id` uuid NOT NULL,
  `subtotal_amount` numeric(12,2) NOT NULL DEFAULT 0,
  `tax_rate` numeric(5,2) NOT NULL DEFAULT 0,
  `tax_amount` numeric(12,2) NOT NULL DEFAULT 0,
  `total_amount` numeric(12,2) NOT NULL,
  `is_approved` boolean NOT NULL DEFAULT false,
  `pdf_cloudinary_url` text,
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `quote_items` (
  `id` uuid PRIMARY KEY,
  `quote_id` uuid NOT NULL,
  `item_id` uuid NOT NULL,
  `quantity` int NOT NULL,
  `unit_price` numeric(12,2) NOT NULL,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `item_categories` (
  `id` bigint PRIMARY KEY AUTO_INCREMENT,
  `name` varchar(100) UNIQUE NOT NULL,
  `is_active` boolean NOT NULL DEFAULT true,
  `created_at` timestamptz NOT NULL
);

CREATE TABLE `inventory_items` (
  `id` uuid PRIMARY KEY,
  `category_id` bigint NOT NULL,
  `sku` varchar(50) UNIQUE NOT NULL,
  `name` varchar(150) NOT NULL,
  `description` text,
  `unit_price` numeric(12,2) NOT NULL,
  `current_stock` int NOT NULL DEFAULT 0,
  `minimum_stock` int NOT NULL DEFAULT 5,
  `is_published` boolean NOT NULL DEFAULT false,
  `public_title` varchar(150),
  `public_description` text,
  `public_price` numeric(10,0),
  `public_image` varchar(100),
  `created_at` timestamptz NOT NULL,
  `updated_at` timestamptz NOT NULL
);

CREATE TABLE `workshop_bookingverification` (
  `id` uuid PRIMARY KEY,
  `rut` varchar(12) NOT NULL,
  `payload_hash` varchar(64) NOT NULL,
  `code_hash` varchar(128) NOT NULL,
  `expires_at` timestamptz NOT NULL,
  `attempts` smallint NOT NULL,
  `consumed_at` timestamptz
);

CREATE TABLE `workshop_emaildelivery` (
  `id` uuid PRIMARY KEY,
  `payload` jsonb NOT NULL,
  `kind` varchar(20) NOT NULL,
  `target_id` uuid NOT NULL,
  `status` varchar(12) NOT NULL DEFAULT 'PENDING',
  `attempts` smallint NOT NULL,
  `available_at` timestamptz NOT NULL,
  `locked_at` timestamptz,
  `last_error` varchar(255) NOT NULL,
  `created_at` timestamptz NOT NULL,
  `sent_at` timestamptz
);

CREATE TABLE `demand_forecast_snapshots` (
  `id` uuid PRIMARY KEY,
  `period` varchar(10) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `forecast` jsonb NOT NULL,
  `generated_at` timestamptz NOT NULL
);

CREATE UNIQUE INDEX `user_roles_index_0` ON `user_roles` (`user_id`, `role_id`);

CREATE UNIQUE INDEX `vehicle_models_index_1` ON `vehicle_models` (`brand_id`, `name`);

CREATE UNIQUE INDEX `appointments_index_2` ON `appointments` (`scheduled_date`, `slot_number`);

CREATE UNIQUE INDEX `work_order_items_index_3` ON `work_order_items` (`work_order_id`, `request_id`);

CREATE INDEX `workshop_bookingverification_index_4` ON `workshop_bookingverification` (`rut`);

CREATE UNIQUE INDEX `workshop_emaildelivery_index_5` ON `workshop_emaildelivery` (`kind`, `target_id`);

CREATE INDEX `workshop_emaildelivery_index_6` ON `workshop_emaildelivery` (`available_at`);

CREATE UNIQUE INDEX `demand_forecast_snapshots_index_7` ON `demand_forecast_snapshots` (`period`, `start_date`, `end_date`);

CREATE INDEX `demand_forecast_snapshots_index_8` ON `demand_forecast_snapshots` (`generated_at`);

ALTER TABLE `user_roles` ADD FOREIGN KEY (`user_id`) REFERENCES `auth_user` (`id`) ON DELETE CASCADE;

ALTER TABLE `user_roles` ADD FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE;

ALTER TABLE `auth_user` ADD FOREIGN KEY (`id`) REFERENCES `authentication_userprofile` (`user_id`) ON DELETE CASCADE;

ALTER TABLE `clients` ADD FOREIGN KEY (`notification_channel_id`) REFERENCES `notification_channels` (`id`);

ALTER TABLE `clients` ADD FOREIGN KEY (`id`) REFERENCES `client_otps` (`client_id`) ON DELETE CASCADE;

ALTER TABLE `clients` ADD FOREIGN KEY (`id`) REFERENCES `clientprofilechange` (`client_id`) ON DELETE CASCADE;

ALTER TABLE `vehicle_models` ADD FOREIGN KEY (`brand_id`) REFERENCES `vehicle_brands` (`id`) ON DELETE CASCADE;

ALTER TABLE `vehicles` ADD FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE CASCADE;

ALTER TABLE `vehicles` ADD FOREIGN KEY (`model_id`) REFERENCES `vehicle_models` (`id`) ON DELETE RESTRICT;

ALTER TABLE `appointments` ADD FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE RESTRICT;

ALTER TABLE `appointments` ADD FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles` (`id`) ON DELETE RESTRICT;

ALTER TABLE `appointments` ADD FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE RESTRICT;

ALTER TABLE `appointments` ADD FOREIGN KEY (`id`) REFERENCES `work_orders` (`appointment_id`) ON DELETE RESTRICT;

ALTER TABLE `work_orders` ADD FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles` (`id`) ON DELETE RESTRICT;

ALTER TABLE `work_orders` ADD FOREIGN KEY (`assigned_mechanic_id`) REFERENCES `auth_user` (`id`) ON DELETE SET NULL;

ALTER TABLE `work_orders` ADD FOREIGN KEY (`status_id`) REFERENCES `work_order_statuses` (`id`) ON DELETE RESTRICT;

ALTER TABLE `work_orders` ADD FOREIGN KEY (`id`) REFERENCES `work_order_checkins` (`work_order_id`) ON DELETE CASCADE;

ALTER TABLE `work_order_checkins` ADD FOREIGN KEY (`receptionist_id`) REFERENCES `auth_user` (`id`) ON DELETE SET NULL;

ALTER TABLE `work_order_photos` ADD FOREIGN KEY (`checkin_id`) REFERENCES `work_order_checkins` (`id`) ON DELETE CASCADE;

ALTER TABLE `work_order_items` ADD FOREIGN KEY (`work_order_id`) REFERENCES `work_orders` (`id`) ON DELETE CASCADE;

ALTER TABLE `work_order_items` ADD FOREIGN KEY (`item_id`) REFERENCES `inventory_items` (`id`) ON DELETE RESTRICT;

ALTER TABLE `work_order_items` ADD FOREIGN KEY (`added_by_user_id`) REFERENCES `auth_user` (`id`) ON DELETE SET NULL;

ALTER TABLE `work_order_status_history` ADD FOREIGN KEY (`work_order_id`) REFERENCES `work_orders` (`id`) ON DELETE CASCADE;

ALTER TABLE `work_order_status_history` ADD FOREIGN KEY (`from_status_id`) REFERENCES `work_order_statuses` (`id`) ON DELETE SET NULL;

ALTER TABLE `work_order_status_history` ADD FOREIGN KEY (`to_status_id`) REFERENCES `work_order_statuses` (`id`) ON DELETE RESTRICT;

ALTER TABLE `work_order_status_history` ADD FOREIGN KEY (`changed_by_id`) REFERENCES `auth_user` (`id`) ON DELETE SET NULL;

ALTER TABLE `quotes` ADD FOREIGN KEY (`work_order_id`) REFERENCES `work_orders` (`id`) ON DELETE SET NULL;

ALTER TABLE `quotes` ADD FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE RESTRICT;

ALTER TABLE `quote_items` ADD FOREIGN KEY (`quote_id`) REFERENCES `quotes` (`id`) ON DELETE CASCADE;

ALTER TABLE `quote_items` ADD FOREIGN KEY (`item_id`) REFERENCES `inventory_items` (`id`) ON DELETE RESTRICT;

ALTER TABLE `inventory_items` ADD FOREIGN KEY (`category_id`) REFERENCES `item_categories` (`id`) ON DELETE RESTRICT;
