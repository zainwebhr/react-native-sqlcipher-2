#define SQLITE_HAS_CODEC 1
#import "RNSqlite2.h"
#import "sqlite3.h"

@implementation RNSqlite2

@synthesize cachedDatabases;

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("dog.craftz.sqlite2", DISPATCH_QUEUE_SERIAL);
}
RCT_EXPORT_MODULE(RNSqlCipher)

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (id) init {
  self = [super init];
  if (self!=nil) {
    [self pluginInitialize];
  }
  return self;
}

-(void)pluginInitialize {
  logDebug(@"pluginInitialize()");
  cachedDatabases = [NSMutableDictionary dictionaryWithCapacity:0];
  NSString *dbDir = [self getDatabaseDir];
  
  // create "NoCloud" if it doesn't exist
  [[NSFileManager defaultManager] createDirectoryAtPath: dbDir
                            withIntermediateDirectories: NO
                                             attributes: nil
                                                  error: nil];
  // make it non-syncable to iCloud
  NSURL *url = [ NSURL fileURLWithPath: dbDir];
  [url setResourceValue: [NSNumber numberWithBool: YES]
                 forKey: NSURLIsExcludedFromBackupKey
                  error: nil];
}

-(NSString*) getDatabaseDir {
  NSString *libDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
  return [libDir stringByAppendingPathComponent:@"NoCloud"];
}

-(id) getPathForDB:(NSString *)dbName {
  
  // special case for in-memory databases
  if ([dbName isEqualToString:@":memory:"]) {
    return dbName;
  }
  // otherwise use this location, which matches the old SQLite Plugin behavior
  // and ensures no iCloud backup, which is apparently disallowed for SQLite dbs
  return [[self getDatabaseDir] stringByAppendingPathComponent: dbName];
}

-(NSValue*)openDatabase: (NSString*)dbName: (NSString*) password {
  logDebug(@"opening DB: %@", dbName);
  NSValue *cachedDB = [cachedDatabases objectForKey:dbName];
  if (cachedDB == nil) {
    logDebug(@"opening new db");
    NSString *fullDbPath = [self getPathForDB: dbName];
    logDebug(@"full path: %@", fullDbPath);
    const char *sqliteName = [fullDbPath UTF8String];
    sqlite3 *db;

    if (sqlite3_open(sqliteName, &db) != SQLITE_OK) {
      @throw[NSException exceptionWithName:@"cannot-open-db" reason:nil userInfo:nil];
    };
    if (sqlite3_key (db, [password UTF8String], password.length) != SQLITE_OK) {
      @throw[NSException exceptionWithName:@"key-error" reason:nil userInfo:nil];
    };
    
    // Validate key upon opening DB
    if (sqlite3_exec(db, (const char*) "SELECT count(*) FROM sqlite_master;",
                     NULL, NULL, NULL) != SQLITE_OK) {
      @throw[NSException exceptionWithName:@"key-error" reason:nil userInfo:nil];
    };
    sqlite3_stmt *stmt;
    if(sqlite3_prepare_v2(db, "PRAGMA cipher_version;", -1, &stmt, NULL) != SQLITE_OK
       || sqlite3_step(stmt) != SQLITE_ROW
       || sqlite3_column_text(stmt, 0) == NULL) {
      sqlite3_finalize(stmt);
      @throw[NSException exceptionWithName:@"key-error" reason:nil userInfo:nil];
    }
    sqlite3_finalize(stmt);
    
    cachedDB = [NSValue valueWithPointer:db];
    [cachedDatabases setObject: cachedDB forKey: dbName];
  } else {
    logDebug(@"re-using existing db");
  }
    
  return cachedDB;
}

RCT_EXPORT_METHOD(exec:(NSString *)dbName
                  password:(NSString *)password
                  queries: (NSArray *)sqlQueries
                  readOnly:(BOOL)readOnly
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  logDebug(@"exec()");
  logDebug(@"queries: %@", sqlQueries);
  logDebug(@"readOnly: %@", readOnly ? @"true" : @"false");

  long numQueries = [sqlQueries count];
  NSArray *sqlResult;
  int i;
  logDebug(@"dbName: %@", dbName);
  
  NSValue *databasePointer;
  @try {
      databasePointer = [self openDatabase:dbName:password];
  } @catch (NSException *exception) {
    reject([exception name], [exception reason], nil);
    return;
  }
  
  sqlite3 *db = [databasePointer pointerValue];
  NSMutableArray *sqlResults = [NSMutableArray arrayWithCapacity:numQueries];

  // execute queries
  for (i = 0; i < numQueries; i++) {
    NSArray *sqlQueryObject = [sqlQueries objectAtIndex:i];
    NSString *sql = [sqlQueryObject objectAtIndex:0];
    NSArray *sqlArgs = [sqlQueryObject objectAtIndex:1];
    logDebug(@"sql: %@", sql);
    logDebug(@"sqlArgs: %@", sqlArgs);
    sqlResult = [self executeSql:sql withSqlArgs:sqlArgs withDb: db withReadOnly: readOnly];
    logDebug(@"sqlResult: %@", sqlResult);
    [sqlResults addObject:sqlResult];
  }

  resolve(sqlResults);
}

-(NSObject*) getSqlValueForColumnType: (int)columnType withStatement: (sqlite3_stmt*)statement withIndex: (int)i {
  switch (columnType) {
    case SQLITE_INTEGER:
      return [NSNumber numberWithLongLong: sqlite3_column_int64(statement, i)];
    case SQLITE_FLOAT:
      return [NSNumber numberWithDouble: sqlite3_column_double(statement, i)];
    case SQLITE_BLOB:
    case SQLITE_TEXT:
      return [[NSString alloc] initWithBytes:(char *)sqlite3_column_text(statement, i)
                                      length:sqlite3_column_bytes(statement, i)
                                    encoding:NSUTF8StringEncoding];
  }
  return [NSNull null];
}

