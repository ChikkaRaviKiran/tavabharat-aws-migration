-- Validation queries for database migration
-- Run this against the migrated database to verify integrity

PRINT '======================================';
PRINT 'DATABASE MIGRATION VALIDATION REPORT';
PRINT '======================================';
PRINT '';

-- Database information
PRINT '1. DATABASE INFORMATION';
PRINT '----------------------';
SELECT 
    DB_NAME() AS DatabaseName,
    SUSER_SNAME() AS CurrentUser,
    @@VERSION AS SQLServerVersion;
PRINT '';

-- Table counts
PRINT '2. TABLE ROW COUNTS';
PRINT '-------------------';
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS RowCount
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
GROUP BY t.name
ORDER BY t.name;
PRINT '';

-- Check for tables
PRINT '3. TOTAL TABLES';
PRINT '---------------';
SELECT COUNT(*) AS TotalTables FROM sys.tables;
PRINT '';

-- Check for views
PRINT '4. VIEWS';
PRINT '--------';
SELECT COUNT(*) AS TotalViews FROM sys.views;
SELECT name AS ViewName FROM sys.views ORDER BY name;
PRINT '';

-- Check for stored procedures
PRINT '5. STORED PROCEDURES';
PRINT '--------------------';
SELECT COUNT(*) AS TotalStoredProcedures 
FROM sys.procedures 
WHERE is_ms_shipped = 0;

SELECT name AS ProcedureName 
FROM sys.procedures 
WHERE is_ms_shipped = 0
ORDER BY name;
PRINT '';

-- Check for indexes
PRINT '6. INDEXES';
PRINT '----------';
SELECT 
    t.name AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType
FROM sys.indexes i
INNER JOIN sys.tables t ON i.object_id = t.object_id
WHERE i.name IS NOT NULL
ORDER BY t.name, i.name;
PRINT '';

-- Check for foreign keys
PRINT '7. FOREIGN KEY CONSTRAINTS';
PRINT '--------------------------';
SELECT 
    fk.name AS ForeignKeyName,
    OBJECT_NAME(fk.parent_object_id) AS TableName,
    OBJECT_NAME(fk.referenced_object_id) AS ReferencedTable
FROM sys.foreign_keys fk
ORDER BY TableName;
PRINT '';

-- Check database size
PRINT '8. DATABASE SIZE';
PRINT '----------------';
EXEC sp_spaceused;
PRINT '';

-- Check for any errors in error log
PRINT '9. RECENT DATABASE ERRORS';
PRINT '-------------------------';
EXEC sp_readerrorlog 0, 1, 'error';
PRINT '';

PRINT '======================================';
PRINT 'VALIDATION COMPLETE';
PRINT '======================================';
PRINT '';
PRINT 'Please review the above information and compare with source database.';
PRINT 'Pay special attention to:';
PRINT '  - Row counts match source database';
PRINT '  - All tables, views, and stored procedures are present';
PRINT '  - All indexes and foreign keys are created';
PRINT '  - No critical errors in the log';
