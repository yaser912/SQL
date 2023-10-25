/* --------------------------------------------------------------- */
/* EMPLOYEE ADDRESS TABLE */
CREATE TABLE employee_address (
    employee_address_id INT NOT NULL AUTO_INCREMENT,
	employee_address varchar(255),
    city varchar(50),
    province varchar(50),
    postal_code varchar(10),

    PRIMARY KEY (employee_address_id)
);

/* --------------------------------------------------------------- */
/* EMPLOYEE TABLE */
CREATE TABLE employee (
    medicare_number INT NOT NULL AUTO_INCREMENT,
    employee_address_id INT, /* Maybe should be NOT NULL */
    first_name varchar(50),
    last_name varchar(50),
    date_of_birth DATE,
    phone_number INT,
    email varchar(255),

    FOREIGN KEY (employee_address_id) REFERENCES employee_address(employee_address_id),
    PRIMARY KEY (medicare_number)
);

CREATE TABLE facility_type (
    facility_type_id INT NOT NULL AUTO_INCREMENT,
    name varchar(255),

    PRIMARY KEY (facility_type_id)
);

/* --------------------------------------------------------------- */
/* FACILITY ADDRESS TABLE */
CREATE TABLE facility_address (
    facility_address_id INT NOT NULL AUTO_INCREMENT,
	facility_address varchar(255),
    city varchar(50),
    province varchar(50),
    postal_code varchar(10),

    PRIMARY KEY (facility_address_id)
);

/* --------------------------------------------------------------- */
/* FACILITY TABLE */
CREATE TABLE facility (
    facility_id INT NOT NULL AUTO_INCREMENT,
    facility_type_id INT NOT NULL,
    facility_address_id INT NOT NULL,
    name varchar(50),
    phone_number INT,
    website_url varchar(255),
	capacity INT,

    FOREIGN KEY (facility_type_id) REFERENCES facility_type(facility_type_id),
    FOREIGN KEY (facility_address_id) REFERENCES facility_address(facility_address_id),
    PRIMARY KEY (facility_id)
);





/* --------------------------------------------------------------- */
/* ROLE TABLE */
CREATE TABLE role (
    role_id INT NOT NULL AUTO_INCREMENT,
    name varchar(255),

    PRIMARY KEY (role_id)
);

/* --------------------------------------------------------------- */
/* JOB TABLE */
CREATE TABLE work (
    work_id INT NOT NULL AUTO_INCREMENT,
    employee_medicare_number INT NOT NULL,
    role_id INT NOT NULL,
    facility_id INT NOT NULL,
	start_date DATE NOT NULL,
	end_date Date,
	

    FOREIGN KEY (employee_medicare_number) REFERENCES employee(medicare_number),
    FOREIGN KEY (role_id) REFERENCES role(role_id),
    FOREIGN KEY (facility_id) REFERENCES facility(facility_id),
    PRIMARY KEY (work_id),
	CONSTRAINT assignment CHECK (start_date < end_date
        OR end_date IS NULL),
    CONSTRAINT timeslot UNIQUE (employee_medicare_number , start_date , end_date)
);

/* --------------------------------------------------------------- */
/* VACCINE TYPE */
CREATE TABLE vaccine_type (
    vaccine_type_id INT NOT NULL AUTO_INCREMENT,
    name varchar(255),
    
    PRIMARY KEY (vaccine_type_id)
);

/* --------------------------------------------------------------- */
/* VACCINE TABLE */
CREATE TABLE patient_vaccine (
    vaccine_id INT NOT NULL AUTO_INCREMENT,
    employee_id INT NOT NULL,
    vaccine_type_id INT NOT NULL,
	date DATE NOT NULL,
	location varchar(255),
	dose_number INT,

    FOREIGN KEY (employee_id) REFERENCES employee(medicare_number),
    FOREIGN KEY (vaccine_type_id) REFERENCES vaccine_type(vaccine_type_id),
    PRIMARY KEY (vaccine_id)
);

CREATE TABLE disease (
    disease_id INT NOT NULL AUTO_INCREMENT,
    name varchar(255),

    PRIMARY KEY (disease_id)
);

/* --------------------------------------------------------------- */
/* CONTRACTED TABLE */
CREATE TABLE contracted (
    contracted_id INT NOT NULL AUTO_INCREMENT,
    employee_id INT NOT NULL,
    disease_id INT NOT NULL,
    date DATE NOT NULL,
	

    FOREIGN KEY (employee_id) REFERENCES employee(medicare_number),
    FOREIGN KEY (disease_id) REFERENCES disease(disease_id),
    PRIMARY KEY (contracted_id)
);