-(NSArray*) executeSql: (NSString*)sql
           withSqlArgs: (NSArray*)sqlArgs
                withDb: (sqlite3*)db
          withReadOnly: (BOOL)readOnly {
  logDebug(@"executeSql sql: %@", sql);
  NSString *error = nil;
  sqlite3_stmt *statement;
  NSMutableArray *resultRows = [NSMutableArray arrayWithCapacity:0];
  NSMutableArray *entry;
  long insertId = 0;
  int rowsAffected = 0;
  int i;
  
  
  // compile the statement, throw an error if necessary
  logDebug(@"sqlite3_prepare_v2");
  if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &statement, NULL) != SQLITE_OK) {
    error = [RNSqlite2 convertSQLiteErrorToString:db];
    logDebug(@"prepare error!");
    logDebug(@"error: %@", error);
    return @[error];
  }
  
  bool queryIsReadOnly = sqlite3_stmt_readonly(statement);
  if (readOnly && !queryIsReadOnly) {
    error = [NSString stringWithFormat:@"could not prepare %@", sql];
    return @[error];
  }
  
  // bind any arguments
  if (sqlArgs != nil) {
    for (i = 0; i < sqlArgs.count; i++) {
      [self bindStatement:statement withArg:[sqlArgs objectAtIndex:i] atIndex:(i + 1)];
    }
  }
  
  int previousRowsAffected;
  if (!queryIsReadOnly) {
    // calculate the total changes in order to diff later
    previousRowsAffected = sqlite3_total_changes(db);
  }
  
  // iterate through sql results
  int columnCount;
  NSMutableArray *columnNames = [NSMutableArray arrayWithCapacity:0];
  NSString *columnName;
  int columnType;
  BOOL fetchedColumns = NO;
  int result;
  NSObject *columnValue;
  BOOL hasMore = YES;
  while (hasMore) {
    logDebug(@"sqlite3_step");
    result = sqlite3_step (statement);
    switch (result) {
      case SQLITE_ROW:
        if (!fetchedColumns) {
          // get all column names once at the beginning
          columnCount = sqlite3_column_count(statement);
          
          for (i = 0; i < columnCount; i++) {
            columnName = [NSString stringWithFormat:@"%s", sqlite3_column_name(statement, i)];
            [columnNames addObject:columnName];
          }
          fetchedColumns = YES;
        }
        entry = [NSMutableArray arrayWithCapacity:columnCount];
        for (i = 0; i < columnCount; i++) {
          columnType = sqlite3_column_type(statement, i);
          columnValue = [self getSqlValueForColumnType:columnType withStatement:statement withIndex: i];
          [entry addObject:columnValue];
        }
        [resultRows addObject:entry];
        break;
      case SQLITE_DONE:
        hasMore = NO;
        break;
      default:
        error = [RNSqlite2 convertSQLiteErrorToString:db];
        hasMore = NO;
        break;
    }
  }
  
  if (!queryIsReadOnly) {
    rowsAffected = (sqlite3_total_changes(db) - previousRowsAffected);
    if (rowsAffected > 0) {
      insertId = sqlite3_last_insert_rowid(db);
    }
  }
  
  logDebug(@"sqlite3_finalize");
  sqlite3_finalize (statement);
  
  if (error) {
    return @[error];
  }
  return @[
           [NSNull null],
           [NSNumber numberWithLong:insertId],
           [NSNumber numberWithInt:rowsAffected],
           columnNames,
           resultRows
           ];
}

-(void)bindStatement:(sqlite3_stmt *)statement withArg:(NSObject *)arg atIndex:(int)argIndex {
  
  if ([arg isEqual:[NSNull null]]) {
    sqlite3_bind_null(statement, argIndex);
  } else if ([arg isKindOfClass:[NSNumber class]]) {
    NSNumber *numberArg = (NSNumber *)arg;
    const char *numberType = [numberArg objCType];
    if (strcmp(numberType, @encode(int)) == 0 ||
        strcmp(numberType, @encode(long long int)) == 0) {
      sqlite3_bind_int64(statement, argIndex, [numberArg longLongValue]);
    } else if (strcmp(numberType, @encode(double)) == 0) {
      sqlite3_bind_double(statement, argIndex, [numberArg doubleValue]);
    } else {
      sqlite3_bind_text(statement, argIndex, [[arg description] UTF8String], -1, SQLITE_TRANSIENT);
    }
  } else { // NSString
    NSString *stringArg;
    
    if ([arg isKindOfClass:[NSString class]]) {
      stringArg = (NSString *)arg;
    } else {
      stringArg = [arg description]; // convert to text
    }
    
    NSData *data = [stringArg dataUsingEncoding:NSUTF8StringEncoding];
    sqlite3_bind_text(statement, argIndex, data.bytes, (int)data.length, SQLITE_TRANSIENT);
  }
}

-(void)dealloc {
  int i;
  NSArray *keys = [cachedDatabases allKeys];
  NSValue *pointer;
  NSString *key;
  sqlite3 *db;
  for (i = 0; i < [keys count]; i++) {
    key = [keys objectAtIndex:i];
    pointer = [cachedDatabases objectForKey:key];
    db = [pointer pointerValue];
    sqlite3_close (db);
  }
}

+(NSString *)convertSQLiteErrorToString:(struct sqlite3 *)db {
  
  int code = sqlite3_errcode(db);
  const char *cMessage = sqlite3_errmsg(db);
  NSString *message = [[NSString alloc] initWithUTF8String: cMessage];
  return [NSString stringWithFormat:@"Error code %i: %@", code, message];
}

@end
