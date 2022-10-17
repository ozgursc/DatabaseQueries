-----------------------
-- REQUIREMENTS
-----------------------

DROP EXTENSION IF EXISTS "uuid-ossp";

CREATE EXTENSION "uuid-ossp" SCHEMA public;

DROP TYPE IF EXISTS foreign_key_data CASCADE;

CREATE TYPE foreign_key_data AS (
	const_name varchar,
	main_table_name varchar,
	main_column_name varchar,
	foreign_table_name varchar,
	foreign_column_name varchar,
	fk_script varchar
);


DROP TABLE IF EXISTS product_product_topics;
COMMIT;

-----------------------
-- FUNCTION TO GET ALL FOREIGN KEYS
-----------------------

CREATE OR REPLACE FUNCTION returnReferencedForeignKeys(IN p_table_name character varying)
	RETURNS SETOF foreign_key_data
AS 
$$	
BEGIN	
	RAISE NOTICE 'FUNCTION		CHECKING RELATIONS for table: %', p_table_name;

	RETURN QUERY
		SELECT 
			c.conname::character varying,
			tbl.relname::character varying,
			col.attname::character varying,
			referenced_tbl.relname::character varying,
			referenced_field.attname::character varying,
			pg_get_constraintdef(c.oid)::character varying
		FROM pg_constraint c
			INNER JOIN pg_namespace AS sh ON sh.oid = c.connamespace
			INNER JOIN (SELECT oid, unnest(conkey) as conkey FROM pg_constraint) con ON c.oid = con.oid
			INNER JOIN pg_class tbl ON tbl.oid = c.conrelid
			INNER JOIN pg_attribute col ON (col.attrelid = tbl.oid AND col.attnum = con.conkey)
			INNER JOIN pg_class referenced_tbl ON c.confrelid = referenced_tbl.oid
			INNER JOIN pg_namespace AS referenced_sh ON referenced_sh.oid = referenced_tbl.relnamespace
			INNER JOIN (SELECT oid, unnest(confkey) as confkey FROM pg_constraint) conf ON c.oid = conf.oid
			INNER JOIN pg_attribute referenced_field ON (referenced_field.attrelid = c.confrelid AND referenced_field.attnum = conf.confkey)
		WHERE referenced_tbl.relname = p_table_name;
END;
$$
LANGUAGE 'plpgsql';
COMMIT;

-----------------------
-- SQL TO REPLACE ALL IDs
-----------------------

DROP PROCEDURE IF EXISTS public.convertintidtouuid(character varying);

CREATE PROCEDURE convertIntIDtoUUID(IN p_table_name character varying)
LANGUAGE 'plpgsql'
AS $BODY$
declare
	const_drop_queries character varying[];
	const_create_queries character varying[];
	main_add_old_fk_queries character varying[];
	set_old_fk_queries character varying[];
	
	const_drop_q character varying;
	const_create_q character varying;
	old_fk_q character varying;
	set_old_fk_q character varying;
	set_fk_q character varying;
	switch_fk_type_q character varying;
	remove_old_fk_q character varying;
	remove_old_id_q character varying;
	
	fk foreign_key_data;
	
