use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};

#[derive(Debug, Clone)]
pub struct RecordingRow {
    pub _id: i64,
    pub name: String,
    pub file_path: String,
    pub _file_size_bytes: i64,
    pub created_at_ms: i64,
}

pub fn app_base_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let base: PathBuf = PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("scribo");
    if !base.exists() {
        fs::create_dir_all(&base).map_err(|e| e.to_string())?;
    }
    Ok(base)
}

pub fn db_path() -> Result<PathBuf, String> {
    Ok(app_base_dir()?.join("scribo.sqlite3"))
}

pub fn get_conn() -> Result<Connection, String> {
    let db_path = db_path()?;
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    conn.pragma_update(None, "busy_timeout", &5000i64)
        .map_err(|e| e.to_string())?;
    ensure_schema(&conn)?;
    Ok(conn)
}

pub fn ensure_schema(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            file_path TEXT NOT NULL UNIQUE,
            file_size_bytes INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_recordings_created_at ON recordings(created_at_ms DESC);
        "#,
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn insert_recording(
    conn: &Connection,
    name: &str,
    file_path: &str,
    file_size_bytes: i64,
    created_at_ms: i64,
) -> Result<(), String> {
    conn.execute(
        "INSERT OR IGNORE INTO recordings(name, file_path, file_size_bytes, created_at_ms) VALUES(?1, ?2, ?3, ?4)",
        params![name, file_path, file_size_bytes, created_at_ms],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_by_path(conn: &Connection, file_path: &str) -> Result<(), String> {
    conn.execute(
        "DELETE FROM recordings WHERE file_path = ?1",
        params![file_path],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn count(conn: &Connection) -> Result<i64, String> {
    let mut stmt = conn
        .prepare("SELECT COUNT(1) FROM recordings")
        .map_err(|e| e.to_string())?;
    let count: i64 = stmt
        .query_row([], |row| row.get(0))
        .map_err(|e| e.to_string())?;
    Ok(count)
}

pub fn list(conn: &Connection) -> Result<Vec<RecordingRow>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, file_path, file_size_bytes, created_at_ms FROM recordings ORDER BY created_at_ms DESC",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(RecordingRow {
                _id: row.get(0)?,
                name: row.get(1)?,
                file_path: row.get(2)?,
                _file_size_bytes: row.get(3)?,
                created_at_ms: row.get(4)?,
            })
        })
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

pub fn file_created_ms(meta: &fs::Metadata) -> i64 {
    let modified = meta.modified().ok().or_else(|| meta.created().ok());
    modified
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn insert_recording_from_path(conn: &Connection, path: &Path) -> Result<(), String> {
    let meta = fs::metadata(path).map_err(|e| e.to_string())?;
    let created_ms = file_created_ms(&meta);
    let file_size = i64::try_from(meta.len()).unwrap_or(i64::MAX);
    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();
    let file_path = path.to_string_lossy().to_string();
    insert_recording(conn, &file_name, &file_path, file_size, created_ms)
}
