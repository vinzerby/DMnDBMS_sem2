
--Create tables
	CREATE TABLE STUDENTS (ID NUMBER PRIMARY KEY, NAME VARCHAR2(256) NOT NULL, GROUP_ID NUMBER NOT NULL);

	CREATE TABLE GROUPS(ID NUMBER PRIMARY KEY, NAME VARCHAR2(64) NOT NULL, C_VAL NUMBER NOT NULL);
	
	CREATE TABLE TEMP_STUDENTS_TO_CASCADE_DELETE (GROUP_ID NUMBER NOT NULL);
	
	CREATE INDEX IDX_STUDENTS_GROUP_ID ON STUDENTS(GROUP_ID);

--Create triggers for autoincrementing unique ids
	CREATE SEQUENCE STUDENTS_ID_SEQ
	START WITH 1
	INCREMENT BY 1
	NOCACHE;

	CREATE SEQUENCE GROUPS_ID_SEQ
	START WITH 1
	INCREMENT BY 1
	NOCACHE;
	
	
-- TODO:
-- I. 	Allow to change c_val only via triggers and block changing with regular query by using
--		packages. Packages may give permissions for triggers to update c_val
--
-- II.	Update c_vals at AFTER STATEMENT block. To do this info about updated groups need to be collected.
--		Is it possible to update all GROUPS with one query? Will it even be faster?
--
	
	
--This triggers must provide following features:
--1. Using sequence for providing unique value when id of a new record is not given,
--   iterate through sequence while not find unique id
--2. Check the uniqueness of the id when given on both insert and update operations
--3. Check the uniqueness of the GROUPS.NAME on both insert and update operations
--4. Control if value given to STUDENTS.GROUP_ID exists in GROUPS.ID on insert and update
	
	
	
	-- Trigger for inserting have to be compound due to mutation table error
	-- when checking for existing record with same id and name as :NEW.id or :NEW.name
	
	-- Checks for parent group existing, guarantee uniqueness of id and name, and updates c_val of parent group
	CREATE OR REPLACE TRIGGER STUDENTS_COMPOUND_INSERT
	FOR INSERT ON STUDENTS
	COMPOUND TRIGGER
		NEW_ID			NUMBER := 0;
	
		TYPE IDs_t		IS TABLE OF STUDENTS.ID%TYPE;
		Student_IDs		IDs_t;
		Group_IDs		IDs_t;
		
		TYPE Names_t	IS TABLE OF STUDENTS.NAME%TYPE;
		Student_names	Names_t;
		
		BEFORE STATEMENT IS
		BEGIN
			SELECT ID BULK COLLECT INTO Student_IDs FROM STUDENTS;
			SELECT ID BULK COLLECT INTO Group_IDs FROM GROUPS;
			SELECT NAME BULK COLLECT INTO Student_names FROM STUDENTS;
		END BEFORE STATEMENT;
		
		BEFORE EACH ROW IS
		BEGIN
			-- Check foreign key group exists
			IF (:NEW.GROUP_ID NOT MEMBER OF Group_IDs) THEN
				RAISE_APPLICATION_ERROR(-20001, 'Соответствующей записи ' || :NEW.GROUP_ID || ' в таблице GROUPS не существует');
			END IF; 
			
			IF (:NEW.NAME MEMBER OF Student_names) THEN
	 				RAISE_APPLICATION_ERROR(-20105, 'Студент с именем ' || :NEW.NAME || ' уже существует');
				END IF; 
			
			-- Generate unique id
			IF :NEW.ID IS NULL THEN
				LOOP
					SELECT STUDENTS_ID_SEQ.NEXTVAL INTO NEW_ID FROM DUAL;
					EXIT WHEN (NEW_ID NOT MEMBER OF Student_IDs);
				END LOOP;
				:NEW.ID := NEW_ID;
			-- Check given id for uniqueness
			ELSE
				IF (:NEW.ID MEMBER OF Student_IDs) THEN
					RAISE_APPLICATION_ERROR(-20002, 'Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
				END IF;
			END IF;
			
		END BEFORE EACH ROW;
		
		AFTER EACH ROW IS
		BEGIN
			-- Update c_val of parent group
			UPDATE GROUPS SET C_VAL = C_VAL + 1 WHERE GROUPS.ID = :NEW.GROUP_ID;
		END AFTER EACH ROW;
		
	END STUDENTS_COMPOUND_INSERT;
	
	
	CREATE OR REPLACE TRIGGER STUDENTS_BEFORE_INSERT
	BEFORE INSERT ON STUDENTS
	FOR EACH ROW
	DECLARE
	    pragma autonomous_transaction;

		NEW_ID NUMBER;
		NEW_ID_IN_TABLE_COUNT NUMBER := 9999;
		GROUPS_WITH_GIVEN_ID NUMBER := 0;	
	
		GROUP_ID_NOT_EXISTS EXCEPTION;
		NOT_UNIQUE_ID EXCEPTION;
	BEGIN
		--Foreign key consistency
		SELECT COUNT(1) INTO GROUPS_WITH_GIVEN_ID FROM GROUPS WHERE GROUPS.ID = :NEW.GROUP_ID;
		IF GROUPS_WITH_GIVEN_ID < 1 THEN
			RAISE GROUP_ID_NOT_EXISTS;
		END IF;
		
		--User can forcefully update record with new ID, in this case it's needed to check
		--Value for sequence for uniqueness
		IF :NEW.ID  IS NULL THEN
			WHILE NEW_ID_IN_TABLE_COUNT > 0
			LOOP
				SELECT STUDENTS_ID_SEQ.NEXTVAL INTO NEW_ID FROM dual;
				SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM STUDENTS WHERE STUDENTS.ID = NEW_ID;
			END LOOP;	
			:NEW.ID := NEW_ID;
				
		--Id is given
		ELSE
			SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM STUDENTS WHERE STUDENTS.ID = :NEW.ID;
			IF NEW_ID_IN_TABLE_COUNT > 0 THEN 
				RAISE NOT_UNIQUE_ID;
			END IF;
		
		END IF;
		
	EXCEPTION
		WHEN GROUP_ID_NOT_EXISTS THEN
 			DBMS_OUTPUT.PUT_LINE('Соответствующей записи ' || :NEW.GROUP_ID || ' в таблице GROUPS не существует');
			RAISE_APPLICATION_ERROR(-20001, 'Соответствующей записи ' || :NEW.GROUP_ID || ' в таблице GROUPS не существует');
		WHEN NOT_UNIQUE_ID THEN
 			DBMS_OUTPUT.PUT_LINE('Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
			RAISE_APPLICATION_ERROR(-20002, 'Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
	END;
	
	CREATE OR REPLACE TRIGGER STUDENTS_BEFORE_UPDATE
	BEFORE UPDATE ON STUDENTS
	FOR EACH ROW 
	DECLARE
		GROUPS_WITH_GIVEN_ID NUMBER := 0;
		NEW_ID_IN_TABLE_COUNT NUMBER := 0;

		GROUP_ID_NOT_EXISTS EXCEPTION;
		NOT_UNIQUE_ID EXCEPTION;
	BEGIN 
		IF :NEW.GROUP_ID != :OLD.GROUP_ID THEN 
			SELECT COUNT(1) INTO GROUPS_WITH_GIVEN_ID FROM GROUPS WHERE GROUPS.ID = :NEW.GROUP_ID;
			IF GROUPS_WITH_GIVEN_ID < 1 THEN
				RAISE GROUP_ID_NOT_EXISTS;
			END IF;
		END IF;
		
		IF :NEW.ID != :OLD.ID THEN
			SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM STUDENTS WHERE STUDENTS.ID = :NEW.ID;
			IF NEW_ID_IN_TABLE_COUNT > 0 THEN 
				RAISE NOT_UNIQUE_ID;
			END IF;
		END IF;
	EXCEPTION
		WHEN GROUP_ID_NOT_EXISTS THEN
 			DBMS_OUTPUT.PUT_LINE('Соответствующей записи ' || :NEW.GROUP_ID || 'в таблице GROUPS не существует');
 			RAISE_APPLICATION_ERROR(-20003, 'Соответствующей записи ' || :NEW.GROUP_ID || 'в таблице GROUPS не существует');		
		WHEN NOT_UNIQUE_ID THEN
 			DBMS_OUTPUT.PUT_LINE('Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
			RAISE_APPLICATION_ERROR(-20004, 'Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
	END;
	
	CREATE OR REPLACE TRIGGER STUDENTS_AFTER_INSERT
	AFTER UPDATE ON STUDENTS
	FOR EACH ROW
	BEGIN 
		UPDATE GROUPS SET C_VAL = C_VAL + 1 WHERE ID = :NEW.GROUP_ID;
	END;
	
	CREATE OR REPLACE TRIGGER STUDENTS_AFTER_UPDATE
	AFTER UPDATE ON STUDENTS
	FOR EACH ROW 	
	BEGIN 
		IF :OLD.GROUP_ID != :NEW.GROUP_ID THEN 
			UPDATE GROUPS SET C_VAL = C_VAL - 1 WHERE ID = :OLD.GROUP_ID;
			UPDATE GROUPS SET C_VAL = C_VAL + 1 WHERE ID = :NEW.GROUP_ID;
		END IF;
	END;
	
	CREATE OR REPLACE TRIGGER STUDENTS_AFTER_DELETE
	AFTER DELETE ON STUDENTS
	FOR EACH ROW
	DECLARE
		PRAGMA AUTONOMOUS_TRANSACTION;
	BEGIN 
		UPDATE GROUPS SET C_VAL = C_VAL - 1 WHERE ID = :OLD.GROUP_ID;
	END;
	
	
	
	
-- Triggers for GROUPS
	
	-- Trigger for inserting have to be compound due to mutation table error
	-- when checking for existing record with same id and name as :NEW.id or :NEW.name
	CREATE OR REPLACE TRIGGER GROUPS_COMPOUND_INSERT
	FOR INSERT ON GROUPS
	COMPOUND TRIGGER
		NEW_ID			NUMBER := 0;
	
		TYPE Names_t	IS TABLE OF GROUPS.NAME%TYPE;
		Group_names		Names_t;
		
		TYPE IDs_t		IS TABLE OF GROUPS.ID%TYPE;
		Group_IDs		IDs_t;
	
		BEFORE STATEMENT IS
		BEGIN
			SELECT NAME, ID BULK COLLECT INTO Group_names, Group_IDs FROM GROUPS;
		END BEFORE STATEMENT;
		
		BEFORE EACH ROW IS
		BEGIN
			-- Set C_VAL to 0
			IF :NEW.C_VAL != 0 THEN
				DBMS_OUTPUT.PUT_LINE('Параметр ' || :NEW.C_VAL || ' принудительно установлен в значение 0');
			END IF;
			:NEW.C_VAL := 0;
		
			-- Check unique name
			IF (:NEW.NAME MEMBER OF Group_names) THEN
 				RAISE_APPLICATION_ERROR(-20005, 'Группа с именем ' || :NEW.NAME || ' уже существует');
			END IF; 
			
			-- Generate unique id
			IF :NEW.ID IS NULL THEN
				LOOP
					SELECT GROUPS_ID_SEQ.NEXTVAL INTO NEW_ID FROM DUAL;
					EXIT WHEN (NEW_ID NOT MEMBER OF Group_IDs);
				END LOOP;
				:NEW.ID := NEW_ID;
			-- Check given id for uniqueness
			ELSE
				IF (:NEW.ID MEMBER OF Group_IDs) THEN
					RAISE_APPLICATION_ERROR(-20006, 'Группа с ID= ' || :NEW.ID || ' уже существует');
				END IF;
			END IF;
			
		END BEFORE EACH ROW;
		
	END GROUPS_COMPOUND_INSERT;
	
	
	
	
	CREATE OR REPLACE TRIGGER GROUPS_BEFORE_INSERT
	BEFORE INSERT ON GROUPS
	FOR EACH ROW 
	DECLARE 
	    pragma autonomous_transaction;
	
		GROUPS_WITH_NEW_NAME_COUNT NUMBER := 0;
		NEW_ID NUMBER := 0;
		NEW_ID_IN_TABLE_COUNT NUMBER := 0;
	
		NOT_UNIQUE_GROUP_NAME EXCEPTION;
		NOT_UNIQUE_ID EXCEPTION;
	BEGIN 
		IF :NEW.C_VAL != 0 THEN
 			DBMS_OUTPUT.PUT_LINE('Параметр ' || :NEW.C_VAL || ' принудительно установлен в значение 0');
		END IF;
		:NEW.C_VAL := 0;
		
		SELECT COUNT(1) INTO GROUPS_WITH_NEW_NAME_COUNT FROM GROUPS WHERE NAME = :NEW.NAME;
		IF GROUPS_WITH_NEW_NAME_COUNT > 0 THEN
			RAISE NOT_UNIQUE_GROUP_NAME;
		END IF;
		
		IF :NEW.ID IS NULL THEN
			LOOP
				SELECT GROUPS_ID_SEQ.NEXTVAL INTO NEW_ID FROM DUAL;
				SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM GROUPS WHERE ID = NEW_ID;
				EXIT WHEN NEW_ID_IN_TABLE_COUNT = 0;
			END LOOP;
			:NEW.ID := NEW_ID;
		ELSE
			SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM GROUPS WHERE ID = :NEW.ID;
			IF NEW_ID_IN_TABLE_COUNT > 0 THEN
				RAISE NOT_UNIQUE_ID;
			END IF;
		END IF;
		
	EXCEPTION
		WHEN NOT_UNIQUE_GROUP_NAME THEN
 			DBMS_OUTPUT.PUT_LINE('Группа с именем ' || :NEW.NAME || ' уже существует');
 			RAISE_APPLICATION_ERROR(-20005, 'Группа с именем ' || :NEW.NAME || ' уже существует');
		WHEN NOT_UNIQUE_ID THEN
 			DBMS_OUTPUT.PUT_LINE('Группа с ID= ' || :NEW.ID || ' уже существует');
			RAISE_APPLICATION_ERROR(-20006, 'Группа с ID= ' || :NEW.ID || ' уже существует');
	END;
	
	--Update all connected records in students
	--C_VAL is setted as amount of students by trigger and can't be changed by update
	CREATE OR REPLACE TRIGGER GROUPS_BEFORE_UPDATE
	BEFORE UPDATE ON GROUPS
	FOR EACH ROW 
	DECLARE 
		pragma autonomous_transaction;
	
		GROUPS_WITH_NEW_NAME_COUNT NUMBER := 0;
		NEW_ID_IN_TABLE_COUNT NUMBER := 0;
		
		C_VAL_IS_CHANGED EXCEPTION;
		NOT_UNIQUE_GROUP_NAME EXCEPTION;
		NOT_UNIQUE_ID EXCEPTION;
	BEGIN
		IF :NEW.C_VAL != :OLD.C_VAL THEN
			RAISE C_VAL_IS_CHANGED;
		END IF;
	
		IF :NEW.NAME != :OLD.NAME THEN 
			SELECT COUNT(1) INTO GROUPS_WITH_NEW_NAME_COUNT FROM GROUPS WHERE NAME = :NEW.NAME;
			IF GROUPS_WITH_NEW_NAME_COUNT > 0 THEN
				RAISE NOT_UNIQUE_GROUP_NAME;
			END IF;
		END IF;
	
		IF :NEW.ID != :OLD.ID THEN
			SELECT COUNT(1) INTO NEW_ID_IN_TABLE_COUNT FROM GROUPS WHERE ID = :NEW.ID;
			IF NEW_ID_IN_TABLE_COUNT > 0 THEN
				RAISE NOT_UNIQUE_ID;
			END IF;
		END IF;
		
	EXCEPTION
		WHEN C_VAL_IS_CHANGED THEN
 			DBMS_OUTPUT.PUT_LINE('Параметр C_VAL не может быть изменён вручную');
 			RAISE_APPLICATION_ERROR(-20007, 'C_VAL cant be changed manually');
		WHEN NOT_UNIQUE_GROUP_NAME THEN
 			DBMS_OUTPUT.PUT_LINE('Группа с именем ' || :NEW.NAME || ' уже существует');
 			RAISE_APPLICATION_ERROR(-20008, 'GROUPS record with NAME=' || :NEW.NAME || ' already exists');
		WHEN NOT_UNIQUE_ID THEN
 			DBMS_OUTPUT.PUT_LINE('Группа с ID= ' || :NEW.ID || ' уже существует');
 			RAISE_APPLICATION_ERROR(-20009, 'GROUPS record with ID=' || :NEW.ID || ' already exists');
	END;
		
	
	--STUDENTS must be updated AFTER GROUPS, because this will invoke UPDATE ON STUDENTS trigger, which
	--updates GROUPS records with GROUPS.ID = (:NEW) STUDENTS.GROUP_ID.
	--If STUDENTS updated BEFORE GROUPS, it would cause error, bacause GROUPS.ID did not updated yet
	
	--Also C_VAL must be setted to 0 here, bacause cascading call of after update on student
	--trigges for all connected STUDENTS records will write sum correct C_VAL to 0
	CREATE OR REPLACE TRIGGER GROUPS_AFTER_UPDATE
	AFTER UPDATE ON GROUPS
	FOR EACH ROW
	BEGIN 
		--C_VAL value will be correctly setted by invoked AFTER UPDATE ON STUDENTS triggers
		:NEW.C_VAL := 0;
		--New ID is unique, update connected students
		UPDATE STUDENTS SET GROUP_ID = :NEW.ID WHERE GROUP_ID = :OLD.ID;
	END;
	
	
	
	CREATE OR REPLACE TRIGGER GROUPS_BEFORE_DELETE
	BEFORE DELETE ON GROUPS
	FOR EACH ROW 
	BEGIN 
		INSERT INTO TEMP_STUDENTS_TO_CASCADE_DELETE (GROUP_ID)
		VALUES
		(:OLD.ID); 
	END;
	
	CREATE OR REPLACE TRIGGER GROUPS_AFTER_DELETE
	AFTER DELETE ON GROUPS
	DECLARE
		PRAGMA AUTONOMOUS_TRANSACTION;
	BEGIN
		PROC_CASCADE_DELETE_STUDENTS();
	END;
	
	CREATE OR REPLACE PROCEDURE PROC_CASCADE_DELETE_STUDENTS 
	IS
		pragma autonomous_transaction;
	BEGIN
		FOR REC IN (SELECT GROUP_ID FROM TEMP_STUDENTS_TO_CASCADE_DELETE) LOOP
			DELETE FROM STUDENTS WHERE GROUP_ID = REC.GROUP_ID;
		END LOOP;
		DELETE FROM TEMP_STUDENTS_TO_CASCADE_DELETE;
	END;
	
	
	
	CREATE OR REPLACE TRIGGER GROUPS_UPDATE_CASCADE
	FOR UPDATE OF ID ON GROUPS
	COMPOUND TRIGGER
	    TYPE t_group_map IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
	    v_old_ids t_group_map;
	    v_new_ids t_group_map;
	
	    -- Инициализация коллекций перед выполнением оператора
	    BEFORE STATEMENT IS
	    BEGIN
	        v_old_ids.DELETE();
	        v_new_ids.DELETE();
	    END BEFORE STATEMENT;
	
	    BEFORE EACH ROW IS
	    BEGIN
	        -- Сохраняем данные с использованием последовательных индексов
	        v_old_ids(v_old_ids.COUNT + 1) := :OLD.ID;
	        v_new_ids(v_new_ids.COUNT + 1) := :NEW.ID;
	    END BEFORE EACH ROW;
	
	    AFTER STATEMENT IS
	    BEGIN 
	        FOR i IN 1..v_old_ids.COUNT LOOP
	            -- Обновляем студентов
	            UPDATE STUDENTS
	            SET GROUP_ID = v_new_ids(i)
	            WHERE GROUP_ID = v_old_ids(i);
	
	            -- Обновляем счетчик C_VAL
	            UPDATE GROUPS
	            SET C_VAL = (
	                SELECT COUNT(*) 
	                FROM STUDENTS 
	                WHERE GROUP_ID = v_new_ids(i)
	            )
	            WHERE ID = v_new_ids(i);
	        END LOOP;
	    END AFTER STATEMENT;
	END;
	
	            
-- 


	            
DROP TRIGGER GROUPS_BEFORE_INSERT;
DROP TRIGGER STUDENTS_BEFORE_INSERT;
DROP TRIGGER GROUPS_UPDATE_CASCADE;

DROP TRIGGER GROUPS_BEFORE_UPDATE;
DROP TRIGGER GROUPS_AFTER_UPDATE;

-- Check objects are created correctly
SELECT OBJECT_TYPE, OBJECT_NAME, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN ('STUDENTS', 'GROUPS', 'IDX_STUDENTS_GROUP_ID',
'STUDENTS_ID_SEQ', 'GROUPS_ID_SEQ', 'STUDENTS_BEFORE_INSERT', 
'STUDENTS_BEFORE_UPDATE', 'STUDENTS_AFTER_INSERT',
'STUDENTS_AFTER_UPDATE', 'STUDENTS_AFTER_DELETE',
'GROUPS_BEFORE_INSERT', 'GROUPS_BEFORE_UPDATE', 'GROUPS_AFTER_UPDATE',
'GROUPS_BEFORE_DELETE', 'GROUPS_AFTER_DELETE', 'PROC_CASCADE_DELETE_STUDENTS',
'GROUPS_UPDATE_CASCADE',
'GROUPS_COMPOUND_INSERT', 'STUDENTS_COMPOUND_INSERT')
AND OBJECT_TYPE IN ('TABLE', 'SEQUENCE', 'TRIGGER', 'PROCEDURE', 'INDEX')
ORDER BY OBJECT_TYPE, OBJECT_NAME;
	
	
