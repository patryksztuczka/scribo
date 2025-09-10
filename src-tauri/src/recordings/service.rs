use std::fs;
use std::path::PathBuf;

use rusqlite::Connection;

use super::repository::{
    app_base_dir, count, delete_by_path, insert_recording_from_path, list, RecordingRow,
};

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct RecordingItem {
    #[serde(rename = "path")]
    pub path: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    #[serde(rename = "createdAtMs")]
    pub created_at_ms: i64,
}

pub fn seed_if_empty(conn: &Connection) -> Result<(), String> {
    if count(conn)? > 0 {
        return Ok(());
    }
    let base = app_base_dir()?;
    let rd = match fs::read_dir(&base) {
        Ok(rd) => rd,
        Err(_) => return Ok(()),
    };
    for entry in rd.flatten() {
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) == Some("wav") {
            if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                if stem.ends_with("-mix") {
                    let _ = insert_recording_from_path(conn, &p);
                }
            }
        }
    }
    Ok(())
}

pub fn find_latest_mix_file() -> Option<PathBuf> {
    let base = app_base_dir().ok()?;
    let rd = fs::read_dir(&base).ok()?;
    let mut best: Option<(PathBuf, i64)> = None;
    for entry in rd.flatten() {
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) == Some("wav") {
            if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                if stem.ends_with("-mix") {
                    if let Ok(meta) = fs::metadata(&p) {
                        let ts = super::repository::file_created_ms(&meta);
                        match &best {
                            Some((_, best_ts)) if ts <= *best_ts => {}
                            _ => best = Some((p.clone(), ts)),
                        }
                    }
                }
            }
        }
    }
    best.map(|(p, _)| p)
}

pub fn list_recordings(conn: &Connection) -> Result<Vec<RecordingItem>, String> {
    let rows: Vec<RecordingRow> = list(conn)?;
    let items = rows
        .into_iter()
        .map(|r| RecordingItem {
            path: r.file_path,
            file_name: r.name,
            created_at_ms: r.created_at_ms,
        })
        .collect();
    Ok(items)
}

pub fn delete_recording(conn: &Connection, mix_file_path: &str) -> Result<(), String> {
    delete_by_path(conn, mix_file_path)?;
    Ok(())
}
