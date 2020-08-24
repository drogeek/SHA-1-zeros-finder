
//use clap::{App, Arg};

use std::str::from_utf8;
//use exasol_challenge::{padding_to_512_multiple, find_n_first_zeros_sha1, sha1};
use sha1_exasol::{padding_to_512_multiple, find_n_first_zeros_sha1, sha1};

fn main() {
//    let matches = App::new("hash_zero_finder")
//        .arg(Arg::with_name("input")
//            .takes_value(true)
//            .required(true)
//        )
//        .arg(Arg::with_name("difficulty")
//            .short("d")
//            .takes_value(true)
//            .required(true)
//        )
//        .arg(Arg::with_name("work_items")
//            .long("work_items")
//            .required(false)
//            .default_value("3000")
//        ).get_matches();
//    let m = matches.value_of("input").unwrap();
//    let difficulty = matches.value_of("difficulty").unwrap().parse().unwrap();
//    let work_items = matches.value_of("work_items").unwrap().parse().unwrap();
    let m = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
//    let m = "a";
    let difficulty = 28;
    let work_items = 3000;
    let mut bytes: Vec<u8> = m.bytes().collect();
    padding_to_512_multiple(&mut bytes, 0);
//    let mut suffix = find_n_first_zeros_sha1(bytes, difficulty, work_items);
//    print!("{}", from_utf8(&suffix).unwrap());
    let suffix = find_n_first_zeros_sha1(bytes.clone(), difficulty, work_items);
    println!();
    bytes.append(&mut suffix.unwrap());
    println!("{:040x}", sha1(from_utf8(&bytes).unwrap()));
}


