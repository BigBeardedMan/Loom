use keyring::Entry;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct KeychainError {
    pub message: String,
}

impl From<keyring::Error> for KeychainError {
    fn from(err: keyring::Error) -> Self {
        Self {
            message: err.to_string(),
        }
    }
}

fn entry(service: &str, account: &str) -> Result<Entry, KeychainError> {
    Entry::new(service, account).map_err(Into::into)
}

#[tauri::command]
pub fn keychain_get(service: String, account: String) -> Result<Option<String>, KeychainError> {
    match entry(&service, &account)?.get_password() {
        Ok(s) => Ok(Some(s)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

#[tauri::command]
pub fn keychain_set(
    service: String,
    account: String,
    value: String,
) -> Result<(), KeychainError> {
    entry(&service, &account)?.set_password(&value).map_err(Into::into)
}

#[tauri::command]
pub fn keychain_delete(service: String, account: String) -> Result<(), KeychainError> {
    match entry(&service, &account)?.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.into()),
    }
}
