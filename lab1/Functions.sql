--Create function for checking which type of 
--numbers - odd of even table has
	CREATE OR REPLACE FUNCTION check_parity RETURN NUMBER 
	IS
	    odd_count  NUMBER := 0;
	    even_count NUMBER := 0;
	BEGIN
	    SELECT COUNT(CASE WHEN BITAND(val, 1) = 1 THEN 1 END),
	           COUNT(CASE WHEN BITAND(val, 1) = 0 THEN 1 END)
	    INTO odd_count, even_count
	    FROM MyTable;
	
	    IF odd_count > even_count THEN
	        RETURN 1;
	    ELSIF odd_count < even_count THEN
	        RETURN 2;
	    ELSE
	        RETURN 3;
	    END IF;
	END check_parity;
	
	SELECT OBJECT_NAME, STATUS
	FROM USER_OBJECTS
	WHERE OBJECT_NAME = 'CHECK_PARITY'
	AND OBJECT_TYPE = 'FUNCTION';
	
	DECLARE
		func_result NUMBER := check_parity();
	BEGIN
		IF func_result = 1 THEN
			DBMS_OUTPUT.PUT_LINE('В таблице больше нечётных чисел');
		ELSIF func_result = 2 THEN
			DBMS_OUTPUT.PUT_LINE('В таблице больше чётных чисел');
		ELSIF func_result = 3 THEN
			DBMS_OUTPUT.PUT_LINE('В таблице равное количество чётных и нечётных чисел');
		END IF;
	END;
	
	
--Function for salary evaluation
	CREATE OR REPLACE FUNCTION salary_eval(wage REAL, bonus NUMBER)
	RETURN REAL IS 
		bonus_real REAL := 0;
		year_salary REAL:= 0;

		wage_is_null   EXCEPTION;
		bonus_is_null  EXCEPTION;
		negative_wage  EXCEPTION;
		negative_bonus EXCEPTION;
	BEGIN
		IF wage IS NULL THEN
			RAISE wage_is_null;
		ELSIF bonus IS NULL THEN
			RAISE bonus_is_null;
		ELSIF wage < 0 THEN
			RAISE negative_wage;
		ELSIF bonus < 0 THEN
			RAISE negative_bonus;
		ELSE
			bonus_real := bonus / 100;
			year_salary := (1 + bonus_real) * 12 * wage;
			RETURN year_salary;
		END IF;
	EXCEPTION
		WHEN wage_is_null THEN
			DBMS_OUTPUT.PUT_LINE('Параметр wage должен быть числом, а не null');
			RETURN -1;
		WHEN bonus_is_null THEN
			DBMS_OUTPUT.PUT_LINE('Параметр bonus должен быть числом, а не null');
			RETURN -1;
		WHEN INVALID_NUMBER THEN
			DBMS_OUTPUT.PUT_LINE('Некорректный ввод, ожидается ввод чисел');
			RETURN -1;
		
		WHEN negative_wage THEN
			DBMS_OUTPUT.PUT_LINE('Зарплата не может быть отрицательной!');
			RETURN -1;
		WHEN negative_bonus THEN
			DBMS_OUTPUT.PUT_LINE('Поощрение не может быть отрицательным!');
			RETURN -1;
	END salary_eval;

	SELECT OBJECT_NAME, STATUS
	FROM USER_OBJECTS
	WHERE OBJECT_NAME = 'SALARY_EVAL'
	AND OBJECT_TYPE = 'FUNCTION';

	DECLARE
		func_result REAL := salary_eval(-1000, 20);
	BEGIN
		DBMS_OUTPUT.PUT_LINE('Вычисленная зарплата: ' || func_result);
	END;
	




















