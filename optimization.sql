-- ##############################################
-- Пример 1: Оптимизация через создание индексов
-- ##############################################

-- Исходная таблица заказов без индексов
CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    user_id INT,
    product_id INT,
    order_date DATE,
    amount DECIMAL(10,2)
);

-- Запрос 1.1: Поиск заказов пользователя (до оптимизации)
EXPLAIN ANALYZE 
SELECT * FROM orders WHERE user_id = 123;
-- Время выполнения: 450 ms (при 1 млн записей)

-- Создаем индекс для user_id
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- Запрос 1.2: Тот же запрос после создания индекса
EXPLAIN ANALYZE 
SELECT * FROM orders WHERE user_id = 123;
-- Время выполнения: 2.3 ms (ускорение в 195 раз)

/*
Объяснение:
Индекс idx_orders_user_id позволяет СУБД быстро находить записи
по user_id без полного сканирования таблицы. B-дерево индекса
оптимизирует поиск по значению, сокращая количество обращений к диску.
*/

-- ##############################################
-- Пример 2: Оптимизация сложных JOIN-запросов
-- ##############################################

-- Исходный запрос с подзапросом
EXPLAIN ANALYZE
SELECT u.name, 
       (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.user_id) AS order_count
FROM users u
WHERE u.registration_date > '2023-01-01';
-- Время выполнения: 1200 ms (при 100k пользователей)

-- Оптимизированный вариант с JOIN
EXPLAIN ANALYZE
SELECT u.name, COUNT(o.order_id) AS order_count
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
WHERE u.registration_date > '2023-01-01'
GROUP BY u.user_id, u.name;
-- Время выполнения: 85 ms (ускорение в 14 раз)

/*
Объяснение:
Использование JOIN вместо коррелированного подзапроса позволяет
СУБД оптимизировать выполнение одним проходом по данным. GROUP BY
с агрегатной функцией COUNT эффективнее множественных подзапросов.
*/

-- ##############################################
-- Пример 3: Оптимизация сортировки с использованием индексов
-- ##############################################

-- Запрос 3.1: Сортировка без индекса
EXPLAIN ANALYZE
SELECT * FROM orders 
WHERE order_date BETWEEN '2023-01-01' AND '2023-12-31'
ORDER BY amount DESC
LIMIT 100;
-- Время выполнения: 650 ms

-- Создаем составной индекс
CREATE INDEX idx_orders_date_amount ON orders(order_date, amount DESC);

-- Запрос 3.2: После добавления индекса
EXPLAIN ANALYZE
SELECT * FROM orders 
WHERE order_date BETWEEN '2023-01-01' AND '2023-12-31'
ORDER BY amount DESC
LIMIT 100;
-- Время выполнения: 12 ms (ускорение в 54 раза)

/*
Объяснение:
Составной индекс (order_date, amount) позволяет:
1. Быстро отфильтровать записи по дате
2. Получить предварительно отсортированные данные по amount
3. Использовать индекс для LIMIT без полной сортировки
*/

-- ##############################################
-- Пример 4: Оптимизация группировки данных
-- ##############################################

-- Исходный запрос с временной таблицей
EXPLAIN ANALYZE
SELECT product_id, AVG(amount) AS avg_price
INTO TEMP temp_results
FROM orders
GROUP BY product_id;

SELECT * FROM temp_results ORDER BY avg_price DESC;
-- Общее время: 320 ms

-- Оптимизированный вариант с оконными функциями
EXPLAIN ANALYZE
SELECT DISTINCT product_id, 
       AVG(amount) OVER (PARTITION BY product_id) AS avg_price
FROM orders
ORDER BY avg_price DESC;
-- Время выполнения: 95 ms (ускорение в 3.4 раза)

/*
Объяснение:
Использование оконных функций позволяет избежать создания
временной таблицы и выполнить операцию за один проход
по данным с использованием индексов.
*/

-- ##############################################
-- Пример 5: Оптимизация обновлений через пакетную обработку
-- ##############################################

-- Медленное поэлементное обновление
DO $$
DECLARE 
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM orders WHERE order_date < '2020-01-01' LOOP
        UPDATE orders 
        SET status = 'archived' 
        WHERE order_id = rec.order_id;
    END LOOP;
END $$;
-- Время выполнения: 25 мин (для 50k записей)

-- Оптимизированное массовое обновление
EXPLAIN ANALYZE
UPDATE orders
SET status = 'archived'
WHERE order_date < '2020-01-01';
-- Время выполнения: 1.2 сек (ускорение в 1250 раз)

/*
Объяснение:
Массовое обновление вместо поэлементной обработки:
- Минимизирует количество транзакций
- Позволяет использовать индексы
- Снижает накладные расходы на парсинг запросов
*/

-- ##############################################
-- Пример 6: Оптимизация поиска по текстовым полям
-- ##############################################

-- Исходная таблица продуктов
CREATE TABLE products (
    product_id INT PRIMARY KEY,
    name VARCHAR(255),
    description TEXT
);

-- Медленный LIKE-запрос
EXPLAIN ANALYZE
SELECT * FROM products 
WHERE description LIKE '%organic%' OR name LIKE '%organic%';
-- Время выполнения: 820 ms (при 100k товаров)

-- Создаем GIN-индекс для полнотекстового поиска
ALTER TABLE products ADD COLUMN search_vector TSVECTOR;
UPDATE products SET search_vector = 
    to_tsvector('english', name || ' ' || description);
CREATE INDEX idx_products_search ON products USING GIN(search_vector);

-- Оптимизированный полнотекстовый поиск
EXPLAIN ANALYZE
SELECT * FROM products 
WHERE search_vector @@ to_tsquery('organic');
-- Время выполнения: 12 ms (ускорение в 68 раз)

/*
Объяснение:
Использование полнотекстового индекса:
- Поддерживает морфологический поиск
- Игнорирует стоп-слова
- Работает с весами и рейтингами совпадений
- Оптимизирован для сложных текстовых поисков
*/

-- ##############################################
-- Пример 7: Оптимизация через материализованные представления
-- ##############################################

-- Часто используемый сложный запрос
EXPLAIN ANALYZE
SELECT u.user_id, u.name, COUNT(o.order_id), SUM(o.amount)
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.name;
-- Время выполнения: 1200 ms (ежедневный отчет)

-- Создаем материализованное представление
CREATE MATERIALIZED VIEW user_statistics AS
SELECT u.user_id, u.name, COUNT(o.order_id) AS orders_count, 
       SUM(o.amount) AS total_amount
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.user_id, u.name;

-- Обновление данных (по расписанию)
REFRESH MATERIALIZED VIEW CONCURRENTLY user_statistics;

-- Запрос из материализованного представления
EXPLAIN ANALYZE
SELECT * FROM user_statistics;
-- Время выполнения: 15 ms (ускорение в 80 раз)

/*
Объяснение:
Материализованные представления:
- Хранят предварительно вычисленные результаты
- Обновляются по расписанию или триггерам
- Экономят ресурсы при частых сложных запросах
- Поддерживают индексы для быстрого доступа
*/
