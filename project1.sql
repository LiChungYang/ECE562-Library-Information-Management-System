REM Li Chung Yang (Andy)

--TABLES

set serveroutput on;

CREATE table Books
(
    /*Column_name1 datatype NOT NULL,*/
    book_id number PRIMARY KEY,
    book_title varchar2(50),
    author_id number,
    year_of_publication number,
    edition number,
    status varchar2(20) CHECK (status IN ('charged', 'not charged'))
);

CREATE table Authors
(
    author_id number PRIMARY KEY,
    name varchar2(30)
);

CREATE table Borrower
(
    borrower_id number PRIMARY KEY,
    name varchar2(30),
    status varchar2(20) CHECK (status IN ('student', 'faculty'))
);

CREATE table Issue
(
    book_id number,
    borrower_id number,
    issue_date date,
    return_date date,
    /*link the keys*/
    FOREIGN KEY (book_id) REFERENCES Books(book_id),
    FOREIGN KEY (borrower_id) REFERENCES Borrower(borrower_id),
    PRIMARY KEY (book_id, borrower_id),
    CHECK (return_date IS NULL OR return_date >= issue_date)
);

CREATE OR REPLACE PACKAGE my_package IS
  unfulfilled_requests NUMBER := 0; -- Initialize the variable here
END my_package;
/

--FUNCTIONS

--This function issues a book to the requester
--if it is not already charged, otherwise the book is not issued.
--current_date = issue_date 
Create or replace FUNCTION fun_issue_book(borrower_id number, book_id2 number, current_date date)
    RETURN NUMBER IS
    book_status VARCHAR2(20);
BEGIN
    -- Get the status of the book
    SELECT status INTO book_status FROM Books WHERE book_id = book_id2;

    -- Check if the book is not charged
    IF book_status = 'not charged' THEN
        -- Insert a new record in the Issue table
        BEGIN
        INSERT INTO Issue (book_id, borrower_id, issue_date, return_date)
        VALUES (book_id2, borrower_id, current_date, NULL);
         exception
           when OTHERS then
             my_package.unfulfilled_requests := my_package.unfulfilled_requests + 1;
        END;

        UPDATE Books SET status = 'charged' WHERE book_id = book_id2;
        RETURN 1;
    ELSE
        my_package.unfulfilled_requests := my_package.unfulfilled_requests + 1;
        RETURN 0;
    END IF;
END fun_issue_book;
/

/*
If no edition of the requested book is currently available, the request is not served. The
function returns ‘1’ if the request is satisfied, otherwise it returns ‘0’*/
Create OR REPLACE FUNCTION fun_issue_anyedition(borrower_id number, book_title varchar2, author_name varchar2, current_date date)
    RETURN NUMBER IS
    book_id NUMBER;
BEGIN
    -- Find the latest available edition of the requested book by title and author
    BEGIN
      SELECT MAX(b.book_id) INTO book_id
      FROM Books b
      JOIN Authors a ON b.author_id = a.author_id
      WHERE b.book_title = book_title
      AND a.Name = author_name
      AND b.status = 'not charged'
      ORDER BY b.year_of_publication DESC;
    exception
      when no_data_found then
        book_id := NULL;
    END;

    IF book_id IS NOT NULL THEN
        -- Issue the latest edition using fun_issue_book
        RETURN fun_issue_book(borrower_id, book_id, current_date);
    ELSE
        -- No available editions found, check for older editions
        begin
          SELECT MIN(b.book_id) INTO book_id
          FROM Books b
          JOIN Authors a ON b.author_id = a.author_id
          WHERE b.book_title = book_title
          AND a.Name = author_name
          AND b.status = 'not charged';
        exception
          when no_data_found then
            book_id := NULL;
        end;

        IF book_id IS NOT NULL THEN
            -- Issue the next available older edition using fun_issue_book
            RETURN fun_issue_book(borrower_id, book_id, current_date);
        ELSE
            -- No editions available for the requested book
            my_package.unfulfilled_requests := my_package.unfulfilled_requests + 1;
            RETURN 0;
        END IF;
    END IF;
END fun_issue_anyedition;
/


/*The function returns '1' if the operation is successful; otherwise, it returns '0'.*/
Create OR REPLACE FUNCTION fun_return_book(book_id2 number, return_date date)
    RETURN NUMBER IS
    book_status VARCHAR2(20);

