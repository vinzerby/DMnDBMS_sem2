-- Create flags
	CREATE OR REPLACE PACKAGE FLAGS AS
		-- Is setted when students group_id cascade changed therefore c_val is not updated
		IS_GROUPS_ID_UPDATED BOOLEAN := FALSE;
		
		-- Is setted when student's group is changed and c_val is updated
		IS_STUDENTS_GROUPID_UPDATED BOOLEAN := FALSE;
		
		-- Is setted when group is deleted therefore connected students need to be deleted too
		IS_GROUPS_DELETED BOOLEAN := FALSE;
		
		-- Is setted when student is deleted and parent's c_val need to be decremented
		IS_STUDENTS_DELETED BOOLEAN := FALSE;
		
		-- Is setted when tables are restored by log
		IS_RESTORING_TABLES_BY_LOG BOOLEAN := FALSE;
		
		-- Indicates that DB is in history mode, created by jumping to timestamp log. Blocks new jumpings
		IS_JUMPED_TO_TIMESTAMP BOOLEAN := FALSE;
		
		JUMPED_TIMESTAMP TIMESTAMP;
	END FLAGS;
	
	
-- Create tables
	CREATE TABLE STUDENTS (ID NUMBER PRIMARY KEY, NAME VARCHAR2(256) NOT NULL, GROUP_ID NUMBER NOT NULL);

	CREATE TABLE GROUPS(ID NUMBER PRIMARY KEY, NAME VARCHAR2(64) NOT NULL, C_VAL NUMBER NOT NULL);
	
	-- Delete it. wont be used in the future
	CREATE TABLE TEMP_STUDENTS_TO_CASCADE_DELETE (GROUP_ID NUMBER NOT NULL);
	
	CREATE INDEX IDX_STUDENTS_GROUP_ID ON STUDENTS(GROUP_ID);

	
-- Create triggers for autoincrementing unique ids
	CREATE SEQUENCE STUDENTS_ID_SEQ
	START WITH 1
	INCREMENT BY 1
	NOCACHE;

	CREATE SEQUENCE GROUPS_ID_SEQ
	START WITH 1
	INCREMENT BY 1
	NOCACHE;
	
	
