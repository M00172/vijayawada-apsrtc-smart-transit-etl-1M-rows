-- ============================================
-- PROJECT: Vijayawada APSRTC Smart Transit & UPI ETL Pipeline
-- 1M ROWS | Data Engineer Project
-- ============================================
-- 1. BUSES MASTER TABLE
create table buses(
  bus_id int primary key,
  route varchar(100),
  capacity int
);
insert into buses values 
(1,'Benz circle - Ganavaram',50), 
(2,'PNBS - Autonagar',45), 
(3,'Vijayawada - Guntur',50),
(4,'Vijayawada - Hyderabad',45),
(5,'Vijayawada - Bhimavaram',50);
select * from buses;
-- 2. MAIN TICKETS TABLE - 1M ROWS WITH PARTITIONING
create table tickets(
  ticket_id int not null,
  route varchar(100),
  source varchar(50),
  destination varchar(50),
  travel_date date,
  crowd_count int not null,
  gps_delay_min int,
  upi_status varchar(20),
  primary key (ticket_id, crowd_count)
) partition by range (crowd_count) (
  partition p_low values less than (30),
  partition p_mid values less than (60),
  partition p_high values less than maxvalue
);
select * from tickets;
-- 3. SUPPORTING TABLES
-- 3A. TICKET AUDIT (FOR BOOKING HISTORY)
create table ticket_audit(
  audit_id int auto_increment primary key,
  ticket_id int,
  action varchar(50),
  audit_time timestamp default current_timestamp
);
select * from ticket_audit;
-- 3B. FAILED LOGS (FOR UPI FAILURE TRACKING)
create table failed_logs(
  log_id int auto_increment primary key,
  ticket_id int,
  route varchar(100),
  fail_time timestamp default current_timestamp
);
select * from failed_logs;
-- 4. PERFORMANCE TUNING - INDEX
create index idx_upi on tickets(upi_status);
create index idx_route on tickets(route);
create index idx_crowd on tickets(crowd_count);
-- 5. MAIN ETL - LOAD 1M ROWS FROM CSV
show variables like 'secure_file_priv';
set global local_infile=1;
load data infile 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/tickets.csv'
into table tickets
fields terminated by ','
enclosed by '"'
lines terminated by '\r\n'
ignore 1 rows
(ticket_id, route, source, destination, travel_date, crowd_count, gps_delay_min, upi_status);
-- 6. VERIFICATION - 1M CHECK
select count(*) as total_rows from tickets;
explain select * from tickets where upi_status='FAILED';
-- 7. TRIGGERS - AUTOMATION
delimiter //
create trigger trg_ticket_booked 
after insert on tickets
for each row 
begin 
  insert into ticket_audit(ticket_id, action) values (NEW.ticket_id, 'BOOKED'); 
end;//
create trigger trg_upi_fail 
after insert on tickets
for each row 
begin 
  if NEW.upi_status='FAILED' then 
    insert into failed_logs(ticket_id, route) values (NEW.ticket_id, NEW.route); 
  end if; 
end;//
delimiter ;
-- 8. TRANSACTION EXAMPLE - SAFE BOOKING
start transaction;
insert into tickets (ticket_id,route,source,destination,travel_date,crowd_count,gps_delay_min,upi_status) 
values (1000001,'Benz circle - Ganavaram','Benz circle','Ganavaram','2026-09-29',55,5,'SUCCESS');
select * from tickets where ticket_id = 1000001;
commit;
-- 9. STORED PROCEDURE - ROUTE STATS WITH COALESCE
delimiter //
create procedure GetRouteStats(in r_name varchar(100))
begin
 select 
   r_name as route, 
   count(*) as total_tickets, 
   sum(case when upi_status='FAILED' then 1 else 0 end) as failed_count,
   coalesce(avg(gps_delay_min), 0) as avg_delay,
   coalesce(avg(crowd_count), 0) as avg_crowd
 from tickets 
 where route=r_name;
end;//
delimiter ;
-- 10. ANALYTICS QUERIES - BUSINESS INSIGHTS
-- 10A. JOIN + COALESCE - TICKET WITH BUS CAPACITY & PAYMENT STATUS
select 
  t.ticket_id, 
  t.route, 
  b.capacity, 
  t.crowd_count,
  coalesce(t.upi_status, 'PENDING') as payment_status,
  coalesce(t.gps_delay_min, 0) as delay
from tickets t 
join buses b on t.route=b.route 
limit 10;
-- 10B. SUBQUERY - CROWD MORE THAN AVERAGE (HIGH DEMAND ROUTES)
select * from tickets 
where crowd_count > (select avg(crowd_count) from tickets)
limit 10;
-- 10C. WINDOW FUNCTION - RANK & AVG CROWD PER ROUTE
select 
  ticket_id, 
  route, 
  crowd_count, 
  rank() over (partition by route order by crowd_count desc) as crowd_rank,
  avg(crowd_count) over (partition by route) as avg_crowd_per_route
from tickets 
limit 20;
-- 11. FINAL TESTS WITH COALESCE
-- 11A. CALL PROCEDURE - SPECIFIC ROUTE PERFORMANCE
call GetRouteStats('Benz circle - Ganavaram');
-- 11B. GROUP BY - UPI SUCCESS vs FAILED COUNT
select 
  coalesce(upi_status, 'UNKNOWN') as upi_status, 
  count(*) as total 
from tickets 
group by upi_status;
-- 11C. GROUP BY + ORDER BY - ROUTE WISE DELAY ANALYSIS
select 
  route, 
  coalesce(avg(gps_delay_min), 0) as avg_delay,
  coalesce(avg(crowd_count), 0) as avg_crowd
from tickets 
group by route 
order by avg_delay desc;