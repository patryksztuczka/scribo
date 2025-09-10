use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;
use std::{fs, path::PathBuf};

use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
mod recordings;
use recordings::repository as rec_repo;
use recordings::service as rec_service;
use recordings::RecordingItem;

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
    #[serde(default, rename = "bundleId")]
    bundle_id: String,
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
    #[serde(default, rename = "uniqueId")]
    unique_id: String,
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

#[tauri::command]
fn list_recordings() -> Result<Vec<RecordingItem>, String> {
    let conn = rec_repo::get_conn()?;
    rec_service::list_recordings(&conn)
}

#[tauri::command]
fn get_recording_data_url(path: String) -> Result<String, String> {
    // Allow only files under the app base directory and only .wav
    let base: PathBuf = rec_repo::app_base_dir()?;

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
fn delete_recording(path: String) -> Result<(), String> {
    // Only allow deleting files under base directory and the related siblings
    let base: PathBuf = rec_repo::app_base_dir()?;

    let target = PathBuf::from(&path);
    let canon_base = base
        .canonicalize()
        .map_err(|_| "invalid base".to_string())?;
    let canon_target = target
        .canonicalize()
        .map_err(|_| "invalid path".to_string())?;
    if !canon_target.starts_with(&canon_base) {
        return Err("path not allowed".into());
    }

    // Compute siblings: baseNoExt + (".wav", "-mic.wav", "-mix.wav")
    let file_name = canon_target
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| "invalid file name".to_string())?;
    let parent = canon_target
        .parent()
        .ok_or_else(|| "invalid parent".to_string())?;
    let mut base_stem = file_name.to_string();
    if let Some(idx) = base_stem.rfind("-mix.wav") {
        base_stem.truncate(idx);
    } else if let Some(idx) = base_stem.rfind("-mic.wav") {
        base_stem.truncate(idx);
    } else if let Some(idx) = base_stem.rfind(".wav") {
        base_stem.truncate(idx);
    }

    let app_path = parent.join(format!("{}.wav", base_stem));
    let mic_path = parent.join(format!("{}-mic.wav", base_stem));
    let mix_path = parent.join(format!("{}-mix.wav", base_stem));

    let _ = fs::remove_file(&app_path);
    let _ = fs::remove_file(&mic_path);
    let _ = fs::remove_file(&mix_path);

    // Remove row for the mix file from DB
    if let Ok(conn) = rec_repo::get_conn() {
        let _ = rec_service::delete_recording(&conn, &mix_path.to_string_lossy());
    }
    Ok(())
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
    if let Ok(conn) = rec_repo::get_conn() {
        if let Some(p) = rec_service::find_latest_mix_file() {
            let _ = rec_repo::insert_recording_from_path(&conn, &p);
        }
    }
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
            get_recording_data_url,
            delete_recording
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