BEGIN
    -- Check if the book is currently issued (return_date is NULL)
    SELECT status INTO book_status FROM Books WHERE book_id = book_id2;

    IF book_status = 'charged' THEN

    --IF EXISTS (SELECT 1 FROM Issue WHERE book_id = book_id AND return_date IS NULL) THEN
        -- Update the return_date for the book
        UPDATE Issue SET return_date = return_date WHERE book_id = book_id2 AND return_date IS NULL;

        -- Update the status of the book to 'not charged'
        UPDATE Books SET status = 'not charged' WHERE book_id = book_id2;

        -- Return 1 to indicate successful return
        RETURN 1;
    ELSE
        -- Return 0 to indicate the book is not currently issued
        RETURN 0;
    END IF;
END fun_return_book;
/


--PROCEDURES
--print out current borrowers' list
CREATE OR REPLACE PROCEDURE pro_print_borrower AS
BEGIN
    FOR borrower_rec IN 
    (SELECT DISTINCT b.name AS 
            borrower_name,
            i.book_id,
            bk.book_title,
            CASE
                WHEN i.return_date IS NULL THEN
                    TO_NUMBER(TO_DATE(SYSDATE, 'YYYY-MM-DD') - TO_DATE(i.issue_date, 'YYYY-MM-DD'))
                ELSE NULL
            END AS days_difference
        FROM Borrower b
        JOIN Issue i ON b.borrower_id = i.borrower_id
        JOIN Books bk ON i.book_id = bk.book_id
        WHERE i.return_date IS NULL OR TO_DATE(SYSDATE, 'YYYY-MM-DD') - TO_DATE(i.issue_date, 'YYYY-MM-DD') <= 15)
     LOOP
        DBMS_OUTPUT.PUT_LINE(RPAD(borrower_rec.borrower_name, 15) ||
                            RPAD(borrower_rec.book_title, 25) ||
                            RPAD(COALESCE(TO_CHAR(borrower_rec.days_difference), '>15', '100'), 15));
    END LOOP;
END pro_print_borrower;
/

-- print out the names of the borrower who have not returned the books yet. 
-- Also print the book_id and issue_date
CREATE OR REPLACE PROCEDURE pro_list_borr AS
BEGIN
    FOR borrower_rec IN (SELECT DISTINCT b.name AS borrower_name,
                                i.book_id,
                                TO_CHAR(i.issue_date, 'YYYY-MM-DD') AS issue_date
                            FROM Borrower b
                            JOIN Issue i ON b.borrower_id = i.borrower_id)
    LOOP
        DBMS_OUTPUT.PUT_LINE('Borrower: ' || borrower_rec.borrower_name);
        DBMS_OUTPUT.PUT_LINE('Book ID: ' || borrower_rec.book_id);
        DBMS_OUTPUT.PUT_LINE('Issue Date: ' || borrower_rec.issue_date);
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;
END pro_list_borr;
/

--TRIGGER
--Implement a trigger that enforces rule 3 in the database
CREATE OR REPLACE TRIGGER trg_maxbooks
BEFORE INSERT ON Issue
FOR EACH ROW
DECLARE
    max_books_student CONSTANT NUMBER := 2;
    max_books_faculty CONSTANT NUMBER := 3;
    borrower_status VARCHAR2(20);
    borrower_count NUMBER;
BEGIN
    SELECT status INTO borrower_status FROM Borrower WHERE borrower_id = :NEW.borrower_id;
    SELECT COUNT(*) INTO borrower_count FROM Issue WHERE borrower_id = :NEW.borrower_id;
    -- Check if the borrower is a student
    IF borrower_status = 'student' THEN
        -- Check if the student is already borrowing the maximum allowed books
        IF borrower_count >= max_books_student THEN
            RAISE_APPLICATION_ERROR(-20001, 'A student cannot borrow more than ' || max_books_student || ' books.');
        END IF;
    ELSIF borrower_status = 'faculty' THEN
        -- Check if the faculty member is already borrowing the maximum allowed books
        IF borrower_count >= max_books_faculty THEN
            RAISE_APPLICATION_ERROR(-20001, 'A faculty member cannot borrow more than ' || max_books_faculty || ' books.');
        END IF;
    END IF;
END trg_maxbooks;
/

--Implement a trigger that changes the status in the Books table to 'charged' whenever
--a book is issued
CREATE OR REPLACE TRIGGER trg_charge
AFTER INSERT ON Issue
FOR EACH ROW
BEGIN
    -- Update the status of the book to 'charged'
    UPDATE Books SET status = 'charged' WHERE book_id = :NEW.book_id;
END trg_charge;
/

