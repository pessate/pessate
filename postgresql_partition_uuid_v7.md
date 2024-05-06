h1. Partitioning tables with UUIDv7 and date range

h3. 
-- draft version - paulo junior
These are the functions to handle the ids / timestamps

All the following were based on https://gitlab.com/postgres-ai/postgresql-consulting/postgres-howtos/-/blob/main/0065_uuid_v7_and_partitioning_timescaledb.md?ref_type=heads

h4. Basic UUID generation: uuid_generate_v7()
# FUNCTION TO GENERATE UUIID WITH THE TIMESTAMP IN IT
```sql
create or replace function uuid_generate_v7() returns uuid
as $$
  -- use random v4 uuid as starting point (which has the same variant we need)
  -- then overlay timestamp
  -- then set version 7 by flipping the 2 and 1 bit in the version 4 string
select encode(
  set_bit(
    set_bit(
      overlay(
        uuid_send(gen_random_uuid())
        placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
        from 1 for 6
      ),
      52, 1
    ),
    53, 1
  ),
  'hex')::uuid;
$$ language SQL volatile;
```

h4. Convert timestamp to UUID_v7: ts_to_uuid_v7(timestamptz)
# ACTIVATE EXTENSION TO CRYPYT/DECRYPT UUIDV7
```sql
create extension pgcrypto;
create or replace function ts_to_uuid_v7(timestamptz) returns uuid
as $$
  select encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
          from 1 for 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex')::uuid;
$$ language SQL volatile;
```

h4. Convert UUIDv7 to timestamp: uuid_v7_to_ts(uuid_v7 uuid) 
```sql
create or replace function uuid_v7_to_ts(uuid_v7 uuid) returns timestamptz
as $$
  select
    to_timestamp(
      (
        'x' || substring(
          encode(uuid_send(uuid_v7), 'hex')
          from 1 for 12
        )
      )::bit(48)::bigint / 1000.0
    )::timestamptz;
$$ language sql;
```

h4. Create monthly partitions: create_daily_uuidv7_partitions(parent_table_name text, curr_partition_date date)

```sql
CREATE OR REPLACE FUNCTION create_daily_uuidv7_partitions(parent_table_name text, curr_partition_date date) RETURNS VOID AS
$BODY$
DECLARE
    sql text;
    partition_date date := curr_partition_date;
    partition_name text;
    dt record;
BEGIN   
    FOR dt IN SELECT generate_series(partition_date, (partition_date + interval '1 month')::date, '1 day'::interval) LOOP
        partition_name := format('%s_p%s', parent_table_name, to_char(dt.generate_series::DATE, 'YYYYMMDD'));   
        raise notice 'partition_name: %', partition_name;
            -- Notifying
            RAISE NOTICE 'A new % partition will be created: %', parent_table_name, partition_name;
            select format('CREATE TABLE IF NOT EXISTS %s PARTITION OF %s FOR VALUES
            FROM (overlay(ts_to_uuid_v7(''%s''::date)::text placing ''00-0000-0000-000000000000'' from 12)::uuid)
            TO (overlay(ts_to_uuid_v7(''%s''::date)::text placing ''00-0000-0000-000000000000'' from 12)::uuid) '
        , partition_name
        , parent_table_name
        , dt.generate_series::DATE
        , dt.generate_series::DATE + interval '1 day') into sql;

        EXECUTE sql;
    end loop;
END;
$BODY$
LANGUAGE plpgsql;
```

