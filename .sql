-- ============================================================================
-- GABUNGAN SQL PRAKTIKUM TRIGGER MYSQL (ACARA 1 - ACARA 3)
-- ============================================================================

-- ============================================================================
-- ACARA 1: Trigger MySQL Dasar (BEFORE INSERT, AFTER INSERT, AFTER UPDATE)
-- ============================================================================
DROP DATABASE IF EXISTS praktikum_trigger;
CREATE DATABASE praktikum_trigger;
USE praktikum_trigger;

CREATE TABLE produk (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    harga DECIMAL(10,2) NOT NULL,
    stok INT NOT NULL DEFAULT 0
);

CREATE TABLE log_produk (
    id INT AUTO_INCREMENT PRIMARY KEY,
    produk_id INT,
    aksi VARCHAR(20),
    keterangan VARCHAR(255),
    waktu TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DELIMITER //

CREATE TRIGGER trg_produk_before_insert
BEFORE INSERT ON produk
FOR EACH ROW
BEGIN
    IF NEW.harga <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Harga produk harus lebih dari 0';
    END IF;
    IF NEW.stok < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stok tidak boleh negatif';
    END IF;
END//

CREATE TRIGGER trg_produk_after_insert
AFTER INSERT ON produk
FOR EACH ROW
BEGIN
    INSERT INTO log_produk (produk_id, aksi, keterangan)
    VALUES (NEW.id, 'INSERT', CONCAT('Produk ', NEW.nama, ' ditambahkan dengan harga ', NEW.harga));
END//

CREATE TRIGGER trg_produk_after_update
AFTER UPDATE ON produk
FOR EACH ROW
BEGIN
    IF OLD.harga <> NEW.harga THEN
        INSERT INTO log_produk (produk_id, aksi, keterangan)
        VALUES (NEW.id, 'UPDATE', CONCAT('Harga berubah dari ', OLD.harga, ' menjadi ', NEW.harga));
    END IF;
END//

DELIMITER ;

-- Pengujian Acara 1
INSERT INTO produk (nama, harga, stok) VALUES ('Pensil', 2500.00, 100);
-- Uji gagal (uncomment untuk menguji validasi error #1644):
-- INSERT INTO produk (nama, harga, stok) VALUES ('Penghapus', -1000.00, 50);
-- INSERT INTO produk (nama, harga, stok) VALUES ('Penggaris', 5000.00, -10);
UPDATE produk SET harga = 3000.00 WHERE id = 1;
UPDATE produk SET stok = 90 WHERE id = 1;


-- ============================================================================
-- ACARA 2: Trigger MySQL Lanjut (BEFORE UPDATE, Audit JSON, FOLLOWS/PRECEDES, AFTER DELETE)
-- ============================================================================
DROP DATABASE IF EXISTS praktikum_trigger2;
CREATE DATABASE praktikum_trigger2;
USE praktikum_trigger2;

CREATE TABLE produk (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    harga DECIMAL(10,2) NOT NULL,
    stok INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE pesanan (
    id INT AUTO_INCREMENT PRIMARY KEY,
    produk_id INT NOT NULL,
    jumlah INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'baru',
    total DECIMAL(12,2) NOT NULL
);

CREATE TABLE audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(64) NOT NULL,
    operation ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    record_id BIGINT NOT NULL,
    changed_by VARCHAR(100) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values JSON,
    new_values JSON,
    INDEX idx_table_record (table_name, record_id)
);

CREATE TABLE arsip_pesanan (
    arsip_id INT AUTO_INCREMENT PRIMARY KEY,
    pesanan_id INT NOT NULL,
    produk_id INT NOT NULL,
    jumlah INT NOT NULL,
    status VARCHAR(20),
    total DECIMAL(12,2),
    dihapus_pada TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO produk (nama, harga, stok) VALUES
('Laptop', 7500000.00, 10),
('Mouse', 150000.00, 50);

DELIMITER //

CREATE TRIGGER trg_produk_before_update_validasi
BEFORE UPDATE ON produk
FOR EACH ROW
BEGIN
    IF NEW.harga < 1000.00 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Harga produk tidak boleh kurang dari 1000.00';
    END IF;
END//

CREATE TRIGGER trg_produk_before_update_timestamp
BEFORE UPDATE ON produk
FOR EACH ROW
PRECEDES trg_produk_before_update_validasi
BEGIN
    SET NEW.updated_at = NOW();
END//

CREATE TRIGGER trg_produk_after_update_audit
AFTER UPDATE ON produk
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, old_values, new_values)
    VALUES (
        'produk',
        'UPDATE',
        NEW.id,
        USER(),
        JSON_OBJECT('nama', OLD.nama, 'harga', OLD.harga, 'stok', OLD.stok),
        JSON_OBJECT('nama', NEW.nama, 'harga', NEW.harga, 'stok', NEW.stok)
    );
END//

CREATE TRIGGER trg_produk_after_update_harga_saja
AFTER UPDATE ON produk
FOR EACH ROW
FOLLOWS trg_produk_after_update_audit
BEGIN
    IF OLD.harga <> NEW.harga THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_by, new_values)
        VALUES (
            'produk',
            'UPDATE',
            NEW.id,
            CONCAT('HARGA-', USER()),
            JSON_OBJECT('harga_baru', NEW.harga, 'harga_lama', OLD.harga)
        );
    END IF;
END//

CREATE TRIGGER trg_pesanan_after_delete_arsip
AFTER DELETE ON pesanan
FOR EACH ROW
BEGIN
    INSERT INTO arsip_pesanan (pesanan_id, produk_id, jumlah, status, total)
    VALUES (OLD.id, OLD.produk_id, OLD.jumlah, OLD.status, OLD.total);
END//

CREATE TRIGGER trg_pesanan_after_delete_audit
AFTER DELETE ON pesanan
FOR EACH ROW
FOLLOWS trg_pesanan_after_delete_arsip
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, old_values)
    VALUES (
        'pesanan',
        'DELETE',
        OLD.id,
        USER(),
        JSON_OBJECT('produk_id', OLD.produk_id, 'jumlah', OLD.jumlah, 'status', OLD.status, 'total', OLD.total)
    );
