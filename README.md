# DatabaseQueries
This repository contains useful queries to address specific problems.


## PostgresIDConversion
This query group creates a function and a procedure in postgres database (public schema) to replace integer ID fields with UUID fields without dataloss.
All foreign keys are dropped and re-created with new IDs. 

const_create_queries = array_append(const_create_queries, remove_old_fk_q); 
line manages the drop of temp old id fields. Comment / Uncomment to check if conversion is correct.