begin
	raise notice 'PROCEDURE		STARTING!! for table: %', p_table_name;
	
	for fk IN select * from returnReferencedForeignKeys(p_table_name) LOOP
		raise notice 'PROCEDURE		start process for table: % -> % key: %', p_table_name, fk.main_table_name, fk.const_name;
		-- create drop queries for main table constraints 
		const_drop_q = FORMAT('ALTER TABLE IF EXISTS %s DROP CONSTRAINT %s', 
						fk.main_table_name, fk.const_name);
		const_drop_queries = array_append(const_drop_queries, const_drop_q);
			
		-- create old fk fields
		old_fk_q = FORMAT('ALTER TABLE IF EXISTS %s ADD COLUMN old_%s integer null;',
						 fk.main_table_name, fk.main_column_name);
						 
		set_old_fk_q  = FORMAT('UPDATE %s SET old_%2$s = %2$s;',
						 fk.main_table_name, fk.main_column_name);
						 
		main_add_old_fk_queries = array_append(main_add_old_fk_queries, old_fk_q);
		set_old_fk_queries = array_append(set_old_fk_queries, set_old_fk_q);
		
		-- create add queries for main table constraints 
		switch_fk_type_q = FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN %2$s TYPE uuid USING (uuid_generate_v4());', 
						 fk.main_table_name, fk.main_column_name);
						 
		set_fk_q = FORMAT('UPDATE %1$s SET %2$s = (SELECT pt.id FROM %3$s pt WHERE pt.old_id = old_%2$s)',
			fk.main_table_name, fk.main_column_name, p_table_name);
		
		const_create_q = FORMAT('ALTER TABLE IF EXISTS %s ADD CONSTRAINT FK_%s_%s_%s %s;',
			fk.main_table_name, fk.main_table_name, 
			fk.foreign_table_name, fk.main_column_name, fk.fk_script);
			
		remove_old_fk_q = FORMAT('ALTER TABLE IF EXISTS %s DROP COLUMN old_%s;',
						 fk.main_table_name, fk.main_column_name);
						 
		remove_old_id_q = FORMAT('ALTER TABLE IF EXISTS %s DROP COLUMN old_id;', p_table_name);
		
		const_create_queries = array_append(const_create_queries, switch_fk_type_q);
		const_create_queries = array_append(const_create_queries, set_fk_q);
		const_create_queries = array_append(const_create_queries, const_create_q);	
		const_create_queries = array_append(const_create_queries, remove_old_fk_q);	
		const_create_queries = array_append(const_create_queries, remove_old_id_q);	
	end loop;
	
	-- add old foreign key columns
	if array_length(main_add_old_fk_queries, 1) > 0 then
		raise notice 'PROCEDURE		add old foreign keys for %', p_table_name;
		for i in array_lower(main_add_old_fk_queries, 1) .. array_upper(main_add_old_fk_queries, 1) loop
			raise notice 'PROCEDURE			old fk % ', main_add_old_fk_queries[i];
			EXECUTE main_add_old_fk_queries[i];
		end loop;
	end if;
	
	-- update old foreign key columns
	if array_length(set_old_fk_queries, 1) > 0 then
		raise notice 'PROCEDURE		update old foreign keys for %', p_table_name;
		for i in array_lower(set_old_fk_queries, 1) .. array_upper(set_old_fk_queries, 1) loop
			raise notice 'PROCEDURE			old fk % ', set_old_fk_queries[i];
			EXECUTE set_old_fk_queries[i];
			COMMIT;
		end loop;
	end if;
	
	-- drop constraints 
	if array_length(const_drop_queries, 1) > 0 then
		raise notice 'PROCEDURE		drop constraints for %', p_table_name;
		for i in array_lower(const_drop_queries, 1) .. array_upper(const_drop_queries, 1) loop
			raise notice 'PROCEDURE			drop % ', const_drop_queries[i];
			EXECUTE const_drop_queries[i];
		end loop;
	end if;

	raise notice 'PROCEDURE		changing id column to uuid for %', p_table_name;
	-- add old id and switch to uuid on primary table
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %s ADD COLUMN old_id integer null;', p_table_name);
	EXECUTE FORMAT('UPDATE %s SET old_id = id;', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s DROP CONSTRAINT %1$s_pkey;', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN id DROP DEFAULT;', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN id DROP NOT NULL;', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN id TYPE uuid USING (uuid_generate_v4());', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN id SET DEFAULT uuid_generate_v4();', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ALTER COLUMN id SET NOT NULL;', p_table_name);
	EXECUTE FORMAT('ALTER TABLE IF EXISTS %1$s ADD PRIMARY KEY (id);', p_table_name);
	COMMIT;
	
	-- recreate constraints
	if array_length(const_create_queries, 1) > 0 then
		raise notice 'PROCEDURE		recreate constraints for %', p_table_name;
		for i in array_lower(const_create_queries, 1) .. array_upper(const_create_queries, 1) loop
			raise notice 'PROCEDURE			create % ', const_create_queries[i];
			EXECUTE const_create_queries[i];
			COMMIT;
		end loop;
	end if;
end;
$BODY$;
COMMIT;
----------------------
-- SQL to check all tables for column name 'id' on position 1 
-- RUN THIS SEPARATELY AFTER FUNCTION AND PROCEDURE IS CREATED
-----------------------
do 
$$
declare 
	tn character varying;
	id_field RECORD;
	rel_name character varying;
begin

	for tn in SELECT table_name FROM information_schema.tables WHERE table_type='BASE TABLE' AND table_schema='public' LOOP
		raise notice 'MAIN QUERY	current table %', tn;
		SELECT *
		FROM information_schema.columns 
		INTO id_field
		WHERE
		table_name = tn AND ordinal_position = 1 AND column_name = 'id'
		order by ordinal_position;
		
		if id_field.data_type = 'integer' then
			raise notice 'MAIN QUERY	id field is integer .. run conversion. current connections are';		
			CALL convertIntIDtoUUID(tn);
		end if;	
		
	end loop;

end;
$$;
