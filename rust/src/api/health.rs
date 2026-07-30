const API_VERSION: u32 = 2;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BridgeHealth {
    pub api_version: u32,
    pub implementation: String,
}

pub fn bridge_health() -> BridgeHealth {
    BridgeHealth {
        api_version: API_VERSION,
        implementation: "voltrike-core-rust".to_owned(),
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
