CREATE OR REPLACE PROCEDURE insert_val(val NUMBER)
IS
BEGIN
	INSERT INTO MyTable(val) VALUES (val);
END insert_val;

CREATE OR REPLACE PROCEDURE update_on_id(id NUMBER, val NUMBER)
IS
BEGIN
	UPDATE MyTable 
	SET MyTable.val = update_on_id.val
	WHERE MyTable.id = update_on_id.id;
END update_on_id;

CREATE OR REPLACE PROCEDURE double_all_even_vals
IS
BEGIN
	UPDATE MyTable
	SET MyTable.val = MyTable.val * 2
	WHERE BITAND(MyTable.val, 1) = 0;
END double_all_even_vals;

CREATE OR REPLACE PROCEDURE delete_val(val NUMBER)
IS 
BEGIN 
	DELETE FROM MyTable
	WHERE MyTable.val = delete_val.val;
END delete_val;

CREATE OR REPLACE PROCEDURE delete_all
IS 
BEGIN 
	DELETE FROM MyTable;
END delete_all;


SELECT OBJECT_NAME, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME = 'DELETE_ALL'
AND OBJECT_TYPE = 'PROCEDURE';
