# DatabaseQueries
This repository contains useful queries to address specific problems.
Queries may not be optimal but they are all tested and working. 


## PostgresIDConversion
This query group creates a function and a procedure in postgres database (public schema) to dynamically replace integer ID fields with UUID fields without dataloss.
* Updates ALL tables with integer "id" column in position 1.
* All foreign keys are dropped and re-created with new IDs. 
* Requires full DB drop & recreate in case a roll back is needed (for testing ie.).

```const_create_queries = array_append(const_create_queries, remove_old_fk_q);``` 
line manages the drop of temp old id fields. Comment / Uncomment to check if conversion is correct.
