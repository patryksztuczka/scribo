use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;
use std::time::{SystemTime, UNIX_EPOCH};
use std::{fs, path::PathBuf};

use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;

extern "C" {
    fn list_sources_json() -> *const c_char;
    fn sc_start_capture(id: *const c_char, out_err: *mut *mut c_char) -> bool;
    fn sc_stop_capture();
    fn sc_free(s: *mut c_char);
    fn sc_list_input_devices() -> *mut c_char;
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
struct AppItem {
    pid: i32,
    name: String,
    #[serde(default)]
    bundleId: String,
}

#[tauri::command]
fn list_apps() -> Result<Vec<AppItem>, String> {
    unsafe {
        let ptr = list_sources_json();
        if ptr.is_null() {
            return Err("native list returned null".into());
        }
        let json = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        sc_free(ptr as *mut c_char);
        serde_json::from_str::<Vec<AppItem>>(&json).map_err(|e| e.to_string())
    }
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
struct InputDevice {
    id: String,
    name: String,
    #[serde(default)]
    uniqueId: String,
}

#[tauri::command]
fn list_input_devices() -> Result<Vec<InputDevice>, String> {
    unsafe {
        let ptr = sc_list_input_devices();
        if ptr.is_null() {
            return Err("native sc_list_input_devices returned null".into());
        }
        let json = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        sc_free(ptr);
        serde_json::from_str::<Vec<InputDevice>>(&json).map_err(|e| e.to_string())
    }
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
struct RecordingItem {
    path: String,
    fileName: String,
    createdAtMs: i64,
}

#[tauri::command]
fn list_recordings() -> Result<Vec<RecordingItem>, String> {
    // Base directory: ~/Library/Application Support/scribo
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let base: PathBuf = PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("scribo");

    let mut items: Vec<RecordingItem> = Vec::new();
    let rd = match fs::read_dir(&base) {
        Ok(rd) => rd,
        Err(_) => return Ok(items),
    };

    for entry in rd {
        if let Ok(entry) = entry {
            let p = entry.path();
            if p.extension().and_then(|e| e.to_str()) == Some("wav") {
                if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                    if stem.ends_with("-mix") {
                        let meta = fs::metadata(&p).ok();
                        let modified: Option<SystemTime> = meta
                            .as_ref()
                            .and_then(|m| m.modified().ok())
                            .or_else(|| meta.as_ref().and_then(|m| m.created().ok()));
                        let created_ms: i64 = modified
                            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                            .map(|d| d.as_millis() as i64)
                            .unwrap_or(0);
                        let file_name = p
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("")
                            .to_string();
                        let path_str = p.to_string_lossy().to_string();
                        items.push(RecordingItem {
                            path: path_str,
                            fileName: file_name,
                            createdAtMs: created_ms,
                        });
                    }
                }
            }
        }
    }

    items.sort_by(|a, b| b.createdAtMs.cmp(&a.createdAtMs));
    Ok(items)
}

#[tauri::command]
fn get_recording_data_url(path: String) -> Result<String, String> {
    // Allow only files under the app base directory and only .wav
    let home = std::env::var("HOME").map_err(|e| e.to_string())?;
    let base: PathBuf = PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("scribo");

    let input_path = PathBuf::from(&path);
    let canon_base = base
        .canonicalize()
        .map_err(|_| "invalid base".to_string())?;
    let canon_path = input_path
        .canonicalize()
        .map_err(|_| "invalid path".to_string())?;
    if !canon_path.starts_with(&canon_base) {
        return Err("path not allowed".into());
    }
    if canon_path.extension().and_then(|e| e.to_str()) != Some("wav") {
        return Err("unsupported file type".into());
    }
    let data = fs::read(&canon_path).map_err(|e| e.to_string())?;
    let b64 = BASE64_STANDARD.encode(data);
    Ok(format!("data:audio/wav;base64,{}", b64))
}

#[tauri::command]
fn start_capture(id: String) -> Result<(), String> {
    let id_c = CString::new(id).map_err(|_| "invalid id".to_string())?;
    let mut err_ptr: *mut c_char = std::ptr::null_mut();
    let ok = unsafe { sc_start_capture(id_c.as_ptr(), &mut err_ptr) };
    if ok {
        Ok(())
    } else {
        let msg = unsafe {
            if err_ptr.is_null() {
                "unknown error".to_string()
            } else {
                let s = CStr::from_ptr(err_ptr).to_string_lossy().into_owned();
                sc_free(err_ptr);
                s
            }
        };
        Err(msg)
    }
}

#[tauri::command]
fn stop_capture() {
    unsafe { sc_stop_capture() }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            list_apps,
            start_capture,
            stop_capture,
            list_input_devices,
            list_recordings,
            get_recording_data_url
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