--Implement a trigger that changes the status in the Books table to 'not charged'
--whenever a borrower returns the book.
CREATE OR REPLACE TRIGGER trg_notcharge
AFTER UPDATE OF return_date ON Issue
FOR EACH ROW
BEGIN
    -- Check if the book is returned (return_date is not NULL)
    IF :NEW.return_date IS NOT NULL THEN
        -- Update the status of the book to 'not charged'
        UPDATE Books SET status = 'not charged' WHERE book_id = :NEW.book_id;
    END IF;
END trg_notcharge;
/


-- Insert records into Author
insert into Authors values(1,'C.J. DATES');
insert into Authors values(2,'H. ANTON');
insert into Authors values(3,'ORACLE PRESS');
insert into Authors values(4,'IEEE');
insert into Authors values(5,'C.J. CATES');
insert into Authors values(6,'W. GATES');
insert into Authors values(7,'CLOIS KICKLIGHTER');
insert into Authors values(8,'J.R.R. TOLKIEN');
insert into Authors values(9,'TOM CLANCY');
insert into Authors values(10,'ROGER ZELAZNY');
-- Insert records into Books
insert into Books values(1,'DATA MANAGEMENT',1,1998,3,'not charged');
insert into Books values(2,'CALCULUS',2,1995,7,'not charged');
insert into Books values(3,'ORACLE',3,1999,8,'not charged');
insert into Books values(4,'IEEE MULTIMEDIA',4,2001,1,'not charged');
insert into Books values(5,'MIS MANAGEMENT',5,1990,1,'not charged');
insert into Books values(6,'CALCULUS II',2,1997,3,'not charged');
insert into Books values(7,'DATA STRUCTURE',6,1992,1,'not charged');
insert into Books values(8,'CALCULUS III',2,1999,1,'not charged');
insert into Books values(9,'CALCULUS III',2,2000,2,'not charged');
insert into Books values(10,'ARCHITECTURE',7,1977,1,'not charged');
insert into Books values(11,'ARCHITECTURE',7,1980,2,'not charged');
insert into Books values(12,'ARCHITECTURE',7,1985,3,'not charged');
insert into Books values(13,'ARCHITECTURE',7,1990,4,'not charged');
insert into Books values(14,'ARCHITECTURE',7,1995,5,'not charged');
insert into Books values(15,'ARCHITECTURE',7,2000,6,'not charged');
insert into Books values(16,'THE HOBBIT',8,1960,1,'not charged');
insert into Books values(17,'THE BEAR AND THE DRAGON',9,2000,1,'not charged');
insert into Books values(18,'NINE PRINCES IN AMBER',10,1970,1,'not charged');
-- Insert records into Borrower
insert into Borrower values(1,'BRAD KICKLIGHTER','student');
insert into Borrower values(2,'JOE STUDENT','student');
insert into Borrower values(3,'GEDDY LEE','student');
insert into Borrower values(4,'JOE FACULTY','faculty');
insert into Borrower values(5,'ALBERT EINSTEIN','faculty');
insert into Borrower values(6,'MIKE POWELL','student');
insert into Borrower values(7,'DAVID GOWER','faculty');
insert into Borrower values(8,'ALBERT SUNARTO','student');
insert into Borrower values(9,'GEOFFERY BYCOTT','faculty');
insert into Borrower values(10,'JOHN KACSZYCA','student');
insert into Borrower values(11,'IAN LAMB','faculty');
insert into Borrower values(12,'ANTONIO AKE','student');

@TA_test_data

DECLARE
  l_success_code NUMBER;
