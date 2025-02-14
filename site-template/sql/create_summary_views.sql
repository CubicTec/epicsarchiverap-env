/* Create views for the database 'archappl_summary' to help manage the AA databases. */
USE archappl_summary;

/*
Each appliance has it's own db on the same instance, so I want to have a
union o f all the RequestPV tables so that I can track from one place which
channels have been added.
*/

/* No longer using all 3 instances, this causes error. 7/22/21
*/
CREATE OR REPLACE VIEW RequestSummary AS
    SELECT pvName, 'archappl' as applianceId FROM archappl.ArchivePVRequests;

/*
Same for the aliases as above with the requests tables. There is a separate
alias table for each appliance so it's good to aggregate them all with a union.
*/

CREATE OR REPLACE VIEW AliasSummary AS
    SELECT pvName, realName FROM archappl.PVAliases;
/* No longer using all 3 instances, this causes error. 7/22/21
    SELECT pvName, realName FROM archappl_protected.PVAliases UNION
    SELECT pvName, realName FROM archappl_fast.PVAliases;
*/

/*
This table is filled by the CF reader program and is used in the
RequestHistory view to organize all the channels.
*/

DROP TABLE IF EXISTS request_meta;
CREATE TABLE request_meta (pvName VARCHAR(65) PRIMARY KEY NOT NULL,
                           ioc VARCHAR(255),
                           cf_status VARCHAR(50),
                           ip VARCHAR(50),
                           ca_status VARCHAR(60),
                           hostname VARCHAR(255),
                           policy VARCHAR(255),
                           table_update TIMESTAMP,
                           workflow VARCHAR(50),
                           applianceId VARCHAR(255) NOT NULL,
                           deleted_on TIMESTAMP,
                           disconnected enum('true', 'false'),
                           disconn_time TIMESTAMP
                          );

/*
Only one PVTypeInfo table is referenced b/c the data is duplicated across all
instances. Note that for the aliases, the PVAliases table uses `realName' as the
real PV and 'pvName' as the alias.
*/

CREATE OR REPLACE VIEW RequestHistory AS
    SELECT RM.*,
           AL.pvName AS 'alias',
           INFO.last_modified as 'date_arch_began',
           (CASE WHEN INFO.pvName is NULL THEN 'false' ELSE 'true' END) AS 'isArchived'
    FROM archappl.PVTypeInfo AS INFO
    RIGHT JOIN request_meta AS RM ON INFO.pvName = RM.pvName
    LEFT JOIN AliasSummary as AL on AL.realName = RM.pvName;

/*
These triggers are used to add a row to the custom table, 'request_meta',
which is an intermediate table used to create views. We first check for the
existance of the PV since it's a unique key and cannot be duplicated.
It's possible that a channel was removed manually and added again via the
automated program.
*/

USE archappl;
DROP TRIGGER IF EXISTS appliance_id_push1;
DELIMITER $$

CREATE TRIGGER appliance_id_push1 BEFORE INSERT ON ArchivePVRequests FOR EACH ROW
            BEGIN
            IF NOT EXISTS
                (SELECT 1 FROM archappl_summary.request_meta WHERE pvName = NEW.pvName) THEN
                    INSERT INTO archappl_summary.request_meta (pvName, applianceId)
                    VALUES (NEW.pvName, 'archappl');
            END IF;
END $$
DELIMITER ;

/*
USE archappl_protected;
DROP TRIGGER IF EXISTS appliance_id_push2;
DELIMITER $$

CREATE TRIGGER appliance_id_push2 BEFORE INSERT ON ArchivePVRequests FOR EACH ROW
            BEGIN
            IF NOT EXISTS
                (SELECT 1 FROM archappl_summary.request_meta WHERE pvName = NEW.pvName) THEN
                    INSERT INTO archappl_summary.request_meta (pvName, applianceId)
                    VALUES (NEW.pvName, 'protected');
            END IF;
END $$
DELIMITER ;


USE archappl_fast;
DROP TRIGGER IF EXISTS appliance_id_push3;
DELIMITER $$

CREATE TRIGGER appliance_id_push3 BEFORE INSERT ON ArchivePVRequests FOR EACH ROW
            BEGIN
            IF NOT EXISTS
                (SELECT 1 FROM archappl_summary.request_meta WHERE pvName = NEW.pvName) THEN
                    INSERT INTO archappl_summary.request_meta (pvName, applianceId)
                    VALUES (NEW.pvName, 'fast');
            END IF;
END $$
DELIMITER ;
*/


/*
Trigger to add meta data to the table 'request_meta', when a channel is
deleted. It's difficult to tell if a channel has been removed.
We only need to check one db and table (generic) b/c all the PVTypeInfo tables are synced
across the cluster.
*/

USE archappl;
DROP TRIGGER IF EXISTS channel_delete;
DELIMITER $$

CREATE TRIGGER channel_delete BEFORE DELETE ON PVTypeInfo FOR EACH ROW
        BEGIN
        UPDATE archappl_summary.request_meta SET deleted_on = CURRENT_TIMESTAMP
        WHERE pvName = pvName;
END $$
DELIMITER ;

