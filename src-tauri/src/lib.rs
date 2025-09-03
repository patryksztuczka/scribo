use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn hello_from_cpp() -> *const c_char;
    fn free_str(s: *const c_char);
    fn list_sources_json() -> *const c_char;
    fn sc_start_capture(
        kind: *const c_char,
        id: *const c_char,
        out_path: *const c_char,
        out_err: *mut *mut c_char,
    ) -> bool;
    fn sc_stop_capture();
    fn sc_free(s: *mut c_char);
}

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[tauri::command]
fn hello_cpp() -> String {
    unsafe {
        let ptr = hello_from_cpp();
        if ptr.is_null() {
            return "C++ returned null".into();
        }
        let msg = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        free_str(ptr);
        msg
    }
}

#[derive(serde::Deserialize, serde::Serialize, Debug, Clone)]
struct SourcesResult {
    #[serde(default)]
    displays: serde_json::Value,
    #[serde(default)]
    windows: serde_json::Value,
    #[serde(default)]
    applications: serde_json::Value,
    #[serde(default)]
    error: Option<String>,
}

#[tauri::command]
fn list_sources() -> Result<SourcesResult, String> {
    unsafe {
        let ptr = list_sources_json();
        if ptr.is_null() {
            return Err("native list_sources_json returned null".into());
        }
        let json = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        free_str(ptr);
        match serde_json::from_str::<SourcesResult>(&json) {
            Ok(mut v) => {
                if let Some(err) = v.error.clone() {
                    Err(err)
                } else {
                    Ok(v)
                }
            }
            Err(e) => Err(format!("failed to parse JSON from native: {}", e)),
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            greet,
            hello_cpp,
            list_sources,
            start_capture,
            stop_capture
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[tauri::command]
fn start_capture(kind: String, id: String, out_path: String) -> Result<(), String> {
    let kind_c = CString::new(kind).map_err(|_| "invalid kind".to_string())?;
    let id_c = CString::new(id).map_err(|_| "invalid id".to_string())?;
    let path_c = CString::new(out_path).map_err(|_| "invalid out_path".to_string())?;
    let mut err_ptr: *mut c_char = std::ptr::null_mut();
    let ok = unsafe {
        sc_start_capture(
            kind_c.as_ptr(),
            id_c.as_ptr(),
            path_c.as_ptr(),
            &mut err_ptr,
        )
    };
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
