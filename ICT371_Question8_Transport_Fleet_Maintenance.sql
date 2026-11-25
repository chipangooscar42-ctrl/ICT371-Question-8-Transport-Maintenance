
/* ============================================================
   ICT371 - ADVANCED DATABASE
   QUESTION 8: TRANSPORT FLEET MAINTENANCE

   Student Name: [Enter your full name]
   Student Number: [Enter your student number]

   Complete PostgreSQL implementation.
   ============================================================ */


/* ============================================================
   PART 1: CLEAN UP OLD QUESTION 8 OBJECTS
   ============================================================ */

DROP VIEW IF EXISTS v_service_due CASCADE;

DROP TABLE IF EXISTS service_alerts CASCADE;
DROP TABLE IF EXISTS trips CASCADE;
DROP TABLE IF EXISTS vehicles CASCADE;


/* ============================================================
   PART 2: CREATE THE REQUIRED TABLES
   ============================================================ */

CREATE TABLE vehicles (
    vehicle_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registration VARCHAR(20) NOT NULL UNIQUE,
    current_odometer NUMERIC(12,2) NOT NULL,
    last_service_odometer NUMERIC(12,2) NOT NULL,

    CONSTRAINT chk_current_odometer
        CHECK (current_odometer >= 0),

    CONSTRAINT chk_last_service_odometer
        CHECK (last_service_odometer >= 0),

    CONSTRAINT chk_service_not_above_current
        CHECK (last_service_odometer <= current_odometer)
);


CREATE TABLE trips (
    trip_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id INTEGER NOT NULL,
    trip_on DATE NOT NULL,
    start_odometer NUMERIC(12,2) NOT NULL,
    end_odometer NUMERIC(12,2) NOT NULL,

    CONSTRAINT fk_trip_vehicle
        FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id),

    CONSTRAINT chk_trip_start
        CHECK (start_odometer >= 0),

    CONSTRAINT chk_trip_end
        CHECK (end_odometer > start_odometer)
);


CREATE TABLE service_alerts (
    vehicle_id INTEGER PRIMARY KEY,
    km_since_service NUMERIC(12,2) NOT NULL,
    flagged_on DATE NOT NULL,

    CONSTRAINT fk_alert_vehicle
        FOREIGN KEY (vehicle_id)
        REFERENCES vehicles(vehicle_id),

    CONSTRAINT chk_alert_km
        CHECK (km_since_service >= 0)
);


/* ============================================================
   PART 3: INSERT THREE VEHICLES
   They have different service positions.
   ============================================================ */

INSERT INTO vehicles (
    registration,
    current_odometer,
    last_service_odometer
)
VALUES
    ('BCA 1234', 10000, 6000),
    ('BCA 5678', 20000, 16000),
    ('BCA 9012', 15000, 9000);


/* Check the vehicles */

SELECT *
FROM vehicles
ORDER BY vehicle_id;


/* ============================================================
   PART 4: CREATE THE SERVICE-DUE FUNCTION

   A vehicle is due for service when it has travelled
   at least 5,000 kilometres since its last service.
   ============================================================ */

