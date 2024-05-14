CREATE TABLE IF NOT EXISTS public.table_name
(
	id uuid DEFAULT gen_random_uuid(),
	created_at timestamp NOT NULL DEFAULT now(), 
	updated_at timestamp null,
	inserted_at timestamp NOT NULL,
 	CONSTRAINT table_name_pkey PRIMARY KEY (id,inserted_at)
	)
	partition by range (inserted_at)
;

######################################################

create table partman.template_public_table_name(like public.table_name including all);

alter table partman.template_public_table_name set (autovacuum_vacuum_cost_delay='0', autovacuum_analyze_scale_factor='0.0', autovacuum_analyze_threshold='500000', autovacuum_vacuum_scale_factor='0.0', autovacuum_vacuum_threshold='1000000', autovacuum_vacuum_insert_threshold='500000', autovacuum_vacuum_insert_scale_factor='0.0');

######################################################

-- starting date to partition 
-- starts with 5 partitions
-- daily partition 

SELECT partman.create_parent( 
 p_parent_table => 'public.table_name',
 p_control => 'inserted_at',
 p_type => 'native',
 p_interval=> 'daily',
 p_start_partition=> '2021-09-28',
 p_premake => 30,
 p_template_table => 'partman.template_public_table_name');

--
UPDATE partman.part_config 
SET infinite_time_partitions = true,
    retention_keep_table=true ,
    retention='5 days'
WHERE parent_table = 'public.table_name';
commit;
-- detach after 5 days

-- daily maintenance
SELECT cron.schedule('Maintenance Partition Tables Transactions', '@daily', $$CALL partman.run_maintenance_proc()$$);
---------------------------------------------------------------------------------------------------------------------
-- ps.
-- if cron is on postgres main db, must set job to run commmand under db_user role
\c postgres postgres
-- result id from above command
UPDATE cron.job SET database = 'database_name', username = 'database_name_username' WHERE jobid = 1; -- <  results of the query above
select * from cron.job;