h4. Create daily partitions: create_monthly_uuidv7_partitions(parent_table_name text, curr_partition_date date)
```sql
CREATE OR REPLACE FUNCTION create_monthly_uuidv7_partitions(parent_table_name text, curr_partition_date date) RETURNS VOID AS
$BODY$
DECLARE
    sql text;
    partition_date date := curr_partition_date;
    partition_name text;
    dt record;
BEGIN   
    FOR dt IN SELECT generate_series(partition_date, (partition_date + interval '1 year')::date, '1 month'::interval) LOOP
        partition_name := format('%s_p%s', parent_table_name, to_char(dt.generate_series::DATE, 'YYYYMM'));   
        raise notice 'partition_name: %', partition_name;
            -- Notifying
            RAISE NOTICE 'A new % partition will be created: %', parent_table_name, partition_name;
            select format('CREATE TABLE IF NOT EXISTS %s PARTITION OF %s FOR VALUES
            FROM (overlay(ts_to_uuid_v7(''%s''::date)::text placing ''00-0000-0000-000000000000'' from 12)::uuid)
            TO (overlay(ts_to_uuid_v7(''%s''::date)::text placing ''00-0000-0000-000000000000'' from 12)::uuid) '
        , partition_name
        , parent_table_name
        , date_trunc('month', dt.generate_series::DATE)
        , date_trunc('month', dt.generate_series::DATE + interval '1 month')) into sql;
        
        EXECUTE sql;
    end loop;
END;
$BODY$
LANGUAGE plpgsql;
```

h4. Let's do some testing

# CREATE A TEST TABLE
```sql
CREATE TABLE if not exists public.test (
    id uuid not null PRIMARY KEY, 
    data text )
PARTITION BY RANGE(id);
```

# CREATE A CRON JOB TO CREATE PARTITIONS (MONTHLY OR DAILY) AS YOUR NEED
```sql
--schedule a weekly job to create daily partitions for the next month
SELECT cron.schedule('Maintenance Partition Tables Test', '@weekly', $$ select create_daily_uuidv7_partitions('test', now()::date); $$);

-- schedule a weekly job to create monthly partitions for the next year
SELECT cron.schedule('Maintenance Partition Tables Test', '@weekly', $$ select create_monthly_uuidv7_partitions('test', now()::date); $$);
```
# HOW TO CHECK IF PARTITION NAMING MATCHES THE DATES:
```sql
--- check if partition name matches dates (daily)
DO $$              
declare dt record;
BEGIN
    FOR dt IN SELECT generate_series(now()::date, (now() + interval '1 month')::date, '1 day'::interval) LOOP
        RAISE NOTICE 'Processing date: % - partition_name %'
        , to_char(dt.generate_series::DATE, 'YYYY-MM-DD')
        , (overlay(ts_to_uuid_v7(dt.generate_series::date)::text placing '00-0000-0000-000000000000' from 12)::uuid);
    end loop;
END;
$$;

--- check if partition name matches dates (monthly)
DO $$              
declare dt record;
BEGIN
    FOR dt IN SELECT generate_series(now()::date, (now() + interval '1 year')::date, '1 month'::interval) LOOP
        RAISE NOTICE 'Processing date: % partition_name %'
                    , to_char(dt.generate_series::DATE, 'YYYY-MM')
                    , (overlay(ts_to_uuid_v7(date_trunc('month', dt.generate_series::DATE)::date)::text placing '00-0000-0000-000000000000' from 12)::uuid);
    end loop;
END;
$$;
```

# TIME TO INSERT SOME DATA
```sql
-- here I'll do on a daily partitioned table
DO $$              
declare dt record;
BEGIN
    FOR dt IN SELECT generate_series(now()::date, (now() + interval '1 month')::date, '1 day'::interval) LOOP
        FOR i IN 1..100000 LOOP
            INSERT INTO test (id, data) VALUES (ts_to_uuid_v7(dt.generate_series), random()::text);
        END LOOP;
    end loop;
END;
$$;
```

# AND FINALLY, TIME TO CHECK IF THE PLAN WILL WORK AS EXPECTED
```sql
select (overlay(ts_to_uuid_v7('2024-05-13'::date)::text placing '00-0000-0000-000000000000' from 12)::uuid) as min_created_at ,(overlay(ts_to_uuid_v7('2024-05-15'::date)::text placing '00-0000-0000-000000000000' from 12)::uuid) as  max_created_at \gset
```
```sql
EXPLAIN (ANALYZE, BUFFERS, verbose)
 select  count(*) from test where id > :'min_created_at' and id < :'max_created_at' ;
```