/* --------------------------------------------------------------- */
/* SCHEDULE TABLE */
Create table Schedule (
    schedule_id INT,
    fac_id INT NOT NULL,
    emp_id INT NOT NULL,
    sch_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    CONSTRAINT start_before_end CHECK (start_time < end_time),

    PRIMARY KEY (schedule_id), 
    FOREIGN KEY (fac_id) references facility (facility_id), 
    FOREIGN KEY (emp_id) references employee (medicare_number)
);

DELIMITER $$
CREATE TRIGGER employee_facility_work_match
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
    IF ((SELECT COUNT(*) FROM work wk WHERE wk.employee_medicare_number = NEW.emp_id AND wk.facility_id = NEW.fac_id) = 0) THEN
        SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "employee does not work at facility" ;
	END IF;
END
$$

DELIMITER %%
CREATE TRIGGER overlapping_time_check
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
    IF ((select count(*)
    from schedule sc
    where  NEW.emp_id = sc.emp_id AND NEW.sch_date = sc.sch_date
    and ((NEW.start_time>=sc.start_time  and NEW.end_time<=sc.end_time) or (NEW.start_time>=sc.start_time  and NEW.start_time<=sc.end_time)  or (NEW.end_time>=sc.start_time  and NEW.end_time<=sc.end_time) or 
	(NEW.start_time<=sc.start_time  and NEW.end_time>=sc.end_time)))!= 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'overlapping time for new employee schedule';
    END IF;
END
%%


DELIMITER ##
CREATE TRIGGER one_hour_schedule_check
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
    IF ((select count(*)
    from schedule sc
    where  NEW.emp_id = sc.emp_id AND NEW.sch_date = sc.sch_date
    AND (timestampdiff(HOUR, sc.end_time, NEW.start_time)<1)) != 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'new schedule needs to be 1 hour after previous schedule end ';
    END IF;
END
##


/* --------------------------------------------------------------- */
/* EMAIL TABLE */
create table email (
email_id INT primary key AUTO_INCREMENT, 
date DATE NOT NULL, 
sender varchar(100) NOT NULL, 
receiver varchar(100) NOT NULL, 
subject varchar(100) NOT NULL, 
body varchar(80) NOT NULL
);

/* trigger 1: schedule only 4 weeks ahead */ 
DELIMITER ^^
CREATE TRIGGER four_week_ahead_constraint
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
	declare today DATE;
    declare newScheduleDate DATE;
    SET today = curdate();
    SET newScheduleDate = NEW.sch_date;
    IF (timestampdiff(DAY, today, newScheduleDate ) > 28) THEN
        SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "cannot schedule beyond 4 weeks" ;
	END IF;
END^^

/* trigger 2: If a nurse or a doctor is infected by COVID-19, then he/she cannot be scheduled to work for at least two weeks from the date of infection 
check work table if doc or nurse, 
subquery contracted to check if covid
if true
stop input to schedule for 2 weeks from date of infection
*/ 
DELIMITER ^^
CREATE TRIGGER docNurse_infected_two_week_constraint
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
	DECLARE contracted_date DATE;
    DECLARE EXIT HANDLER FOR NOT FOUND
	BEGIN
	  SET contracted_date = NEW.sch_date + 15; 
	END;
		/* take the last time employee( that is being inserted) was infected with covid 19 to check if it has been 14 days atleast*/
	SELECT date into contracted_date  FROM contracted ct WHERE ct.disease_id = 1 AND ct.employee_id=NEW.emp_id order by date desc limit 1;
	if (timestampdiff(DAY, contracted_date, NEW.sch_date)<=14) THEN
		SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "Doctor or nurse recently infected with covid, wait for 2 weeks from date of infection" ;
	END if;
END^^


/* trigger 3: An employee cannot be scheduled if she/he is not vaccinated, at least one vaccine for COVID-19 in the past six months prior to the 
date of the new schedule. 
take emp_id and check in patient_vaccine
take latest vaccine and timestampdiff, if more than 6 months show error.
*/ 
DELIMITER ^^
CREATE TRIGGER employee_vaccine_check
BEFORE INSERT ON schedule
FOR EACH ROW
BEGIN
    DECLARE latest_employee_vaccine DATE;
    DECLARE EXIT HANDLER FOR NOT FOUND
	BEGIN
	  SET latest_employee_vaccine = NEW.sch_date - 1000; 
	END;
	select date into latest_employee_vaccine from patient_vaccine where employee_id=NEW.emp_id order by date DESC LIMIT 1;
	if(timestampdiff(MONTH, latest_employee_vaccine, NEW.sch_date)>6) THEN
		SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "employee not recently vaccinated, cannot be scheduled for work" ;
	END if;
END^^

/* trigger 4: If a doctor or a nurse gets infected by COVID-19, then the system should automatically cancel all the assignments for the infected employee for two weeks from the date of infection 
once a doc/nurse has been infected by covid(after insertion to patient_vaccine table)
remove that doc/nurse from all schdeuls for the next 2 weeks
*/ 
DELIMITER !!
CREATE TRIGGER del_doc_nurse_schedule_when_infected
AFTER INSERT  ON contracted
FOR EACH ROW
BEGIN
    declare roleNum int;
    declare currentDate DATE;
    declare dateplus14 DATE;
    set currentDate =curdate();
    set dateplus14 = DATE_ADD(currentDate, INTERVAL 14 DAY);
    select role_id into roleNum from work wk where wk.employee_medicare_number=NEW.employee_id and (wk.role_id = 5 or wk.role_id=6) limit 1;
    if (NEW.disease_id = 1) then
        DELETE from schedule where emp_id = NEW.employee_id and sch_date between curdate() AND dateplus14;
    END if;
END!!

/* trigger 5 email: the system should send an email to inform/track all the doctors and nurses who have been in contact by having the same schedule as the infected employee. Each email should have as a subject “Warning” and as a body “One of your colleagues that you have worked with in the past two weeks have been infected with COVID-19”
inform all employee in facility when the doc/nurse in facility has gotten covid 19
after insert on contracted,
find facility in concern,  
 */ 
 
DELIMITER !!
CREATE TRIGGER caution_colleague_infected_warning_email
AFTER INSERT ON contracted 
FOR EACH ROW
BEGIN
	DECLARE currentDate DATE;
	DECLARE previousTwoWeek Date;
	DECLARE noReturnWork int default false;
	DECLARE facilityList int;
	DECLARE facilityInConcern cursor for select facility_id from work where employee_medicare_number = NEW.employee_id and end_date is null;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET noReturnWork=true;
	SET currentDate = curdate();
	SET previousTwoWeek = DATE_ADD(currentDate, INTERVAL -14 DAY) ;
	open facilityInConcern;

	facilityLoop: LOOP 
		Fetch facilityInConcern INTO facilityList;
		-- inside this loop, 
		if noReturnWork then
			leave facilityLoop;
		end if; 
        
        innerBlock:BEGIN
            DECLARE innerComplete INT DEFAULT FALSE;
            DECLARE employeeList int;
            DECLARE innerEmployeeList cursor for select employee_medicare_number from work where (facility_id = facilityList) AND ((role_id=6)or(role_id=5));
            DECLARE CONTINUE HANDLER FOR NOT FOUND SET innerComplete=true;
            open innerEmployeeList;
            employeeLoop: LOOP 
                fetch innerEmployeeList INTO employeeList;
                if innerComplete then
                    leave employeeLoop;
                end if;
                -- email the employees 
                secondBlock:BEGIN
                    DECLARE receiver varchar(100) ;
                    SET receiver = (select email from employee where medicare_number=employeeList );
                    if (NEW.disease_id =1) then 
                        INSERT INTO email ( date, sender, receiver, subject, body)
                        VALUES ( curdate(), 'System' , receiver, 'Warning', 'One of your colleagues that you have worked with in the past two weeks have been');
                    end if;
                END secondBlock;
            end loop employeeLoop;
            close innerEmployeeList;
        END innerBlock;
	end loop;  
	close facilityInConcern ;
END!!


/* trigger 6 email: On Sunday of every week, for every employee working in every facility, the system 
should automatically send an email to every employee indicating the schedule of the 
employee in the facility for the coming week. 
performed using flask server*/ 



/* reference: https://dev.mysql.com/doc/refman/8.0/en/signal.html#:~:text=To%20signal%20a%20generic%20SQLSTATE,simple_value_specification%20assignments%2C%20separated%20by%20commas. */
/* reference: https://dev.mysql.com/doc/refman/8.0/en/trigger-syntax.html */
/* reference: https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html#function_date-add*/
/*reference: https://dev.mysql.com/doc/refman/8.0/en/cursors.html*/
