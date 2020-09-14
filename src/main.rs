use std::str::from_utf8;
use sha1_exasol::{padding_to_512_multiple, find_n_first_zeros_sha1, sha1};
use std::time::{Duration, Instant};
use std::path::Path;
use std::fs::File;
use std::io::Write;

fn main() {
    let mut m = String::from("abaauieiauiea");
    let proba_len = 9;
    let difficulty = 9*4;
    let work_items = 3*1024;
//    let mut file = File::create(String::from("new_proba_") + &work_items.to_string() + "_" + &difficulty.to_string() + "_" + &proba_len.to_string() + ".txt").unwrap();
//    let mut result: Vec<u32>  = Vec::new();
//    for i in 0..50 {
//        m += "c";
    println!("started");
    let mut bytes: Vec<u8> = m.bytes().collect();
    padding_to_512_multiple(&mut bytes, 0);
    let start = Instant::now();
    let mut suffix = find_n_first_zeros_sha1(bytes.clone(), difficulty, work_items, proba_len).unwrap();
    let duration = start.elapsed();
//    file.write((duration.as_millis().to_string() + "\n").as_ref());
    println!("Time elapsed is {:?}", duration);
    println!();
    bytes.append(&mut suffix);
    println!("{:040x}", sha1(from_utf8(&bytes).unwrap()));
//    }

}