END//

DELIMITER ;

-- Pengujian Acara 2
-- Uji gagal (uncomment untuk menguji validasi harga < 1000.00):
-- UPDATE produk SET harga = 500.00 WHERE id = 1;
UPDATE produk SET stok = 8 WHERE id = 1;
UPDATE produk SET harga = 820000.00 WHERE id = 1;
INSERT INTO pesanan (produk_id, jumlah, status, total) VALUES (1, 2, 'selesai', 16400000.00);
DELETE FROM pesanan WHERE id = 1;


-- ============================================================================
-- ACARA 3: Sistem Manajemen Pesanan (Validasi, Audit JSON, Sinkronisasi & Price History)
-- ============================================================================
DROP DATABASE IF EXISTS trigger_lab;
CREATE DATABASE trigger_lab;
USE trigger_lab;

CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    total_spent DECIMAL(12,2) DEFAULT 0.00
);

CREATE TABLE audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(64) NOT NULL,
    operation ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    record_id BIGINT NOT NULL,
    changed_by VARCHAR(100) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values JSON,
    new_values JSON,
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_changed_at (changed_at)
);

CREATE TABLE price_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50)
);

CREATE TABLE products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

INSERT INTO customers (name, total_spent) VALUES ('Andi', 0.00), ('Budi', 0.00);

DELIMITER //

CREATE TRIGGER trg_orders_before_insert_validate
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.total_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Total amount harus lebih besar dari nol';
    END IF;
END//

CREATE TRIGGER trg_orders_after_insert_audit
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, new_values)
    VALUES (
        'orders',
        'INSERT',
        NEW.id,
        USER(),
        JSON_OBJECT('id', NEW.id, 'customer_id', NEW.customer_id, 'status', NEW.status, 'total_amount', NEW.total_amount)
    );
END//

CREATE TRIGGER trg_orders_after_insert_customer_spent
AFTER INSERT ON orders
FOR EACH ROW
FOLLOWS trg_orders_after_insert_audit
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE customers
        SET total_spent = total_spent + NEW.total_amount
        WHERE id = NEW.customer_id;
    END IF;
END//

CREATE TRIGGER trg_orders_after_update_audit
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, old_values, new_values)
    VALUES (
        'orders',
        'UPDATE',
        NEW.id,
        USER(),
        JSON_OBJECT('status', OLD.status, 'total_amount', OLD.total_amount, 'notes', OLD.notes),
        JSON_OBJECT('status', NEW.status, 'total_amount', NEW.total_amount, 'notes', NEW.notes)
    );
END//

CREATE TRIGGER trg_orders_after_update_customer_spent
AFTER UPDATE ON orders
FOR EACH ROW
FOLLOWS trg_orders_after_update_audit
BEGIN
    IF OLD.status <> 'completed' AND NEW.status = 'completed' THEN
        UPDATE customers
        SET total_spent = total_spent + NEW.total_amount
        WHERE id = NEW.customer_id;
    ELSEIF OLD.status = 'completed' AND NEW.status <> 'completed' THEN
        UPDATE customers
        SET total_spent = total_spent - OLD.total_amount
        WHERE id = NEW.customer_id;
    END IF;
END//

CREATE TRIGGER trg_orders_after_delete_audit
AFTER DELETE ON orders
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, old_values)
    VALUES (
        'orders',
        'DELETE',
        OLD.id,
        USER(),
        JSON_OBJECT('customer_id', OLD.customer_id, 'status', OLD.status, 'total_amount', OLD.total_amount, 'notes', OLD.notes)
    );
END//

CREATE TRIGGER trg_orders_after_delete_customer_spent
AFTER DELETE ON orders
FOR EACH ROW
FOLLOWS trg_orders_after_delete_audit
BEGIN
    IF OLD.status = 'completed' THEN
        UPDATE customers
        SET total_spent = total_spent - OLD.total_amount
        WHERE id = OLD.customer_id;
    END IF;
END//

CREATE TRIGGER trg_products_after_update_price
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
    IF OLD.price <> NEW.price THEN
        INSERT INTO price_history (product_id, old_price, new_price, changed_by)
        VALUES (NEW.id, OLD.price, NEW.price, USER());
    END IF;
END//

DELIMITER ;

-- Pengujian Acara 3
-- Uji gagal (uncomment untuk menguji validasi total_amount <= 0):
-- INSERT INTO orders (customer_id, status, total_amount, notes) VALUES (1, 'pending', -50.00, 'Order minus');
INSERT INTO orders (customer_id, status, total_amount, notes) VALUES (1, 'pending', 150.00, 'Pesanan pertama Andi');
INSERT INTO orders (customer_id, status, total_amount, notes) VALUES (2, 'completed', 300.00, 'Pesanan selesai Budi');
UPDATE orders SET status = 'completed' WHERE id = 1;

INSERT INTO products (name, price) VALUES
('Keyboard Mechanical', 500000.00),
('Mouse Wireless', 250000.00);
UPDATE products SET price = 550000.00 WHERE id = 1;
UPDATE products SET name = 'Keyboard Mechanical RGB' WHERE id = 1;