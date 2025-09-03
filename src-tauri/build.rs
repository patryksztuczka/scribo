fn main() {
    // najpierw kompilujemy C++ (np. hello.cpp)
    let mut build_cpp = cc::Build::new();
    build_cpp
        .cpp(true)
        .file("native/hello.cpp")
        .flag_if_supported("-std=c++17");
    build_cpp.compile("hello");

    // następnie Objective-C++ (ScreenCaptureKit)
    let mut build_objcpp = cc::Build::new();
    build_objcpp
        .cpp(true)
        .file("native/sources.mm")
        .file("native/capture.mm")
        .flag_if_supported("-std=c++17")
        .flag_if_supported("-fobjc-arc");
    build_objcpp.compile("sources");

    println!("cargo:rerun-if-changed=native/hello.h");
    println!("cargo:rerun-if-changed=native/hello.cpp");
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

    // potem dopiero generujemy build info dla tauri
    tauri_build::build();
}
