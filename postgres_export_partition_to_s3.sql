-- pre-requisites
    
-- as postgres user
grant usage ON schema aws_s3 to database_user ;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA aws_s3 TO database_user ;

-- as app user
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE public.export_to_s3(partition_name_to_export text)
LANGUAGE 'plpgsql'
AS $BODY$
declare 
 curr_year text := sum(EXTRACT(YEAR FROM now()));
 curr_month text := lpad(extract(month from now())::text, 2, '0') ;
 curr_day text := lpad(extract(day from now()-interval '1 day')::text, 2, '0') ;
begin
    if partition_name_to_export is not null then
        set application_name to aws_query_export_manually_to_s3; 
        -- ('query to upload', aws_commons.create_s3_uri('bucket_name', 'bucket-path', 'region') );
        perform * from aws_s3.query_export_to_s3('select * from ' || $1, 
        aws_commons.create_s3_uri('bucket_name', partition_name_to_export||'/'||partition_name_to_export||'',
        'us-east-1'), 
        options :='format csv');
    else
        set application_name to aws_query_export_automatically_to_s3; 
        PERFORM * from aws_s3.query_export_to_s3('select * from table_name_p'|| curr_year || curr_month || curr_day ||'', 
        aws_commons.create_s3_uri('bucket_name', 
        'table_name_p'|| curr_year || curr_month || curr_day ||'/table_name_p'|| curr_year || curr_month || curr_day ||'',
        'us-east-1'), 
        options :='format csv'); 
    end if;
    -- HOW TO USE
    -- MANUAL EXPORT TO S3 SPECIFIC PARTITION
    -- call export_to_s3('table_name_p20240310');
    -- AUTOMATIC EXPORT OF DAY BEFORE
    --call export_to_s3(null);
end;
$BODY$;
---------------------------------------------------------------
-- remember to schedule with 3 hours difference
-- 00 17 * * *
-- will run at 14
SELECT cron.schedule ('Manual execution of s3 export', '00 01 03 1 2', 'call export_to_s3(''table_name_p20240310'')');
---------------------------------------------------------------

-- remember to schedule with 3 hours difference
-- 00 04 * * *
-- will run at 01AM BRT
SELECT cron.schedule ('Automatic execution of s3 export', '00 04 * * *', 'call export_to_s3(null)');

