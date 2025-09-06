fn main() {
    let mut build_objcpp = cc::Build::new();
    build_objcpp
        .cpp(true)
        .file("native/sources.mm")
        .file("native/capture.mm")
        .flag_if_supported("-std=c++17")
        .flag_if_supported("-fobjc-arc");
    build_objcpp.compile("sources");

    println!("cargo:rerun-if-changed=native/sources.h");
    println!("cargo:rerun-if-changed=native/sources.mm");
    println!("cargo:rerun-if-changed=native/capture.h");
    println!("cargo:rerun-if-changed=native/capture.mm");

    // Link wymaganych frameworków macOS
    println!("cargo:rustc-link-lib=framework=ScreenCaptureKit");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=CoreGraphics");
    println!("cargo:rustc-link-lib=framework=CoreMedia");
    println!("cargo:rustc-link-lib=framework=CoreAudio");
    println!("cargo:rustc-link-lib=framework=AudioToolbox");
    println!("cargo:rustc-link-lib=framework=AVFoundation");

    // potem dopiero generujemy build info dla tauri
    tauri_build::build();
}