begin
  l_success_code := fun_issue_anyedition(2, 'DATA MANAGEMENT', 'C.J. DATES', '03/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code);
end;
/

DECLARE
  l_success_code2 NUMBER;
begin
  l_success_code2 := fun_issue_anyedition(4, 'CALCULUS', 'H. ANTON', '4/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code2);
end;
/

DECLARE
  l_success_code3 NUMBER;
begin
  l_success_code3 := fun_issue_anyedition(5, 'ORACLE', 'ORACLE PRESS', '4/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code3);
end;
/

DECLARE
  l_success_code4 NUMBER;
begin
  l_success_code4 := fun_issue_anyedition(10, 'IEEE MULTIMEDIA', 'IEEE', '27/FEBRUARY/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code4);
end;
/

DECLARE
  l_success_code5 NUMBER;
begin
  l_success_code5 := fun_issue_anyedition(2, 'MIS MANAGEMENT', 'C.J. CATES', '3/MAY/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code5);
end;
/

DECLARE
  l_success_code6 NUMBER;
begin
  l_success_code6 := fun_issue_anyedition(4, 'CALCULUS II', 'H. ANTON', '4/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code6);
end;
/

DECLARE
  l_success_code7 NUMBER;
begin
  l_success_code7 := fun_issue_anyedition(10, 'ORACLE', 'ORACLE PRESS', '4/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code7);
end;
/

DECLARE
  l_success_code8 NUMBER;
begin
  l_success_code8 := fun_issue_anyedition(5, 'IEEE MULTIMEDIA', 'IEEE', '26/FEBRUARY/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code8);
end;
/

DECLARE
  l_success_code9 NUMBER;
begin
  l_success_code9 := fun_issue_anyedition(2, 'DATA SRUCTURE', 'W. GATES', '3/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code9);
end;
/

DECLARE
  l_success_code10 NUMBER;
begin
  l_success_code10 := fun_issue_anyedition(4, 'CALCULUS III', 'H. ANTON', '4/APRIL/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code10);
end;
/


DECLARE
  l_success_code11 NUMBER;
begin
  l_success_code11 := fun_issue_anyedition(11, 'ORACLE', 'ORACLE PRESS', '8/MARCH/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code11);
end;
/

DECLARE
  l_success_code12 NUMBER;
begin
  l_success_code12 := fun_issue_anyedition(6, 'IEEE MULTIMEDIA', 'IEEE', '17/FEBRUARY/05');
  DBMS_OUTPUT.PUT_LINE(l_success_code12);
end;
/


--Execute pro_print_borrower:
BEGIN
  pro_print_borrower;
END;
/

--Use the function fun_return_book() to return books with book_id 1,2, 4, 10. Also,
--specify the returns date as the second parameter.
DECLARE
  return_status NUMBER;
  return_date DATE := TO_DATE('30-OCTOBER-23', 'YYYY-MM-DD');

BEGIN
  -- Return books with book_id 1, 2, 4, and 10
  --not sure how to returns date as the second parameter.
  return_status := fun_return_book(1, return_date);
  return_status := fun_return_book(2, return_date);
  return_status := fun_return_book(4, return_date);
  return_status := fun_return_book(10, return_date);
  
END;
/

--Print the Issue table
SELECT * FROM Issue;

--Execute pro_list_borr.
BEGIN
  pro_list_borr;
END;
/


--keep track and finally print out the total number of borrowers’ requests
--that could not be fulfilled

DECLARE
  unfulfilled_requests NUMBER := 0;
BEGIN
  -- For each unfulfilled request, increment the counter
  IF fun_issue_anyedition(4, 'CALCULUS', 'H. ANTON', '4/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(2, 'DATA MANAGEMENT', 'C.J. DATES', '03/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(5, 'ORACLE', 'ORACLE PRESS', '4/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(10, 'IEEE MULTIMEDIA', 'IEEE', '27/FEBRUARY/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(2, 'MIS MANAGEMENT', 'C.J. CATES', '3/MAY/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(4, 'CALCULUS II', 'H. ANTON', '4/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(10, 'ORACLE', 'ORACLE PRESS', '4/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(5, 'IEEE MULTIMEDIA', 'IEEE', '26/FEBRUARY/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(2, 'DATA SRUCTURE', 'W. GATES', '3/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(4, 'CALCULUS III', 'H. ANTON', '4/APRIL/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(11, 'ORACLE', 'ORACLE PRESS', '8/MARCH/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  IF fun_issue_anyedition(6, 'IEEE MULTIMEDIA', 'IEEE', '17/FEBRUARY/05') = 0 THEN
    unfulfilled_requests := unfulfilled_requests + 1;
  END IF;

  -- Print the total number of unfulfilled requests
  DBMS_OUTPUT.PUT_LINE('Total unfulfilled requests: ' || unfulfilled_requests);
END;
/


-- Drop tables
DROP TABLE Issue;
DROP TABLE Books;
DROP TABLE Authors;
DROP TABLE Borrower;

-- Drop triggers
--DROP TRIGGER trg_maxbooks;
--DROP TRIGGER trg_charge;
--DROP TRIGGER trg_notcharge;

-- Drop functions
DROP FUNCTION fun_issue_book;
DROP FUNCTION fun_issue_anyedition;
DROP FUNCTION fun_return_book;

-- Drop procedures
DROP PROCEDURE pro_print_borrower;
DROP PROCEDURE pro_list_borr;






