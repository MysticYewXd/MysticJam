//! Basic facts about the native library, used to check that Dart can reach
//! Rust at all.

/// Version of this Rust library (from Cargo.toml).
#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_the_crate_version() {
        assert_eq!(core_version(), "0.1.0");
    }
}