CREATE OR REPLACE FUNCTION fn_service_due(
    p_vehicle_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_odometer NUMERIC(12,2);
    v_last_service_odometer NUMERIC(12,2);
BEGIN
    SELECT current_odometer, last_service_odometer
    INTO v_current_odometer, v_last_service_odometer
    FROM vehicles
    WHERE vehicle_id = p_vehicle_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Vehicle ID % does not exist',
            p_vehicle_id;
    END IF;

    RETURN (
        v_current_odometer - v_last_service_odometer
    ) >= 5000;
END;
$$;


/* Test the function before recording trips */

SELECT
    vehicle_id,
    registration,
    current_odometer - last_service_odometer
        AS km_since_service,
    fn_service_due(vehicle_id) AS service_due
FROM vehicles
ORDER BY vehicle_id;


/* ============================================================
   PART 5: CREATE THE TRIP VALIDATION TRIGGER

   The trigger:
   1. Checks that the vehicle exists.
   2. Checks that the trip starts at the current odometer.
   3. Rejects invalid mileage.
   4. Updates the vehicle odometer to the trip end.

   The trigger updates the odometer exactly once.
   ============================================================ */

CREATE OR REPLACE FUNCTION fn_validate_and_update_odometer()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_odometer NUMERIC(12,2);
BEGIN
    SELECT current_odometer
    INTO v_current_odometer
    FROM vehicles
    WHERE vehicle_id = NEW.vehicle_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Vehicle ID % does not exist',
            NEW.vehicle_id;
    END IF;

    IF NEW.start_odometer < 0 THEN
        RAISE EXCEPTION
            'Starting odometer cannot be negative';
    END IF;

    IF NEW.end_odometer <= NEW.start_odometer THEN
        RAISE EXCEPTION
            'Ending odometer must be greater than starting odometer';
    END IF;

    IF NEW.start_odometer <> v_current_odometer THEN
        RAISE EXCEPTION
            'Invalid trip start. Expected odometer %, but received %',
            v_current_odometer,
            NEW.start_odometer;
    END IF;

    UPDATE vehicles
    SET current_odometer = NEW.end_odometer
    WHERE vehicle_id = NEW.vehicle_id;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_update_vehicle_odometer
ON trips;


CREATE TRIGGER trg_update_vehicle_odometer
BEFORE INSERT
ON trips
FOR EACH ROW
EXECUTE FUNCTION fn_validate_and_update_odometer();


/* ============================================================
   PART 6: CREATE THE TRIP RECORDING PROCEDURE

   The procedure validates the inputs and inserts a trip.
   It does not update the vehicle odometer itself.
   The trigger performs that update.
   ============================================================ */

CREATE OR REPLACE PROCEDURE pr_record_trip(
    p_vehicle_id INTEGER,
    p_trip_on DATE,
    p_start NUMERIC,
    p_end NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM vehicles
        WHERE vehicle_id = p_vehicle_id
    ) THEN
        RAISE EXCEPTION
            'Vehicle ID % does not exist',
            p_vehicle_id;
    END IF;

    IF p_trip_on IS NULL THEN
        RAISE EXCEPTION
            'Trip date cannot be NULL';
    END IF;

    IF p_start IS NULL OR p_end IS NULL THEN
        RAISE EXCEPTION
            'Trip odometer readings cannot be NULL';
    END IF;

    IF p_start < 0 THEN
        RAISE EXCEPTION
            'Starting odometer cannot be negative';
    END IF;

    IF p_end <= p_start THEN
        RAISE EXCEPTION
            'Ending odometer must be greater than starting odometer';
    END IF;

    INSERT INTO trips (
        vehicle_id,
        trip_on,
        start_odometer,
        end_odometer
    )
    VALUES (
        p_vehicle_id,
        p_trip_on,
        p_start,
        p_end
    );

END;
$$;


/* ============================================================
   PART 7: RECORD SIX TRIPS THROUGH THE PROCEDURE

   Vehicle 1: 10,000 -> 10,500 -> 11,000
   Vehicle 2: 20,000 -> 20,200 -> 20,400
   Vehicle 3: 15,000 -> 15,100 -> 15,200

   Each trip starts at the vehicle's current odometer.
   ============================================================ */

-- Vehicle 1: first trip
CALL pr_record_trip(
    1, CURRENT_DATE - 5, 10000, 10500
);

-- Vehicle 1: second trip
CALL pr_record_trip(
    1, CURRENT_DATE - 4, 10500, 11000
);

-- Vehicle 2: first trip
CALL pr_record_trip(
    2, CURRENT_DATE - 3, 20000, 20200
);

-- Vehicle 2: second trip
CALL pr_record_trip(
    2, CURRENT_DATE - 2, 20200, 20400
);

-- Vehicle 3: first trip
CALL pr_record_trip(
    3, CURRENT_DATE - 1, 15000, 15100
);

-- Vehicle 3: second trip
CALL pr_record_trip(
    3, CURRENT_DATE, 15100, 15200
);


/* ============================================================
   PART 8: CHECK THE SIX TRIPS
   ============================================================ */

SELECT
    t.trip_id,
    v.registration,
    t.trip_on,
    t.start_odometer,
    t.end_odometer,
    (t.end_odometer - t.start_odometer) AS distance_travelled
FROM trips t
JOIN vehicles v
    ON t.vehicle_id = v.vehicle_id
ORDER BY t.trip_id;


/* ============================================================
   PART 9: CHECK THE UPDATED VEHICLE ODOMETERS
   ============================================================ */

SELECT
    vehicle_id,
    registration,
    current_odometer,
    last_service_odometer,
    (current_odometer - last_service_odometer)
        AS km_since_service,
    fn_service_due(vehicle_id) AS service_due
FROM vehicles
ORDER BY vehicle_id;


/* ============================================================
   PART 10: CREATE THE SERVICE-DUE VIEW

   Show registration and kilometres since service for
   vehicles that have travelled at least 5,000 km.
   ============================================================ */

CREATE OR REPLACE VIEW v_service_due AS
SELECT
    registration,
    (current_odometer - last_service_odometer)
        AS km_since_service
FROM vehicles
WHERE (current_odometer - last_service_odometer) >= 5000;


/* Display vehicles that need servicing */

SELECT *
FROM v_service_due
ORDER BY registration;


/* ============================================================
   PART 11: CREATE AN INDEX FOR VEHICLE TRIP SEARCHES

   The index supports searching one vehicle's trips
   within a specified trip date range.
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_trips_vehicle_trip_on
ON trips (vehicle_id, trip_on);


/* Matching query */

SELECT
    trip_id,
    vehicle_id,
    trip_on,
    start_odometer,
    end_odometer
FROM trips
WHERE vehicle_id = 1
  AND trip_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE
ORDER BY trip_on;


/* EXPLAIN query plan */

EXPLAIN
SELECT
    trip_id,
    vehicle_id,
    trip_on,
    start_odometer,
    end_odometer
FROM trips
WHERE vehicle_id = 1
  AND trip_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE
ORDER BY trip_on;


/* ============================================================
   PART 12: CREATE THE SERVICE ALERT REFRESH PROCEDURE

   It creates or updates alerts for vehicles due for service.
   It removes alerts for vehicles that are no longer due.
   ============================================================ */

CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
LANGUAGE plpgsql
AS $$
BEGIN

    /* Add new alerts or update existing alerts */

    INSERT INTO service_alerts (
        vehicle_id,
        km_since_service,
        flagged_on
    )
    SELECT
        vehicle_id,
        (current_odometer - last_service_odometer),
        CURRENT_DATE
    FROM vehicles
    WHERE (current_odometer - last_service_odometer) >= 5000

    ON CONFLICT (vehicle_id)
    DO UPDATE SET
        km_since_service = EXCLUDED.km_since_service,
        flagged_on = EXCLUDED.flagged_on;


    /* Remove alerts for vehicles no longer due */

    DELETE FROM service_alerts sa
    WHERE NOT EXISTS (
        SELECT 1
        FROM vehicles v
        WHERE v.vehicle_id = sa.vehicle_id
          AND (v.current_odometer - v.last_service_odometer) >= 5000
    );

END;
$$;


/* Run the procedure once */

CALL pr_refresh_service_alerts();


/* Display the service alerts */

SELECT
    sa.vehicle_id,
    v.registration,
    sa.km_since_service,
    sa.flagged_on
FROM service_alerts sa
JOIN vehicles v
    ON sa.vehicle_id = v.vehicle_id
ORDER BY sa.vehicle_id;


/* ============================================================
   PART 13: SCHEDULE THE JOB EVERY MONDAY AT 06:00

   pg_cron must be installed and configured by the server.
   ============================================================ */

DO $$
BEGIN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';

    EXECUTE $schedule$
        SELECT cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'ict371_weekly_service_alerts'
    $schedule$;

    EXECUTE $schedule$
        SELECT cron.schedule(
            'ict371_weekly_service_alerts',
            '0 6 * * 1',
            'CALL pr_refresh_service_alerts();'
        )
    $schedule$;

    RAISE NOTICE
        'Weekly service alert job scheduled for Monday at 06:00';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE
            'Automatic scheduling was not configured: %',
            SQLERRM;
END;
$$;


/* ============================================================
   PART 14: FINAL VERIFICATION QUERIES
   ============================================================ */


/* 1. Total number of vehicles */

SELECT COUNT(*) AS total_vehicles
FROM vehicles;


/* 2. Total number of trips */

SELECT COUNT(*) AS total_trips
FROM trips;


/* 3. Display all vehicles and their service positions */

SELECT
    registration,
    current_odometer,
    last_service_odometer,
    (current_odometer - last_service_odometer)
        AS km_since_service,
    fn_service_due(vehicle_id) AS service_due
FROM vehicles
ORDER BY vehicle_id;


/* 4. Display all recorded trips */

SELECT *
FROM trips
ORDER BY trip_id;


/* 5. Display vehicles due for service */

SELECT *
FROM v_service_due;


/* 6. Display all service alerts */

SELECT *
FROM service_alerts
ORDER BY vehicle_id;


/* 7. Confirm the index exists */

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'trips';


/* 8. Confirm the trigger exists */

SELECT
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'trips';


/* 9. Confirm the function and procedures exist */

SELECT
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_name IN (
    'fn_service_due',
    'fn_validate_and_update_odometer',
    'pr_record_trip',
    'pr_refresh_service_alerts'
)
ORDER BY routine_name;
