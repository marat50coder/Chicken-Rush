//! Runtime unsealer. Mirror of the keystream in `build.rs`.
//!
//! The embedded blob only contains ciphertext bytes and per-entry nonces;
//! plaintexts are recovered on demand via [`unseal`].

include!(concat!(env!("OUT_DIR"), "/sealed_blob.rs"));

fn ks(seed: u64, nonce: &[u8; 16], len: usize) -> Vec<u8> {
    let mut state: u64 = seed
        ^ u64::from_le_bytes(nonce[..8].try_into().unwrap())
        ^ u64::from_le_bytes(nonce[8..].try_into().unwrap()).rotate_left(13);
    let mut out = Vec::with_capacity(len);
    for _ in 0..len {
        state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^= z >> 31;
        out.push(z as u8);
    }
    out
}

/// Fetch and decrypt one entry by id. Returns `None` if the id is unknown.
pub fn unseal(id: u32) -> Option<Vec<u8>> {
    let e = SEALED.iter().find(|e| e.id == id)?;
    let k = ks(e.seed, &e.nonce, e.ct.len());
    Some(e.ct.iter().zip(k.iter()).map(|(a, b)| a ^ b).collect())
}
