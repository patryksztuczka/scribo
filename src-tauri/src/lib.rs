use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn hello_from_cpp() -> *const c_char;
    fn free_str(s: *const c_char);
    fn list_sources_json() -> *const c_char;
    fn sc_start_capture(id: *const c_char, out_err: *mut *mut c_char) -> bool;
    fn sc_stop_capture();
    fn sc_free(s: *mut c_char);
    fn sc_list_input_devices() -> *mut c_char;
}

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
        free_str(ptr);
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
            greet,
            hello_cpp,
            list_apps,
            start_capture,
            stop_capture,
            list_input_devices
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
