import Foundation
#if !COCOAPODS
import Apollo
#endif

/// A representation of a single row in the database
public struct DatabaseRow {
  /// The key used to cache a piece of data
  let cacheKey: CacheKey
  
  /// The data which was cached, as a JSON string.
  let storedInfo: String
}

/// A protocol for a SQLite table allowing key-value style storage of data locally.
public protocol SQLiteDatabase {
  
  /// Initializes and opens a database at the given file URL.
  ///
  /// - Parameter fileURL: The URL where the database should be opened and/or created.
  init(fileURL: URL) throws
  
  /// Creates the table for storing records. The table should have three columns with the following contents:
  ///
  /// - An auto-incremented `Int64` primary key. Named using `SQLiteDatabase.idColumnName`.
  /// - The `CacheKey` for the stored data. Named using `SQLiteDatabase.keyColumnName`.
  /// - The actual stored data, serialized as a JSON `String`. Named using `SQLiteDatabase.recordColumnName`.
  ///
  /// There should also be an index on the column storing cache keys. 
  func createRecordsTableIfNeeded() throws
  
  /// Selects rows from the database using the given keys, and returns their contents.
  /// - Parameter keys: A set of `CacheKey` objects to fetch the rows for
  /// - Returns: `DatabaseRow` objects with the raw, unparsed data from the database.
  func selectRawRows(forKeys keys: Set<CacheKey>) throws -> [DatabaseRow]

  /// Creates or updates the stored string for the given cache key
  ///
  /// - Parameters:
  ///   - recordString: The data to store as a serialized JSON string.
  ///   - cacheKey: The cache key to store it with
  func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws
  
  /// Deletes the stored `String` for a given cache key
  /// - Parameters:
  ///   - cacheKey: The cache key to remove data for
  func deleteRecord(for cacheKey: CacheKey) throws
  
  /// Deletes all records from the database, with an option to run the SQLite `VACUUM` command when executing.
  /// - Parameter shouldVacuumOnClear: Pass `true` to vacuum on clear. Should default to `false`.
  func clearDatabase(shouldVacuumOnClear: Bool) throws
}

public extension SQLiteDatabase {
  
  /// The name of the table to create
  static var tableName: String {
    "records"
  }
  
  /// The name of the column for storing auto-incremented IDs
  static var idColumnName: String {
    "_id"
  }
  
  /// The name of the column for storing cache keys
  static var keyColumnName: String {
    "key"
  }

  /// The name of the column for storing serialized JSON
  static var recordColumName: String {
    "record"
  }
}
