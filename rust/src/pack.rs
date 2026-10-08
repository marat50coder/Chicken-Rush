//! Envelope packer for the attribution relay (`/edge/sync`).
//!
//! Mirrors the Python reference in the relay-edge-deploy skill:
//!   raw       = utf8(json(body))
//!   keystream = sha256(secret || nonce || counter_be32) repeated
//!   enc       = raw ^ keystream
//!   payload   = base64url(enc) without padding
//!   tag       = hmac_sha256(secret, nonce || enc).hex()[:16]
//! field names + schema rev come from sealed strings 5/6/7/8/9, the HMAC
//! secret from id 10 — none appear in Dart.
//!
//! This is wired for a future verdict call; the current white-only build
//! never invokes it, but keeping the primitive in Rust satisfies the
//! "no plaintext envelope packing on the Dart side" invariant.

use crate::sealed;

// ─────────────────────────────── sha256 (tiny) ───────────────────────────────

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const H0: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

fn sha256(data: &[u8]) -> [u8; 32] {
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut buf: Vec<u8> = Vec::with_capacity(data.len() + 72);
    buf.extend_from_slice(data);
    buf.push(0x80);
    while buf.len() % 64 != 56 {
        buf.push(0);
    }
    buf.extend_from_slice(&bit_len.to_be_bytes());

    let mut h = H0;
    for chunk in buf.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[4 * i],
                chunk[4 * i + 1],
                chunk[4 * i + 2],
                chunk[4 * i + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    let mut out = [0u8; 32];
    for (i, v) in h.iter().enumerate() {
        out[4 * i..4 * i + 4].copy_from_slice(&v.to_be_bytes());
    }
    out
}

fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 {
        let d = sha256(key);
        k[..32].copy_from_slice(&d);
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= k[i];
        opad[i] ^= k[i];
    }
    let mut inner = Vec::with_capacity(64 + msg.len());
    inner.extend_from_slice(&ipad);
    inner.extend_from_slice(msg);
    let h1 = sha256(&inner);
    let mut outer = Vec::with_capacity(64 + 32);
    outer.extend_from_slice(&opad);
    outer.extend_from_slice(&h1);
    sha256(&outer)
}

fn keystream(secret: &[u8], nonce: &[u8], len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(len);
    let mut counter: u32 = 0;
    while out.len() < len {
        let mut buf = Vec::with_capacity(secret.len() + nonce.len() + 4);
        buf.extend_from_slice(secret);
        buf.extend_from_slice(nonce);
        buf.extend_from_slice(&counter.to_be_bytes());
        out.extend_from_slice(&sha256(&buf));
        counter = counter.wrapping_add(1);
    }
    out.truncate(len);
    out
}

const B64URL: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

fn b64url_nopad(input: &[u8]) -> String {
    let mut out = String::with_capacity((input.len() + 2) / 3 * 4);
    let mut i = 0;
    while i + 3 <= input.len() {
        let a = input[i] as u32;
        let b = input[i + 1] as u32;
        let c = input[i + 2] as u32;
        let n = (a << 16) | (b << 8) | c;
        out.push(B64URL[((n >> 18) & 0x3f) as usize] as char);
        out.push(B64URL[((n >> 12) & 0x3f) as usize] as char);
        out.push(B64URL[((n >> 6) & 0x3f) as usize] as char);
        out.push(B64URL[(n & 0x3f) as usize] as char);
        i += 3;
    }
    let rem = input.len() - i;
    if rem == 1 {
        let n = (input[i] as u32) << 16;
        out.push(B64URL[((n >> 18) & 0x3f) as usize] as char);
        out.push(B64URL[((n >> 12) & 0x3f) as usize] as char);
    } else if rem == 2 {
        let n = ((input[i] as u32) << 16) | ((input[i + 1] as u32) << 8);
        out.push(B64URL[((n >> 18) & 0x3f) as usize] as char);
        out.push(B64URL[((n >> 12) & 0x3f) as usize] as char);
        out.push(B64URL[((n >> 6) & 0x3f) as usize] as char);
    }
    out
}

fn hex16(bytes: &[u8]) -> String {
    const HEX: &[u8] = b"0123456789abcdef";
    let n = bytes.len().min(8); // 8 bytes → 16 hex chars
    let mut s = String::with_capacity(n * 2);
    for b in &bytes[..n] {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

fn hex_all(bytes: &[u8]) -> String {
    const HEX: &[u8] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

fn json_escape_into(dst: &mut String, s: &str) {
    dst.push('"');
    for c in s.chars() {
        match c {
            '"' => dst.push_str("\\\""),
            '\\' => dst.push_str("\\\\"),
            '\n' => dst.push_str("\\n"),
            '\r' => dst.push_str("\\r"),
            '\t' => dst.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                dst.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => dst.push(c),
        }
    }
    dst.push('"');
}

/// Pack a JSON body (verbatim bytes) + nonce into a wire envelope as a
/// UTF-8 JSON string, using sealed field names and the sealed secret.
pub fn pack_envelope(body_json: &[u8], nonce: &[u8; 16]) -> Option<Vec<u8>> {
    let secret = sealed::unseal(10)?;
    let f_schema = String::from_utf8(sealed::unseal(5)?).ok()?;
    let f_nonce = String::from_utf8(sealed::unseal(6)?).ok()?;
    let f_payload = String::from_utf8(sealed::unseal(7)?).ok()?;
    let f_tag = String::from_utf8(sealed::unseal(8)?).ok()?;
    let schema_rev_s = String::from_utf8(sealed::unseal(9)?).ok()?;
    let schema_rev: u64 = schema_rev_s.parse().ok()?;

    let ks = keystream(&secret, nonce, body_json.len());
    let enc: Vec<u8> = body_json.iter().zip(ks.iter()).map(|(a, b)| a ^ b).collect();
    let payload = b64url_nopad(&enc);

    let mut tag_msg = Vec::with_capacity(nonce.len() + enc.len());
    tag_msg.extend_from_slice(nonce);
    tag_msg.extend_from_slice(&enc);
    let tag_full = hmac_sha256(&secret, &tag_msg);
    let tag = hex16(&tag_full);

    let nonce_hex = hex_all(nonce);

    let mut out = String::new();
    out.push('{');
    json_escape_into(&mut out, &f_schema);
    out.push(':');
    out.push_str(&schema_rev.to_string());
    out.push(',');
    json_escape_into(&mut out, &f_nonce);
    out.push(':');
    json_escape_into(&mut out, &nonce_hex);
    out.push(',');
    json_escape_into(&mut out, &f_payload);
    out.push(':');
    json_escape_into(&mut out, &payload);
    out.push(',');
    json_escape_into(&mut out, &f_tag);
    out.push(':');
    json_escape_into(&mut out, &tag);
    out.push('}');
    Some(out.into_bytes())
}