-- TODO:
--
-- I.	Update c_vals at AFTER STATEMENT block. To do this info about updated groups need to be collected.
--		Is it possible to update all GROUPS with one query? Will it even be faster?
--
-- II.	Add trigger to check if c_val is changed. Students table's triggers should set flag C_VAL_UPDATED
--		and groups table's triggers should block any update on c_val if this flag is not set (c_val is changed
--		by user if this flag is not set which is forbidden)
--
	
	
--This triggers must provide following features:
--1. Using sequence for providing unique value when id of a new record is not given,
--   iterate through sequence while not find unique id
--2. Check the uniqueness of the id when given on both insert and update operations
--3. Check the uniqueness of the GROUPS.NAME on both insert and update operations
--4. Control if value given to STUDENTS.GROUP_ID exists in GROUPS.ID on insert and update
	

	
-- About logging:
-- 1. c_val can't be changed manually therefore all changes to c_val is not logged
	
	
	
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
			FLAGS.IS_STUDENTS_GROUPID_UPDATED := TRUE;
			
			SELECT ID BULK COLLECT INTO Student_IDs FROM STUDENTS;
			SELECT ID BULK COLLECT INTO Group_IDs FROM GROUPS;
			SELECT NAME BULK COLLECT INTO Student_names FROM STUDENTS;
		END BEFORE STATEMENT;
		
		BEFORE EACH ROW IS
		BEGIN
			-- Check foreign key group exists
			IF (:NEW.GROUP_ID NOT MEMBER OF Group_IDs) THEN
				FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
				RAISE_APPLICATION_ERROR(-20001, 'Соответствующей записи ' || :NEW.GROUP_ID || ' в таблице GROUPS не существует');
			END IF; 
			
			IF (:NEW.NAME MEMBER OF Student_names) THEN
				FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
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
					FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
					RAISE_APPLICATION_ERROR(-20002, 'Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
				END IF;
			END IF;
			
		END BEFORE EACH ROW;
		
		AFTER EACH ROW IS
		BEGIN
			-- Update c_val of parent group
			UPDATE GROUPS SET C_VAL = C_VAL + 1 WHERE GROUPS.ID = :NEW.GROUP_ID;
		
			-- Log insertion to STUDENTS if not restoring table condition by logs
			IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
				INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
				VALUES('STUDENTS', 'INSERT', NULL, :NEW.ID, NULL, :NEW.NAME, NULL, :NEW.GROUP_ID);
			END IF;
			
		END AFTER EACH ROW;
		
		AFTER STATEMENT IS
		BEGIN
			FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
		END AFTER STATEMENT;
		
	END STUDENTS_COMPOUND_INSERT;
		
	
	
	-- Checks uniqueness of id and name, existence of parent group and updates parent group c_val
	CREATE OR REPLACE TRIGGER STUDENTS_COMPOUND_UPDATE
	FOR UPDATE ON STUDENTS
	COMPOUND TRIGGER
		NEW_ID			NUMBER := 0;
	
		TYPE IDs_t		IS TABLE OF STUDENTS.ID%TYPE;
		Student_IDs		IDs_t;
		Group_IDs		IDs_t;
		
		TYPE Names_t	IS TABLE OF STUDENTS.NAME%TYPE;
		Student_names	Names_t;
		
		BEFORE STATEMENT IS
		BEGIN
			-- If this trigger is caused by UPDATE STUDENTS query for GROUPS trigger, only group_id value
			-- is changed and there is no need to check group_id for correctness
			IF NOT FLAGS.IS_GROUPS_ID_UPDATED THEN
				IF UPDATING('ID') THEN
					SELECT ID BULK COLLECT INTO Student_IDs FROM STUDENTS;
				END IF;
				IF UPDATING('NAME') THEN
					SELECT NAME BULK COLLECT INTO Student_names FROM STUDENTS;
				END IF;
				IF UPDATING('GROUP_ID') THEN
					-- Used to show FOR UPDATE ON GROUPS trigger that C_VAL need to be updated
					FLAGS.IS_STUDENTS_GROUPID_UPDATED := TRUE;
			
					SELECT ID BULK COLLECT INTO Group_IDs FROM GROUPS;
				END IF;
			END IF;
		END BEFORE STATEMENT;
		
		BEFORE EACH ROW IS
		BEGIN
			-- Check unique name
			IF (UPDATING('NAME') AND :NEW.NAME != :OLD.NAME) THEN
				IF (:NEW.NAME MEMBER OF Student_names) THEN
					FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
	 				RAISE_APPLICATION_ERROR(-20105, 'Студент с именем ' || :NEW.NAME || ' уже существует');
				END IF; 
			END IF;
		
			-- Check unique id
			IF (UPDATING('ID') AND :NEW.ID != :OLD.ID) THEN
				IF (:NEW.ID MEMBER OF Student_IDs) THEN
					FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
					RAISE_APPLICATION_ERROR(-20002, 'Первичный ключ ID= ' || :NEW.ID || ' не является уникальным');
				END IF;
			END IF;
		
			IF (UPDATING('GROUP_ID') AND :NEW.GROUP_ID != :OLD.GROUP_ID) THEN
				-- This check is needed only when group_id changed by user (when student is transfered to another group),
				-- unless group_id changed by FOR UPDATE OF GROUPS trigger and no need for check
				IF NOT FLAGS.IS_GROUPS_ID_UPDATED THEN
					IF (:NEW.GROUP_ID NOT MEMBER OF Group_IDs) THEN
						FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
						RAISE_APPLICATION_ERROR(-20001, 'Соответствующей записи ' || :NEW.GROUP_ID || ' в таблице GROUPS не существует');
					END IF;
				END IF;
			END IF;
		END BEFORE EACH ROW;
		
		AFTER EACH ROW IS
		BEGIN
			IF (UPDATING('GROUP_ID') AND :NEW.GROUP_ID != :OLD.GROUP_ID) THEN
				-- update c_val if group_id is changed via moving student for one group to another
				IF NOT FLAGS.IS_GROUPS_ID_UPDATED THEN
					UPDATE GROUPS SET C_VAL = C_VAL-1 WHERE GROUPS.ID = :OLD.GROUP_ID;
					UPDATE GROUPS SET C_VAL = C_VAL+1 WHERE GROUPS.ID = :NEW.GROUP_ID;
				END IF;
			END IF;
		
			-- If STUDENTS table changed by user (and not cascading from changing parent group) and LOG is not restored
			IF NOT FLAGS.IS_GROUPS_ID_UPDATED THEN
				IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
					INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
					VALUES('STUDENTS', 'UPDATE', :OLD.ID, :NEW.ID, :OLD.NAME, :NEW.NAME, :OLD.GROUP_ID, :NEW.GROUP_ID);
				END IF;
			END IF;
			
		END AFTER EACH ROW;
				
		AFTER STATEMENT IS
		BEGIN
			IF UPDATING('GROUP_ID') THEN
				FLAGS.IS_STUDENTS_GROUPID_UPDATED := FALSE;
			END IF;
		END AFTER STATEMENT;
		
	END STUDENTS_COMPOUND_UPDATE;
	
	
	CREATE OR REPLACE TRIGGER STUDENTS_COMPOUND_DELETE
	FOR DELETE ON STUDENTS
	COMPOUND TRIGGER
		BEFORE STATEMENT IS
		BEGIN
			IF (NOT FLAGS.IS_GROUPS_DELETED) THEN
				FLAGS.IS_STUDENTS_DELETED := TRUE;
			END IF;
		END BEFORE STATEMENT;
	
		BEFORE EACH ROW IS
		BEGIN
			IF (NOT FLAGS.IS_GROUPS_DELETED) THEN
				UPDATE GROUPS SET C_VAL = C_VAL-1 WHERE GROUPS.ID = :OLD.GROUP_ID;
			END IF;
		END BEFORE EACH ROW;
		
		AFTER EACH ROW IS
		BEGIN
			-- Add to log if this action is not invoked by restoring table conditions via logs
			IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
				INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
				VALUES('STUDENTS', 'DELETE', :OLD.ID, NULL, :OLD.NAME, NULL, :OLD.GROUP_ID, NULL);
			END IF;
		END AFTER EACH ROW;
		
		AFTER STATEMENT IS
		BEGIN
			IF (NOT FLAGS.IS_GROUPS_DELETED) THEN
				FLAGS.IS_STUDENTS_DELETED := FALSE;
			END IF;
		
		END AFTER STATEMENT;
	
	END STUDENTS_COMPOUND_DELETE;
	
	
	
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
		
		AFTER EACH ROW IS
		BEGIN
			-- Log insertion to GROUPS if not restoring table condition by logs
			IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
				INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
				VALUES('GROUPS', 'INSERT', NULL, :NEW.ID, NULL, :NEW.NAME, NULL, :NEW.C_VAL);
			END IF;
		END AFTER EACH ROW;
		
	END GROUPS_COMPOUND_INSERT;
	
	
	
	-- Trigger blocks manual changing of C_VAL. C_VAL MODIFICATION IS PERMITTED ONLY FROM STUDENTS TRIGGERS
	CREATE OR REPLACE TRIGGER GROUPS_COMPOUND_UPDATE_CVAL
	FOR UPDATE OF C_VAL ON GROUPS
	COMPOUND TRIGGER
		BEFORE STATEMENT IS
		BEGIN
			DBMS_OUTPUT.PUT_LINE('Я внутри триггера GROUPS_COMPOUND_UPDATE_CVAL');
			IF (NOT (FLAGS.IS_STUDENTS_GROUPID_UPDATED OR FLAGS.IS_STUDENTS_DELETED)) THEN
				DBMS_OUTPUT.PUT_LINE('Я вызываю исключение');
				-- If flag is not setted, c_val is changed by user which is forbidden.
				-- C_VAL can be changed only by STUDENTS trigger
				 RAISE_APPLICATION_ERROR(-20206, 'Manual changing of C_VAL is forbidden');
			END IF;
		END BEFORE STATEMENT;
	
	END GROUPS_COMPOUND_UPDATE_CVAL;
	
	
	CREATE OR REPLACE TRIGGER GROUPS_COMPOUND_UPDATE
	FOR UPDATE OF ID, NAME ON GROUPS
	COMPOUND TRIGGER
		NEW_ID			NUMBER := 0;
	
		TYPE Names_t	IS TABLE OF GROUPS.NAME%TYPE;
		Group_names		Names_t;
		
		TYPE IDs_t		IS TABLE OF GROUPS.ID%TYPE;
		Group_IDs		IDs_t;
		
		BEFORE STATEMENT IS
		BEGIN
			IF UPDATING('ID') THEN
				-- this flag is used in students on update triggers to check if it is 
				-- needed to update parent c_val when student's GROUP_ID is changed.
				-- this flag shows that change of student's GROUP_ID is caused by c
				-- hanging group's id therefore updating of c_val is not needed
				-- because no student was transfered to another group
				FLAGS.IS_GROUPS_ID_UPDATED := TRUE;
				
				SELECT ID BULK COLLECT INTO Group_IDs FROM GROUPS;
			END IF;
				
			IF UPDATING('NAME') THEN
				SELECT NAME BULK COLLECT INTO Group_names FROM GROUPS;
			END IF;
			
		END BEFORE STATEMENT;
		
		BEFORE EACH ROW IS
		BEGIN
			-- Check unique name
			IF (UPDATING('NAME') AND :NEW.NAME != :OLD.NAME) THEN
				IF (:NEW.NAME MEMBER OF Group_names) THEN
					FLAGS.IS_GROUPS_ID_UPDATED := FALSE;
	 				RAISE_APPLICATION_ERROR(-20005, 'Группа с именем ' || :NEW.NAME || ' уже существует');
				END IF; 
			END IF;
		
			-- Check unique id
			IF (UPDATING('ID') AND :NEW.ID != :OLD.ID) THEN
				IF (:NEW.ID MEMBER OF Group_IDs) THEN
					FLAGS.IS_GROUPS_ID_UPDATED := FALSE;
					RAISE_APPLICATION_ERROR(-20006, 'Группа с ID= ' || :NEW.ID || ' уже существует');
				END IF;
			END IF;
		END BEFORE EACH ROW;
			
		-- This may cause mutation error due to selecting for updating GROUPS table at STUDENTS trigger
		AFTER EACH ROW IS
		BEGIN
			IF (UPDATING('ID') AND :NEW.ID != :OLD.ID) THEN
				-- Update child students
				UPDATE STUDENTS SET GROUP_ID=:NEW.ID WHERE GROUP_ID=:OLD.ID;
			END IF;
		
			-- If GROUPS table changed by user (and not cascade changing from changing child students) and LOG is not restored
			IF NOT FLAGS.IS_STUDENTS_GROUPID_UPDATED THEN
				IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
					INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
					VALUES('GROUPS', 'UPDATE', :OLD.ID, :NEW.ID, :OLD.NAME, :NEW.NAME, :OLD.C_VAL, :NEW.C_VAL);
				END IF;
			END IF;
		END AFTER EACH ROW;
		
		AFTER STATEMENT IS
		BEGIN
			IF UPDATING('ID') THEN
				-- drop flag after updating child students
				FLAGS.IS_GROUPS_ID_UPDATED := FALSE;
			END IF;
		END AFTER STATEMENT;
		
	END GROUPS_COMPOUND_UPDATE;
	
	
	-- This trigger causes cascade deletion on child students. Before final deletion and logging of group, child students are deleted an logged
	CREATE OR REPLACE TRIGGER GROUPS_COMPOUND_DELETE
	FOR DELETE ON GROUPS
	COMPOUND TRIGGER
		BEFORE STATEMENT IS
		BEGIN
			IF (NOT FLAGS.IS_STUDENTS_DELETED) THEN
				FLAGS.IS_GROUPS_DELETED := TRUE;
			END IF;
		END BEFORE STATEMENT;
	
		BEFORE EACH ROW IS
		BEGIN
			IF (NOT FLAGS.IS_STUDENTS_DELETED) THEN
				DELETE FROM STUDENTS WHERE STUDENTS.GROUP_ID = :OLD.ID;
			END IF;
		END BEFORE EACH ROW;
		
		AFTER EACH ROW IS
		BEGIN
			-- Add to log if this action is not invoked by restoring table conditions via logs
			IF NOT FLAGS.IS_RESTORING_TABLES_BY_LOG THEN
				INSERT INTO LOGS (TABLE_NAME, OPERATION_TYPE, ID_OLD, ID_NEW, NAME_OLD, NAME_NEW, NUMB_FIELD_OLD, NUMB_FIELD_NEW)
				VALUES('GROUPS', 'DELETE', :OLD.ID, NULL, :OLD.NAME, NULL, NULL, NULL);
			END IF;
		END AFTER EACH ROW;
		
		AFTER STATEMENT IS
		BEGIN
			IF (NOT FLAGS.IS_STUDENTS_DELETED) THEN
				FLAGS.IS_GROUPS_DELETED := FALSE;
			END IF;
		END AFTER STATEMENT;
	
	END GROUPS_COMPOUND_DELETE;


	            
DROP TRIGGER GROUPS_BEFORE_INSERT;
DROP TRIGGER STUDENTS_BEFORE_INSERT;
DROP TRIGGER GROUPS_UPDATE_CASCADE;
DROP TRIGGER STUDENTS_AFTER_INSERT;

DROP TRIGGER STUDENTS_BEFORE_UPDATE;
DROP TRIGGER STUDENTS_AFTER_UPDATE;

DROP TRIGGER GROUPS_BEFORE_UPDATE;
DROP TRIGGER GROUPS_AFTER_UPDATE;

DROP TRIGGER STUDENTS_AFTER_DELETE;
DROP TRIGGER GROUPS_AFTER_DELETE;
DROP TRIGGER GROUPS_BEFORE_DELETE;

-- Check objects are created correctly
SELECT OBJECT_TYPE, OBJECT_NAME, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN ('STUDENTS', 'GROUPS', 'IDX_STUDENTS_GROUP_ID', 'FLAGS',
'STUDENTS_ID_SEQ', 'GROUPS_ID_SEQ', 'STUDENTS_BEFORE_INSERT', 
'STUDENTS_BEFORE_UPDATE', 'STUDENTS_AFTER_INSERT',
'STUDENTS_AFTER_UPDATE', 'STUDENTS_AFTER_DELETE',
'GROUPS_BEFORE_INSERT', 'GROUPS_BEFORE_UPDATE', 'GROUPS_AFTER_UPDATE',
'GROUPS_BEFORE_DELETE', 'GROUPS_AFTER_DELETE', 'PROC_CASCADE_DELETE_STUDENTS',
'GROUPS_UPDATE_CASCADE',
'GROUPS_COMPOUND_INSERT', 'STUDENTS_COMPOUND_INSERT', 'GROUPS_COMPOUND_UPDATE', 'GROUPS_COMPOUND_UPDATE_CVAL', 'STUDENTS_COMPOUND_UPDATE',
'STUDENTS_COMPOUND_DELETE', 'GROUPS_COMPOUND_DELETE')
AND OBJECT_TYPE IN ('TABLE', 'SEQUENCE', 'TRIGGER', 'PROCEDURE', 'INDEX', 'PACKAGE')
ORDER BY OBJECT_TYPE, OBJECT_NAME;

SELECT OBJECT_TYPE, OBJECT_NAME, STATUS FROM USER_OBJECTS
WHERE OBJECT_TYPE IN 'TRIGGER'
ORDER BY OBJECT_TYPE, OBJECT_NAME;
	
	